# FrameMatter 2.0 staged validation

## A — TIFF recipes (2026-11-09)

- Ordinary TIFF retains LZW by default and offers uncompressed output. Current recipe-store checks cover compression surviving save/reload and old recipes retaining LZW. Current branch: 39 recipe/metadata tests passed, zero skips or unexpected failures.
- Writer checks cover 16-bit samples, compression tags 1/5, ICC, timestamps, preview pages and atomic replacement. Previous named-recipe CLI/MCP checks remain applicable; no product code changed in this stage.
- GUI acceptance remains **unverified**: selecting the separately identified verification app through computer use did not return and was cancelled. No compression control or save/reopen interaction was observed. The verification process used an isolated Foundation user directory and a copied photograph; no real user recipe was edited.
- This stage does not claim true-window or quit/relaunch acceptance. Detailed logs and samples are private. Earlier integrated result: 635 total, 559 passed, 73 missing-fixture skips plus 2 opt-in skips, 1 existing expected failure, 0 unexpected failures.

## B — resident full → proof → TIFF → return (2026-11-09)

Two isolated real-host runs used the same copied 7008×4672 RAW: normal grain/glare and a deterministic control with both disabled. Both passed, zero skips. Proof and ordinary export each issued one full reprint and no decode; after another frame developed, returning displayed the cached print without decoding or waiting for a full render.

The default resident full and repeated full reprint had different hashes. Reusing that resident texture would freeze an existing stochastic redraw and change the current product behavior. The deterministic control matched, but a single non-default condition is insufficient evidence for a generally useful cache. **No new reuse path was added.** This avoids changing glare/grain semantics or admitting ambiguous pairs, DI or film edges. No simultaneous system-load sample was captured for these two probes; the timings below are individual observations, not benchmark medians or speedup evidence.

- default: proof 816.2 ms / 0 decode / 1 full reprint, export 2575.2 ms / 0 decode / 1 full reprint, return 41.4 ms / 0 decode / 0 full reprint.
- deterministic: proof 820.0 ms / 0 decode / 1 full reprint, export 2319.2 ms / 0 decode / 1 full reprint, return 9.3 ms / 0 decode / 0 full reprint.

## C — eight-range HSL (2026-11-09)

- Native rail controls use eight colour selectors and the existing scrub sliders. Hue anchors wrap continuously through red; neutral HSL is an exact bypass. HSL operates on encoded ProPhoto after tone/colour balance, before curves. Grey and non-target ranges stay unchanged; excess values from preceding exposure survive until the existing final clamp.
- Old sidecars load zero HSL; new values roundtrip. A new explicit Post-Dev clipboard group is off by default, and copies the complete grade only when selected. CLI/MCP share 24 bounded schema fields, readback and whole-patch refusal. Undo/redo restores a single-frame grade without film reprocessing.
- 24 targeted model/schema/clipboard/GPU checks passed without skips, including red continuity, skin/saturated samples, tiny edits after out-of-range exposure, and 4/8 local masks. Global HSL has its own uniform block; existing mask size is unchanged, and oversized mask arrays use a Metal buffer.
- One additional opt-in real-RAW workflow passed with zero skips: 7008×4672, no extra decode or render during grade/undo/redo, saved named uncompressed TIFF, ICC/compression readback, full RGB16 soft-proof/file hash equality. This controlled comparison disables grain/glare without changing defaults. The test was run directly with its RAW environment after xcodebuild correctly skipped it without that opt-in.
- True-window HSL interaction is not claimed; the computer-use limitation in A remains.

## D — RAW perspective (2026-11-09)

- Two axes (±30°) correct both linear RAW and original display after decoding, before film and simulated film borders. The centred projection preserves the source size and fills the frame. Zero is an exact image-object bypass; older edits decode zero. Existing post-crop geometry is applied once as before.
- Settings live under `decode.perspective`, are part of RAM/decode/print identity, and support saved edits, undo/redo, shared schema/readback and whole-patch rejection. An explicit RAW Perspective clipboard group is off by default and skips non-RAW targets. Cache-only encoding omits neutral perspective, retaining the historical display and ordinary-print keys; sidecar/schema readback remains complete. No old edit/default look changes.
- Pairs normalize both source axes to zero before decoding and use that normalized cache identity. Saved hole/source values remain intact. A real RAW saved with nonzero correction and then composed as a pair matches the neutral pair in a 2048-pixel display readback (both cache arms cleared), and retains its original single-frame setting.
- Real 7008×4672 RAW re-decoded after correction; the single-crop TIFF was 5606×3738, 16-bit with the requested ICC. A full film output was 5860×5413 with neutral post-geometry. At 2048×1892, factory-lettering bounds were exactly [229,12,1199,87] for zero/nonzero perspective while the inner region changed (mean absolute normalized RGB difference 0.09986). This is an independently located lettering ROI, not just an identity flag. Date was enabled and visually present, but its geometry was not independently located/measured.
- Regression also covers all four corners and inverse maps across 25 axis combinations, actual Core Image coordinate pixels, cache keys and optional-copy behavior. Post-Dev clipboard application now updates the renderer directly and avoids a film render for grade-only copies, covered by the real HSL workflow.
- Early probe failures came from a decode-only test entrance, a black-hole/black-base threshold that could not locate perforations, and a test-only CPU read of a private texture. The accepted test uses a real develop request, a factory-text ROI and shared readback textures; none of those failed attempts count as acceptance.

D final gate: 32 targeted checks passed with zero skips or failures, plus an application build. The final integrated gate is recorded below after all stages.

### D follow-up — preserve neutral cache identity

Independent review requested preserving existing hits for photographs without perspective. Two new regressions first failed with 5 assertions: historical display/live/full key strings changed and two stored values missed. The cache-only Codable view now omits zero perspective while including both axes at nonzero values. Normal sidecar/MCP encoding is unchanged. Seven perspective/cache checks passed without skips, including reads of values stored under the frozen pre-perspective keys.

## Research — scene curve before film (2026-11-09)

A private controlled study used one fixed scene-linear photograph and a synthetic gray/colour control, with the same optical engine, fixed exposure and stochastic stages disabled. Six optical renders and two bit-identical baseline returns completed; an isolated probe used the current local Metal Layer 2 for a post curve matched to the gray response. Six native TIFFs passed full RGB16/ICC readback and all view PNGs used the same sRGB conversion/profile.

The selected before/after curves produced similar overall tone but different colour/local transitions. The gray match still had a residual, and one scene does not establish universal fidelity or benefit. This supports keeping the two stages conceptually distinct; it does not justify a new default or a production scene-curve control in this round. No image, private path or one-off study probe is included in the public target.

## Final integration

Final functional source: `900e1b9` on `development/framematter-2.0`. The built application passed its build. XCTest: **652 total = 576 passed + 75 skipped + 1 existing expected failure; 0 unexpected failures**. Skips are 73 unavailable original fixtures and 2 opt-in cases; the new real-RAW HSL/perspective and original RAW cache regression actually ran with a copied input in an isolated user directory. The existing expected failure is the uncropped histogram. DiagnosticsTests retains a QoS runtime warning.

A 650-test integration had already passed before review requested neutral-key compatibility; the final 652-test integration was necessary because that follow-up changed code and added two regressions. Native GPU smoke against the actual application's Metal library passed, and the fast-math guard rejected unsafe math while accepting the shipped safe library. No full Python-oracle parity or cross-Mac/Linux acceptance is claimed. GUI save/reopen remains unverified, and the date glyph did not receive an independent geometry ROI check. No commit was pushed or published; the separate startup-tool work on main was left intact.

## Supplemental live-window and geometry acceptance (2026-11-09)

The earlier GUI/date “unverified” statements in A, C and Final integration describe the previous acceptance attempt. The following later checks supersede those specific gaps; they do not add a true-window HSL interaction claim.

Using a separately identified copy of the current built application and an isolated user directory, computer use created a named TIFF recipe in the real export window: 16-bit, Display P3, uncompressed, original size. The UI automatically saved it. A normal Command-Q ended the first process; a new process with a different PID reopened the application. Manually selecting the existing named recipe restored every setting without editing compression again. The complete saved recipe and UUID matched before/after. Clicking Export in that reopened window succeeded for one photograph with no skips or failures. The actual TIFF independently read back as 7008×4672, 16-bit, Compression=1, one page, with ICC bytes matching system Display P3 and a nonblank full pixel decode. Private evidence retains process IDs, the actual output, raw window-tool results and metadata readback.

The independent [RAW perspective geometry acceptance](raw-perspective-geometry-validation.md) closes the date/perforation geometry gap for the measured RAW and settings: perforation positions and the actual date coverage mask remain fixed. Faint date-fringe output changes with the underlying photograph; this does not claim every exported date-adjacent pixel is identical.

This supplement changes documentation only. No new full test run, cross-machine acceptance, main-branch merge, push or release is claimed.

## Three-RAW comparison against SpektraLab 2.2.0

FrameMatter’s development executable and the official SpektraLab 2.2.0 application each exported three fresh RAW edits and three edits with matched Gold 200 / Portra Endura optical controls. Image readback confirmed full-size 16-bit Display P3 TIFFs in both orientations. A single-setting experiment in FrameMatter showed that its balanced meter, which measured +6.55 EV on the night scene, substantially brightened the illuminated signs and reduced highlight detail relative to manual 0 EV.

With identical scene-linear inputs, the two optical engines matched at all 15 directly comparable float boundaries and in the final 16-bit output for both tested stock pairs. Within the upstream Portra 400 / Portra Endura experiment, enabling minilab first changed the paper CMY densities. Doubling print exposure and changing the magenta filter affected the optical control but yielded identical minilab output in the tested scene. The upstream new-source decoder and the two applications’ post-processing spaces also produced measurable differences. These observations apply to the three samples and settings tested on one camera model. Private inputs, TIFFs, pixel comparisons and GUI evidence are kept outside public source.

## Opt-in balanced-highlight meter experiment (2026-11-09)

A frozen, image-independent research equation now builds into a separate temporary application through [the experiment tool](../../engine/tools/build_balanced_highlight_experiment.py); ordinary product builds do not include its integration. The candidate smoothly reduces the actual balanced auto-exposure baseline only when both strong lift and a nontrivial endangered-highlight area are present. Exposure compensation, material curves, saved recipes, other meter methods and manual exposure are unchanged. The [v1 equation and thresholds](../research/balanced-highlight-candidate-v1.md) remain experimental; they were not retuned per sample.

Fresh, isolated full-size TIFF exports compared baseline and candidate with deterministic common settings. Two portrait samples retained their respective +2.34 and +2.38 EV readings, and all 32,741,376 RGB16 pixels in each sample matched its baseline exactly. On the night scene, the actual auto-exposure node changed from +6.55 to +0.55 EV with user compensation still zero. Illuminated sign strokes became more distinguishable while more of the road became dark; this is a rendering observation, not a claim of recovering physically clipped source information.

Pure-function checks and real engine checks cover uniform-dark and isolated-light negative controls, positive broad-highlight response, reduction bounds, smooth joins, manual invariance, compensation isolation, and same-session mode/AE/meter-method cache transitions. The temporary app separates ordinary, baseline and candidate print-cache identities; engine traces record measured and actually applied EV. Same-scene bracketed exposures and bright-sign/dark-face mixtures remain necessary before considering a default: continuity in the +3..+5 EV activation interval does not guarantee small output changes. No default replacement, cross-camera generality, merge, push or release is claimed. Private photographs and output evidence remain untracked.

The same frozen candidate was run on 16 RAW files (the original three and 13 additional samples) with default rendering effects enabled. Both arms used fresh, isolated edits and produced 1024 px long-edge previews. Five pairs had different measured and applied exposure, with reductions of 0.07, 0.33, 2.18, 6.00 and 6.00 EV. The other 11 pairs had identical decoded preview pixels. The six previews from the original three photos also reproduced their previous pixels. Both phone DNGs reached the native RAW render path. A backlit portrait shifted by 0.33 EV, while a night street scene with people and illuminated signs stayed at +2.67 EV. This batch checks the default-look previews; it does not establish full-resolution output equality for the additional samples.

For the three-way default-look comparison, the official SpektraLab 2.2.0 application exported the same 16 RAW files (including both phone DNGs) at native resolution. All 16 successful export log entries identified full RAW renders in sRGB, with neither preview sourcing nor resolution capping. Each saved upstream edit used manual film exposure at 0 EV with auto metering off, RAW decoder exposure at +1 EV, and Portra 400 / Portra Endura from the application's last-used stock selection. The two FrameMatter arms used Portra 400 / Supra Endura. The 1024 px viewing images preserve orientation and use sRGB. Only the two FrameMatter arms isolate the effect of changing the meter.
