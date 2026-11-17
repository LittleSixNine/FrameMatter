# Optional independent factory-lettering exposure

Implemented on `development/framematter-2.0`, 2026-11-10. This is an explicit
Film Edge option, **off for new photographs and missing saved fields**. It does
not change the accepted default look. API-SPEC §13 defines the wire and
ARCHITECTURE §7.11 describes its host ownership.

## Source and behavior

Adapted from Hanze Qiu's [SpektraLab 2.2.0, commit
243d3a362a6443db34109a93b622230699596d68](https://github.com/JamesQiu2005/SpektraLab/commit/243d3a362a6443db34109a93b622230699596d68),
specifically `engine/src/pipeline/overscan.cpp` factory/date groups and
`pipeline.cpp`'s independent branch in `film_blurs`. The fixed source was read
through GitHub's fetch tool. Existing attribution and material profiles remain.

The option separates only factory groups into a linear exposure plane. The
scene/date exposure still receives scene lens blur and halation. Factory marks
skip that lens blur, use unit halation/scatter amounts and spatial scales, and
0.02 times the current channel return strengths. Both exposures rejoin before
log exposure, development, DIR and grain. Master halation activation and
back-reflection still apply. The 0.02 is upstream look policy, not a measured
universal material constant; the result is not promised to be universally sharper.

Unlike the upstream persistent member, the auxiliary image is local `Chain`
state. It is allocated only for a successfully rasterised factory group and
released after the merge or on an error/cancelled run. Retained auxiliary RGB
float32 storage is 12 bytes per canvas pixel, in addition to temporary blur
working images. It is not stored in session caches or pre-grain checkpoints.

The frozen previous engine explicitly rejects film edge + striped execution.
That existing restriction remains for both option values. An initial trial
showed that adding strip support would also require full-canvas coordinates in
print masks and overlays; that expansion was withdrawn. There is no silent
whole-frame fallback. Vulkan retains its existing explicit overscan rejection.

## Host contract

- Wire: `overscan_factory_separate_halation`, Boolean SHOOT, default false.
- Sidecar/Agent: `params.filmEdge.independentLetteringHalation`.
- Undo/redo and save/reopen use the normal parameter state. Agent shares the
  GUI schema and rejects non-Boolean values before applying edits.
- Only this new leaf joins the Film Effects clipboard group. Format, framing,
  seeds and other Film Edge settings keep their existing exclusion.
- Enabled print stamps identify the new look. False is omitted from the stamp
  to preserve prior disabled-path identities; true → false still sends a
  SHOOT wire delta. Preview, full and export use that same engine setting.

## Focused validation

No historical-fixture full suite was run. Native tests use generated linear
controls; Session tests use a generated PNG in a private temporary directory.

| Gate | Result |
|---|---|
| Frozen old dylib versus new disabled path | 10 independent deterministic cases, decoded pixels exactly equal |
| Independent native compatibility/scope checks | 30 checks passed |
| Independent optical/common-stage/refusal controls | 13 checks passed |
| Independent half-frame pair controls | 6 checks passed |
| `engine/tests/factory_lettering_checks.py` | Old library fails on the missing new field; new library passes isolation, date-only, common DIR/grain, reprint, SHOOT toggle and striped refusal/recovery |
| `FactoryLetteringTests` | 4 passed: defaults/persistence, delta/cache identity, clipboard/schema, actual Session Agent/undo/save/reopen |
| Clipboard ownership, Agent schema, rail layout | 20 passed; one optional menu-image capture skipped because its output directory was not requested |

The initial Session test incorrectly required a decoded image/service-ready
state before explicitly developing a reopened cached preview. Cached previews
intentionally defer decoding; the test now awaits `ensureDeveloped()` directly
on reopen. This changed only the test precondition, not product scheduling.

## Independent real-RAW and live-window acceptance

The final frozen application was tested with an explicitly identified 7008×4672
ILCE-7CM2 sea photograph, not the missing original historical A7 III fixture.
With identical saved settings, disabled-mode sRGB preview RGB and native
7330×6766 TIFF decoded 16-bit RGB exactly matched the frozen previous build.
The enabled setting survived separate-process CLI readback, rejected an invalid
mixed patch atomically, and produced an actual RGB16 unsigned/LZW/ROMM TIFF with
the expected changed pixels. Grain/glare were disabled for this numerical A/B.
The shared Agent field was exercised through CLI; a separate MCP stdio handshake
was not repeated.

An independent GUI application with a private home and RAW copy was also checked
through the actual native window. The option started unchecked, enabled normally,
and was still checked after Cmd-Q/reconnection and reopening the source. Pressing
Develop restored a complete full-tier bordered image. The normal grain/glare
settings were kept in this window check. Reopening initially showed an original
preview before explicit Develop; this does not claim immediate film-border cache
restoration was fixed. No user source or ordinary application preferences changed.
Window snapshots were observed directly in CUA; the TIFF checks used actual CLI
files, not a claim that GUI export was repeated.

The existing GPU smoke check passed with zero failures, and both math-guard
controls passed. No full historical-fixture suite, Python-oracle parity or native
Windows/Vulkan runtime validation is claimed. The auxiliary plane alone occupies
about 568 MiB at the tested TIFF canvas size; total peak memory and workflow speed
were not benchmarked. Normal settings produced a subtle visual difference rather
than a universal sharpness improvement.

Implementation is saved in local commit `eb32c77`; plan and acceptance records
are saved separately. No main-branch merge, push or release was performed.

Private reproducible scripts, frozen binaries, logs and image comparisons live
under `pravite/04-开发与故障记录/工厂片边字独立曝光-20261110/`.
