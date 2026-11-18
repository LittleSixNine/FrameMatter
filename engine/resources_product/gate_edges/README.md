# Measured gate-edge silhouettes

Eight monochrome edge assets, four sides from each of two anonymous source groups supplied by the product owner. No source photograph pixels, people, scenery or identifying metadata are distributed. Source photographs remain outside this repository.

`profiles.json` is the canonical contour data, 1024 inward offsets per edge. Side order is top, right, bottom, left. Coordinates are normalised to a **36×24 reference opening**, expressed in reference mm; these are not calibrated measurements of the cameras' physical apertures. Scan rotation/straight-line slope is removed. Reliable light/dark boundary segments from multiple photographs are combined; ambiguous scene intrusions, dust spikes and incomplete edges are excluded or repaired. The final 2% at each end tapers to zero for seamless independent corner joins. Corners use a small neutral radius, rather than claiming an exact reconstruction of the original corners.

`g1-s0.png` ... `g2-s3.png` are reusable black/white silhouette strips derived only from the contour coordinates. White denotes the open/photo side. The strip width spans 36 reference mm for top/bottom and 24 for left/right; the normal offsets use the same pixel scale. These are individual edge strips, not complete frame masks.

`engine/src/pipeline/gate_edges.h` embeds the same arrays so rendering requires neither a runtime file loader nor Python. Four sides are selected independently using the saved gate seed (zero follows the frame seed). Reprints, reopening and export reuse that seed. Existing explicit legacy gate values remain accepted; the app's automatic gate uses `sampled`, and Another Frame returns legacy shapes to measured random composition. Native `auto` remains compatible. Full-width exposed film bypasses the gate; cinema-specific formats retain their existing physical gate behaviour.

Regenerate the compiled header after editing the canonical data: `python3 engine/tools/gen_gate_edges.py`. The generator validates sample counts, bounds, endpoints and side coverage before writing.

Source: product owner-provided scans, 2026-11-18. Detailed extraction diagnostics and source mapping remain in the private development records.

Four sample lengths use divisors 1/2/3/4. Each source edge and its start position are independently drawn from the saved gate seed; zero seed preserves the frame-seed behaviour above. The UI offers a continuous 1.0×–4.0× normal-depth slider. Changing depth preserves the saved gate seed, sample divisor and camera/frame seeds. Another Frame retains depth and redraws the seed, divisor and advance. Reprint, reopening and export do not draw anything. Shorter samples stretch along the edge independently of the selected depth multiplier; sample length alone does not guarantee a roughness ranking.
