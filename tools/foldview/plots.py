#!/usr/bin/env python3
"""heat(rows, names, out): metrics against time and radius as a small multiple of heatmaps (PIL only)."""
import numpy as np, sys
sys.path.insert(0,__file__.rsplit('/',1)[0])
from fv import COLS
from PIL import Image,ImageDraw
SPEC={'area50':('area50 land area scale (log .05-20)',0.05,20,'log'),'area5':('area5 most crushed 5% (log .01-10)',0.01,10,'log'),'aniso95':('aniso95 sheared 5% (log 1-20)',1,20,'log'),'squash':('squash share to a line',0,1,'lin'),
'rel50':('rel50 of 8 blocks (0-3)',0,3,'lin'),'rel90':('rel90',0,3,'lin'),'tall50':('tall50 of 40 blocks (0-2)',0,2,'lin'),'tall90':('tall90',0,2,'lin'),'flip':('flip share',0,1,'lin'),'lean50':('lean50 deg',0,90,'lin'),'lean95':('lean95 deg (0-120)',0,120,'lin'),'kink95':('kink95 deg (0-60)',0,60,'lin'),'rout95':('rout95 blocks (0-3000)',0,3000,'lin'),'tint95':('tint95',0.4,1.6,'lin'),'tint5':('tint5',0.4,1.6,'lin'),'moved95':('moved95',0,3000,'lin')}
def cmap(x):
    x=np.clip(x,0,1)
    st=np.array([[0,0,4],[59,15,112],[140,41,129],[222,73,104],[254,159,109],[252,253,191]],float)
    i=x*5; j=np.minimum(i.astype(int),4); f=(i-j)[...,None]
    return (st[j]*(1-f)+st[j+1]*f).astype(np.uint8)
def heat(R,names,out,cols=4,title='',cw=4,ch=8):
    ts=np.unique(R[:,0]); rs=np.unique(R[:,1])
    W,H=len(ts)*cw,len(rs)*ch
    n=len(names); rows=(n+cols-1)//cols
    pad=(34,16,18,16)
    im=Image.new('RGB',((W+pad[0]+pad[2])*cols,(H+pad[1]+pad[3])*rows+16),(20,20,24)); d=ImageDraw.Draw(im)
    d.text((4,2),title,fill=(255,255,255))
    for i,nm in enumerate(names):
        sp=SPEC[nm]; c=COLS.index(nm); Z=np.zeros((len(rs),len(ts)))
        Z[np.searchsorted(rs,R[:,1]),np.searchsorted(ts,R[:,0])]=R[:,c]
        x=(np.log(np.maximum(Z,1e-6)/sp[1])/np.log(sp[2]/sp[1])) if sp[3]=='log' else (Z-sp[1])/(sp[2]-sp[1])
        a=Image.fromarray(cmap(x)[::-1]).resize((W,H),Image.NEAREST)
        ox,oy=(W+pad[0]+pad[2])*(i%cols)+pad[0],(H+pad[1]+pad[3])*(i//cols)+pad[1]+16
        im.paste(a,(ox,oy)); d.text((ox,oy-13),sp[0],fill=(230,230,230))
        for tt in range(int(ts[0])+(-int(ts[0])%4),int(ts[-1])+1,4):
            px=ox+int((tt-ts[0])/(ts[1]-ts[0]))*cw; d.line((px,oy+H,px,oy+H+3),fill=(200,200,200)); d.text((px-6,oy+H+3),str(tt),fill=(200,200,200))
        for k in range(0,len(rs),max(1,len(rs)//5)):
            py=oy+H-(k+1)*ch; d.text((ox-30,py),f'{rs[k]:.0f}',fill=(200,200,200))
    im.save(out)
