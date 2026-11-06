"""Seeded film-border scratches: actual Metal output and geometry exclusion."""
import numpy as np
from spk_ctypes import Engine, EngineError

BASE = dict(auto_exposure=False, grain_active=False, glare_active=False, halation_active=False,
            overscan_active=True, overscan_format='135', overscan_fog=0., overscan_leaks=0.,
            film_format_mm=36.)
with Engine() as engine:
    def render(width=1800, height=1200, **extra):
        with engine.open(np.full((height,width,3),.18,np.float32),dict(BASE,**extra)) as s:
            image,_=s.render('full')
            geometry=s.overscan_geometry()
            return image,geometry

    for width,height,fmt,pair in [(1800,1200,'135',False),(1200,1800,'135',False),
                                  (1200,1600,'135_half',False),(1850,1200,'135_half',True)]:
        options=dict(overscan_format=fmt,overscan_pair=pair)
        bare,g=render(width,height,**options)
        zero,_=render(width,height,**options,scratch_active=True,scratch_strength=0.)
        assert np.array_equal(bare,zero),'zero strength altered the output'
        none,_=render(width,height,**options,scratch_active=True,scratch_long_lines=0.,scratch_short_scuffs=0.)
        assert np.array_equal(bare,none),'zero density altered the output'
        ys,xs=np.indices(bare.shape[:2]);px=np.stack([(xs+.5)/bare.shape[1],(ys+.5)/bare.shape[0]],axis=-1)
        for kind in ('long','short','both'):
            params=dict(options,scratch_active=True,scratch_strength=1.,scratch_long_lines=float(kind!='short'),
                        scratch_short_scuffs=float(kind!='long'),scratch_seed=17)
            worn,_=render(width,height,**params)
            again,_=render(width,height,**params)
            assert np.array_equal(worn,again),'seeded pattern moved between identical renders'
            assert not np.array_equal(worn,bare),('no visible scratches',fmt,kind)
            changed=np.max(np.abs(worn.astype(int)-bare.astype(int)),axis=2)>2
            for gate in g['gates']:
                q=np.array(gate).reshape(4,2)
                crosses=[]
                for i in range(4):
                    edge=q[(i+1)%4]-q[i]
                    cross=(px[...,0]-q[i,0])*edge[1]-(px[...,1]-q[i,1])*edge[0]
                    crosses.append(cross/np.linalg.norm(edge))
                cr=np.stack(crosses)
                inside=(np.all(cr>.01,axis=0)|np.all(cr<-.01,axis=0))
                assert not changed[inside].any(),('scratch entered picture',fmt,kind)
            hole=np.all(bare[...,:3]>65000,axis=2)
            assert not changed[hole].any(),('scratch entered white perforation',fmt,kind)
        other,_=render(width,height,**dict(params,scratch_seed=18))
        assert not np.array_equal(worn,other),'another seed had no effect'
        print('PASS border-only long/short scratches, rotation/pair, zero bypass and repeatability:',fmt,width,height,pair,flush=True)

    bare,_=render(1200,900,overscan_format='120_645')
    worn,_=render(1200,900,overscan_format='120_645',scratch_active=True,scratch_strength=1.)
    assert np.array_equal(bare,worn),'unsupported 120 format gained scratches'
    bare,_=render(1200,800,overscan_active=False)
    worn,_=render(1200,800,overscan_active=False,scratch_active=True,scratch_strength=1.)
    assert np.array_equal(bare,worn),'scratch rendered without film edge'
    with engine.open(np.full((1200,1800,3),.18,np.float32),dict(BASE,scratch_active=True,scratch_seed=17)) as s:
        full,_=s.render('full'); reprint,_=s.render('full',reprint=True)
        assert np.array_equal(full,reprint),'export changed the scratch pattern'
    for name,values in [('scratch_strength',(-.01,1.01)),('scratch_long_lines',(-.01,1.01)),
                        ('scratch_short_scuffs',(-.01,1.01)),('scratch_seed',(0,2147483648))]:
        for value in values:
            try: render(600,400,**{name:value})
            except EngineError: pass
            else: raise AssertionError(('invalid scratch parameter accepted',name,value))
    print('PASS format gating, export and parameter validation',flush=True)
