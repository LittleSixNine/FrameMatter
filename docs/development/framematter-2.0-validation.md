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
