# FrameMatter 2.0 staged validation

## A — TIFF recipes (2026-11-09)

- Ordinary TIFF retains LZW by default and offers uncompressed output. Current recipe-store checks cover compression surviving save/reload and old recipes retaining LZW. Current branch: 39 recipe/metadata tests passed, zero skips or unexpected failures.
- Writer checks cover 16-bit samples, compression tags 1/5, ICC, timestamps, preview pages and atomic replacement. Previous named-recipe CLI/MCP checks remain applicable; no product code changed in this stage.
- GUI acceptance remains **unverified**: selecting the separately identified verification app through computer use did not return and was cancelled. No compression control or save/reopen interaction was observed. The verification process used an isolated Foundation user directory and a copied photograph; no real user recipe was edited.
- This stage does not claim true-window or quit/relaunch acceptance. Detailed logs and samples are private. Earlier integrated result: 635 total, 559 passed, 73 missing-fixture skips plus 2 opt-in skips, 1 existing expected failure, 0 unexpected failures.

## B — resident full → proof → TIFF → return (2026-11-09)

Two isolated real-host runs used the same copied 7008×4672 RAW: normal grain/glare and a deterministic control with both disabled. Both passed, zero skips. Proof and ordinary export each issued one full reprint and no decode; after another frame developed, returning displayed the cached print without decoding or waiting for a full render.

The default resident full and repeated full reprint had different hashes. Reusing that resident texture would freeze an existing stochastic redraw and change the current product behavior. The deterministic control matched, but a single non-default condition is insufficient evidence for a generally useful cache. **No new reuse path was added.** This avoids changing glare/grain semantics or admitting ambiguous pairs, DI or film edges. Timings below are individual observations, not benchmark medians.

- default: proof 816.2 ms / 0 decode / 1 full reprint, export 2575.2 ms / 0 decode / 1 full reprint, return 41.4 ms / 0 decode / 0 full reprint.
- deterministic: proof 820.0 ms / 0 decode / 1 full reprint, export 2319.2 ms / 0 decode / 1 full reprint, return 9.3 ms / 0 decode / 0 full reprint.

## C — eight-range HSL (2026-11-09)

- Native rail controls use eight colour selectors and the existing scrub sliders. Hue anchors wrap continuously through red; neutral HSL is an exact bypass. HSL operates on encoded ProPhoto after tone/colour balance, before curves. Grey and non-target ranges stay unchanged; excess values from preceding exposure survive until the existing final clamp.
- Old sidecars load zero HSL; new values roundtrip. A new explicit Post-Dev clipboard group is off by default, and copies the complete grade only when selected. CLI/MCP share 24 bounded schema fields, readback and whole-patch refusal. Undo/redo restores a single-frame grade without film reprocessing.
- 24 targeted model/schema/clipboard/GPU checks passed without skips, including red continuity, skin/saturated samples, tiny edits after out-of-range exposure, and 4/8 local masks. Global HSL has its own uniform block; existing mask size is unchanged, and oversized mask arrays use a Metal buffer.
- One additional opt-in real-RAW workflow passed with zero skips: 7008×4672, no extra decode or render during grade/undo/redo, saved named uncompressed TIFF, ICC/compression readback, full RGB16 soft-proof/file hash equality. This controlled comparison disables grain/glare without changing defaults. The test was run directly with its RAW environment after xcodebuild correctly skipped it without that opt-in.
- True-window HSL interaction is not claimed; the computer-use limitation in A remains.
