#ifndef SAM_NPU_MATMUL_LAYOUT_H
#define SAM_NPU_MATMUL_LAYOUT_H
#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* Hardware emits valid 32-bit result words tile-by-tile, row-major inside each
 * tile. Convert that stream into conventional row-major MxN order. src/dst
 * must not overlap. Returns the number of 32-bit words consumed. */
static inline size_t sam_npu_matmul_tile_to_row_major(uint8_t *dst,
                                                       const uint8_t *src,
                                                       unsigned M,
                                                       unsigned N,
                                                       unsigned tile)
{
    size_t si = 0;
    if (!dst || !src || !M || !N || !tile)
        return 0;
    for (unsigned tm = 0; tm < (M + tile - 1u) / tile; ++tm) {
        for (unsigned tn = 0; tn < (N + tile - 1u) / tile; ++tn) {
            for (unsigned r = 0; r < tile; ++r) {
                unsigned row = tm * tile + r;
                if (row >= M) continue;
                for (unsigned c = 0; c < tile; ++c) {
                    unsigned col = tn * tile + c;
                    if (col >= N) continue;
                    size_t di = ((size_t)row * (size_t)N + col) * 4u;
                    memcpy(dst + di, src + si * 4u, 4u);
                    ++si;
                }
            }
        }
    }
    return si;
}
#endif
