#!/usr/bin/env python3
"""pattern.py: the Fold's crease pattern, the tables fold_warp.wgsl and strike/fold.rs share. The pattern lives here: run it after changing anything
below to write them into both files (`--to SHADERS_DIR [FOLD_RS]`), `--plan out.png` to draw it from above with its mountains and valleys.
Twelve straight creases 30 degrees apart, mountain and valley in turn, and five rings; every number that isn't regular is said here."""
import math,re,sys,pathlib
N=12
# the rings' mean radii. All but the fourth are strike/fold.rs's FD_RINGS and fw_ring; the fourth is the crater's edge, drawn in to keep the crater its size (about 220,000 blocks of floor, what the land's wave is paced for)
RINGS=[44.0,104.0,176.0,266.0,480.0]
# how far ring i's corners stand in and out of its circle, by turns round it and from ring to ring
INOUT=[0.0,0.07,0.07,0.12,0.11]
K_DEG=30.0
# when each crease sets off from the target: all within 1.2 s, no order to it
BORN=[12.10,12.72,12.34,13.05,12.48,12.88,12.20,13.18,12.60,12.95,12.28,12.78]
# how far past its last ring each runs: the mountains on past the ring, the valleys stopping short of it, none two the same
ENDK=[1.17,0.74,1.09,0.86,1.21,0.70,1.13,0.81,1.06,0.77,1.19,0.90]
# when ring i's chord in wedge k is scored, after the first of its two creases has come to it: a fraction of a second, seeded
DELAY_SEED=7.0
Z=0.085     # how far up or down a ring stands, of its radius, in turn from ring to ring
def q(k,i):
    return RINGS[i]*(1.0+INOUT[i]*(1 if (k+i)%2==0 else -1))
def score(u): return 40*u+26*u*u+3*u*u*u
def invs(x):
    a,b=0,12
    for _ in range(60):
        m=(a+b)/2
        if score(m)<x: a=m
        else: b=m
    return a
def fract(x): return x-math.floor(x)
def h(k,i): return fract(math.sin(k*12.9898+i*78.233+DELAY_SEED)*43758.5453)
def tables():
    Q=[[q(k,i) for i in range(5)] for k in range(N)]
    # one over how far out ring i's chord is at a crease
    INV=[[1.0/Q[k][i] for i in range(5)] for k in range(N)]
    AT=[[BORN[k]+invs(Q[k][i]) for i in range(5)] for k in range(N)]
    # the chord between k and k + 1: when it sets off, from the crease that got there first
    CH=[[min(AT[k][i],AT[(k+1)%N][i])+0.25+0.9*h(k,i) for i in range(5)] for k in range(N)]
    # when a ring's stand comes to a crease: its two chords', either side
    CORD=[[0.5*(CH[k][i]+CH[(k-1)%N][i]) for i in range(5)] for k in range(N)]
    # up and down in turn from ring to ring, the same all the way round: each ring one mountain or one valley
    ZT=[[(Z if i%2 else -Z) for i in range(5)] for k in range(N)]
    return dict(Q=Q,INV=INV,AT=AT,CH=CH,CORD=CORD,Z=ZT)
def flat(T,f): return ', '.join(f.format(x) for r in T for x in r)
def wgsl(s):
    t=tables(); n=N*5
    def arr(name,T,f):
        nonlocal s
        s,c=re.subn(r'var<private> '+name+r': array<f32, \d+> = array<f32, \d+>\([^)]*\);',f'var<private> {name}: array<f32, {n}> = array<f32, {n}>({flat(T,f)});',s)
        assert c==1,name
    arr('CP_INV',t['INV'],'{:.6f}'); arr('CP_Q',t['Q'],'{:.2f}'); arr('CP_Z',t['Z'],'{:.4f}'); arr('CP_AT',t['AT'],'{:.2f}'); arr('CP_CORD',t['CORD'],'{:.2f}'); arr('CP_CH',t['CH'],'{:.2f}')
    def sw(name,ret,vals):
        nonlocal s
        body=''.join(f'        case {k}: {{ return {v}; }}\n' for k,v in enumerate(vals[:-1]))+f'        default: {{ return {vals[-1]}; }}\n'
        s,c=re.subn(r'(fn '+name+r'\(k: i32\) -> '+ret+r' \{\n    switch k \{\n).*?(    \}\n\})',lambda m:m.group(1)+body+m.group(2),s,count=1,flags=re.S)
        assert c==1,name
    sw('cp_dir','vec2<f32>',[f'vec2<f32>({math.cos(math.radians(k*K_DEG)):.6f}, {math.sin(math.radians(k*K_DEG)):.6f})' for k in range(N)])
    rise=math.radians(K_DEG)/2
    sw('cp_rise','f32',[f'{(rise if k%2==0 else -rise):.6f}' for k in range(N)])
    sw('cp_end','f32',[f'{t["Q"][k][4]*ENDK[k]:.1f}' for k in range(N)])
    sw('cp_born','f32',[f'{BORN[k]:.2f}' for k in range(N)])
    return s
def rust(s):
    t=tables()
    cre=', '.join(f'{k*K_DEG:.1f}' for k in range(N))
    s,c=re.subn(r'const FD_CREASES: \[f32; \d+\] = \[[^\]]*\];',f'const FD_CREASES: [f32; {N}] = [{cre}];',s); assert c==1
    rows=''.join('    ['+', '.join(f'{x:.6f}' for x in r)+'],\n' for r in t['INV'])
    s,c=re.subn(r'const FD_INV: \[\[f32; 5\]; \d+\] = \[\n.*?\n\];',lambda m:f'const FD_INV: [[f32; 5]; {N}] = [\n{rows.rstrip()}\n];',s,flags=re.S); assert c==1
    return s
def plan(path,size=700,span=620,mode=0):
    """the pattern from above: mountains red, valleys blue; mode 0 umbrella, 1 waterbomb, 2 diagonal"""
    from PIL import Image,ImageDraw
    t=tables(); Q=t['Q']; im=Image.new('RGB',(size,size),(250,247,240)); d=ImageDraw.Draw(im)
    S=size/2/span; P=lambda r,k:(size/2+r*math.cos(math.radians(k*K_DEG))*S,size/2+r*math.sin(math.radians(k*K_DEG))*S)
    M,V=(190,40,30),(40,70,190)
    for i in range(5):
        for k in range(N):
            a=P(Q[k][i-1],k) if i else (size/2,size/2); b=P(Q[k][i],k); c=P(Q[(k+1)%N][i],k+1); e=P(Q[(k+1)%N][i-1],k+1) if i else (size/2,size/2)
            mid=tuple(.25*(a[j]+b[j]+c[j]+e[j]) for j in (0,1)); odd=(k+i)%2==1
            if mode==1:
                for n,p in enumerate((a,b,c,e)): d.line((mid,p),fill=M if (n+k+i)%2 else V,width=1)
            if mode==2:
                d.line((b,e) if odd else (a,c),fill=V,width=1)
    for k in range(N):
        d.line((P(0,k),P(Q[k][4]*ENDK[k],k)),fill=M if k%2==0 else V,width=2)
    for i in range(5):
        for k in range(N):
            d.line((P(Q[k][i],k),P(Q[(k+1)%N][i],k+1)),fill=M if i%2 else V,width=2)
    im.save(path)
if __name__=='__main__':
    a=sys.argv[1:]
    if '--plan' in a:
        p=a[a.index('--plan')+1]
        for m,n in enumerate('abc'): plan(p.replace('.png',f'_{n}.png'),mode=m)
    if '--to' in a:
        d=pathlib.Path(a[a.index('--to')+1]); f=d/'fold_warp.wgsl'; f.write_text(wgsl(f.read_text()))
        r=a[a.index('--to')+2:]
        if r and not r[0].startswith('--'):
            p=pathlib.Path(r[0]); p.write_text(rust(p.read_text()))
