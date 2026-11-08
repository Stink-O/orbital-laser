#!/usr/bin/env python3
"""land_from_save.py SAVE X Z HALF OUT.npz: the real land of a world save (read only) round (X, Z), HALF blocks each way, as columns:
ground (the top that isn't leaves), top (with leaves), block class, so warpview can draw the land the user's frames show and not a sum of sines."""
import sys,struct,zlib,gzip,pathlib,io
import numpy as np
def nbt(b,o,tag):
    # returns value, next offset. Lists and compounds as python; long arrays as numpy
    if tag==1: return struct.unpack_from('>b',b,o)[0],o+1
    if tag==2: return struct.unpack_from('>h',b,o)[0],o+2
    if tag==3: return struct.unpack_from('>i',b,o)[0],o+4
    if tag==4: return struct.unpack_from('>q',b,o)[0],o+8
    if tag==5: return struct.unpack_from('>f',b,o)[0],o+4
    if tag==6: return struct.unpack_from('>d',b,o)[0],o+8
    if tag==7:
        n=struct.unpack_from('>i',b,o)[0]; return None,o+4+n
    if tag==8:
        n=struct.unpack_from('>H',b,o)[0]; return b[o+2:o+2+n].decode('utf8','replace'),o+2+n
    if tag==9:
        t=b[o]; n=struct.unpack_from('>i',b,o+1)[0]; o+=5; l=[]
        for _ in range(n):
            v,o=nbt(b,o,t); l.append(v)
        return l,o
    if tag==10:
        d={}
        while True:
            t=b[o]; o+=1
            if t==0: return d,o
            n=struct.unpack_from('>H',b,o)[0]; k=b[o+2:o+2+n].decode('utf8','replace'); o+=2+n
            d[k],o=nbt(b,o,t)
    if tag==11:
        n=struct.unpack_from('>i',b,o)[0]; return None,o+4+4*n
    if tag==12:
        n=struct.unpack_from('>i',b,o)[0]; return np.frombuffer(b,dtype='>i8',count=n,offset=o+4),o+4+8*n
    raise ValueError(tag)
# classes: colour of each (the game's average textures, near enough)
CLS={'air':0,'grass':1,'dirt':2,'stone':3,'sand':4,'water':5,'leaves':6,'log':7,'snow':8,'wood':9,'path':10,'cherry':11,'gravel':12,'other':13,'lava':14}
COL=np.array([[0,0,0],[92,150,62],[120,86,58],[125,125,125],[219,207,163],[52,84,205],[48,105,42],[90,68,42],[240,245,250],[160,120,70],[150,120,70],[235,170,190],[130,126,122],[140,120,100],[210,90,20]],np.uint8)
def klass(n):
    n=n.split(':')[-1]
    if n in('air','cave_air','void_air','short_grass','tall_grass','fern','large_fern','dandelion','poppy','seagrass','tall_seagrass','kelp','kelp_plant','bubble_column','vine'): return 0 if n not in('seagrass','tall_seagrass','kelp','kelp_plant','bubble_column') else 5
    if 'leaves' in n: return 11 if 'cherry' in n else 6
    if n=='water': return 5
    if n=='lava': return 14
    if n=='grass_block' or n=='moss_block' or n=='podzol' or n=='mycelium': return 1
    if n in('dirt','coarse_dirt','rooted_dirt','mud','clay','farmland'): return 2
    if n.endswith('sand') or n.endswith('sandstone'): return 4
    if n in('snow','snow_block','ice','packed_ice','blue_ice','powder_snow'): return 8
    if n.endswith('_log') or n.endswith('_wood'): return 7
    if n.endswith('_planks') or n.endswith('_stairs') or n.endswith('_slab') or n.endswith('_fence') or n.endswith('door') or n.endswith('_roof'): return 9
    if n=='dirt_path': return 10
    if n in('gravel',): return 12
    if n in('stone','granite','diorite','andesite','deepslate','tuff','calcite','cobblestone','mossy_cobblestone','stone_bricks','bedrock','terracotta') or n.endswith('terracotta'): return 3
    if 'flower' in n or 'tulip' in n or 'bush' in n or 'petals' in n or 'sapling' in n or 'orchid' in n or 'allium' in n or 'bluet' in n or 'daisy' in n or 'cornflower' in n or 'lily' in n or 'torch' in n or 'lantern' in n: return 0
    return 13
def main():
    save=pathlib.Path(sys.argv[1]); X,Z,H=int(sys.argv[2]),int(sys.argv[3]),int(sys.argv[4]); out=sys.argv[5]
    W=2*H
    ground=np.full((W,W),-1,np.int16); top=np.full((W,W),-1,np.int16); cls=np.zeros((W,W),np.uint8); gcl=np.zeros((W,W),np.uint8)
    x0,z0=X-H,Z-H
    rx0,rz0=x0>>9,z0>>9; rx1,rz1=(x0+W-1)>>9,(z0+W-1)>>9
    cache={}
    def kls(n):
        if n not in cache: cache[n]=klass(n)
        return cache[n]
    done=0
    for rx in range(rx0,rx1+1):
      for rz in range(rz0,rz1+1):
        f=save/f'r.{rx}.{rz}.mca'
        if not f.exists(): continue
        data=f.read_bytes()
        for i in range(1024):
            off=int.from_bytes(data[i*4:i*4+3],'big'); 
            if off==0: continue
            n=struct.unpack_from('>i',data,off*4096)[0]; ct=data[off*4096+4]
            body=data[off*4096+5:off*4096+4+n]
            cx,cz=rx*32+(i&31),rz*32+(i>>5)
            ax,az=cx*16-x0,cz*16-z0
            if ax<=-16 or az<=-16 or ax>=W or az>=W: continue
            raw=zlib.decompress(body) if ct==2 else gzip.decompress(body)
            ch,_=nbt(raw,3+struct.unpack_from('>H',raw,1)[0],10)
            secs=ch.get('sections') or []
            col=np.zeros((16,16),int)-1; colg=np.zeros((16,16),int)-1; c0=np.zeros((16,16),np.uint8); c1=np.zeros((16,16),np.uint8)
            secs=sorted([s for s in secs if 'block_states' in s],key=lambda s:-s['Y'])
            for s in secs:
                bs=s['block_states']
                pal=[kls((p if isinstance(p,str) else (p.get('id') or p.get('') or p.get('Name'))).split('[')[0]) for p in bs['palette']]
                if all(p==0 for p in pal): continue
                if len(pal)==1:
                    a=np.full(4096,pal[0],np.uint8)
                else:
                    bits=max(4,int(np.ceil(np.log2(len(pal))))); per=64//bits
                    d=np.frombuffer(bs['data'].tobytes(),dtype='>u8').astype(np.uint64)
                    idx=np.zeros(4096,np.int32)
                    ar=np.arange(4096); w=ar//per; sh=(ar%per)*bits
                    idx=((d[w]>>sh.astype(np.uint64))&np.uint64((1<<bits)-1)).astype(np.int32)
                    a=np.array(pal,np.uint8)[np.clip(idx,0,len(pal)-1)]
                a=a.reshape(16,16,16) # y z x
                base=s['Y']*16
                for y in range(15,-1,-1):
                    lay=a[y]
                    nz=lay!=0
                    m=nz&(col<0)
                    col[m]=base+y; c0[m]=lay[m]
                    solid=nz&(lay!=6)&(lay!=11)&(lay!=7)
                    m2=solid&(colg<0)
                    colg[m2]=base+y; c1[m2]=lay[m2]
                if (colg>=0).all(): break
            for z in range(16):
                for x in range(16):
                    gx,gz=ax+x,az+z
                    if 0<=gx<W and 0<=gz<W:
                        top[gz,gx]=col[z,x]; ground[gz,gx]=colg[z,x]; cls[gz,gx]=c0[z,x]; gcl[gz,gx]=c1[z,x]
            done+=1
    print('chunks',done,'known',(top>=0).mean())
    np.savez_compressed(out,ground=ground,top=top,cls=cls,gcl=gcl,x0=x0,z0=z0,col=COL)
main()
