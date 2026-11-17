# Optional CAM16 C_max initialization artifacts

These six native float64 tables were recomputed by FrameMatter's existing serial
`cam16_setup_for` and are byte-identical to SpektraLab 2.2.0's corresponding
artifacts (commit `243d3a362a6443db34109a93b622230699596d68`). No optical,
colour-space, knee, inverse-CAM16 or search mathematics changed.

`engine/build.sh cam16` recomputes them without reading existing artifacts.
It also updates `SHA256SUMS`; then run `engine/build.sh bundle`. A fresh application
build uses the tracked files; it does not run a bake or require a Python oracle.

Only macOS reads qualified artifacts from the engine's actual resource root.
The versioned header checks the colour-space name, current viewing conditions,
matrices, grids and bisection parameters. The reader also checks exact length,
payload checksum, finiteness and bounds. Missing, stale or malformed artifacts
leave the existing serial computation in charge. Linux/Vulkan keeps its original
computation. The existing in-memory setup cache is unchanged.

Serialization and validation come from Hanze Qiu's SpektraLab 2.2.0
`engine/src/core/cam16_bake.hpp`; attribution is retained in the source.
FrameMatter recomputes the tables from its own current implementation and baked
colour-space constants. Existing GPL-3.0-or-later code and spektrafilm data
attribution/CC BY-SA 4.0 terms remain in force; the bundle already carries both
licence texts. Andrea Volpato's profiles and the print LUTs are unchanged.

Validation: `engine/build/cam16_cache_checks engine/resources` or pass the
`Contents/Resources/Resources/engine` directory of an actual built `.app`.
