"""Bake upstream real-scan Dust annotation outlines (stdlib only)."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[2]
base=root/'engine/third_party/film_damage_simulator'
x=json.loads((base/'dust-scan10.json').read_text())
shapes=[(k,v['points']) for k,v in x.items() if v['label']['name']=='Dust' and len(v['points'])>=5][:16]
assert len(shapes)==16
out=['// Derived from FilmDamageSimulator Scan (10).json, Dust polygons; MIT. See third_party/film_damage_simulator/SOURCE.md.','constant uint kDustCounts[16] = {'+', '.join(str(len(p)) for _,p in shapes)+'};','constant float2 kDustShapes[16][14] = {']
for key,pts in shapes:
 xs=[p['x'] for p in pts];ys=[p['y'] for p in pts];scale=max(max(xs)-min(xs),max(ys)-min(ys))/2;cx=(max(xs)+min(xs))/2;cy=(max(ys)+min(ys))/2
 coords=[f'float2({(p["x"]-cx)/scale:.6f}f, {(p["y"]-cy)/scale:.6f}f)' for p in pts]
 coords+=['float2(0.0f)']*(14-len(coords));out.append('    {'+', '.join(coords)+'}, // annotation '+key)
out.append('};')
(root/'engine/src/shaders/dust_shapes.h').write_text('\n'.join(out)+'\n')
