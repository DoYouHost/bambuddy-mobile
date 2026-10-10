import re,subprocess,math,sys,xml.dom.minidom as m
K='#0A0C08'; G='#34C46E'; DG='#18733D'
L5=open('source_l5.svg').read(); C1=open('source_c1.svg').read(); cp=re.findall(r'<path[^>]*>',C1)
def defs_of(mid):
    return re.search(rf'<(mask|clipPath) id="{mid}".*?</\1>',L5,re.S).group(0)
spool_defs=defs_of('spoolcut')+defs_of('nostalk')+defs_of('coil')
i=L5.index('<g mask="url(#spoolcut)">'); j=L5.index('<path d="M 516 1324',i)
spool=L5[i:j]
STRAND='M 516 1324 L 690 1324 C 760 1324 800 1290 800 1220 L 800 760 C 800 503 1115 443 1115 600'
leaves=cp[13]+cp[17]
inner_leaf=re.sub(r'fill="[^"]+"',f'fill="{G}"',cp[15]); leaf_d=re.search(r' d="([^"]+)"',cp[15]).group(1)
vein=re.search(r' d="([^"]+)"',cp[16]).group(1)

# ---- geometry of the B: two identical bowls, the lower one the mirror of the upper
T,B=703,1709; M=(T+B)/2           # top, bottom, axis
t,g=83,14                          # band width, gap
X0=870                             # bars start behind the bamboo
XR=1450                            # rightmost point of the outer arc
Rd=(M-g/2-(T+t+g))/2               # dark ring outer radius
cyU=T+t+g+Rd                       # upper bowl centre
Ro=Rd+t+g                          # light ring outer radius
xc=XR-Ro
def ring_half(cy,ro,ri,top_bar,bot_bar):
    # right half of a ring centred (xc,cy); optional straight bars to X0 at top/bottom
    p=f'M {X0} {cy-ro} L {xc} {cy-ro} A {ro} {ro} 0 0 1 {xc} {cy+ro} '
    p+= f'L {X0} {cy+ro} L {X0} {cy+ri} ' if bot_bar else f'L {xc} {cy+ro} L {xc} {cy+ri} '
    p+= f'L {xc} {cy+ri} A {ri} {ri} 0 0 0 {xc} {cy-ri} L {X0} {cy-ri} Z'
    return p
cyL=2*M-cyU
dark=(f'<path d="{ring_half(cyU,Rd,Rd-t,1,1)}" fill="{DG}"/>'
      f'<path d="{ring_half(cyL,Rd,Rd-t,1,1)}" fill="{DG}"/>')
lightU=ring_half(cyU,Ro,Ro-t,1,0); lightL=ring_half(cyL,Ro,Ro-t,1,0)
# light: upper ring above the axis, lower ring (mirror) below it; they meet in the waist
light=(f'<clipPath id="above"><rect x="0" y="0" width="2048" height="{M}"/></clipPath>'
       f'<clipPath id="below"><rect x="0" y="{M}" width="2048" height="2048"/></clipPath>'
       f'<path d="M {X0} {T} L {xc} {T} A {Ro} {Ro} 0 0 1 {xc} {T+2*Ro} L {xc} {T+2*Ro-t} A {Ro-t} {Ro-t} 0 0 0 {xc} {T+t} L {X0} {T+t} Z" fill="{G}" clip-path="url(#above)"/>'
       f'<path d="M {X0} {B} L {xc} {B} A {Ro} {Ro} 0 0 0 {xc} {B-2*Ro} L {xc} {B-2*Ro+t} A {Ro-t} {Ro-t} 0 0 1 {xc} {B-t} L {X0} {B-t} Z" fill="{G}" clip-path="url(#below)"/>')

# ---- bamboo: straight stalk, identical segments, each symmetric top/bottom
BX0,BX1=694,913; W=BX1-BX0; inset=30; flare=55; gap=16
EXT=0
segs=[(701-EXT,939)]; segs.append((939+gap,2*M-939-gap)); segs.append((2*M-939,1709+EXT))
FLARES=[]
import math
HALO=14
RC=12            # ring corner radius (convex)
DEPTH=31         # how far the stalk sits inside the ring
LIFT=2           # the B's bar edge is this far inside the bamboo's end
# concave radius RF chosen so the B's corner arc (RF-HALO, concentric) is tangent
# to the bar edge: |C1C2| = RC+RF with C1=(b-RC, y0+RC), C2=(b-DEPTH+RF, y0+LIFT+RF-HALO)
_a=RC-DEPTH; _b=LIFT-HALO-RC          # dx=RF+_a, dy=RF+_b
_A=2-1; _B=2*(_a+_b)-2*RC; _Cc=_a*_a+_b*_b-RC*RC
RF=(-_B+math.sqrt(_B*_B-4*_A*_Cc))/(2*_A)
def node_geom(b, y0, sgn):
    # sgn=+1: node at the top of a segment (stalk goes down), -1: at the bottom
    C1=(b-RC, y0+sgn*RC); C2=(b-DEPTH+RF, y0+sgn*(LIFT+RF-HALO))
    k=RC/(RC+RF); Tp=(C1[0]+(C2[0]-C1[0])*k, C1[1]+(C2[1]-C1[1])*k)
    return C1,C2,Tp
def seg(y0,y1):
    a,b=BX0,BX1; cx=(a+b)/2
    f=lambda x,y:f'{x:.2f} {y:.2f}'
    def right_side():
        _,C2t,Tt=node_geom(b,y0,1); _,C2b,Tb=node_geom(b,y1,-1)
        p =f'A {RC} {RC} 0 0 1 {f(*Tt)} A {RF} {RF} 0 0 0 {f(b-DEPTH,C2t[1])} '
        p+=f'L {f(b-DEPTH,C2b[1])} A {RF} {RF} 0 0 0 {f(*Tb)} A {RC} {RC} 0 0 1 {f(b-RC,y1)} '
        return p
    def left_side():
        L=lambda x:2*cx-x
        _,C2b,Tb=node_geom(b,y1,-1); _,C2t,Tt=node_geom(b,y0,1)
        p =f'A {RC} {RC} 0 0 1 {f(L(Tb[0]),Tb[1])} A {RF} {RF} 0 0 0 {f(L(b-DEPTH),C2b[1])} '
        p+=f'L {f(L(b-DEPTH),C2t[1])} A {RF} {RF} 0 0 0 {f(L(Tt[0]),Tt[1])} A {RC} {RC} 0 0 1 {f(a+RC,y0)} '
        return p
    return (f'M {f(a+RC,y0)} L {f(b-RC,y0)} '+right_side()+f'L {f(a+RC,y1)} '+left_side()+'Z')
# nodes sit where the B's bars end, so every B corner meets a node the same way
segs=[(T-LIFT, T+t+g+t+LIFT), (T+t+g+t+LIFT+16, 2*M-(T+t+g+t+LIFT)-16), (2*M-(T+t+g+t+LIFT), B+LIFT)]
bamboo_d=' '.join(seg(*sg) for sg in segs)

def corner_cut(yE, sgn, lead, mirror=False):
    # sgn=+1: corner on a bar's top edge (node above), -1: on its bottom edge
    y0=yE-sgn*LIFT
    _,C2,_=node_geom(BX1,y0,sgn); r=RF-HALO
    xs=BX1-DEPTH+HALO
    d=(f'M {X0-20} {yE-sgn*lead} L {C2[0]:.2f} {yE-sgn*lead} L {C2[0]:.2f} {yE} '
       f'A {r} {r} 0 0 {0 if sgn>0 else 1} {xs:.2f} {C2[1]:.2f} L {X0-20} {C2[1]:.2f} Z')
    shp=f'<path d="{d}" fill="#000"/>'
    return shp if not mirror else f'<g transform="translate(0,{2*M}) scale(1,-1)">{shp}</g>'
fillets=''.join(corner_cut(T,1,40,m_)+corner_cut(T+t+g+t,-1,g/2,m_) for m_ in (False,True))
bamboo=f'<path d="{bamboo_d}" fill="{K}"/>'

# ---- hotend (own layer, outline cut into what is below)
hot_shapes=('<rect x="1098" y="574" width="34" height="28" rx="6" {a}/><rect x="1035" y="594" width="160" height="106" rx="16" {a}/>'
            '<rect x="1100" y="700" width="30" height="62" {a}/><rect x="1072" y="760" width="86" height="40" rx="8" {a}/>'
            '<polygon points="1082,798 1148,798 1115,872" {a}/>')
fins=''.join(f'M 1020 {y} h 190 v 12 h -190 z ' for y in (626,660))
defs=f'''<defs>{spool_defs}
<mask id="frontcut" maskUnits="userSpaceOnUse" x="0" y="0" width="2048" height="2048"><rect width="2048" height="2048" fill="#fff"/>
 {hot_shapes.format(a='fill="#000" stroke="#000" stroke-width="36" stroke-linejoin="round"')}</mask>
<mask id="bamboocut" maskUnits="userSpaceOnUse" x="0" y="0" width="2048" height="2048"><rect width="2048" height="2048" fill="#fff"/>
 <path d="{bamboo_d}" fill="#000" stroke="#000" stroke-width="28"/>{fillets}</mask>
<mask id="leafcut" maskUnits="userSpaceOnUse" x="0" y="0" width="2048" height="2048"><rect width="2048" height="2048" fill="#fff"/>
 <path d="{leaf_d}" fill="#000" stroke="#000" stroke-width="24"/></mask>
<mask id="vein" maskUnits="userSpaceOnUse" x="0" y="0" width="2048" height="2048"><rect width="2048" height="2048" fill="#fff"/><path d="{vein}" fill="#000"/></mask>
<mask id="fins2" maskUnits="userSpaceOnUse" x="0" y="0" width="2048" height="2048"><rect width="2048" height="2048" fill="#fff"/><path d="{fins}" fill="#000"/></mask>
</defs>'''
def build(with_hotend=True,with_extras=True):
    under=''
    if with_extras: under+=leaves+f'<path d="{STRAND}" fill="none" stroke="{G}" stroke-width="25"/>'
    under+=f'<g mask="url(#leafcut)">{light}{dark}</g><g mask="url(#vein)">{inner_leaf}</g>'
    body=f'<g mask="url(#bamboocut)">{under}</g>{bamboo}'
    if with_hotend: body=f'<g mask="url(#frontcut)">{body}</g>'
    if with_extras: body+=spool+f'<g mask="url(#bamboocut)"><path d="{STRAND}" fill="none" stroke="{G}" stroke-width="25" clip-path="url(#nostalk)"/></g>'
    if with_hotend: body+=f'<g mask="url(#fins2)" fill="{K}">{hot_shapes.format(a="")}</g>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2048 2048">{defs}{body}</svg>'
open('logo.svg','w').write(build()); m.parse('logo.svg')
open('logo_simple.svg','w').write(build(False,False)); m.parse('logo_simple.svg')
print('axis',M,'Rd',Rd,'Ro',Ro,'xc',xc,'cyU',cyU)

# Dark launcher variant: bamboo and hotend go light on the dark background.
open('logo_dark.svg','w').write(open('logo.svg').read().replace(K,'#F2F5F3'))
