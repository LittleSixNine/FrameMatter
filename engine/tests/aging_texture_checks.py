# SPDX-FileCopyrightText: 2026 LittleSixNine
# SPDX-License-Identifier: GPL-3.0-or-later
# Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

"""Screen and geometry checks through the native Metal C ABI; no private assets required."""
from pathlib import Path
import tempfile, struct
import numpy as np
from spk_ctypes import Engine, EngineError

BASE = dict(auto_exposure=False, grain_active=False, glare_active=False, halation_active=False,
            output_color_space='sRGB')
with tempfile.TemporaryDirectory() as directory, Engine() as engine:
    assert 'aging_border_only' in {f['name'] for f in engine.params_schema()['fields']}
    folder = Path(directory)
    def texture(name, pixels):
        path = folder/name
        h,w,_ = pixels.shape
        path.write_bytes(struct.pack('<4sIIIIf', b'SPKL',1,w,h,1,0.) + pixels.astype('<u2').tobytes())
        return str(path)
    solid = np.full((32,48,3), [30000,18000,8000], np.uint16)
    path = texture('solid.spkleak', solid)
    def render(w=180,h=120,**extra):
        source = np.full((h,w,3), .035, np.float32)
        with engine.open(source, {**BASE, "aging_texture": path, **extra}) as session:
            return session.render('full')[0][...,:3]
    clean=render()
    assert np.array_equal(clean,render(aging_active=True,aging_border_only=True,aging_texture='/missing'))
    assert np.array_equal(clean,render(aging_active=True,aging_strength=0,aging_texture='/missing'))
    base=clean.astype(float)/65535
    for strength in [.1,.5,.7,1.]:
        actual=render(aging_active=True,aging_strength=strength).astype(float)/65535
        expected=base+(1-base)*solid[0,0]/65535*strength
        np.testing.assert_allclose(actual,expected,atol=4/65535)
    for w,h,fmt,pair in [(600,400,'135',False),(400,600,'135',False),
                          (740,480,'135_half',True),(400,400,'120_6x6',False),
                          (695,350,'135_full_67',False)]:
        options=dict(overscan_active=True,overscan_format=fmt,overscan_pair=pair,
                     overscan_camera_seed=19,overscan_frame_seed=5,overscan_fog=0.,overscan_leaks=0.,overscan_holes='white')
        bare=render(w,h,**options)
        border=render(w,h,**options,aging_active=True,aging_strength=1.,aging_border_only=True)
        with engine.open(np.full((h,w,3),.035,np.float32),{**BASE,**options}) as session:
            session.render('full')
            g=session.overscan_geometry()
        changed=np.max(abs(border.astype(int)-bare.astype(int)),axis=2)>2
        if fmt=='135_full_67':
            assert not changed.any(), 'fully exposed film acquired an artificial rebate'
            continue
        assert changed.any(), 'border-only aging is invisible'
        ys,xs=np.indices(bare.shape[:2]); px=np.stack([(xs+.5)/bare.shape[1],(ys+.5)/bare.shape[0]],axis=-1)
        for gate in g['gates']:
            q=np.array(gate).reshape(4,2);cr=[]
            for i in range(4):
                e=q[(i+1)%4]-q[i]
                cr.append(((px[...,0]-q[i,0])*e[1]-(px[...,1]-q[i,1])*e[0])/np.linalg.norm(e))
            cr=np.stack(cr); picture=np.all(cr>.02,axis=0)|np.all(cr<-.02,axis=0)
            assert picture.any() and not changed[picture].any(), 'border-only aging entered the exposed photo'
        holes=np.all(bare>65000,axis=2)
        inside=holes.copy()
        for axis in (0,1):
            for shift in (-3,3): inside &= np.roll(holes,shift,axis=axis)
        assert not changed[inside].any(), 'aging entered empty hole interiors'
    print('PASS border-only aging protects landscape/portrait/pair/120 photos and holes; no-edge/full-width bypass')
    # Asymmetric smooth coordinates avoid relying on a private texture or a photographic baseline.
    y,x=np.mgrid[:96,:144]
    grid=np.stack([x/143*.8,y/95*.6,(x/143+y/95)*.2],axis=-1)
    path=texture('coordinates.spkleak',np.rint(grid*65535).astype(np.uint16))
    for w,h in [(180,120),(120,180),(120,120),(160,120),(192,108)]:
        normal=render(w,h,aging_active=True,aging_strength=1.)
        # Mirror axes remain intuitive in both landscape and portrait.
        for flip in [1,2,3]:
            screen_flip = flip
            view=normal[:,::-1] if screen_flip==1 else normal[::-1] if screen_flip==2 else normal[::-1,::-1]
            np.testing.assert_allclose(render(w,h,aging_active=True,aging_strength=1.,aging_flip=flip),view,atol=4)
        rotated=render(w,h,aging_active=True,aging_strength=1.,aging_rotation=2)
        np.testing.assert_allclose(rotated,normal[::-1,::-1],atol=4)
    for turn in [1,3]:
        normal=render(120,120,aging_active=True,aging_strength=1.)
        np.testing.assert_allclose(render(120,120,aging_active=True,aging_strength=1.,aging_rotation=turn),
                                   np.rot90(normal,-turn),atol=4)
    for key in ['aging_rotation','aging_flip']:
        for value in [-1,4,.5]:
            try: render(aging_active=True,**{key:value})
            except EngineError: pass
            else: raise AssertionError((key,value))
    for options in [dict(digital_intermediate=True),dict(striped=True)]:
        try: render(aging_active=True,**options)
        except EngineError: pass
        else: raise AssertionError('unsupported mode accepted')
    # A print-only edit must retain the negative cache; export DI must ignore the appearance.
    source=np.full((120,180,3),.035,np.float32)
    with engine.open(source,{**BASE,'aging_texture':path}) as session:
        before=session.render('full')[0]
        di=session.export_di('kodak_portra_endura')[0]
        session.set_params(dict(aging_active=True,aging_strength=.8,aging_rotation=1,aging_flip=2))
        aged,meta=session.render('full',reprint=True)
        assert meta.negative_was_cached and not np.array_equal(aged,before)
        assert np.array_equal(di,session.export_di('kodak_portra_endura')[0])
        assert np.array_equal(aged,session.render('full',reprint=True)[0])
        session.set_params(dict(aging_active=False))
        assert np.array_equal(before,session.render('full',reprint=True)[0])
    for content in [b'bad',struct.pack('<4sIIIIf',b'SPKL',1,2000,1333,1,0.)]:
        bad=folder/'bad.spkleak';bad.write_bytes(content)
        try: render(aging_active=True,aging_texture=str(bad))
        except EngineError: pass
        else: raise AssertionError('malformed texture accepted')
    print('PASS native Screen curve, zero bypass, five aspects, mirrors/rotations, invalid controls, modes and textures')
