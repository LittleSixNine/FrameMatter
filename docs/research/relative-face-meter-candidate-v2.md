# Relative highlight and primary-face candidate v2 — frozen research equation

Frozen before implementation/rendering on 2026-11-09. This is one independent research candidate, not a product default. It never reads a v1 result, image identity, manual ROI or preference table. The RAW interpretation has shadow bias zero; baseline exposure, decoder exposure and white balance remain unchanged. There is no RAW +1 operation or local tone mapping.

Use the real balanced meter's scene-linear luminance sample `Y`, its width/height and unchanged reading `Eb`. Set `g=0.184`, clamp `Y` below `g/4096` exactly as the existing meter does, and use `S(t)=clamp(t,0,1)^2*(3-2*clamp(t,0,1))`. Percentile rank is exact integer division `995*(N-1)/1000`.

```
T = log2(Y/g) + Eb
A = mean S((T - 2.5)/0.5)
wA = S((A - 0.005)/0.025)
H = log2(P99.5(Y)/g) + Eb - 2.5
R = wA * clamp(H, 0, 2)
Escene = Eb - R
```

There is no gate on the absolute value of `Eb`. The endangered-highlight interval is gray +2.5..3 stops after balanced placement. Area at or below 0.5% has zero influence; 3% has full influence. The global highlight budget is 2 EV. These constants are frozen for all photographs. The same 16 photographs informed the design and are an exploratory, non-blind comparison, not an independent validation set.

Apple Vision detects rectangles on the actual upright, perspective-adjusted display decode, downscaled to a 1600-pixel long edge. This display rendering is used only to locate faces. The independent linear decode remains the film/meter input, with identical extent and geometry. Export metadata orientation is not applied a second time. Full-frame/default geometry is required for this experiment; nonneutral crop/rotation/mirroring is unsupported.

Clip Vision normalized bottom-left boxes to the unit square. Eligible boxes have confidence at least 0.6 and width and height at least 16 pixels in the actual meter sample. Choose the largest clipped area; equal areas use ascending normalized x, then y. This primary-face rule deliberately does not let the darkest small background face decide the frame. Retain each box's central 60% (inset 20% per side). Convert to top-row-first meter coordinates with `x0=ceil((x+.2*w)*W)`, `x1=ceil((x+.8*w)*W)`, `y0=ceil((1-y-.8*h)*H)`, `y1=ceil((1-y-.2*h)*H)` and use half-open ranges clipped to image bounds. `F` is the integer-rank median `(N-1)/2` of the same floored linear `Y` samples in that rectangle.

```
Eface = log2(g * 2^0.5 / F)
EfaceBound = min(Eface, Eb + 1)
E2 = max(Escene, EfaceBound)       # valid selected face
E2 = Escene                       # no eligible face / empty face sample
```

The face target is gray +0.5 EV, with at most +1 EV lift relative to balanced. It is a box-luminance hypothesis, not skin segmentation or a claim of accurate skin tone. Eye sockets, hair, facial shadows, detection errors and background within the box can influence it. The face bound takes priority over highlight protection, so a detected face can make signs or sky brighter; undetected faces receive only the scene rule. A single global exposure cannot guarantee both bright highlights and dark subjects remain legible.

For fixed detected boxes and samples that do not cross the existing luminance floor, scaling input by `k` and shifting `Eb` by `-log2(k)` leaves `T/A/H/R` unchanged and shifts `Eface/Escene/E2` by that same amount. Vision detection itself can change with input appearance; the complete detection pipeline is not claimed to be exposure invariant. Uniform dark scenes and isolated lights no larger than 0.5% retain balanced exposure without a face bound.

The isolated build will record all detections, selected box/sample pixels, face median/raw and budgeted target, original balanced EV, A/wA/P99.5/H/R/Escene/E2, actual downstream native EV, compensation and runtime product print-exposure compensation. Fresh source copies/homes and fresh decoder traces are mandatory. Original candidate v1 and the previous shadow-zero/frozen-EV B outputs are byte-copied references with hash verification, not freshly simulated arms. No thresholds will be retuned after viewing this batch.

## Isolated integration and checks

The existing `engine/tools/build_balanced_highlight_experiment.py` copies the current working tree to a fresh external temporary directory and adds the v2 integration only there. Set `FRAMEMATTER_RELATIVE_FACE_CANDIDATE=1`, `FRAMEMATTER_RAW_SHADOW_BIAS=0`, `FRAMEMATTER_BALANCED_FACE_INFO` to a per-source private JSON path and `FRAMEMATTER_BALANCED_FACE_SOURCE` to the copied RAW's absolute path. Candidate v1, fixed offset and frozen EV must all be disabled/unset. Both experimental print and engine meter cache identities include v2 and face-file identity; RAW decode identity stays unchanged, so fresh source/home and process-launch-fixed shadow mode remain mandatory.

Before returning the decoded frame, the temporary Swift decoder writes the actual Vision input PNG and source/extent/revision/duration/box metadata atomically. Only AE with the balanced method reads the file in the engine. Manual and other-meter modes, including the startup's centre-weighted warmup, do not require it. A successful Vision request with an empty array is the legitimate no-face branch; request failure, missing/invalid file, missing box fields or mismatched source/extent fail the research run. The engine permits only neutral full-frame geometry, preventing a stale face box from being applied through an unmodelled crop/turn.

The private batch at `pravite/02-研究与实验/相对测光候选v2-20261109/` completed all 16 new default-look previews through the normal CLI and kept byte-verified copies of both previous reference arms. Its manifests retain the frozen-equation hash, build/runtime hashes, all detected boxes, actual meter dimensions, sampled face rectangle, native applied EV, zero user compensation and runtime `print_exposure_compensation=false`. The 1600-pixel detection PNG is explicitly rendered as sRGB; it is evidence of the detector input, not the linear film input or final effect.

Pure-function checks cover negative controls, scene/face budgets, confidence and minimum-size boundaries, primary-face selection, non-symmetric bottom-left-to-top-first mapping in landscape and portrait, fixed-box exposure covariance and invalid luminance. A library linked from the actual application's C++ objects passed 14 additional v2 controls: startup/other-meter/manual behavior without a face file, same-session face-cache transitions, malformed/missing/wrong-source refusal and mutually exclusive research modes. The earlier 13 frozen-EV and 16 offset compatibility controls also passed against the same build. These narrow research gates do not claim the full app suite, general face-detection accuracy or an independent validation set.
