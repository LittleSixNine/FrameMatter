// overscan.metal -- RFC-032 §26-§27: the film outside the frame, as exposure.
//
// All three kernels read one parameter block `P` (floats; layout in
// `overscan.cpp`, `enum OsP`, which is the single source of the indices).
// Geometry is in film millimetres: `s` along the film, `t` across it, `t = 0`
// at the film's first long edge. A canvas pixel maps to film coordinates
// through the scan registration (a rotation and an offset), so the film --
// gate, perforations, edge print -- can sit a hair off square in the output,
// as it does in a real scan.
#include <metal_stdlib>
using namespace metal;

enum : uint {
    P_CW = 0, P_CH, P_PX, P_FW, P_FH,
    P_A00, P_A01, P_A10, P_A11, P_CS, P_CT, P_CU, P_CV,
    P_VERTICAL,
    P_GS0, P_GT0, P_GW, P_GH, P_CORNER, P_PENUMBRA,
    P_WOB_A = 20,                 // 4 sides x 3 harmonics
    P_WOB_PH = 32,                // 4 sides x 3 harmonics
    P_FILM_W = 44, P_FOG_AMP, P_FOG_WIDTH, P_FOG_SEED, P_FOG_PERIOD,
    P_FOG_R, P_FOG_G, P_FOG_B,
    P_N_LEAKS = 52,
    P_PERFORATED = 83, P_PERF_PITCH, P_PERF_W, P_PERF_H, P_PERF_EDGE, P_PERF_R, P_PERF_PHASE,
    P_HOLE_C = 90, P_HOLE_M, P_HOLE_Y,
    P_FLARE_AMP = 93, P_FLARE_WIDTH,
    P_GATE_R = 95,                // 4 corner radii: (s-,t-), (s+,t-), (s+,t+), (s-,t+)
    P_N_Q = 99, P_Q = 100,        // up to 8 x (4 vertices s,t; round; sign: +1/-1 quad adds/cuts, +2/-2 ellipse (cs, ct, rs, rt))
    P_ROUGH_AMP = 180, P_ROUGH_PERIOD, P_ROUGH_SEED,
    P_HOLES_LIGHT = 183, P_LIGHT_R, P_LIGHT_G, P_LIGHT_B,
    P_PERF_SEED = 187, P_LIGHT_FALL, P_LIGHT_DIR,
    P_WALL_T = 190, P_WALL_VS, P_WALL_VT, P_WALL_PAR, P_BASE_R, P_BASE_G, P_BASE_B, P_WALL_GLOW, P_WALL_SCATTER,
    P_CARRIER = 199,
    P_LEAKS = 200,          // up to 12 x (s, side, amp, sigma_s, sigma_t)
    P_PAIR_ADV = 260,       // > 0: the same gate exposed again this far along (a half-frame pair)
    P_SCRATCH_STRENGTH = 261, P_SCRATCH_LONG, P_SCRATCH_SEED, P_SCRATCH_EDGE, P_PERF_LEAK, P_PERF_LEAK_SPREAD,
    P_COUNT = 267
};
constant uint kQStride = 10u;

static float2 canvas_to_film(float x, float y, device const float* P) {
    const float u = (x + 0.5f) * P[P_PX] - P[P_CU];
    const float v = (y + 0.5f) * P[P_PX] - P[P_CV];
    return float2(P[P_A00] * u + P[P_A01] * v + P[P_CS], P[P_A10] * u + P[P_A11] * v + P[P_CT]);
}

static uint hash_u(uint x) {
    x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16;
    return x;
}
static float hash_f(int i, uint seed) { return float(hash_u(uint(i) * 0x9E3779B9u ^ seed)) * (1.0f / 4294967295.0f); }
static float value_noise(float x, uint seed) {
    const float i0 = floor(x), f = x - i0;
    const float w = f * f * (3.0f - 2.0f * f);
    return mix(hash_f(int(i0), seed), hash_f(int(i0) + 1, seed), w);
}

// Signed distance to a convex quad (either winding; a repeated vertex makes a
// triangle), negative inside.
static float sd_quad(float2 p, device const float* q) {
    float2 v[4] = {float2(q[0], q[1]), float2(q[2], q[3]), float2(q[4], q[5]), float2(q[6], q[7])};
    float d = dot(p - v[0], p - v[0]);
    float sgn = 1.0f;
    for (uint i = 0u, j = 3u; i < 4u; j = i, ++i) {
        const float2 e = v[j] - v[i], w = p - v[i];
        const float ee = dot(e, e);
        if (ee < 1e-12f) continue;
        const float2 b = w - e * clamp(dot(w, e) / ee, 0.0f, 1.0f);
        d = min(d, dot(b, b));
        const bool c0 = p.y >= v[i].y, c1 = p.y < v[j].y, c2 = e.x * w.y > e.y * w.x;
        if ((c0 && c1 && c2) || (!c0 && !c1 && !c2)) sgn = -sgn;
    }
    return sgn * sqrt(d);
}

// The gate (RFC-032 §29). Real gates are not symmetric rounded rectangles:
// each corner has its own radius, and a camera's gate carries its own
// features -- the eared sides of a 645 whose film rails stand proud, the
// shoulders of a 6x8 mask, the kicked-out corners of a 6x6 insert, a burr.
// Those come in as convex quads that add to or cut from the opening, and a
// fine roughness models the machined edge. On top, each side keeps the
// camera's low-frequency wobble (three harmonics, vanishing at the corners).
// Signed distance, negative inside, in mm.
static float gate_sdf(float2 st, device const float* P) {
    const float hw = 0.5f * P[P_GW], hh = 0.5f * P[P_GH];
    const float ds = st.x - (P[P_GS0] + hw), dt = st.y - (P[P_GT0] + hh);
    const float r = ds > 0.0f ? (dt > 0.0f ? P[P_GATE_R + 2u] : P[P_GATE_R + 1u])
                              : (dt > 0.0f ? P[P_GATE_R + 3u] : P[P_GATE_R + 0u]);
    const float qs = fabs(ds) - (hw - r), qt = fabs(dt) - (hh - r);
    float d = length(max(float2(qs, qt), 0.0f)) + min(max(qs, qt), 0.0f) - r;
    uint side; float along, len;
    if (qs > qt) { side = ds > 0.0f ? 1u : 3u; along = dt + hh; len = 2.0f * hh; }
    else         { side = dt > 0.0f ? 2u : 0u; along = ds + hw; len = 2.0f * hw; }
    const float u = clamp(along / len, 0.0f, 1.0f);
    float w = 0.0f;
    for (uint k = 0; k < 3u; ++k)
        w += P[P_WOB_A + side * 3u + k] * sin(float(k + 1u) * M_PI_F * u + P[P_WOB_PH + side * 3u + k]);
    d -= w * sin(M_PI_F * u);
    const uint nq = uint(P[P_N_Q]);
    for (uint k = 0; k < nq; ++k) {
        device const float* q = P + P_Q + kQStride * k;
        float dq;
        if (fabs(q[9]) > 1.5f) {
            // an ellipse: centre q[0..1], radii q[2..3]; distance scaled by the
            // smaller radius, exact on the boundary, which is all a penumbra reads
            const float2 r = max(float2(q[2], q[3]), float2(1e-4f));
            dq = (length((st - float2(q[0], q[1])) / r) - 1.0f) * min(r.x, r.y);
        } else {
            dq = sd_quad(st, q) - q[8];
        }
        d = q[9] > 0.0f ? min(d, dq) : max(d, -dq);
    }
    if (P[P_ROUGH_AMP] > 0.0f) {
        const uint seed = uint(P[P_ROUGH_SEED]);
        const float per = max(P[P_ROUGH_PERIOD], 1e-3f);
        d += P[P_ROUGH_AMP] * (value_noise(st.x / per, seed) + value_noise(st.y / per, seed ^ 0x5bd1e995u) - 1.0f);
    }
    return d;
}

// The gate's shadow on the emulsion from a circular aperture: the lit fraction
// of a disc of radius r cut by a straight edge at signed distance d. Not a
// Gaussian -- a Gaussian has tails a real penumbra does not have.
static float penumbra(float d, float r) {
    if (r <= 1e-6f) return d < 0.0f ? 1.0f : 0.0f;
    const float u = clamp(-d / r, -1.0f, 1.0f);
    return 0.5f + (u * sqrt(max(1.0f - u * u, 0.0f)) + asin(u)) * (1.0f / M_PI_F);
}

static float3 sample_frame(device const float* f, float fx, float fy, uint fw, uint fh) {
    fx = clamp(fx, 0.0f, float(fw) - 1.0f);
    fy = clamp(fy, 0.0f, float(fh) - 1.0f);
    const uint x0 = uint(floor(fx)), y0 = uint(floor(fy));
    const uint x1 = min(x0 + 1u, fw - 1u), y1 = min(y0 + 1u, fh - 1u);
    const float ax = fx - float(x0), ay = fy - float(y0);
    const uint i00 = 3u * (y0 * fw + x0), i01 = 3u * (y0 * fw + x1);
    const uint i10 = 3u * (y1 * fw + x0), i11 = 3u * (y1 * fw + x1);
    const float3 a = float3(f[i00], f[i00 + 1u], f[i00 + 2u]);
    const float3 b = float3(f[i01], f[i01 + 1u], f[i01 + 2u]);
    const float3 c = float3(f[i10], f[i10 + 1u], f[i10 + 2u]);
    const float3 d = float3(f[i11], f[i11 + 1u], f[i11 + 2u]);
    return mix(mix(a, b, ax), mix(c, d, ax), ay);
}

static float perf_sdf(float2 st, device const float* P, thread uint& hole);

// Adapt the existing spool-leak Gaussian/exposure model to perforation anchors.
// shortcut: a visual exposure model, not measured light propagation through a specific film base.
static float perforation_leak(float2 st, device const float* P) {
    if (P[P_PERF_LEAK] <= 0.0f || P[P_PERFORATED] < 0.5f) return 0.0f;
    const float spread = mix(0.15f, 1.80f, P[P_PERF_LEAK_SPREAD]);
    const bool top = st.y < 0.5f * P[P_FILM_W];
    const float inner = P[P_PERF_EDGE] + P[P_PERF_H];
    const float dt = st.y - (top ? inner : P[P_FILM_W] - inner);
    uint hole;
    const float d = perf_sdf(st, P, hole);
    if (d < 0.0f) return 0.0f;
    const float pitch = P[P_PERF_PITCH], phase = P[P_PERF_PHASE];
    const int nearest = int(floor((st.x - phase - 0.5f * P[P_PERF_W]) / pitch + 0.5f));
    // Share the anchors and slow exposure trend; only small local variation differs by row.
    const uint seed = uint(P[P_SCRATCH_SEED]) ^ 0x1EAFu;
    const uint row_seed = seed ^ (top ? 0xA101u : 0xB202u);
    // The existing hole distance and pixel footprint define a separate, narrow exposure rim.
    const float rim_sigma = sqrt(0.012f * 0.012f + 0.0961f * P[P_PX] * P[P_PX]);
    const uint rim_seed = row_seed ^ hole;
    const float patch = smoothstep(0.20f, 0.80f, 0.5f * (value_noise(st.x / 0.20f, rim_seed) +
                                                                    value_noise(st.y / 0.20f, rim_seed ^ 0x33u)));
    const float rim_weight = (0.25f + 0.75f * hash_f(nearest, seed ^ 0x44u)) * (0.35f + 0.65f * patch);
    const float rim_x = (d - 0.012f) / rim_sigma;
    float amount = 0.80f * P[P_PERF_LEAK] * rim_weight * exp(-0.5f * rim_x * rim_x);
    if (abs(dt) > 6.0f * spread) return amount;
    const float sigma_s = 0.55f + 0.55f * spread;
    for (int offset = -1; offset <= 1; ++offset) {
        const int k = nearest + offset;
        if (hash_f(k, seed ^ 0x11u) > 0.65f) continue;
        const float cluster = smoothstep(0.40f, 0.70f, value_noise(float(k) / 3.0f, seed));
        const float center = phase + float(k) * pitch + 0.5f * P[P_PERF_W];
        const float ds = st.x - center;
        const float local = 0.85f + 0.30f * hash_f(k, row_seed);
        const float amplitude = 0.36f * P[P_PERF_LEAK] * cluster * (0.3f + 0.7f * hash_f(k, seed ^ 0x22u)) * local;
        amount += amplitude * exp(-0.5f * ds * ds / (sigma_s * sigma_s)) * exp(-0.5f * dt * dt / (spread * spread));
    }
    return amount;
}

// ① + ② + the fog of ③: raw exposure on the film canvas.
kernel void spk_overscan_canvas(device const float* frame [[buffer(0)]],
                                device const float* P [[buffer(1)]],
                                device const uint* n [[buffer(2)]],
                                device float* out [[buffer(3)]],
                                uint3 tid [[thread_position_in_grid]]) {
    const uint i = tid.x;
    if (i >= n[0]) return;
    const uint cw = uint(P[P_CW]);
    const float2 st = canvas_to_film(float(i % cw), float(i / cw), P);
    const float W = P[P_FILM_W];
    float3 e = float3(0.0f);
    if (P[P_CARRIER] > 1.5f || (st.y >= 0.0f && st.y <= W)) {
        // A pair: past the middle of the gap, the second exposure of the same gate.
        float2 sg = st;
        float shift = 0.0f;
        if (P[P_PAIR_ADV] > 0.0f && st.x > P[P_GS0] + 0.5f * (P[P_GW] + P[P_PAIR_ADV])) { shift = P[P_PAIR_ADV]; sg.x -= shift; }
        const float cov = penumbra(gate_sdf(sg, P), P[P_PENUMBRA]);
        if (cov > 0.0f) {
            const float px = P[P_PX];
            float fx, fy;
            if (P[P_VERTICAL] < 0.5f) { fx = (st.x - P[P_GS0]) / px - 0.5f; fy = (st.y - P[P_GT0]) / px - 0.5f; }
            else                      { fx = (P[P_GT0] + P[P_GH] - st.y) / px - 0.5f; fy = (st.x - P[P_GS0]) / px - 0.5f; }
            e += cov * sample_frame(frame, fx, fy, uint(P[P_FW]), uint(P[P_FH]));
        }
        // Gate flare: the gate's bevelled edge reflects scene light onto the
        // film just outside the frame -- a thin line that follows the scene's
        // brightness along the edge (bright sky, bright line).
        const float d_gate = gate_sdf(sg, P);
        if (P[P_FLARE_AMP] > 0.0f && d_gate > -0.02f && d_gate < 6.0f * P[P_FLARE_WIDTH]) {
            const float px = P[P_PX];
            const float in_s = clamp(sg.x, P[P_GS0] + 0.12f, P[P_GS0] + P[P_GW] - 0.12f) + shift;
            const float in_t = clamp(st.y, P[P_GT0] + 0.12f, P[P_GT0] + P[P_GH] - 0.12f);
            float fx, fy;
            if (P[P_VERTICAL] < 0.5f) { fx = (in_s - P[P_GS0]) / px - 0.5f; fy = (in_t - P[P_GT0]) / px - 0.5f; }
            else                      { fx = (P[P_GT0] + P[P_GH] - in_t) / px - 0.5f; fy = (in_s - P[P_GS0]) / px - 0.5f; }
            const float3 edge_light = sample_frame(frame, fx, fy, uint(P[P_FW]), uint(P[P_FH]));
            const float prof = exp(-max(d_gate, 0.0f) / P[P_FLARE_WIDTH]);
            e += P[P_FLARE_AMP] * prof * edge_light;
        }
        // Edge fog: warm exposure decaying inward from each long edge, slowly
        // varying along the length; and the spool leaks, seeded blobs on an edge.
        // (clamped: the canvas reaches past the film, where there is none to fog)
        const float d_top = max(st.y, 0.0f), d_bot = max(W - st.y, 0.0f);
        const uint seed = uint(P[P_FOG_SEED]);
        const float period = max(P[P_FOG_PERIOD], 0.1f);
        const float nz = 0.6f * value_noise(st.x / period, seed) +
                         0.4f * value_noise(st.x / (0.37f * period), seed ^ 0xA5A5A5A5u);
        float fog = P[P_FOG_AMP] * exp(-min(d_top, d_bot) / max(P[P_FOG_WIDTH], 1e-3f)) * (0.3f + 0.7f * nz);
        const uint nl = uint(P[P_N_LEAKS]);
        for (uint k = 0; k < nl; ++k) {
            const uint b = P_LEAKS + 5u * k;
            const float dd = P[b + 1u] < 0.5f ? d_top : d_bot;
            const float ds = st.x - P[b];
            fog += P[b + 2u] * exp(-ds * ds / (2.0f * P[b + 3u] * P[b + 3u])) * exp(-dd / P[b + 4u]);
        }
        fog += perforation_leak(st, P);
        e += fog * float3(P[P_FOG_R], P[P_FOG_G], P[P_FOG_B]);
    }
    out[3u * i] = e.x;
    out[3u * i + 1u] = e.y;
    out[3u * i + 2u] = e.z;
}

// ③: a rasterised imprint (coverage, canvas-aligned) added as exposure.
// M = {x0, y0, mw, mh, cw, ch, e_r, e_g, e_b}.
kernel void spk_overscan_add_mask(device const float* mask [[buffer(0)]],
                                  device const float* M [[buffer(1)]],
                                  device const uint* n [[buffer(2)]],
                                  device float* canvas [[buffer(3)]],
                                  uint3 tid [[thread_position_in_grid]]) {
    const uint i = tid.x;
    if (i >= n[0]) return;
    const uint mw = uint(M[2]);
    const int x = int(M[0]) + int(i % mw), y = int(M[1]) + int(i / mw);
    if (x < 0 || y < 0 || x >= int(M[4]) || y >= int(M[5])) return;
    const float c = mask[i];
    if (c <= 0.0f) return;
    const uint o = 3u * (uint(y) * uint(M[4]) + uint(x));
    canvas[o] += c * M[6];
    canvas[o + 1u] += c * M[7];
    canvas[o + 2u] += c * M[8];
}

// The nearest perforation's signed distance (mm, negative inside). KS holes
// are punched to tight tolerances, not drawn: each hole sits a few microns
// off the ideal pitch and row, is a few microns off size, its corners are not
// all the same, and the punched edge is not a perfect line. `hole` returns the
// hole's own hash (row and index) for the scan's dust.
static float perf_sdf(float2 st, device const float* P, thread uint& hole) {
    const float W = P[P_FILM_W];
    const float pitch = P[P_PERF_PITCH], ph = P[P_PERF_PHASE];
    // The nearest hole: the cell is centred on it. (It began at the hole's
    // leading edge, so just outside that edge the distance was the previous
    // hole's -- 2.8 mm -- and that side had no shoulder, no flare, and a hard
    // cut where the other three sides were soft.)
    const float k = floor((st.x - ph - 0.5f * P[P_PERF_W]) / pitch + 0.5f);
    const bool top = st.y < 0.5f * W;
    const uint seed = uint(P[P_PERF_SEED]);
    hole = hash_u(uint(int(k) * 2 + (top ? 0 : 1)) * 0x9E3779B9u ^ seed);
    const float j0 = hash_f(int(hole & 0xFFFFu), seed ^ 0x1u) - 0.5f, j1 = hash_f(int(hole & 0xFFFFu), seed ^ 0x2u) - 0.5f;
    const float j2 = hash_f(int(hole & 0xFFFFu), seed ^ 0x3u) - 0.5f, j3 = hash_f(int(hole & 0xFFFFu), seed ^ 0x4u) - 0.5f;
    const float j4 = hash_f(int(hole & 0xFFFFu), seed ^ 0x5u) - 0.5f;
    const float wa = P[P_PERF_W] + 0.016f * j2, hc = P[P_PERF_H] + 0.016f * j3;
    const float r = clamp(P[P_PERF_R] + 0.08f * j4, 0.3f, 0.6f);
    const float sc = ph + k * pitch + 0.5f * P[P_PERF_W] + 0.020f * j0;
    const float tc = (top ? P[P_PERF_EDGE] + 0.5f * P[P_PERF_H] : W - P[P_PERF_EDGE] - 0.5f * P[P_PERF_H]) + 0.024f * j1;
    const float2 q = fabs(float2(st.x - sc, st.y - tc)) - float2(0.5f * wa - r, 0.5f * hc - r);
    float d = length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - r;
    // the punched edge: each hole's own roughness, 1-4 microns
    const float rough = 0.001f + 0.003f * hash_f(int(hole & 0xFFFFu), seed ^ 0x6u);
    d += rough * (value_noise(st.x / 0.05f, seed ^ 0x77u) + value_noise(st.y / 0.05f, seed ^ 0x99u) - 1.0f) * 2.0f;
    // a burr or a chip on about one hole in four: a 20-50 micron bump on the
    // edge, extending the hole outward at its left short-edge centre
    if (hash_f(int(hole & 0xFFFFu), seed ^ 0x7u) < 0.25f) {
        // The owner fixes the film leader at s-: pull contact is the left short-edge centre.
        const float2 pb = float2(sc - 0.5f * wa, tc);
        const float sig = 0.020f + 0.030f * hash_f(int(hole & 0xFFFFu), seed ^ 0x9u);
        // Negative signed-distance displacement expands the hole into the film, towards s-.
        const float amp = -(0.006f + 0.010f * hash_f(int(hole & 0xFFFFu), seed ^ 0xBu));
        d += amp * exp(-dot(st - pb, st - pb) / (sig * sig));
    }
    // Extend the existing Gaussian burr/chip at the sprocket's pull-contact point.
    // shortcut: dimensions are visual estimates; calibrate against measured negatives for physical claims.
    const float wear = P[P_SCRATCH_EDGE];
    const float2 contact = float2(sc - 0.5f * wa, tc);
    const float2 qwear = st - contact;
    if (wear > 0.0f && abs(qwear.x) < 0.20f && abs(qwear.y) < 0.18f) {
        const uint ws = uint(P[P_SCRATCH_SEED]) ^ hole ^ 0xD271u;
        if (hash_f(0, ws ^ 0x7u) < 0.75f) {
            const float2 sig = float2(0.025f + 0.020f * hash_f(0, ws ^ 0x8u),
                                      0.035f + 0.040f * hash_f(0, ws ^ 0x9u));
            const float amp = -wear * (0.015f + 0.035f * hash_f(0, ws ^ 0xBu));
            const float2 z = qwear / sig;
            const float end = 1.0f - smoothstep(0.10f, 0.18f, abs(qwear.y));
            d += amp * exp(-dot(z,z)) * end *
                 (0.75f + 0.25f * value_noise(qwear.y / 0.012f, ws ^ 0x77u));
        }
    }
    return d;
}

// How soft a perforation's edge is in a scan, as the sigma of a Gaussian edge
// in film millimetres. Measured on the owner's strips in reference_film/135
// (2026-10-04): across 61-80 hole edges on each of eight scans the edge takes
// 44-71 microns to go from 10 % to 90 % of the hole's light (median 59), at
// 21-32 px/mm -- where this engine's one-pixel edge took 34, and at the full
// tier of a 45 MP frame 5: a knife. Less the scans' own pixels that is a
// sigma of 17 microns: the scanner's lens, and a cut wall 0.13 mm deep that
// is not all in focus at once.
constant float kHoleEdgeSigma = 0.017f;

// erf, Abramowitz and Stegun 7.1.26 (|error| < 1.5e-7).
static float erf_as(float x) {
    const float t = 1.0f / (1.0f + 0.3275911f * fabs(x));
    const float y = 1.0f - (((((1.061405429f * t - 1.453152027f) * t) + 1.421413741f) * t - 0.284496736f) * t + 0.254829592f) * t * exp(-x * x);
    return x < 0.0f ? -y : y;
}

// Where there is film: 1 on the strip, 0 in the perforations and past its edges.
static float film_alpha(float2 st, device const float* P) {
    const float W = P[P_FILM_W], px = P[P_PX];
    // (with no carrier the canvas is the film's width, and the film runs on
    // under the corners a tilted scan carries past its edge)
    float a = P[P_CARRIER] > 1.5f ? 1.0f : clamp(min(st.y, W - st.y) / px + 0.5f, 0.0f, 1.0f);
    if (P[P_PERFORATED] > 0.5f) {
        uint hole;
        // The hole's edge as the scan resolves it: the measured softness, and
        // the pixel's own width (a one-pixel ramp is a sigma of 0.31 px), so a
        // small render is no softer than it was and a large one no harder
        // than film.
        const float sigma = sqrt(kHoleEdgeSigma * kHoleEdgeSigma + 0.0961f * px * px);
        a *= 0.5f + 0.5f * erf_as(perf_sdf(st, P, hole) / (1.41421356f * sigma));
    }
    return a;
}

// Line mask/envelope adapted from FilmDamageSimulator's line_scratch;
// see third_party/film_damage_simulator. Geometry uses this engine's film mm.
static float scratch_line(float2 st, float2 center, float len, float width, float angle, uint seed) {
    const float2 axis = float2(cos(angle), sin(angle));
    const float2 q = st - center;
    const float along = dot(q, axis);
    if (abs(along) >= 0.5f * len) return 0.0f;
    const float across = dot(q, float2(-axis.y, axis.x));
    const float fade = smoothstep(0.0f, min(0.15f, len * 0.15f), 0.5f * len - abs(along));
    const float envelope = smoothstep(0.25f, 0.65f, value_noise((along + len) / max(0.12f, len * 0.09f), seed));
    return exp(-0.5f * across * across / (width * width)) * fade * envelope;
}

static float scratch_mask(float2 st, device const float* P) {
    const uint seed = uint(P[P_SCRATCH_SEED]);
    float2 other = st; other.x -= P[P_PAIR_ADV];
    const float gate = min(gate_sdf(st, P), P[P_PAIR_ADV] > 0.0f ? gate_sdf(other, P) : 1e6f);
    if (gate < 0.10f || st.y <= 0.0f || st.y >= P[P_FILM_W]) return 0.0f;
    uint hole;
    if (perf_sdf(st, P, hole) < 0.07f) return 0.0f;
    const float along_span = P[P_GW] + P[P_PAIR_ADV];
    float mask = 0.0f;
    // Three neighboring tracks share a band, while their starts/ends differ.
    for (int i = 0; i < 12; ++i) {
        if (hash_f(i, seed ^ 0x101u) >= P[P_SCRATCH_LONG]) continue;
        const int group = i / 3;
        const bool top = hash_f(group, seed ^ 0x202u) < 0.5f;
        const float offset = 0.28f + 0.65f * hash_f(group, seed ^ 0x303u) + float(i % 3) * 0.07f;
        const float t = top ? P[P_GT0] - offset : P[P_GT0] + P[P_GH] + offset;
        const float ss = P[P_GS0] + along_span * hash_f(i, seed ^ 0x404u);
        const float len = along_span * (0.3f + 0.8f * hash_f(i, seed ^ 0x505u));
        const float w = sqrt(pow(0.009f + 0.0105f * hash_f(i, seed ^ 0x606u), 2.0f) + 0.0961f * P[P_PX] * P[P_PX]);
        mask = max(mask, scratch_line(st, float2(ss,t), len, w, 0.0f, seed ^ uint(i + 1)));
    }
    return mask;
}

// ④: where there is no film -- the perforations, and outside the strip --
// the negative's density goes to the cmy that cancels this film's base, so
// the enlarger or the scanner sees clear light.
kernel void spk_overscan_film_present(device const float* cmy [[buffer(0)]],
                                      device const float* P [[buffer(1)]],
                                      device const uint* n [[buffer(2)]],
                                      device float* out [[buffer(3)]],
                                      uint3 tid [[thread_position_in_grid]]) {
    const uint i = tid.x;
    if (i >= n[0]) return;
    const uint cw = uint(P[P_CW]);
    const float a = film_alpha(canvas_to_film(float(i % cw), float(i / cw), P), P);
    float3 c = float3(cmy[3u * i], cmy[3u * i + 1u], cmy[3u * i + 2u]);
    if (P[P_SCRATCH_STRENGTH] > 0.0f && P[P_PERFORATED] > 0.5f && a > 0.999f) {
        // shortcut: neutral density approximates scratch obstruction; calibrate against measured wear before claiming a physical model.
        const float wear = scratch_mask(canvas_to_film(float(i % cw), float(i / cw), P), P);
        c += 0.90f * P[P_SCRATCH_STRENGTH] * wear;
    }
    const float3 hole = float3(P[P_HOLE_C], P[P_HOLE_M], P[P_HOLE_Y]);
    const float3 r3 = a * c + (1.0f - a) * hole;
    out[3u * i] = r3.x;
    out[3u * i + 1u] = r3.y;
    out[3u * i + 2u] = r3.z;
}

// ⑤ (RFC-032 §30.5, §31): the scan's view of the holes. Inside a hole: the
// picture's own white (holes = white) or a black backing (holes = black).
// Around it, the cut wall: the punch shears the top of the base clean and
// fractures the rest at a slant, and a scan seen a little off-axis sees the
// wall on the side away from its axis. Seen from above, that is a band where
// the base thins from full to nothing -- brown through the orange mask on a
// white hole, a dim warm rim around a black one. Each hole's slant is its
// own; the viewing tilt and parallax are the scan's. Linear output RGB,
// after the scanner's blur and sharpening (the edge's softness is `film_alpha`'s).
kernel void spk_overscan_light(device const float* rgb [[buffer(0)]],
                               device const float* P [[buffer(1)]],
                               device const uint* n [[buffer(2)]],
                               device float* out [[buffer(3)]],
                               uint3 tid [[thread_position_in_grid]]) {
    const uint i = tid.x;
    if (i >= n[0]) return;
    const uint cw = uint(P[P_CW]);
    const float2 st = canvas_to_film(float(i % cw), float(i / cw), P);
    const float a = film_alpha(st, P);
    const bool white = P[P_HOLES_LIGHT] > 0.5f;
    float3 light = float3(P[P_LIGHT_R], P[P_LIGHT_G], P[P_LIGHT_B]);
    float3 c = float3(rgb[3u * i], rgb[3u * i + 1u], rgb[3u * i + 2u]);
    if (P[P_PERFORATED] > 0.5f) {
        uint hole;
        const float d = perf_sdf(st, P, hole);
        // The cut is not a perfectly vertical knife: the base is a little rounded
        // where the punch went through, and a scan sees that as a soft shoulder
        // just outside the hole -- measured on the owner's reference at 1-2 px
        // of 0.03 mm, lifting the black by ~1-5 % (linear), a faint olive-warm,
        // and not the same on every side or every hole. Inside, a few edges
        // carry a faint cream line. Subtle on purpose (RFC-032 §31.5).
        const uint seed = uint(P[P_PERF_SEED]);
        const int h = int(hole & 0xFFFFu);
        if (d > -0.03f && d < 0.15f) {
            const float e = 0.003f;
            uint hh;
            const float2 g = float2(perf_sdf(st + float2(e, 0), P, hh) - perf_sdf(st - float2(e, 0), P, hh),
                                    perf_sdf(st + float2(0, e), P, hh) - perf_sdf(st - float2(0, e), P, hh));
            const float2 nrm = g / max(length(g), 1e-6f);
            const float2 vdir = float2(P[P_WALL_VS], P[P_WALL_VT]);
            // how much this stretch of this hole's outline shows: per hole, patchy
            // along the outline, a little more on the side the scan leans to
            const float per_hole = 0.4f + 0.6f * hash_f(h, seed ^ 0xE1u);
            const float patch = smoothstep(0.25f, 0.75f, 0.5f * (value_noise(st.x / 0.35f, seed ^ uint(h)) +
                                                                 value_noise(st.y / 0.35f, seed ^ uint(h) ^ 0x3Cu)));
            const float side = 0.6f + 0.8f * max(0.0f, dot(nrm, vdir));
            const float k = per_hole * patch * side;
            // the base's tint, mostly washed out
            const float3 tint = mix(float3(1.0f), float3(P[P_BASE_R], P[P_BASE_G], P[P_BASE_B]), 0.3f);
            const float lam = P[P_WALL_SCATTER];
            if (P[P_SCRATCH_EDGE] > 0.0f && abs(d) < 0.06f) {
                const uint ws = uint(P[P_SCRATCH_SEED]) ^ hole ^ 0xC010u;
                const float patch = smoothstep(0.25f, 0.75f, 0.5f * (value_noise(st.x / 0.20f, ws) +
                                                                             value_noise(st.y / 0.20f, ws ^ 0x33u)));
                // Existing spectral base transmittance: a narrow absorptive colour mark, not added light.
                const float amount = 0.65f * P[P_SCRATCH_EDGE] * patch * exp(-abs(d) / 0.018f);
                const float3 filter = mix(float3(1.0f), clamp(float3(P[P_BASE_R], P[P_BASE_G], P[P_BASE_B]), 0.01f, 1.0f), amount);
                // Output-space conversion can leave negative channels; absorption must not lift them.
                if (d >= 0.0f) c -= max(c, 0.0f) * (1.0f - filter);
                else light *= filter;
            }
            if (d >= 0.0f) {
                const float lift = P[P_WALL_GLOW] * k * exp(-d / lam);
                c += lift * tint * (white ? light : float3(1.0f));
            } else if (white && hash_f(h, seed ^ 0xE4u) < 0.5f) {
                light *= 1.0f - 0.12f * k * (1.0f - tint) * exp(d / 0.012f);
            }
        }
        if (white && d >= 0.0f) {
            // a faint flare from the hole's light into the film, on some holes
            const float fl = 0.012f * hash_f(h, seed ^ 0xC4u) * step(0.5f, hash_f(h, seed ^ 0xC5u));
            c += fl * exp(-d / 0.025f) * light;
        }
    }
    // Past the film's long edges is the scan's carrier, not a hole: black, or
    // the scan's open light.
    const float W = P[P_FILM_W], px = P[P_PX];
    const float on_strip = P[P_CARRIER] > 1.5f ? 1.0f : clamp(min(st.y, W - st.y) / px + 0.5f, 0.0f, 1.0f);
    const float in_film = on_strip > 0.0f ? a / on_strip : 0.0f;
    const float3 r3 = mix(float3(P[P_CARRIER]), mix(light, c, in_film), on_strip);
    out[3u * i] = r3.x;
    out[3u * i + 1u] = r3.y;
    out[3u * i + 2u] = r3.z;
}
