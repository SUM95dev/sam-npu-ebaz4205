def matmul(A,B):
    return [[sum(A[i][k]*B[k][j] for k in range(len(B))) for j in range(len(B[0]))] for i in range(len(A))]

def requant(x,bias=0,mul=1,shift=0,relu=False,zp=0):
    y=(x+bias)*mul
    if shift:y >>= shift
    if relu and y<0:y=0
    return max(-128,min(127,y+zp))

def conv2d_grouped(inp,w,bias=None,stride=1,pad=0,groups=1):
    H=len(inp); W=len(inp[0]); Cin=len(inp[0][0]); Cout=len(w)
    Kh=len(w[0]); Kw=len(w[0][0])
    if groups<1 or Cin%groups or Cout%groups: raise ValueError('invalid groups')
    Cpg=Cin//groups; Opg=Cout//groups
    if bias is None: bias=[0]*Cout
    Oh=(H+2*pad-Kh)//stride+1; Ow=(W+2*pad-Kw)//stride+1
    out=[[[0 for _ in range(Cout)] for _ in range(Ow)] for _ in range(Oh)]
    for oy in range(Oh):
      for ox in range(Ow):
        for oc in range(Cout):
          g=oc//Opg; base=g*Cpg; s=bias[oc]
          for ky in range(Kh):
            for kx in range(Kw):
              iy=oy*stride+ky-pad; ix=ox*stride+kx-pad
              if 0<=iy<H and 0<=ix<W:
                for lic in range(Cpg): s += inp[iy][ix][base+lic]*w[oc][ky][kx][lic]
          out[oy][ox][oc]=s
    return out

def maxpool2_groups(groups): return [max(g) for g in groups]
def add_i8(a,b,relu=False):
    out=[]
    for x,y in zip(a,b):
        z=x+y
        if relu and z<0:z=0
        out.append(max(-128,min(127,z)))
    return out

def self_test():
    assert matmul([[1,2],[3,4]],[[5,6],[7,8]])==[[19,22],[43,50]]
    assert requant(-10,relu=True)==0 and requant(1000)==127
    assert maxpool2_groups([[1,5,-2,3],[-8,-1,-3,-4]])==[5,-1]
    assert add_i8([120,-100],[20,-50])==[127,-128]
    # depthwise 1x1: two channels, two output channels, groups=2
    x=[[[2,3]]]; w=[[[[4]]],[[[5]]]]
    assert conv2d_grouped(x,w,[1,-1],groups=2)==[[[9,14]]]
    print('PASS numerical golden tests')
if __name__=='__main__':self_test()
