"""Prepare user-owned TIFF overlays for local builds; not a runtime dependency."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import numpy as np
from PIL import Image
import tifffile

SELECTED = (11, 14, 28, 36, 42, 17)

def prepare(source, destination):
    destination.mkdir(parents=True, exist_ok=True)
    records = []
    for number in SELECTED:
        path = source / f'Chemlooks-Film-Overlay-{number}.tif'
        raw = tifffile.imread(path)
        if raw.dtype != np.uint16 or raw.ndim != 3 or raw.shape[2] != 3:
            raise ValueError(f'{path.name}: expected 16-bit RGB')
        data = raw.astype(np.float32) / 65535.
        factor = min(1., 1536 / max(data.shape[:2]))
        size = (round(data.shape[1]*factor), round(data.shape[0]*factor))
        data = np.stack([np.asarray(Image.fromarray(data[...,c]).resize(size, Image.Resampling.LANCZOS)) for c in range(3)], axis=2)
        data = np.clip(data, 0, 1)
        luminance = data @ np.array([.2126,.7152,.0722], np.float32)
        floor = np.median(data[luminance <= np.quantile(luminance,.15)], axis=0)
        residual = np.maximum(data-floor,0)
        mask = np.clip((np.max(residual,axis=2)-.015)/(.09-.015),0,1)
        texture = np.clip(residual/(1-floor),0,1) * (mask*mask*(3-2*mask))[...,None]
        front = 0.
        flipped = False
        if number != 17:
            edge = max(2, texture.shape[1]//20)
            flipped = bool(texture[:,-edge:].mean() > texture[:,:edge].mean())
            if flipped: texture = texture[:,::-1].copy()
            profile = np.median(texture @ np.array([.2126,.7152,.0722],np.float32),axis=0)
            active = np.flatnonzero(profile > max(.035,float(profile.max())*.2))
            if not len(active): raise ValueError(f'{path.name}: no light front')
            front = float(active[-1]/(texture.shape[1]-1))
        output = destination / f'{number:02d}.spkleak'
        pixels = np.rint(texture*65535).astype('<u2')
        header = struct.pack('<4sIIIIf', b'SPKL',1,pixels.shape[1],pixels.shape[0],int(number==17),front)
        output.write_bytes(header+pixels.tobytes())
        records.append(dict(number=number,source=path.name,source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                            file=output.name,sha256=hashlib.sha256(output.read_bytes()).hexdigest(),width=pixels.shape[1],height=pixels.shape[0],
                            dark_floor_rgb=floor.tolist(),front_u=front,flipped=flipped))
    (destination/'manifest.json').write_text(json.dumps(dict(version=1,encoding='assumed sRGB',distribution='local development only; redistribution permission not established',materials=records),ensure_ascii=False,indent=2))
    print(f'Prepared {len(records)} local textures at {destination}')

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,default=Path(__file__).resolve().parents[1]/'resources/local_light_leaks')
    args=parser.parse_args()
    prepare(args.source_dir,args.output_dir)
