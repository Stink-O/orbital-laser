#!/usr/bin/env python3
"""fv.py: the Fold looked at with numbers. Runs the real fold_warp.wgsl (tools/foldview's warpview) over the real land of the test save and measures what the warp does to it.
Library: Scene (where the player stands, the seed), warp(points, times), grid(), metrics(); knockouts: patched copies of the shader, one term taken out, to say which term makes which artifact.
Paths: $FV_DIR scratch (default ~/.cache/orbital-scratch-archive/fv), $FV_BIN the warpview binary."""
import os,re,sys,math,struct,subprocess,pathlib,tempfile,shutil
import numpy as np
HOME=pathlib.Path.home()
ROOT=pathlib.Path(__file__).resolve().parents[2]
WARP=ROOT/'mod/shaders/fold_warp.wgsl'
FV=pathlib.Path(os.environ.get('FV_DIR',HOME/'.cache/orbital-scratch-archive/fv'))
BIN=pathlib.Path(os.environ.get('FV_BIN',HOME/'.cache/orbital-fold-team/probe/warpview/target/release/warpview'))
TY=109
def src(): return WARP.read_text()
def table(name,s=None):
    s=s or src()
    m=re.search(r'var<private> '+name+r': array<f32, 40> = array<f32, 40>\(([^)]*)\)',s)
    return np.array([float(x) for x in m.group(1).split(',')])
CREASES=[0.0,38.0,109.0,125.0,180.0,263.0,289.0,332.0]
def fd_pin(mx,mz,seed):
    """strike/fold.rs fd_pin: target at the origin"""
    inv=table('CP_INV').reshape(8,5)
    r=math.hypot(mx,mz); turn=((seed*0.618034)%1.0)*360
    x=(math.degrees(math.atan2(mz,mx))-turn)%360
    k=max(i for i,c in enumerate(CREASES) if x>=c); k1=(k+1)%8
    cr=lambda a,b: math.sin(math.radians(b-a))
    a0,a1=CREASES[k],CREASES[k1]
    u,v=cr(x,a1)/cr(a0,a1),cr(a0,x)/cr(a0,a1)
    cell=next((i for i in range(5) if r*(u*inv[k,i]+v*inv[k1,i])<1.0),5)
    return 6*k+cell
class Land:
    """the save's land, target in the middle; columns the save hasn't are mirrored in from the ones it has, so it goes on like itself"""
    def __init__(s,npz=None):
        d=np.load(npz or FV/'village.npz')
        s.g,s.t,s.c,s.gc,s.col=d['ground'].copy(),d['top'].copy(),d['cls'].copy(),d['gcl'].copy(),d['col']
        s.W=s.g.shape[0]; s.H=s.W//2
        known=s.g>=0
        # mirror fill: nearest known by reflecting about the bounding box of known columns, by rows then columns
        ys,xs=np.where(known)
        import scipy.ndimage as ndi
        idx=ndi.distance_transform_edt(~known,return_distances=False,return_indices=True)
        dy=idx[0]-np.arange(s.W)[:,None]; dx=idx[1]-np.arange(s.W)[None,:]
        my=np.clip(idx[0]+dy,0,s.W-1); mx=np.clip(idx[1]+dx,0,s.W-1)
        for _ in range(3):
            bad=~known[my,mx]
            if not bad.any(): break
            i2=idx[0][my,mx],idx[1][my,mx]
            my=np.where(bad,i2[0],my); mx=np.where(bad,i2[1],mx)
        for a in (s.g,s.t,s.c,s.gc):
            a[~known]=a[my,mx][~known]
    def ground(s,x,z):
        i=np.clip(np.floor(z).astype(int)+s.H,0,s.W-1); j=np.clip(np.floor(x).astype(int)+s.H,0,s.W-1)
        return s.g[i,j].astype(np.float32)+1.0
    def smooth(s,sig=6.0):
        import scipy.ndimage as ndi
        return ndi.gaussian_filter(s.g.astype(np.float32),sig)+1.0
    def write(s,path):
        with open(path,'wb') as f:
            f.write(struct.pack('<i',s.W)); f.write(s.g.astype('<i2').tobytes()); f.write(s.t.astype('<i2').tobytes()); f.write(s.c.tobytes()); f.write(s.gc.tobytes())
            c=np.zeros((16,3),np.uint8); c[:len(s.col)]=s.col; f.write(c.tobytes())
    def level(s,ty=TY):
        """strike/fold.rs fd_survey + fd_level"""
        h=[]
        for r in (90.0,170.0,280.0,420.0):
            for k in range(16):
                a=(k+0.5*(r>200))*math.tau/16
                x,z=int(r*math.cos(a)),int(r*math.sin(a))
                h.append(int(s.g[z+s.H,x+s.H])+0)
        h.sort(); low=h[len(h)//6]
        return float(max(min(low-ty-1,0),-80))
class Scene:
    def __init__(s,dist=170.0,high=33.0,bearing=-90.0,seed=5.0,level=None,land=None,fog=4096.0):
        s.fog=fog
        a=math.radians(bearing); s.mx,s.mz=dist*math.cos(a),dist*math.sin(a); s.my=TY+high
        s.seed=seed; s.land=land
        s.level=(land.level() if land else -8.0) if level is None else level
        s.pin=fd_pin(s.mx,s.mz,seed)
        s.lev=s.level-(s.pin+1)/64.0
    def args(s):
        return [f'tx=0',f'ty={TY}','tz=0',f'seed={s.seed}',f'level={s.lev}',f'cx={s.mx}',f'cy={s.my}',f'cz={s.mz}',f'fog={s.fog}']
SH_CACHE={}
def shader(patch=None):
    """the shader with text replacements [(old,new),...]; every old must be there; patch 'old' is the base build ($FV/old_warp.wgsl)"""
    if patch=='old': return FV/'old_warp.wgsl'
    if not patch: return WARP
    t=src()
    for a,b in patch:
        assert a in t,a
        t=t.replace(a,b)
    p=FV/'patched'; p.mkdir(exist_ok=True,parents=True)
    f=p/f'w{abs(hash(t))%10**12}.wgsl'
    f.write_text(t)
    return f
def run(args,out,env=None,patch=None):
    out=pathlib.Path(out); out.mkdir(parents=True,exist_ok=True)
    e=dict(os.environ); e.update(env or {})
    r=subprocess.run([str(BIN),str(shader(patch)),str(out)]+args,capture_output=True,text=True,env=e)
    if r.returncode: raise RuntimeError(r.stderr[-3000:])
    return r.stderr
def warp(pts,times,scene,patch=None,ex=()):
    """pts: (...,3) or (...,4) from the target (x, Y over the target, z[, copy]); returns (len(times), ..., 4): where each goes, from the target, and tint.x"""
    pts=np.asarray(pts,np.float32); shape=pts.shape[:-1]
    p4=np.zeros((int(np.prod(shape)),4),np.float32); p4[:,:pts.shape[-1]]=pts.reshape(-1,pts.shape[-1])
    with tempfile.TemporaryDirectory(dir=FV) as d:
        f=pathlib.Path(d)/'in.bin'; p4.tofile(f)
        a=scene.args()+['noland=1','pts=1']+list(ex)
        for t in times: a+=['--',f't={t}']
        run(a,d,{'WV_PTS':str(f)},patch)
        o=np.stack([np.fromfile(pathlib.Path(d)/f'pts_{i:03d}.bin',np.float32).reshape(-1,4) for i in range(len(times))])
    return o.reshape((len(times),)+shape+(4,))
def polar(nr=240,nm=480,rmax=720.0,y=None):
    """a polar grid: r (nr), a (nm); y: a number, or a function of (x, z)"""
    r=(np.arange(nr)+0.5)/nr*rmax; a=np.arange(nm)/nm*math.tau
    R,A=np.meshgrid(r,a,indexing='ij'); X,Z=R*np.cos(A),R*np.sin(A)
    Y=(y(X,Z) if callable(y) else np.full_like(X,y or 0.0))
    return r,a,X,Y,Z
def jac(P,dr,da):
    """P (nr, nm, 3): the 2x2 first form against the land's own r and arc, centred differences; dr: blocks, da: blocks per column of r"""
    Pr=(P[2:,:,:]-P[:-2,:,:])/(2*dr)
    Pa=(np.roll(P,-1,1)-np.roll(P,1,1))[1:-1]/(2*da[:,None,None])
    E=(Pr*Pr).sum(-1); F=(Pr*Pa).sum(-1); G=(Pa*Pa).sum(-1)
    tr=E+G; det=np.maximum(E*G-F*F,0)
    disc=np.sqrt(np.maximum(tr*tr-4*det,0))
    s1=np.sqrt((tr+disc)/2); s2=np.sqrt(np.maximum((tr-disc)/2,0))
    n=np.cross(Pa,Pr)
    return s1,s2,n,Pr,Pa
COLS=['t','r','area50','area5','area95','aniso50','aniso95','squash','rel50','rel10','rel90','tall50','tall90','flip','lean50','lean95','kink95','moved50','moved95','rout50','rout95','tint5','tint95']
def metrics(t,a,b,c,r,ang,bins):
    """a the sheet warped, b 8 blocks over it, c 40 over it; returns one row per radial bin. The land's own shape is taken out of nothing: the sheets are smooth."""
    nr,nm=a.shape[:2]; dr=r[1]-r[0]; da=r*(ang[1]-ang[0])
    s1,s2,n,Pr,Pa=jac(a[...,:3],dr,da[1:-1])
    rr=r[1:-1]
    up=(b-a)[1:-1,:,:3]; up2=(c-a)[1:-1,:,:3]
    rel=np.linalg.norm(up,axis=-1)/8; tall=np.linalg.norm(up2,axis=-1)/40
    nn=np.linalg.norm(n,axis=-1); cosv=(up*n).sum(-1)/np.maximum(nn*np.linalg.norm(up,axis=-1),1e-6)
    cosv=np.clip(cosv,-1,1)
    un=n/np.maximum(nn,1e-6)[...,None]
    k1=np.degrees(np.arccos(np.clip((un[1:]*un[:-1]).sum(-1),-1,1)))
    k2=np.degrees(np.arccos(np.clip((un*np.roll(un,-1,1)).sum(-1),-1,1)))
    kink=np.maximum(k1,k2[1:])
    rows=[]
    for lo,hi in bins:
        m=(rr>=lo)&(rr<hi)
        if not m.any(): continue
        S1,S2=s1[m],s2[m]
        area=S1*S2; an=S1/np.maximum(S2,1e-5)
        mv=np.linalg.norm(a[1:-1][m,:,:3]-0,axis=-1)
        q=lambda v,p: float(np.percentile(v,p))
        rout=np.hypot(a[1:-1][m,:,0],a[1:-1][m,:,2]); 
        tint=a[1:-1][m,:,3]
        rows.append([t,(lo+hi)/2,q(area,50),q(area,5),q(area,95),q(an,50),q(an,95),float((S2<0.05).mean()),q(rel[m],50),q(rel[m],10),q(rel[m],90),q(tall[m],50),q(tall[m],90),float((cosv[m]<-0.05).mean()),q(np.degrees(np.arccos(cosv[m])),50),q(np.degrees(np.arccos(cosv[m])),95),q(kink[m[:-1]] if m[:-1].any() else np.zeros(1),95),q(mv,50),q(mv,95),q(rout,50),q(rout,95),q(tint,5),q(tint,95)])
    return rows
def onland(land,dist,bearing,above,**k):
    a=math.radians(bearing); x,z=dist*math.cos(a),dist*math.sin(a)
    g=float(land.ground(np.array([x]),np.array([z]))[0])
    return Scene(dist=dist,bearing=bearing,high=g+above+1.62-TY,land=land,**k)
KO={ # one term taken out at a time, by text. Each says which line it stands for.
 'clear':[("out.pos = fw_clear(P + c.tgt + stay, pos + stay, bubble * (1.0 - fw_ss(FW_SLAM4, FW_SLAM4 + 1.0, t)));","out.pos = P + c.tgt + stay;")],
 'share':[("let P = mix(rest, fw_place(R, ca, sa, y, fw_bend(tau, span.x, mq, e, edge, span.y - sink)), share);","let P = fw_place(R, ca, sa, y, fw_bend(tau, span.x, mq, e, edge, span.y - sink));")],
 'dish':[("if (y > dish && tau > FW_FOLD) {","if (false) {")],
 'press':[("const CP_FLAT: f32 = 0.68;","const CP_FLAT: f32 = 0.0;"),("return vec2<f32>(1.0 - CP_FLAT * fw_ss(FW_SCORE + 0.3, FW_TEAR + 1.5, t) * fw_ss(0.0, 150.0, fw_score(t) - r) * fw_ss(FW_LEN * 1.25, FW_LEN, r), 1.0 - 0.9 * max(bl, fine));","return vec2<f32>(1.0, 1.0);")],
 'panels':[("const CP_K: f32 = 0.5;","const CP_K: f32 = 0.0;"),("const CP_V: f32 = 0.16;","const CP_V: f32 = 0.0;")],
 'zigs':[("var ring = CP_Z[k * 5 + i];","var ring = 0.0;")],
 'normal':[("let P = S + n * max(hh - level, 0.0) + under * min(hh, level);","let P = S + under * hh;")],
 'soft':[("h = mix(h, soft, folded);","")],
 'chain':[("fn fw_soft(t: f32, rt: f32) -> f32 {\n    return select(1.0, fw_ss(25.5, 27.5, t), rt >= FW_REL);","fn fw_soft(t: f32, rt: f32) -> f32 {\n    return 1.0;")],
}
def sweep(times,scene,land=None,rmax=720.0,nr=240,nm=480,bins=None,patch=None,batch=20,centre=(0.0,0.0)):
    """every time: a smooth sheet on the land (or flat), and over it 8 and 40 blocks. Returns rows"""
    H=land.smooth() if land is not None else None
    if land is not None:
        def Y(x,z):
            i=np.clip(np.round(z).astype(int)+land.H,0,land.W-1); j=np.clip(np.round(x).astype(int)+land.H,0,land.W-1)
            return H[i,j]-TY
    else: Y=0.0
    r,ang,X,y,Z=polar(nr,nm,rmax,(lambda x,z: Y(x+centre[0],z+centre[1])) if callable(Y) else Y)
    base=np.stack([X+centre[0],y,Z+centre[1]],-1)
    bins=bins or [(i*40.0,(i+1)*40.0) for i in range(int(rmax//40))]
    rows=[]
    for i in range(0,len(times),batch):
        ts=times[i:i+batch]
        A=warp(base,ts,scene,patch); B=warp(base+[0,8,0],ts,scene,patch); C=warp(base+[0,40,0],ts,scene,patch)
        for k,t in enumerate(ts):
            rows+=metrics(t,A[k],B[k],C[k],r,ang,bins)
    return np.array(rows)

def views(sc):
    ty=TY; mx,my,mz=sc.mx,sc.my,sc.mz
    # e: out from the target through the player; s: to their side
    L=math.hypot(mx,mz) or 1; ex,ez=mx/L,mz/L; sx,sz=-ez,ex
    P=lambda d,h,side=0: (mx+ex*d+sx*side,h,mz+ez*d+sz*side)
    me=dict(cx=mx,cy=my,cz=mz)
    def v(c,l,**k):
        d=dict(cx=c[0],cy=c[1],cz=c[2],mx=mx,my=my,mz=mz,lx=l[0],ly=l[1],lz=l[2]); d.update(k); return d
    def ext(c,l):
        # a free camera: the eye stays the player's (so the warp's frame is theirs, fw_stay), only the view moved (warpview's ox oy oz)
        o=(c[0]-mx,c[1]-my,c[2]-mz)
        return dict(cx=mx,cy=my,cz=mz,mx=mx,my=my,mz=mz,lx=mx+l[0]-c[0],ly=my+l[1]-c[1],lz=mz+l[2]-c[2],ox=o[0],oy=o[1],oz=o[2])
    ty=TY
    return {'player':v((mx,my,mz),(0,ty,0)),
     'feet':v((mx,my,mz),P(-60,my-70)),
     'left':v((mx,my,mz),P(-20,my-14,-200)),'right':v((mx,my,mz),P(-20,my-14,200)),
     'behind':v((mx,my,mz),P(330,my+6)),
     'up':v((mx,my,mz),(mx+.1,my+800,mz)),'up2':v((mx,my,mz),P(-430,my+560)),
     'high':ext((mx,my+130,mz),(0,ty,0)),
     'top':ext((0,ty+1600,1),(0,ty,0)),'oblique':ext((-900,ty+620,-900),(0,ty+40,0)),'low':ext((-700,ty+80,-700),(0,ty+60,0)),'far':ext((-1500,ty+350,-1500),(0,ty+80,0)),
     'side':ext((mx+sx*210-ex*50,my+220,mz+sz*210-ez*50),P(-20,my+386,-200))}
def sheet(name,vs,times,scene,w=480,h=270,patch=None,ex=(),out=None,noise=None,keep=False):
    """rendered contact sheet: rows the views, columns the times. keep: leave the frames as files"""
    from PIL import Image,ImageDraw
    V=views(scene); a=[f'w={w}',f'h={h}']+scene.args()+list(ex)
    for v in vs:
        for t in times:
            a+=['--',f't={t}']+[f'{k}={x}' for k,x in V[v].items()]
    o=pathlib.Path(out or FV/'sheets'/name); o.mkdir(parents=True,exist_ok=True)
    log=run(a,o,{'WV_MAP':str(FV/'village.bin')},patch)
    s=Image.new('RGB',(w*len(times),h*len(vs))); n=0
    for j,v in enumerate(vs):
        for i,t in enumerate(times):
            p=o/f'{n:03d}.png'
            im=Image.open(p).convert('RGB'); d=ImageDraw.Draw(im); d.text((6,4),f'{v} {t}',fill=(255,255,0)); s.paste(im,(i*w,j*h)); n+=1
            if not keep: p.unlink()
    f=o/'sheet.jpg'; s.save(f,quality=86); return f

def planmap(name,scene,times,land=None,half=640,n=640,patch=None,y=None,cell=None):
    """the land from above, target in the middle, player a white ring: per cell what the warp does. Red: inside out. Blue: crushed (area<.15). Yellow: sheared (s1/s2>6). Green: columns over 60 degrees off. Grey shows the land's height."""
    from PIL import Image,ImageDraw
    xs=(np.arange(n)+.5)/n*2*half-half
    X,Z=np.meshgrid(xs,xs)
    if land is not None:
        H=land.smooth(3.0); Y=H[np.clip(np.round(Z).astype(int)+land.H,0,land.W-1),np.clip(np.round(X).astype(int)+land.H,0,land.W-1)]-TY
    else: Y=np.full_like(X,y or 0.0)
    base=np.stack([X,Y,Z],-1).astype(np.float32)
    A=warp(base,times,scene,patch); B=warp(base+[0,8,0],times,scene,patch)
    dx=xs[1]-xs[0]
    out=[]; ims=[]
    for k,t in enumerate(times):
        a=A[k][...,:3]; up=(B[k]-A[k])[...,:3]
        Px=(a[1:-1,2:]-a[1:-1,:-2])/(2*dx); Pz=(a[2:,1:-1]-a[:-2,1:-1])/(2*dx)
        E,F,G=(Px*Px).sum(-1),(Px*Pz).sum(-1),(Pz*Pz).sum(-1); tr=E+G; dt=np.maximum(E*G-F*F,0); ds=np.sqrt(np.maximum(tr*tr-4*dt,0))
        s1=np.sqrt((tr+ds)/2); s2=np.sqrt(np.maximum((tr-ds)/2,0))
        nrm=np.cross(Pz,Px); u=up[1:-1,1:-1]
        cs=(nrm*u).sum(-1)/np.maximum(np.linalg.norm(nrm,axis=-1)*np.linalg.norm(u,axis=-1),1e-6)
        area=s1*s2; an=s1/np.maximum(s2,1e-5)
        g=np.clip((Y[1:-1,1:-1]+60)/140,0,1)*90+30
        im=np.stack([g,g,g],-1)
        im[an>6]=[240,210,40]; im[area<.15]=[60,110,255]; im[cs<np.cos(np.radians(60))]=[60,220,90]; im[cs<-0.05]=[255,40,40]
        i=Image.fromarray(im.astype(np.uint8)); d=ImageDraw.Draw(i)
        c=lambda x: (x+half)/(2*half)*n
        d.ellipse((c(scene.mx)-6,c(scene.mz)-6,c(scene.mx)+6,c(scene.mz)+6),outline=(255,255,255)); d.ellipse((c(0)-3,c(0)-3,c(0)+3,c(0)+3),fill=(255,255,255))
        d.text((6,4),f't {t}  red {(cs<-.05).mean():.3f}  blue {(area<.15).mean():.3f}  yellow {(an>6).mean():.3f}  green {(cs<.5).mean():.3f}',fill=(255,255,0))
        ims.append(i); out.append(dict(t=t,flip=float((cs<-.05).mean()),crush=float((area<.15).mean()),shear=float((an>6).mean()),lean=float((cs<.5).mean())))
    cols=min(len(ims),4); rows=(len(ims)+cols-1)//cols
    s=Image.new('RGB',(cols*(n-2),rows*(n-2)))
    for k,i in enumerate(ims): s.paste(i,((k%cols)*(n-2),(k//cols)*(n-2)))
    f=FV/f'pm_{name}.png'; s.save(f); return f,out
def xsec(name,scene,times,bearing=None,y=0.0,w=560,h=420,span=1500,patch=None,land=None,marks=True):
    """the sheet cut through the axis: the plane through the target and the player (or `bearing` degrees), blocks out either side, a strip per time. Colour: how far out the point was on the land. Red: inside out."""
    from PIL import Image,ImageDraw
    b=math.atan2(scene.mz,scene.mx) if bearing is None else math.radians(bearing)
    rs=np.concatenate([np.arange(-span*2,-720,6.0),np.arange(-720,720,1.0),np.arange(720,span*2,6.0)])
    X,Z=rs*math.cos(b),rs*math.sin(b)
    Y=(land.smooth()[np.clip(np.round(Z).astype(int)+land.H,0,land.W-1),np.clip(np.round(X).astype(int)+land.H,0,land.W-1)]-TY) if land is not None else np.full_like(X,y)
    o=warp(np.stack([X,Y,Z],-1),times,scene,patch)
    n=len(times); cols=min(n,5); rows=(n+cols-1)//cols
    im=Image.new('RGB',(w*cols,h*rows),(12,12,16)); d=ImageDraw.Draw(im)
    for i,t in enumerate(times):
        ox,oy=(i%cols)*w,(i//cols)*h
        P=o[i]; s=(P[:,0]*math.cos(b)+P[:,2]*math.sin(b)); yy=P[:,1]
        sc=w/(2.0*span*0.62)
        cx,cy=ox+w/2,oy+h*0.82
        # the player
        px=cx+(math.hypot(scene.mx,scene.mz))*sc; 
        pts=[(cx+a*sc,cy-c*sc) for a,c in zip(s,yy)]
        for j in range(len(pts)-1):
            if abs(rs[j])>span*2: continue
            q=abs(rs[j]); 
            c=(255,int(220*min(q/480,1)),60) if q<480 else (70,150,255) if q<1000 else (90,90,120)
            if rs[j]<0: c=(c[0]//2+30,c[1]//2+30,c[2]//2+30)
            if abs(pts[j][0]-ox-w/2)<w/2 and abs(pts[j+1][0]-ox-w/2)<w/2 and oy<pts[j][1]<oy+h: d.line((pts[j],pts[j+1]),fill=c)
        # the player's eye
        if marks:
            mp=warp(np.array([[scene.mx,scene.my-TY,scene.mz]],np.float32),[t],scene,patch)[0,0]
            d.ellipse((cx+(mp[0]*math.cos(b)+mp[2]*math.sin(b))*sc-3,cy-mp[1]*sc-3,cx+(mp[0]*math.cos(b)+mp[2]*math.sin(b))*sc+3,cy-mp[1]*sc+3),outline=(255,255,255))
        d.text((ox+6,oy+4),f't {t}',fill=(255,255,0))
    f=FV/f'xs_{name}.png'; im.save(f); return f
if __name__=='__main__':
    # self test: maps whose answers are known, through the same metrics
    r,ang,X,Y,Z=polar(120,240,600.0,0.0)
    bins=[(100,200),(300,400)]
    def m(f):
        a=f(X,Y,Z); b=f(X,Y+8,Z); c=f(X,Y+40,Z)
        pad=lambda p: np.concatenate([p,np.ones(p.shape[:-1]+(1,))],-1)
        return np.array(metrics(0,pad(a),pad(b),pad(c),r,ang,bins))
    I=COLS.index
    id_=m(lambda x,y,z: np.stack([x,y,z],-1))
    print('identity: area',id_[0,I('area50')],'aniso',id_[0,I('aniso50')],'rel',id_[0,I('rel50')],'flip',id_[0,I('flip')],'lean',id_[0,I('lean50')],'kink',id_[0,I('kink95')])
    rot=m(lambda x,y,z: np.stack([x*.6+y*.8,-x*.8+y*.6,z],-1)+[50,2,3])
    print('rigid: area',rot[0,I('area50')],'aniso',rot[0,I('aniso50')],'rel',rot[0,I('rel50')],'flip',rot[0,I('flip')],'lean',rot[0,I('lean50')])
    sc=m(lambda x,y,z: np.stack([3*x,y,3*z],-1))
    print('scale 3 flat, heights kept: area (9)',sc[0,I('area50')],'aniso (1)',sc[0,I('aniso50')],'rel (1)',sc[0,I('rel50')])
    an=m(lambda x,y,z: np.stack([4*x,y*.25,z],-1))
    print('4 by 1: area median (~2.5-4)',an[:,I('area50')],'aniso95 (<=4)',an[:,I('aniso95')],'rel (.25)',an[0,I('rel50')])
    fl=m(lambda x,y,z: np.stack([x,-y,z],-1)*np.array([1,1,1]))
    print('heights upside down: flip (1)',fl[0,I('flip')],'lean (180)',fl[0,I('lean50')])
    sh=m(lambda x,y,z: np.stack([x+y,y,z],-1))
    print('columns sheared 45 degrees: lean (45)',sh[0,I('lean95')],'rel (1.41)',sh[0,I('rel50')])
    sq=m(lambda x,y,z: np.stack([np.minimum(np.hypot(x,z),350)*x/np.maximum(np.hypot(x,z),1),y,np.minimum(np.hypot(x,z),350)*z/np.maximum(np.hypot(x,z),1)],-1))
    print('all past 350 crushed to a circle: squash in bin 300-400 (~.5)',sq[1,I('squash')],'rout95',sq[1,I('rout95')])
