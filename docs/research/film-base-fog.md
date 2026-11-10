# Optional film-base fog

2026-11-11. Film Edge → Light offers **Film Base Fog / 片基雾化**, one 0–100%
control. It defaults to zero for both existing and new photographs. Zero keeps
the previous rendering and host print-cache stamp; no photograph changes on its own.

Positive strength gives the film outside the picture a uniform exposure in the
existing warm edge-fog colour. It can brighten/warm the rebate and make the film’s
existing grain more visible. At 100%, the added normalized exposure is 0.18.
This is a chosen appearance, not a correction to measured film/paper profiles;
it adds no synthetic grain and changes no RAW or scene-exposure setting.

The new exposure is masked by the real film and the gate, so actual perforation
interiors remain empty. Gate/hole/letter/date positions and sizes are retained.
It proceeds through the shared optics, development, grain and print path:
halation and diffusion may change the picture edge, and lettering/date tones can
change. It does not promise pixel identity across the whole picture with spatial
effects enabled. A full-width image that fills the film has no separate rebate
to fog. Bare and date-only images ignore the control.

The setting saves/reopens, supports undo/redo, copies with Film Effects, and is
available to CLI/MCP as `params.filmEdge.baseFog` (number, 0–1). Invalid mixed
patches are refused atomically. It invalidates the negative and is shared by
preview, full-resolution rendering and export. Overscan’s current explicit
striped/Vulkan refusal remains; there is no fallback renderer.

Validation uses deterministic synthetic controls and a protected real RAW copy.
It does not establish universal material accuracy, performance improvements or
coverage of every film/format/platform. See the additive wire contract in
`API-SPEC-callable-render-service.md` §13.
