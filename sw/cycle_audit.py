import random

def matmul(A,B):
    return [[sum(A[i][k]*B[k][j] for k in range(len(B))) for j in range(len(B[0]))] for i in range(len(A))]

def tile_cycle(A,B,T,tm,tn,stall_p=.25):
    M,K,Nd=len(A),len(A[0]),len(B[0])
    aout=[[0]*T for _ in range(T)]; bout=[[0]*T for _ in range(T)]; acc=[[0]*T for _ in range(T)]
    step=0
    while step<K+T-1:
        if random.random()<stall_p: continue
        avec=[A[tm*T+r][step-r] if tm*T+r<M and 0<=step-r<K else 0 for r in range(T)]
        bvec=[B[step-c][tn*T+c] if tn*T+c<Nd and 0<=step-c<K else 0 for c in range(T)]
        oa=[x[:] for x in aout]; ob=[x[:] for x in bout]
        for r in range(T):
            for c in range(T):
                ai=avec[r] if c==0 else oa[r][c-1]
                bi=bvec[c] if r==0 else ob[r-1][c]
                acc[r][c]+=ai*bi; aout[r][c]=ai; bout[r][c]=bi
        step+=1
    for _ in range(T-1):
        oa=[x[:] for x in aout]; ob=[x[:] for x in bout]
        for r in range(T):
            for c in range(T):
                ai=0 if c==0 else oa[r][c-1]
                bi=0 if r==0 else ob[r-1][c]
                acc[r][c]+=ai*bi; aout[r][c]=ai; bout[r][c]=bi
    return acc

def main():
    cases=0
    for T in (1,2,4,8):
        for _ in range(250):
            M=random.randint(1,2*T+3); N=random.randint(1,2*T+3); K=random.randint(1,20)
            A=[[random.randint(-8,7) for _ in range(K)] for _ in range(M)]
            B=[[random.randint(-8,7) for _ in range(N)] for _ in range(K)]
            C=matmul(A,B)
            for tm in range((M+T-1)//T):
                for tn in range((N+T-1)//T):
                    got=tile_cycle(A,B,T,tm,tn)
                    for r in range(T):
                        for c in range(T):
                            rr,cc=tm*T+r,tn*T+c
                            if rr<M and cc<N:
                                assert got[r][c]==C[rr][cc], (T,M,N,K,tm,tn,r,c,got[r][c],C[rr][cc])
            cases+=1
    print(f'PASS: {cases} random matrix shapes, all tiles, random stalls')
if __name__=='__main__': main()
