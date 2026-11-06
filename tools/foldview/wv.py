#!/usr/bin/env python3
# wv.py NAME VIEWS TIMES [key=value ...]: contact sheet, rows the views, columns the times. views: player,top,oblique,far,back,up
import subprocess,sys,pathlib,os
from PIL import Image,ImageDraw
R=pathlib.Path(__file__).parent
WT=pathlib.Path.home()/'.cache/orbital-fold-visuals'
ARCH=pathlib.Path(os.environ.get('WV_OUT',str(R/'wv')))
name=sys.argv[1]; views=sys.argv[2].split(','); times=[float(x) for x in sys.argv[3].split(',')]
ex=sys.argv[4:]
w=[e for e in ex if e.startswith('w=')]; W=int(w[0][2:]) if w else 640
h=[e for e in ex if e.startswith('h=')]; H=int(h[0][2:]) if h else 360
ty=65.0
for e in ex:
    if e.startswith('ty='): ty=float(e[3:])
V={'player':dict(cx=0,cy=ty+34,cz=170,lx=0,ly=ty,lz=0),
   'left':dict(cx=0,cy=ty+34,cz=170,mx=0,mz=170,lx=-200,ly=ty+20,lz=150),
   'right':dict(cx=0,cy=ty+34,cz=170,mx=0,mz=170,lx=200,ly=ty+20,lz=150),
   'behind':dict(cx=0,cy=ty+34,cz=170,mx=0,mz=170,lx=0,ly=ty+40,lz=500),
   'up':dict(cx=0,cy=ty+34,cz=170,mx=0,mz=170,lx=0.1,ly=ty+800,lz=170),
   'up2':dict(cx=0,cy=ty+34,cz=170,mx=0,mz=170,lx=0.1,ly=ty+600,lz=-260),
   # from inside the sphere, off the player: free views, the frame being theirs (it goes with the camera)
   'side':dict(cx=0,cy=ty+34,cz=170,mx=0,mz=170,lx=-200,ly=ty+420,lz=170,ox=210,oy=220,oz=-50),
   'side2':dict(cx=0,cy=ty+34,cz=170,mx=0,mz=170,lx=170,ly=ty+420,lz=170,ox=-190,oy=200,oz=-100),
   'top':dict(cx=0,cy=ty+1250,cz=1,mx=0,my=ty+34,mz=170,lx=0,ly=ty,lz=0),
   'oblique':dict(cx=-650,cy=ty+420,cz=720,mx=0,my=ty+34,mz=170,lx=0,ly=ty+40,lz=0),
   'low':dict(cx=-500,cy=ty+60,cz=520,mx=0,my=ty+34,mz=170,lx=0,ly=ty+60,lz=0),
   'far':dict(cx=-1100,cy=ty+260,cz=1100,mx=0,my=ty+34,mz=170,lx=0,ly=ty+80,lz=0)}
args=[f'w={W}',f'h={H}','level=-8.2']+[e for e in ex if not e.startswith(('w=','h='))]
for v in views:
    for t in times:
        args+=['--',f't={t}']+[f'{k}={x}' for k,x in V[v].items()]
out=R/'wvout'/name
out.mkdir(parents=True,exist_ok=True)
for p in out.glob('*.png'): p.unlink()
r=subprocess.run([str(R/'warpview/target/release/warpview'),str(WT/'mod/shaders/fold_warp.wgsl'),str(out)]+args,capture_output=True,text=True)
if r.returncode: print(r.stderr[-3000:]); sys.exit(1)
s=Image.new('RGB',(W*len(times),H*len(views)))
n=0
for j,v in enumerate(views):
    for i,t in enumerate(times):
        im=Image.open(out/f'{n:03d}.png').convert('RGB'); d=ImageDraw.Draw(im); d.text((6,4),f"{v} {t}",fill=(255,255,0)); s.paste(im,(i*W,j*H)); n+=1
for p in out.glob('*.png'): p.unlink()
o=out/'sheet.jpg'; s.save(o,quality=88); print(o,s.size)
