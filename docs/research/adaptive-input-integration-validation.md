# Adaptive input integration — 2.0 candidate

2026-11-10. The approved stage-C equation is now available as the `adaptive`
meter. New photos without an existing sidecar use it and `shadowNeutralV1` RAW
interpretation. Existing sidecars retain their meter; a missing interpretation
field remains `legacy`. Changing meter never changes the RAW interpretation.
No material profile was changed. This candidate is not a merged or published
release.

## Completed checks

- Twenty new input/Session/Agent controls passed with no skips: legacy loading,
  new-photo persistence, undo/redo, explicit RAW clipboard ownership/default-off,
  schema atomic refusal of invalid values/face edits, cache separation, successful
  no-face evidence, finite extents, actual RAW shadow-only override, manual
  dormant-adaptive Solve, same-source/framing edit races, current-method EV label,
  canonical pair exposure and invalidation, and undecodable pair holes.
- New RAW shadow behavior, valid Agent decode edits and the asynchronous EV-label
  regression were demonstrated red before their fixes and green afterwards.
- The first frozen production build reproduced 15 of the 16 stage-C applied EVs
  and reference JPEG decoded RGB pixels exactly; photo 14 was initially rejected.
  After the edge-box clip correction, the final frozen build reproduced 14/10/16
  with identical EVs and decoded RGB pixels. Together these checks cover all 16;
  the final build was not rerun over every image. Existing balanced output matched the original product
  control. Valid decode edits before develop and after Custom +1.25 EV survived
  separate-process reopen, including switching both interpretation versions.
- A real window displayed the adaptive/neutral choices and a working canvas.
  Native TIFF export was read back as 4672×7008, unsigned 16-bit RGB, LZW and ROMM
  profile. These observations are not a claim about every scene or platform.

## Test environment and unresolved checks

The one full-suite attempt was **interrupted**, not passed: 444 completed cases
passed, 10 failed and 7 skipped before interruption. The available substitute
smoke was discovered to be **all-black 8-bit RGB, 1000×666**; its size and content
invalidated native-render, color and scene-range premises. The RAW alias was an
ILCE-7CM2 photo, not the original A7 III calibration frame. Original Nikon and
other reference fixtures were absent. No original-fixture full-suite or Python
oracle parity success is claimed.

A concentrated nine-case repetition used a documented non-black 1800×1200 sRGB
synthetic chart and the explicitly identified RAW alias. Six passed without
lowering thresholds: the full-render memory boundary, enlarger-filter visibility,
adaptive latitude with/without film border, both pair decode checks, and zoom
using the source's actual aspect ratio. Thus the initial latitude failure did
not establish a missing-face or material-probe regression.

Three checks remain unresolved:

- Immediate restoration of a resident film-border print failed with both new
  defaults and explicit balanced/legacy controls. The nil-key invalidation branch
  already existed, but this does not establish when the behavior originated.
- The native-WB/cache test failed with both defaults and the same legacy control;
  the available substitute RAW/cache environment does not establish an original
  baseline. This is not reported as a passing native-cache check.
- **The date image-difference check failed under the new defaults, while its
  explicit legacy control passed.** A manual-exposure isolation attempt also
  failed and was reverted. Its cause is undetermined; no date geometry or
  exposure parameter was changed to hide it. The candidate retains this known
  validation gap.

Private evidence, logs and fixture manifests are under
`pravite/04-开发与故障记录/自适应测光正式接入-20261110/`, including `宿主验证/`,
`产品16图/final-verification/` and `窗口验收/`.
