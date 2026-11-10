#!/usr/bin/env python3
"""Native adaptive input/geometry checks; optional bit-exact pre-change seven-meter baseline."""
from pathlib import Path
import argparse,copy,json,os
import numpy as np
from spk_ctypes import Engine,EngineError

P=dict(input_color_space='ProPhoto RGB',input_cctf_decoding=False,auto_exposure=True,
       grain_active=False,halation_active=False,glare_active=False,product_defaults=True)
METHODS=['balanced','center','protect_highlights','protect_shadows','center_weighted','average','median']

def metadata(a,faces):
    return dict(version=1,width=a.shape[1],height=a.shape[0],detector='vision-face-v3-tile-v1',faces=faces)

def independent(y,faces):
    h,w=y.shape;y=np.maximum(y.astype(float),.184/4096);flat=y.flatten();n=flat.size
    rank=lambda q:float(np.partition(flat,q*(n-1)//1000)[q*(n-1)//1000])
    trim=flat[(flat>=rank(10))&(flat<=rank(990))];eb=-np.log2(np.exp(np.log(trim).mean())/.184)
    smooth=lambda t:np.clip(t,0,1)**2*(3-2*np.clip(t,0,1))
    area=float(smooth((np.log2(flat/.184)+eb-2.5)/.5).mean());scene=eb-float(smooth((area-.005)/.025))*min(max(np.log2(rank(995)/.184)+eb-2.5,0),2)
    eligible=[]
    for i,f in enumerate(faces):
        x,y0=np.clip(f['x'],0,1),np.clip(f['y'],0,1);fw=np.clip(f['x']+f['width'],0,1)-x;fh=np.clip(f['y']+f['height'],0,1)-y0
        if f['confidence']>=.6 and fw*w>=16 and fh*h>=16:eligible.append((-(fw*fh),x,y0,i,fw,fh))
    if not eligible:return scene
    _,x,y0,_,fw,fh=min(eligible);x0,x1=np.ceil([(x+.2*fw)*w,(x+.8*fw)*w]).astype(int);y0p,y1=np.ceil([(1-y0-.8*fh)*h,(1-y0-.2*fh)*h]).astype(int)
    sample=y[max(y0p,0):min(y1,h),max(x0,0):min(x1,w)].flatten()
    if not sample.size:return scene
    mid=float(np.partition(sample,(sample.size-1)//2)[(sample.size-1)//2]);old=max(scene,min(np.log2(.184*np.sqrt(2)/mid),eb+1))
    return old+min(.5,max(0,eb-old))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--library');parser.add_argument('--resources');parser.add_argument('--baseline-library');parser.add_argument('--baseline-resources');parser.add_argument('--report');args=parser.parse_args()
    for key in list(os.environ):
        if key.startswith('FRAMEMATTER_'):os.environ.pop(key)
    a=np.full((256,256,3),.184/64,np.float32);a[:26]=1;a[128:230,40:180]=.184/2
    face=dict(x=.25,y=.25,width=.25,height=.25,confidence=.9);rows=[]
    with Engine(library=args.library,resources=args.resources)as e:
        assert e.capabilities()['meter_face_input']==dict(version=1,detector='vision-face-v3-tile-v1',method='adaptive')
        for faces in [[],[face],[dict(face,confidence=.599)]]:
            with e.open(a,dict(P,auto_exposure_method='adaptive'),faces=metadata(a,faces))as s:
                solved=s.solve('exposure');ev=solved['solved_params']['exposure_compensation_ev'];expected=independent(a[...,0],faces)
                assert abs(ev-expected)<1e-9,(ev,expected);assert abs(solved['exposure_ev_by_method']['adaptive']-ev)<1e-12
                s.render('full');rows.append(dict(case='fresh native adaptive equation',faces=len(faces),EV=ev))
        # A cached legacy reading must not hide missing evidence on a later switch.
        with e.open(a,dict(P,auto_exposure_method='balanced'))as s:
            old=s.solve('exposure');assert 'adaptive'not in old['exposure_ev_by_method'];s.render('full');s.set_params(dict(auto_exposure_method='adaptive'))
            for operation in [lambda:s.solve('exposure'),lambda:s.render('full')]:
                try:operation()
                except EngineError as exc:assert 'face evidence'in str(exc)
                else:raise AssertionError('missing evidence accepted after legacy cache hit')
            s.set_params(dict(auto_exposure=False,exposure_compensation_ev=1.25));s.render('full')
            for target in ['exposure','both']:
                manual=s.solve(target);assert 'exposure_compensation_ev'not in manual['solved_params'];assert set(METHODS).issubset(manual['exposure_ev_by_method'])
                assert s.get_params()['exposure_compensation_ev']==1.25
                if target=='both':assert 'm_filter_neutral'in manual['solved_params']
        rows.append(dict(case='legacy cache then adaptive missing evidence rejects solve/render; AE-off manual renders'))
        valid=metadata(a,[face]);bad=[]
        for key,value in [('version',2),('width',255),('height',0),('detector','wrong'),('faces',[face]*4097)]:
            v=copy.deepcopy(valid);v[key]=value;bad.append(v)
        for key,value in [('x',-.1),('width',0),('confidence',1.1),('height',float('nan'))]:
            v=copy.deepcopy(valid);v['faces'][0][key]=value;bad.append(v)
        v=copy.deepcopy(valid);del v['faces'][0]['y'];bad.append(v)
        entries=e.capabilities()['backend']['session_cache']['entries']
        for v in bad:
            try:
                with e.open(a,dict(P,auto_exposure_method='adaptive'),faces=v):pass
            except EngineError:pass
            else:raise AssertionError('invalid face evidence accepted')
            assert e.capabilities()['backend']['session_cache']['entries']==entries
        rows.append(dict(case='invalid evidence leaves no registered half-session',cases=len(bad)))
        # Independently pre-cropped/turned pixels and boxes agree with engine-owned geometry.
        for geom,physical,boxes in [
            (dict(geometry_quarter_turns=1),np.rot90(a,-1).copy(),[dict(face,x=.25,y=.5)]),
            (dict(geometry_flip_h=True),a[:,::-1].copy(),[dict(face,x=.5)]),
            (dict(geometry_crop_x=.25,geometry_crop_y=0,geometry_crop_w=.5,geometry_crop_h=.75),a[:192,64:192].copy(),[dict(face,x=0,y=0,width=.5,height=1/3)]),
        ]:
            with e.open(a,dict(P,auto_exposure_method='adaptive',**geom),faces=metadata(a,[face]))as s:transformed=s.solve('exposure')['solved_params']['exposure_compensation_ev'];s.render('full')
            with e.open(physical,dict(P,auto_exposure_method='adaptive'),faces=metadata(physical,boxes))as s:direct=s.solve('exposure')['solved_params']['exposure_compensation_ev'];s.render('full')
            assert abs(transformed-direct)<1e-9,(geom,transformed,direct);rows.append(dict(case='geometry equivalence',geometry=geom,EV=direct))
        if args.baseline_library:
            rng=np.random.default_rng(14);colored=np.exp(rng.normal(-2,1,(128,192,3))).astype(np.float32)
            with Engine(library=args.baseline_library,resources=args.baseline_resources)as old:
                assert e.params_schema()==old.params_schema(),'shared schema/defaults changed'
                for name,image,decode in [('neutral',a,{}),('colored',colored,{}),('encoded-colored',np.clip(colored,0,1),dict(input_color_space='sRGB',input_cctf_decoding=True))]:
                    for method in METHODS:
                        params=dict(P,auto_exposure_method=method,**decode)
                        with old.open(image,params)as s:reference=s.solve('exposure');pixels=s.render('full')[0]
                        for faces in [None,metadata(image,[])]:
                            with e.open(image,params,faces=faces)as s:
                                got=s.solve('exposure');actual=s.render('full')[0]
                            assert reference['solved_params']==got['solved_params']
                            for key,val in reference['exposure_ev_by_method'].items():assert got['exposure_ev_by_method'][key]==val
                            assert np.array_equal(pixels,actual),(name,method,faces is not None)
                rows.append(dict(case='seven old methods against pre-change binary, two inputs, old/new ABI',render_comparisons=42,bit_exact=True))
    result=dict(status='PASS',checks=rows,external_python_oracle='not exercised by this native regression test')
    if args.report:Path(args.report).write_text(json.dumps(result,indent=2)+'\n')
    print('PASS',len(rows),'adaptive native controls; old-seven baseline',bool(args.baseline_library))
if __name__=='__main__':main()
