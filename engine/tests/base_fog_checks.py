# SPDX-FileCopyrightText: 2026 LittleSixNine
# SPDX-License-Identifier: GPL-3.0-or-later
"""Film-base fog's neutral path, bounds, spatial ownership and negative lifetime."""
import argparse
import numpy as np
from spk_ctypes import Engine, EngineError
from spk_test_paths import add_engine_arguments, engine_options

KEY = 'overscan_base_fog'
BASE = dict(product_defaults=True, film_stock='kodak_portra_400', print_stock='kodak_supra_endura',
            auto_exposure=False, grain_active=False, glare_active=False, overscan_active=True,
            overscan_format='135', overscan_edge_text='KODAK PORTRA 400', overscan_frame_number=15,
            overscan_camera_seed=3, overscan_frame_seed=5, overscan_fog=1., overscan_leaks=0.)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_engine_arguments(parser)
    args = parser.parse_args()
    image = np.full((800, 1200, 3), .184, np.float32)
    with Engine(**engine_options(args)) as engine:
        fields = {f['name']: f for f in engine.params_schema()['fields']}
        assert KEY in fields, 'missing base-fog field'
        f = fields[KEY]
        assert f['type'] == 'float' and f['layer'] == 'shoot' and f['default'] == 0 and f['range'] == [0, 1]

        def render(**extra):
            with engine.open(image, dict(BASE, **extra)) as s:
                out, _ = s.render('full')
                return out, s.overscan_geometry()

        zero, geometry = render()
        assert np.array_equal(zero, render(**{KEY: 0.})[0]), 'missing must equal explicit zero'
        on, geometry_on = render(**{KEY: 1.})
        assert geometry == geometry_on, 'base exposure changed gate/hole geometry'
        assert not np.array_equal(on, zero), 'nonzero base exposure is disconnected'
        for date in (False, True):
            p = dict(overscan_active=False, date_imprint_active=date, date_imprint_text='88 8 8')
            assert np.array_equal(render(**p)[0], render(**p, **{KEY: 1.})[0]), 'bare/date-only path changed'
        print('PASS schema, neutral zero, geometry and bare/date-only ownership', flush=True)

        quiet = dict(halation_active=False, dir_couplers_active=False, lens_blur_um=0.)
        a, g = render(**quiet)
        b, _ = render(**quiet, **{KEY: 1.})
        h, w = a.shape[:2]
        # Deep inside the real gate, away from penumbra and scanner neighbourhoods.
        gate = np.asarray(g['gates'][0]).reshape(4, 2)
        lo = np.ceil(gate.min(0) * [w, h] + 80).astype(int)
        hi = np.floor(gate.max(0) * [w, h] - 80).astype(int)
        assert np.all(hi > lo), 'picture-interior control is empty'
        assert np.array_equal(a[lo[1]:hi[1], lo[0]:hi[0]], b[lo[1]:hi[1], lo[0]:hi[0]]), 'base fog exposed the picture interior'
        white, _ = render(overscan_holes='white')
        white_on, _ = render(overscan_holes='white', **{KEY: 1.})
        hole = np.all(white[..., :3] == 65535, axis=2)
        # Erode to genuine hole interiors; the wall may change through shared optics.
        for axis in (0, 1):
            for shift in (-5, 5): hole &= np.roll(hole, shift, axis)
        assert hole.sum() > 100 and np.array_equal(white[hole], white_on[hole]), 'base fog filled actual holes'
        print('PASS picture interior and empty hole interiors', flush=True)
        r = [round(3795*w/7330), round(590*h/6766), round(4041*w/7330), round(710*h/6766)]
        x0, y0, x1, y1 = r
        grain_zero = render(grain_active=True)[0][y0:y1, x0:x1, :3].astype(float) - zero[y0:y1, x0:x1, :3]
        grain_on = render(grain_active=True, **{KEY: 1.})[0][y0:y1, x0:x1, :3].astype(float) - on[y0:y1, x0:x1, :3]
        assert grain_on.std((0, 1))[1] > grain_zero.std((0, 1))[1], 'existing grain did not become more visible'
        print('PASS existing grain response on the clean rebate', flush=True)

        with engine.open(image, BASE) as s:
            s.render('full')
            assert s.set_params({KEY: 1.})['invalidated'] == 'shoot'
            rendered, _ = s.render('full')
            assert np.array_equal(rendered, on), 'stale negative survived base edit'
            assert np.array_equal(rendered, s.render('full', reprint=True)[0]), 'reprint lost base fog'
            before = s.get_params()
            try:
                s.set_params({'print_exposure': 2., KEY: 1.01})
            except EngineError:
                pass
            else:
                raise AssertionError('out-of-range base fog accepted')
            assert s.get_params() == before, 'invalid mixed patch partially applied'
            s.set_params({KEY: 0.})
            assert np.array_equal(s.render('full')[0], zero), 'zero did not restore old negative'
        print('PASS SHOOT invalidation, reprint, bounds and atomic refusal', flush=True)


if __name__ == '__main__':
    main()
