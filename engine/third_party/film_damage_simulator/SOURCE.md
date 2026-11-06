# Film border scratch masks

Shape reference: Daniela Ivanova, John Williamson and Paul Henderson,
FilmDamageSimulator (Eurographics 2023), MIT, copyright Daniela Ivanova 2022.
https://github.com/daniela997/FilmDamageSimulator
https://github.com/daniela997/FilmDamageSimulator/blob/main/damage_generator/generate_masks.py

The native shader adapts line_scratch's thin-line times low-frequency
noise envelope, Gaussian softness and random length. It uses SpektraLab's
existing seeded value noise instead of the Python Perlin/image buffers.
The placement adapts the source's nonuniform artifact placement into
small groups of parallel friction scratches along a film edge, constrained by the existing gate and hole
geometry. No reference images or external datasets are bundled.

The neutral optical-density offset is an explicit first-version approximation
of light obstructed at a scratch. It reuses the existing CMY-density to
print/scan path, not a physically calibrated emulsion-loss or refractive model.
It does not copy the unlicensed ComfyUI-Darkroom implementation.
The user's two scan crops (2026-11-06) guide fine grouped lines and sparse
scuffs, not their orange negative colour or the central coloured stripes.

Perforation-edge marks reuse SpektraLab's existing `perf_sdf` roughness and
Gaussian burr/chip geometry. They do not use FilmDamageSimulator to claim
that a scan colour fringe is wear, and they do not amplify the light kernel.
Additional wear dimensions are visual estimates from the owner's crops,
not measured calibration; the hole centres and pitch stay unchanged.

Pull-contact burrs are restricted to the left short-edge centre per the
owner's fixed film-leader direction. Additional edge colour uses the existing
spectral base transmittance as absorption, with no glow or invented RGB fringe.

Pull deformation expands the hole towards the leader (negative signed-distance
displacement); it does not push a film-coloured spike into the hole. Both the
baseline tiny deformation and extra seeded wear follow this convention.
