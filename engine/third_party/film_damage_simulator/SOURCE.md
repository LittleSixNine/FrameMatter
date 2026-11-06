# Film border scratch masks

Shape reference: Daniela Ivanova, John Williamson and Paul Henderson,
FilmDamageSimulator (Eurographics 2023), MIT, copyright Daniela Ivanova 2022.
https://github.com/daniela997/FilmDamageSimulator
https://github.com/daniela997/FilmDamageSimulator/blob/main/damage_generator/generate_masks.py

The native shader adapts line_scratch's thin-line times low-frequency
noise envelope, Gaussian softness and random length. It uses SpektraLab's
existing seeded value noise instead of the Python Perlin/image buffers.
The placement adapts the source's nonuniform artifact placement into
small groups along a film edge, constrained by the existing gate and hole
geometry. No reference images or external datasets are bundled.

The neutral optical-density offset is an explicit first-version approximation
of light obstructed at a scratch. It reuses the existing CMY-density to
print/scan path, not a physically calibrated emulsion-loss or refractive model.
It does not copy the unlicensed ComfyUI-Darkroom implementation.
The user's two scan crops (2026-11-06) guide fine grouped lines and sparse
scuffs, not their orange negative colour or the central coloured stripes.
