#!/usr/bin/env python3
"""Mocks of the end states the user is choosing between: patched copies of the shader, nothing committed to the mod. hold(T): the world stops closing at fold-clock T (the tube); horn: the far land pinches off the hole's rim down to the target; ribbon: the arm's copies laid as a flat ribbon spiralling off the rim; each in warpview only."""
import sys
sys.path.insert(0,__file__.rsplit('/',1)[0])
from fv import *
def hold(T):
    return [("""    if (t < FW_BEAT) {
        return t;
    }
    if (t < FW_REL) {""",f"""    if (t < FW_BEAT) {{
        return min(t, {T});
    }}
    if (t < FW_REL) {{"""),
    ("""    let tau = fw_tau(c.t);
    let mq = c.me - c.tgt;
    let dist = length(mq.xz);
    let S = fw_radius(dist, mq.y);
    let reach = max(fw_reached(tau, S), fw_swell(tau));""","""    let tau = min(c.t, FW_BEAT);
    let mq = c.me - c.tgt;
    let dist = length(mq.xz);
    let S = fw_radius(dist, mq.y);
    let reach = max(fw_reached(tau, S), fw_swell(tau));""")]
def horn(R1=2200.0,R2=9000.0,turns=1.2,late=1.0):
    # the far land past R1 goes on off the rim, down the axis, winding, as far as the arm's clock has it by
    return [("""fn fw_place(R: f32, ca: f32, sa: f32, y: f32, g: FwBend) -> vec3<f32> {
    let on = fw_roll(R, y, g);
    let p = vec3<f32>(on.x * ca, on.y, on.x * sa);""",f"""fn fw_place(R: f32, ca0: f32, sa0: f32, y: f32, g: FwBend) -> vec3<f32> {{
    var on = fw_roll(min(R, {R1}), y, g);
    var ca = ca0;
    var sa = sa0;
    let clk = clamp((globals.warp[0].w - 35.0) / 5.0, 0.0, 1.0);
    let open = 1.0 - pow(1.0 - clk, 2.0);
    if (R > {R1} && clk > 0.0) {{
        let s = clamp((R - {R1}) / ({R2} - {R1}), 0.0, 1.0);
        let z = s * open;
        let tip = pow(1.0 - z, 1.8);
        let tw = {turns} * FW_TAU * z * z;
        let cc = cos(tw);
        let ss = sin(tw);
        let c2 = ca * cc - sa * ss;
        sa = ca * ss + sa * cc;
        ca = c2;
        on = vec3<f32>(on.x * tip, on.y * (1.0 - z * z * (3.0 - 2.0 * z)) + 2.0 * z, on.z);
    }} else if (R > {R1}) {{
        on = fw_roll(R, y, g);
    }}
    let p = vec3<f32>(on.x * ca, on.y, on.x * sa);""")]
def ribbon(H,Hr,T,turns=1.1,flat=0.22,bear=0.0):
    # the arm's copies, along a spiral from the rim (H its centre, Hr its radius) to the target T, a flat ribbon, its land to the inside
    return [("""    let P = fw_path(x, S);
    // (turning a little as it goes, each length its own way round)
    let phi = -a + f32(k) * 1.9 + x * 2.2;
    let at = atan2(-e.y, -e.x) + fw_bear(x);
    let ca = cos(at);
    let sa = sin(at);
    let c2 = P.c + P.n * (rho * cos(phi));
    let side = rho * sin(phi);
    let bend = fw_bend(FW_BEAT, 0.0, mq, e, 1.0e6, 0.0);
    out.pos = fw_turn(c2.x * ca - side * sa, c2.y, c2.x * sa + side * ca, fw_seat(dist, mq.y), bend) + c.tgt + fw_stay(c, tau);""",f"""    let H = vec3<f32>({H[0]}, {H[1]}, {H[2]});
    let T = vec3<f32>({T[0]}, {T[1]}, {T[2]});
    let u = clamp(x, 0.0, 1.0);
    let pos_of = fn_arm(u, H, T);
    let n = normalize(fn_arm(u + 0.01, H, T) - pos_of);
    let rad = normalize(vec3<f32>(pos_of.x - mix(H.x, T.x, u * u), 0.0, pos_of.z - mix(H.z, T.z, u * u)) + vec3<f32>(0.001, 0.0, 0.0));
    let wid = normalize(cross(n, rad));
    let nor = cross(wid, n);
    let phi = -a + f32(k) * 1.9 + x * 2.2;
    let w0 = 2.4 * rho * mix(1.0, 0.25, u);
    out.pos = pos_of + wid * (w0 * sin(phi)) + nor * (w0 * {flat} * cos(phi)) + c.tgt + fw_stay(c, tau);"""),
    ("""const FW_THROAT: f32 = 22.0;""",f"""fn fn_arm(u: f32, H: vec3<f32>, T: vec3<f32>) -> vec3<f32> {{
    let m = u * u * (3.0 - 2.0 * u);
    let ring = {Hr} * pow(1.0 - u, 1.3);
    let th = {bear} + {turns} * FW_TAU * u;
    return mix(H, T, m) + vec3<f32>(ring * cos(th), 0.0, ring * sin(th));
}}
const FW_THROAT: f32 = 22.0;""")]
def spend(x0=650.0,y0=600.0,a=1.9,d=170.0,floor=40.0,n=17):
    """FW_SPEND of fold_warp.wgsl: the curve's parameter at equal steps of length over width, the width floored; returns the table and the land's stretch K it costs for the band of FW_RIM0"""
    v=np.linspace(0,1,8001); m=1-v
    T=np.array([np.cos(a),np.sin(a)]); P0=np.array([x0,y0]); P1=P0+T*0.3*x0
    P2=np.array([min(0.2*x0,0.75*max(d,60.0)),-10.0]); P3=np.array([0.0,1.0])
    C=np.outer(m**3,P0)+np.outer(3*m*m*v,P1)+np.outer(3*m*v*v,P2)+np.outer(v**3,P3)
    dl=np.linalg.norm(np.diff(C,axis=0),axis=1)
    q=np.concatenate([[0],np.cumsum(dl/np.maximum(C[:-1,0],floor))]); tot=q[-1]
    return np.interp(np.linspace(0,1,n),q/tot,v),tot,C
