# SPDX-FileCopyrightText: 2026 LittleSixNine
# SPDX-License-Identifier: GPL-3.0-or-later
# Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

"""Offline DMG artwork: sample the existing app engine, then grade its grain residual."""
from pathlib import Path
import json
import subprocess
import sys
import numpy as np
from PIL import Image

here = Path(__file__).resolve().parent
root = here.parents[3]
output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else here
output.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(root / 'engine/tests'))
from spk_ctypes import Engine

subprocess.run(['swift', '-module-cache-path', '/tmp/framematter-swift-cache',
                str(here / 'render-background.swift'), str(output)], check=True)
noise_path = here / 'engine-grain.npy'
if noise_path.exists():
    noise = np.load(noise_path)
else:
    frame = np.full((322, 660, 3), 0.184, np.float32)
    params = dict(film_stock='kodak_portra_400', print_stock='kodak_portra_endura',
                  auto_exposure=False, glare_active=False, grain_active=False,
                  film_format_mm=16.0)
    with Engine(library=root / 'engine/build/libspektrafilm_engine.dylib',
                resources=root / 'engine/resources') as engine:
        print(engine.build_info)
        with engine.open(frame, params) as session:
            off, _ = session.render('full')
            control, _ = session.render('full')
            assert np.array_equal(off, control), 'Grain-off control must reproduce exactly'
            session.set_params({'grain_active': True})
            on, _ = session.render('full')
            noise = (on[..., :3].astype(np.float32) - off[..., :3].astype(np.float32)).mean(axis=2)
    np.save(noise_path, noise)
assert noise.shape == (322, 660) and np.isfinite(noise).all() and noise.std() > 0
field = np.asarray(Image.fromarray(noise).resize((1320, 644), Image.Resampling.BICUBIC))
field = (field - field.mean()) / field.std() * 1.8
base = Image.open(output / 'background@2x.png')
pixels = np.array(base)
original = pixels.copy()
pixels[220:864, :, :3] = np.clip(np.rint(pixels[220:864, :, :3].astype(np.float32) + field[..., None]), 0, 255).astype(np.uint8)
assert np.array_equal(original[:220], pixels[:220])
assert np.array_equal(original[864:], pixels[864:])
result = Image.fromarray(pixels)
result.save(output / 'background@2x.png', dpi=(144, 144), icc_profile=base.info.get('icc_profile'))
result.resize((660, 440), Image.Resampling.LANCZOS).save(output / 'background.png', dpi=(72, 72), icc_profile=base.info.get('icc_profile'))
report = dict(engine='existing native Metal dylib', film='kodak_portra_400',
              paper='kodak_portra_endura', film_format_mm=16, neutral_input=0.184,
              source_shape=list(noise.shape), grayscale_residual=True,
              grain_off_control='bit-exact on first generation',
              target_retina_std_8bit=1.8, header_and_copper_unchanged=True)
(output / 'grain-validation.json').write_text(json.dumps(report, indent=2))
print('PASS: actual engine grain sampled; residual finite and nonzero; header and copper unchanged')

subprocess.run(['tiffutil', '-cathidpicheck', str(output/'background.png'), str(output/'background@2x.png'), '-out', str(output/'background.tiff')], check=True)
