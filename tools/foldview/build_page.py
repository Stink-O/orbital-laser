#!/usr/bin/env python3
"""build_page.py OUTDIR: frames of the moments from several cameras (one sprite per camera) and the metrics' heatmaps, as data for the Fold evidence page. Run sections on demand."""
import sys,json,pathlib
sys.path.insert(0,__file__.rsplit('/',1)[0])
from fv import *
from PIL import Image
def sprites(out,scene,vs,times,w=360,h=202,patch=None,tag=''):
    V=views(scene); a=[f'w={w}',f'h={h}']+scene.args()
    for v in vs:
        for t in times: a+=['--',f't={t}']+[f'{k}={x}' for k,x in V[v].items()]
    o=FV/'sp'; shutil.rmtree(o,ignore_errors=True); o.mkdir()
    run(a,o,{'WV_MAP':str(FV/'village.bin')},patch)
    n=0
    for v in vs:
        s=Image.new('RGB',(w*len(times),h))
        for i,t in enumerate(times):
            s.paste(Image.open(o/f'{n:03d}.png').convert('RGB'),(i*w,0)); n+=1
        s.save(pathlib.Path(out)/f'{tag}{v}.jpg',quality=72,optimize=True)
    return dict(w=w,h=h,times=list(map(float,times)),views=vs)
def heat_data(R,names):
    ts=np.unique(R[:,0]); rs=np.unique(R[:,1])
    d={}
    for nm in names:
        c=COLS.index(nm); Z=np.zeros((len(rs),len(ts)))
        Z[np.searchsorted(rs,R[:,1]),np.searchsorted(ts,R[:,0])]=R[:,c]
        d[nm]=[[round(float(x),3) for x in row] for row in Z]
    return dict(t=[float(x) for x in ts],r=[float(x) for x in rs],m=d)
