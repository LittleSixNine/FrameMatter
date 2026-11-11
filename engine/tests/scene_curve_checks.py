# SPDX-FileCopyrightText: 2026 LittleSixNine
# SPDX-License-Identifier: GPL-3.0-or-later
"""Pre-film curve contract, causal exposure order and stale-negative regression."""
import argparse
import numpy as np
from spk_ctypes import Engine, EngineError
from spk_test_paths import add_engine_arguments, engine_options

def main():
    parser=argparse.ArgumentParser(description=__doc__);add_engine_arguments(parser);args=parser.parse_args()
    x=np.linspace(.001,1.4,180*120*3,dtype=np.float32).reshape(120,180,3)
    u=np.linspace(0,1,129);table=np.stack([u,u+.035*np.sin(np.pi*u),u,u,u])
    curve=','.join(format(v,'.9g') for v in table.ravel())
    base=dict(product_defaults=True,auto_exposure=False,grain_active=False,glare_active=False,scan_film=True)
    with Engine(**engine_options(args)) as e:
        f={f['name']:f for f in e.params_schema()['fields']};assert 'scene_curve' in f,'missing scene curve'
        assert f['scene_curve']['default']=='' and f['scene_curve']['layer']=='shoot'
        def render(image=x,**delta):
            with e.open(image,dict(base,**delta)) as s:return s.render('full')[0]
        neutral=render();assert np.array_equal(neutral,render(scene_curve=''))
        changed=render(scene_curve=curve);assert not np.array_equal(neutral,changed)
        # E+1 samples the same curve as doubling scene light before film, not after curve.
        a=render(scene_curve=curve,exposure_compensation_ev=1.);b=render(image=x*2,scene_curve=curve)
        assert np.max(np.abs(a.astype(float)-b.astype(float)))<=2,'curve/exposure order'
        with e.open(x,base) as s:
            first=s.render('full')[0]
            assert s.set_params({'scene_curve':curve})['invalidated']=='shoot'
            assert np.array_equal(s.render('full',reprint=True)[0],changed),'stale negative'
            assert s.set_params({'scene_curve':''})['invalidated']=='shoot'
            assert np.array_equal(s.render('full',reprint=True)[0],first)
            for bad in ['1,2','nan,0','0,1,0,1,0,1,0,1,0,1,','0,1,0,1,0,1,0,1,0']:
                before=s.get_params()
                try:s.set_params({'scene_curve':bad,'exposure_compensation_ev':2.})
                except EngineError:pass
                else:raise AssertionError('invalid curve accepted')
                assert s.get_params()==before,'non-atomic rejected patch'
        assert np.array_equal(changed,render(scene_curve=curve,striped=True,strip_rows=32)),'strip mismatch'
        print('PASS scene schema, empty neutral, visible signal, exposed-stop ordering, SHOOT invalidation, atomic validation, strips')
if __name__=='__main__':main()
