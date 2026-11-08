# FrameMatter 2.0 staged validation

## A — TIFF recipes (2026-11-09)

- Ordinary TIFF retains LZW by default and offers uncompressed output. Current recipe-store checks cover compression surviving save/reload and old recipes retaining LZW. Current branch: 39 recipe/metadata tests passed, zero skips or unexpected failures.
- Writer checks cover 16-bit samples, compression tags 1/5, ICC, timestamps, preview pages and atomic replacement. Previous named-recipe CLI/MCP checks remain applicable; no product code changed in this stage.
- GUI acceptance remains **unverified**: selecting the separately identified verification app through computer use did not return and was cancelled. No compression control or save/reopen interaction was observed. The verification process used an isolated Foundation user directory and a copied photograph; no real user recipe was edited.
- This stage does not claim true-window or quit/relaunch acceptance. Detailed logs and samples are private. Earlier integrated result: 635 total, 559 passed, 73 missing-fixture skips plus 2 opt-in skips, 1 existing expected failure, 0 unexpected failures.
