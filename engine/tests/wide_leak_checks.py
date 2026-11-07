"""Wide texture looks through the shipping C ABI/Metal pipeline."""
from pathlib import Path
import struct,tempfile,ctypes
import numpy as np
from spk_ctypes import Engine,EngineError,SpkResult

ROOT=Path(__file__).resolve().parents[1]
BASE=dict(auto_exposure=False,grain_active=False,glare_active=False,halation_active=False,
          output_color_space='sRGB',wide_leak_depth=.28,wide_leak_scale=1.2,wide_leak_seed=1)
with tempfile.TemporaryDirectory() as directory,Engine() as engine:
    folder=Path(directory)
    # A tiny original test texture keeps CI independent of the private source material.
    texture=np.zeros((64,128,3),np.uint16)
    ramp=np.clip((.65-np.arange(128)/127)/.2,0,1)
    texture[:]=np.rint(ramp[None,:,None]*65535).astype(np.uint16)
    path=folder/'test.spkleak';path.write_bytes(struct.pack('<4sIIIIf',b'SPKL',1,128,64,0,.5)+texture.astype('<u2').tobytes())
    source=np.full((800,1600,3),.035,np.float32)
    def render(**extra):
        with engine.open(source,dict(BASE,wide_leak_texture=str(path),**extra)) as session:return session.render('full')[0]
    schema={f['name']:f for f in engine.params_schema()['fields']}
    assert schema['wide_leak_active']['layer']=='print'
    clean=render(wide_leak_active=False)
    # Inactive/zero strength never read a missing file.
    with engine.open(source,dict(BASE,wide_leak_active=True,wide_leak_strength=0.,wide_leak_texture='/not/a/texture')) as session:
        assert np.array_equal(clean,session.render('full')[0])
    gains=[];white=[]
    for strength in [0.,.25,.5,.75,1.]:
        image=render(wide_leak_active=True,wide_leak_strength=strength)
        if strength==0:assert np.array_equal(clean,image)
        delta=np.abs(image[...,:3].astype(float)-clean[...,:3])
        gains.append(delta.mean());white.append(np.all(image[...,:3]>65000,axis=2).mean())
        assert np.array_equal(image[:,int(image.shape[1]*.8):],clean[:,int(clean.shape[1]*.8):]),'dark texture tinted the unaffected region'
    print('mean change / white fraction by strength:',gains,white,flush=True)
    assert np.all(np.diff(gains)>0)
    assert white[-1]>.1 and white[-1]>white[-2]+.02,'100% is not substantially white'
    full=render(wide_leak_active=True,wide_leak_strength=1.)
    assert np.array_equal(full,render(wide_leak_active=True,wide_leak_strength=1.))
    assert not np.array_equal(full,render(wide_leak_active=True,wide_leak_strength=1.,wide_leak_seed=29))
    mirrored=render(wide_leak_active=True,wide_leak_strength=1.,wide_leak_direction=1)
    np.testing.assert_allclose(full[:,::-1],mirrored,atol=2)
    for direction in [2,3]:assert not np.array_equal(full,render(wide_leak_active=True,wide_leak_strength=1.,wide_leak_direction=direction))
    assert not np.array_equal(full,render(wide_leak_active=True,wide_leak_strength=1.,wide_leak_softness=1.))
    for depth in [.1,.5]:assert not np.array_equal(full,render(wide_leak_active=True,wide_leak_strength=1.,wide_leak_depth=depth))
    for space in ['Display P3','ProPhoto RGB']:
        image=render(wide_leak_active=True,wide_leak_strength=1.,output_color_space=space)
        assert np.all(image[...,:3]>65000,axis=2).mean()>.1,('white core not neutral/white',space)
    def direct_di(session):
        fn=engine._lib.spk_render_digital_intermediate
        fn.restype=ctypes.c_int32
        fn.argtypes=[ctypes.c_void_p,ctypes.POINTER(SpkResult),ctypes.POINTER(ctypes.c_char_p)]
        result,metadata=SpkResult(),ctypes.c_char_p()
        status=fn(session._handle,ctypes.byref(result),ctypes.byref(metadata))
        if status:raise EngineError(engine._last_error())
        image=session._take_result(result);engine._take_json(metadata)
        return image
    with engine.open(source,dict(BASE,wide_leak_active=False,wide_leak_texture=str(path))) as session:
        session.render('full')
        di_before=direct_di(session)
        lut_di_before=session.export_di('kodak_portra_endura')[0]
        reply=session.set_params({'wide_leak_active':True,'wide_leak_strength':1.})
        assert reply['invalidated']=='print'
        image,result=session.render('full',reprint=True)
        assert result.negative_was_cached,'texture edit re-exposed the film'
        exported,_=session.render('full',reprint=True)
        assert np.array_equal(full,image) and np.array_equal(full,exported)
        assert np.array_equal(di_before,direct_di(session)), 'scan overlay altered the direct DI'
        assert np.array_equal(lut_di_before,session.export_di('kodak_portra_endura')[0]), 'scan overlay altered the LUT DI'
    # Do not colour empty perforations or the carrier when the film edge is present.
    options=dict(wide_leak_active=False,overscan_active=True,overscan_format='135_full_67',overscan_holes='white',overscan_fog=0.,overscan_leaks=0.)
    white_back=render(**options);holes=np.all(white_back[...,:3]>65000,axis=2)
    inside=holes.copy()
    for axis in [0,1]:
        for shift in [-8,8]:inside &= np.roll(holes,shift,axis=axis)
    black=render(**dict(options,overscan_holes='black'))
    lit=render(**dict(options,overscan_holes='black',wide_leak_active=True,wide_leak_strength=1.))
    assert inside.any() and np.max(np.abs(lit[inside].astype(int)-black[inside].astype(int)))<=2,'wide light filled the holes'
    for bad in [{'wide_leak_strength':1.1},{'wide_leak_direction':1.5},{'wide_leak_seed':0}]:
        try:render(**bad)
        except EngineError:pass
        else:raise AssertionError(('bad parameter accepted',bad))
    for unsupported in [dict(digital_intermediate=True),dict(striped=True)]:
        try:
            with engine.open(source,dict(BASE,wide_leak_active=True,wide_leak_strength=1.,wide_leak_texture=str(path),**unsupported)) as session:session.render('full')
        except EngineError as error:assert 'wide light leaks' in str(error),str(error)
        else:raise AssertionError(('unsupported mode silently accepted',unsupported))
    for bad_bytes in [b'',struct.pack('<4sIIIIf',b'SPKL',1,0,3,0,0.),struct.pack('<4sIIIIf',b'SPKL',1,4096,4096,0,.5)]:
        broken=folder/'broken.spkleak';broken.write_bytes(bad_bytes)
        try:
            with engine.open(source,dict(BASE,wide_leak_active=True,wide_leak_strength=1.,wide_leak_texture=str(broken))) as session:session.render('full')
        except EngineError:pass
        else:raise AssertionError('malformed texture accepted')
    print('PASS directions, bounds, seeds, white output spaces, print caching, holes, export and malformed files',flush=True)
    materials=ROOT/'resources/local_light_leaks'
    for number in [11,14,28,36,42,17]:
        material=materials/f'{number:02d}.spkleak'
        if not material.exists():
            print('SKIP private material absent:',number,flush=True);continue
        with engine.open(source,dict(BASE,wide_leak_active=True,wide_leak_strength=1.,wide_leak_texture=str(material))) as session:image,_=session.render('full')
        white_fraction=np.all(image[...,:3]>65000,axis=2).mean()
        print('private material',number,'white fraction at 100%',round(white_fraction,4),flush=True)
        assert white_fraction>.001,(number,'maximum did not reach white')
    source=np.full((1800,3600,3),.035,np.float32)
    baseline={}
    with engine.open(source,BASE) as session:
        for tier in ['live','full']:baseline[tier]=session.render(tier)[0]
    gains=[]
    with engine.open(source,dict(BASE,wide_leak_active=True,wide_leak_strength=.75,wide_leak_texture=str(path))) as session:
        for tier in ['live','full']:
            image,_=session.render(tier);gains.append(np.abs(image[...,:3].astype(float)-baseline[tier][...,:3]).mean())
    ratio=gains[0]/gains[1];assert abs(ratio-1)<.05,ratio
    print('PASS live/full intensity',round(ratio,3),flush=True)
