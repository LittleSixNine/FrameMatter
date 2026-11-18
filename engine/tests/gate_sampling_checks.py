"""Gate-only random windows: deterministic persistence, independent positions and legacy full scale."""
from pathlib import Path
import numpy as np
from spk_ctypes import Engine,EngineError
base=dict(auto_exposure=False,grain_active=False,glare_active=False,halation_active=False,
 overscan_active=True,overscan_format='135',overscan_gate='sampled',overscan_fog=0.,overscan_leaks=0.,
 overscan_camera_seed=19,overscan_frame_seed=5,output_color_space='sRGB')
photo=np.full((480,720,3),.035,np.float32)
with Engine() as engine:
 def render(**extra):
  with engine.open(photo,{**base,**extra}) as session:
   image,_=session.render('full');again,_=session.render('full',reprint=True)
   assert np.array_equal(image,again),'reprint changed saved gate'
   return image
 for depth in (1,1.5,2,2.75,3,4):
  image=render(overscan_gate_seed=15,overscan_gate_depth=depth)
  assert np.array_equal(image,render(overscan_gate_seed=15,overscan_gate_depth=depth)), 'depth changed on reopen'
  if depth == 1:
   original=image
   assert np.array_equal(original,render(overscan_gate_seed=15)), 'default depth changed legacy output'
  else:
   assert not np.array_equal(image,original), 'depth had no visible effect'
   h,w=image.shape[:2]
   assert np.array_equal(image[h//3:2*h//3,w//3:2*w//3],original[h//3:2*h//3,w//3:2*w//3]), 'depth changed photo center'
 with engine.open(photo,{**base,'overscan_gate_seed':15}) as session:
  before,_=session.render('full')
  session.set_params(dict(overscan_gate_depth=4))
  changed,_=session.render('full')
  session.set_params(dict(overscan_gate_depth=1))
  restored,_=session.render('full')
  assert not np.array_equal(before,changed) and np.array_equal(before,restored), 'depth update/reset cache stale'
 for gate in ('rounded','square'):
  assert np.array_equal(render(overscan_gate=gate,overscan_gate_depth=1),render(overscan_gate=gate,overscan_gate_depth=4)), 'depth changed a legacy gate'
 saved_photo=photo
 photo=np.full((350,695,3),.035,np.float32)
 assert np.array_equal(render(overscan_format='135_full_67',overscan_gate_depth=1),render(overscan_format='135_full_67',overscan_gate_depth=4)), 'depth changed full-width exposure'
 photo=saved_photo
 print('PASS continuous depths, unchanged center, legacy/full-width bypass, reopen/reprint and update/reset',flush=True)
 for divisor in (1,2,3,4):
  image=render(overscan_gate_seed=15,overscan_gate_sample_divisor=divisor)
  assert np.array_equal(image,render(overscan_gate_seed=15,overscan_gate_sample_divisor=divisor)),'reopen changed gate'
  print('PASS saved seed/length, reprint and reopen:',divisor,flush=True)
 # 15 and 21 select the same four source edges, so only the crop positions can differ.
 assert np.array_equal(render(overscan_gate_seed=15),render(overscan_gate_seed=21))
 assert not np.array_equal(render(overscan_gate_seed=15,overscan_gate_sample_divisor=4),render(overscan_gate_seed=21,overscan_gate_sample_divisor=4)),'window positions stayed fixed'
 default=render()
 assert np.array_equal(default,render(overscan_gate_seed=5,overscan_gate_sample_divisor=1)),'zero seed stopped following frameSeed'
 baseline=Path('/tmp/framematter-gate-sampling-baseline.npy')
 if baseline.exists():assert np.array_equal(default,np.load(baseline)),'legacy complete-length output changed'
 with engine.open(photo,base) as session:
  before,_=session.render('full')
  session.set_params(dict(overscan_gate_seed=15,overscan_gate_sample_divisor=4))
  changed,_=session.render('full')
  session.set_params(dict(overscan_gate_seed=0,overscan_gate_sample_divisor=1))
  restored,_=session.render('full')
  assert not np.array_equal(before,changed) and np.array_equal(before,restored),'live edit/reset cache is stale'
 for key,values in {'overscan_gate_seed':[-1,.5,2147483648], 'overscan_gate_sample_divisor':[0,5,1.5], 'overscan_gate_depth':[0,5]}.items():
  for v in values:
   try:render(**{key:v})
   except EngineError:pass
   else:raise AssertionError((key,v))
 print('PASS random crop positions, legacy output, live update/reset and validation',flush=True)
