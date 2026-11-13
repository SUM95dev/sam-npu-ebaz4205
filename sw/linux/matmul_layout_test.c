#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "matmul_layout.h"

static void putw32(uint8_t *p, uint32_t v){ memcpy(p,&v,4); }
static uint32_t getw32(const uint8_t *p){ uint32_t v; memcpy(&v,p,4); return v; }

int main(void)
{
    /* 3x5, tile=2. Create a synthetic hardware tile-major stream whose word
       value is row*100+col, then prove the converter restores row-major. */
    enum { M=3, N=5, T=2 };
    uint8_t src[M*N*4], dst[M*N*4];
    size_t si=0;
    memset(src,0,sizeof(src)); memset(dst,0,sizeof(dst));
    for(unsigned tm=0; tm<(M+T-1)/T; ++tm)
      for(unsigned tn=0; tn<(N+T-1)/T; ++tn)
        for(unsigned r=0;r<T;++r){ unsigned row=tm*T+r; if(row>=M) continue;
          for(unsigned c=0;c<T;++c){ unsigned col=tn*T+c; if(col>=N) continue;
            putw32(src+4*si++, row*100u+col); }}
    if(sam_npu_matmul_tile_to_row_major(dst,src,M,N,T)!=M*N) return 2;
    for(unsigned r=0;r<M;++r) for(unsigned c=0;c<N;++c)
      if(getw32(dst+4*(r*N+c)) != r*100u+c) return 3;
    puts("PASS MatMul tile-major -> row-major layout");
    return 0;
}
