"""Measured gate assets, deterministic native rendering, geometry and bypass."""
import json
from pathlib import Path
import numpy as np
from spk_ctypes import Engine,EngineError
bank=json.loads(Path('engine/resources_product/gate_edges/profiles.json').read_text())
assert len(bank['profiles'])==8
for row in bank['profiles']:
 a=np.array(row['offsets_mm'])
 assert a.size==1024 and np.isfinite(a).all() and abs(a).max()<.5
 assert abs(a[0])<1e-5 and abs(a[-1])<1e-5
 assert np.ptp(a)>.01
base=dict(auto_exposure=False,grain_active=False,glare_active=False,halation_active=False,
 overscan_active=True,overscan_format='135',overscan_gate='sampled',overscan_fog=0.,overscan_leaks=0.,
 overscan_camera_seed=19,overscan_frame_seed=5,output_color_space='sRGB')
with Engine() as engine:
 def render(w=720,h=480,**extra):
  with engine.open(np.full((h,w,3),.035,np.float32),{**base,**extra}) as session:
   image,_=session.render('full');again,_=session.render('full',reprint=True)
   assert np.array_equal(image,again),'reprint rerolled gate'
   return image,session.overscan_geometry()
 for w,h,fmt,pair in [(720,480,'135',False),(480,720,'135',False),(740,480,'135_half',True),(480,480,'120_6x6',False)]:
  im,g=render(w,h,overscan_format=fmt,overscan_pair=pair)
  same,_=render(w,h,overscan_format=fmt,overscan_pair=pair)
  assert np.array_equal(im,same),'reopen changed gate'
  legacy,_=render(w,h,overscan_format=fmt,overscan_pair=pair,overscan_gate='square')
  assert not np.array_equal(im,legacy),'measured contour absent'
  # A constant exposed centre remains identical; only the opening changes.
  y,x=im.shape[0]//2,im.shape[1]//2
  if not pair: np.testing.assert_allclose(im[y-5:y+5,x-5:x+5],legacy[y-5:y+5,x-5:x+5],atol=2)
  print('PASS sampled gate, stable reprint/reopen and geometry:',fmt,w,h,pair,flush=True)
 a,_=render();b,_=render(overscan_frame_seed=6)
 assert not np.array_equal(a,b),'frame randomisation has no effect'
 wide,_=render(695,350,overscan_format='135_full_67')
 oldwide,_=render(695,350,overscan_format='135_full_67',overscan_gate='square')
 assert np.array_equal(wide,oldwide),'fully exposed film acquired an artificial gate'
 try:render(overscan_gate='missing')
 except EngineError:pass
 else:raise AssertionError('invalid gate accepted')
 print('PASS new frame, full-width bypass and validation',flush=True)
