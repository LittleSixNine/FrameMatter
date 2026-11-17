# SPDX-FileCopyrightText: 2026 LittleSixNine
# SPDX-License-Identifier: GPL-3.0-or-later
"""Native factory-exposure contract; synthetic controls, no historical fixtures.

Use --library/--resources to run against a frozen binary. The pre-change engine
fails the new-field assertion before any render; the opt-in split additionally
has to pass optical invariance controls, not merely produce different pixels.
"""
import argparse
import numpy as np
from spk_ctypes import Engine, EngineError
from spk_test_paths import add_engine_arguments, engine_options

KEY = 'overscan_factory_separate_halation'
BASE = dict(product_defaults=True, auto_exposure=False, grain_active=False,
            glare_active=False, overscan_active=True, overscan_format='135',
            overscan_edge_text='KODAK PORTRA 400', overscan_frame_number=15,
            overscan_camera_seed=3, overscan_frame_seed=5, overscan_fog=0., overscan_leaks=0.)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_engine_arguments(parser)
    args = parser.parse_args()
    black = np.zeros((800, 1200, 3), np.float32)
    with Engine(**engine_options(args)) as engine:
        fields = {f['name']: f for f in engine.params_schema()['fields']}
        assert KEY in fields, 'missing independent factory exposure field'
        field = fields[KEY]
        assert field['type'] == 'bool' and field['layer'] == 'shoot' and field['default'] is False

        def render(image=black, **extra):
            with engine.open(image, dict(BASE, **extra)) as session:
                return session.render('full')[0]

        original = render()
        assert np.array_equal(original, render(**{KEY: False})), 'missing must equal explicit off'
        independent = render(**{KEY: True})
        assert not np.array_equal(independent, original), 'control has no factory exposure signal'
        for name, end in [('lens_blur_um', 200.), ('halation_amount', 3.), ('halation_scatter_amount', .8)]:
            for on in (False, True):
                a = render(**{KEY: on, name: 0.})
                b = render(**{KEY: on, name: end})
                assert np.array_equal(a, b) == on, (name, on, 'factory isolation failed')
        print('PASS schema, neutral off and factory optical isolation', flush=True)

        assert not np.array_equal(independent, render(**{KEY: True, 'grain_active': True})), 'grain bypassed factory'
        assert not np.array_equal(render(**{KEY: True, 'dir_couplers_active': False}), independent), 'DIR bypassed factory'
        for date in (False, True):
            config = dict(overscan_active=False, date_imprint_active=date, date_imprint_text='88 8 8')
            assert np.array_equal(render(**config), render(**config, **{KEY: True})), 'date-only path changed'
        print('PASS common development/grain and untouched date-only path', flush=True)

        with engine.open(black, dict(BASE, **{KEY: True})) as session:
            a, _ = session.render('full')
            reprinted, _ = session.render('full', reprint=True)
            assert np.array_equal(a, reprinted), 'reprint lost independent exposure'
            assert session.set_params({KEY: False})['invalidated'] == 'shoot'
            off, _ = session.render('full')
            assert np.array_equal(off, original), 'off reused stale separated negative'
            session.set_params({KEY: True})
            on, _ = session.render('full')
            assert np.array_equal(on, independent), 'on retained original negative'
        for on in (False, True):
            with engine.open(black, dict(BASE, striped=True, strip_rows=37, **{KEY: on})) as session:
                try:
                    session.render('full')
                except EngineError as error:
                    assert 'not supported by the striped executor' in str(error)
                else:
                    raise AssertionError('overscan striped unsupported combination was silently accepted')
                session.set_params({'striped': False})
                recovered, _ = session.render('full')
                assert np.array_equal(recovered, independent if on else original), 'refusal poisoned session state'
        print('PASS SHOOT invalidation, deterministic reprint and explicit striped refusal/recovery', flush=True)


if __name__ == '__main__':
    main()
