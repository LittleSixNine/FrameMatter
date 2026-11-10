# Optional factory-lettering exposure — implementation plan

Scope approved 2026-11-10. Work stays on `development/framematter-2.0`; no merge, push or release. Reference is SpektraLab `spektralab-v2.2.0`, specifically `overscan.cpp` factory groups and `Pipeline::film_blurs`.

## Behavior and compatibility

Add one optional film-border setting, off by default for both missing saved fields and new photographs. The disabled path retains the existing computation. Enabled factory marks get their own exposure plane, bypass scene lens blur, use the reference's unit halation/scatter amounts and scales and 0.02 channel-strength multiplier, then rejoin before development/DIR/grain/printing. The 2% factor is a versioned model choice, not a universal measured constant. Retain the reference's master-effect gates; do not claim complete control independence.

Do not change date-back exposure, scene spill, independent leaks, wear, dust, fonts, mark layout, film/paper profiles, RAW interpretation or metering. Preserve FrameMatter attribution and reference provenance. New settings must reach the engine wire, sidecars, undo/redo, existing film-effects clipboard group, shared Agent schema, cache identity, preview/full/export, and the native film-border panel. No new strength sliders.

## Sequence

1. Pin current deterministic disabled-path output and define the additive SHOOT field; verify the factory/date group boundary and strip executor dependencies before editing shared logic.
2. Port the exposure branch with matching lifetime/error handling and correct whole-frame/strip behavior. Do not silently fall back to a different model or unsupported platform implementation. Update wire documentation with its implementation.
3. Connect Swift state, panel, persistence/undo/copy/schema/cache and regression coverage. Preserve neutral cache identity where the existing mechanism allows it.
4. Independently review real RAW before/after samples and runtime consistency, then save stage commits.

## Acceptance

- Disabled mode matches the pre-change deterministic output; no-border and date-only inputs are unchanged.
- Only factory groups are separated. Explicit changes to scene blur/halation demonstrate the intended decoupling; common development and grain remain effective on the marks.
- Whole and striped execution agree within the existing justified bounds, including large halo/carried cases and odd strip boundaries. New auxiliary planes are sliced/assembled and released correctly.
- New settings survive save/reopen and undo/redo, copy with the correct settings group, reject invalid Agent edits atomically, and invalidate the appropriate negative/finished-print identities.
- Preview, full-tier render and an actual output file use the same selected model. Show actual image evidence rather than treating a successful build as visual acceptance.

Run focused native/Swift checks first. Original historical camera fixtures and Python oracle are missing on this machine; use explicitly identified private copies or generated controls and report those limits. Do not rerun a broad suite with known invalid substitute fixtures. Local Metal builds may require normal unsandboxed execution because sandbox compilation misreports toolchain availability.
