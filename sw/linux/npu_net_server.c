/*
 * Sam NPU TCP accelerator server for Linux on EBAZ4205.
 *
 * Network path:
 *   PC/main board -> TCP -> Cortex-A9/Linux -> coherent AXI-DMA buffers
 *                 -> AXI DMA -> Sam NPU -> AXI DMA -> TCP reply
 *
 * Protocol v1 stays wire-compatible with the earlier release and now supports:
 *   0 INFO, 1 MatMul, 2 Conv stream, 3 MaxPool2x2, 4 elementwise INT8 Add.
 */
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#include "matmul_layout.h"

#define BUF_BYTES (4u*1024u*1024u)
#define UIO_MAP_SIZE 0x1000u
#define DEFAULT_PORT 9505

#define NPU_DMA_IOC_MAGIC 'N'
#define NPU_DMA_TX_START _IOW(NPU_DMA_IOC_MAGIC, 3, unsigned int)
#define NPU_DMA_RX_START _IOW(NPU_DMA_IOC_MAGIC, 4, unsigned int)
#define NPU_DMA_TX_WAIT  _IO(NPU_DMA_IOC_MAGIC, 5)
#define NPU_DMA_RX_WAIT  _IO(NPU_DMA_IOC_MAGIC, 6)
#define NPU_DMA_TX_CANCEL _IO(NPU_DMA_IOC_MAGIC, 7)
#define NPU_DMA_RX_CANCEL _IO(NPU_DMA_IOC_MAGIC, 8)

#define REG_CTRL    0x00
#define REG_M       0x04
#define REG_N       0x08
#define REG_K       0x0C
#define REG_ACT     0x10
#define REG_CMD     0x14
#define REG_QMUL    0x18
#define REG_QSHIFT  0x1C
#define REG_ZP      0x20
#define REG_VERSION 0x24
#define REG_CAPS    0x28
#define REG_TOTAL   0x2C
#define REG_BUSY    0x30
#define REG_JOBS    0x34
#define REG_ERRORS  0x38
#define REG_LASTJOB 0x3C

#define CMD_IRQ_EN     (1u << 0)
#define CMD_ACK_DONE   (1u << 1)
#define CMD_ACK_ERROR  (1u << 2)
#define CMD_PERF_CLEAR (1u << 3)
#define CMD_ABORT      (1u << 4)

#define OP_INFO    0
#define OP_MATMUL  1
#define OP_CONV    2
#define OP_MAXPOOL 3
#define OP_ADD     4
#define FLAG_RELU        1u
#define FLAG_MATMUL_BIAS 2u

#pragma pack(push,1)
struct req_hdr_wire {
    char magic[4];
    uint16_t version_be;
    uint16_t opcode_be;
    uint16_t m_be;
    uint16_t n_be;
    uint16_t k_be;
    uint16_t flags_be;
    uint32_t qmul_be;
    uint8_t qshift;
    int8_t zero_point;
    uint16_t reserved_be;
    uint32_t input_bytes_be;
    uint32_t output_bytes_be;
    uint32_t request_id_be;
};

struct rep_hdr_wire {
    char magic[4];
    uint32_t request_id_be;
    uint32_t status_be;
    uint32_t output_bytes_be;
};
#pragma pack(pop)

static volatile sig_atomic_t keep_running = 1;
static volatile uint32_t *regs;

static void on_signal(int sig) { (void)sig; keep_running = 0; }
/* Do not restart accept/recv automatically: SIGTERM must stop an idle service. */
static int install_signal_handlers(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sigemptyset(&sa.sa_mask);
    sa.sa_handler = on_signal;
    if (sigaction(SIGINT, &sa, NULL) || sigaction(SIGTERM, &sa, NULL)) return -1;
    sa.sa_handler = SIG_IGN;
    return sigaction(SIGPIPE, &sa, NULL);
}
static inline void wr(unsigned off, uint32_t v) { regs[off >> 2] = v; }
static inline uint32_t rd(unsigned off) { return regs[off >> 2]; }

static int recv_all(int fd, void *buf, size_t len)
{
    uint8_t *p = buf;
    while (len && keep_running) {
        ssize_t n = recv(fd, p, len, 0);
        if (n == 0) return -1;
        if (n < 0) { if (errno == EINTR && keep_running) continue; return -1; }
        p += (size_t)n; len -= (size_t)n;
    }
    return len ? -1 : 0;
}

static int send_all(int fd, const void *buf, size_t len)
{
    const uint8_t *p = buf;
    while (len && keep_running) {
        ssize_t n = send(fd, p, len, MSG_NOSIGNAL);
        if (n == 0) return -1;
        if (n < 0) { if (errno == EINTR && keep_running) continue; return -1; }
        p += (size_t)n; len -= (size_t)n;
    }
    return len ? -1 : 0;
}

static int npu_wait_done_ms(unsigned timeout_ms)
{
    struct timespec t0, now;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (;;) {
        uint32_t s = rd(REG_CTRL);
        if (s & (1u << 2)) return -2;
        if (s & (1u << 1)) return 0;
        clock_gettime(CLOCK_MONOTONIC, &now);
        uint64_t ms = (uint64_t)(now.tv_sec - t0.tv_sec) * 1000u;
        long ns = now.tv_nsec - t0.tv_nsec;
        if (ns < 0) { ms -= 1000u; ns += 1000000000L; }
        ms += (uint64_t)ns / 1000000u;
        if (ms >= timeout_ms) return -3;
        struct timespec nap = {0, 100000L};
        nanosleep(&nap, NULL);
    }
}

static void dma_cancel_both(int dma_fd)
{
    (void)ioctl(dma_fd, NPU_DMA_TX_CANCEL);
    (void)ioctl(dma_fd, NPU_DMA_RX_CANCEL);
}

static void abort_job(int dma_fd)
{
    dma_cancel_both(dma_fd);
    wr(REG_CMD, (rd(REG_CMD) & CMD_IRQ_EN) | CMD_ABORT | CMD_ACK_DONE | CMD_ACK_ERROR);
}

static int send_reply_header(int cfd, uint32_t reqid, int32_t status, uint32_t out_bytes)
{
    struct rep_hdr_wire r;
    memcpy(r.magic, "SNPR", 4);
    r.request_id_be = htonl(reqid);
    r.status_be = htonl((uint32_t)status);
    r.output_bytes_be = htonl(out_bytes);
    return send_all(cfd, &r, sizeof(r));
}


static int send_info(int cfd, uint32_t reqid)
{
    uint32_t info[7] = {
        htonl(rd(REG_VERSION)), htonl(rd(REG_CAPS)), htonl(rd(REG_TOTAL)),
        htonl(rd(REG_BUSY)), htonl(rd(REG_JOBS)), htonl(rd(REG_ERRORS)),
        htonl(rd(REG_LASTJOB))
    };
    if (send_reply_header(cfd, reqid, 0, sizeof(info)) < 0) return -1;
    return send_all(cfd, info, sizeof(info));
}

static int validate_conv_payload(const uint8_t *buf, unsigned in_len, unsigned out_len)
{
    if ((in_len & 0xFu) || (out_len & 0x3u) || !in_len || !out_len) return -1;
    unsigned end_markers = 0;
    unsigned macs_this_output = 0;
    unsigned beats = in_len / 16u;
    for (unsigned i = 0; i < beats; ++i) {
        const uint8_t *p = buf + (size_t)i * 16u;
        uint32_t w = (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
                     ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
        ++macs_this_output;
        /* INT32 accumulation is safe for at most 131071 worst-case
         * signed INT8 products (|-128 * -128| = 16384). */
        if (macs_this_output > 131071u) return -1;
        if (w & (1u << 16)) {
            ++end_markers;
            macs_this_output = 0;
        }
    }
    if (macs_this_output != 0u) return -1;
    if (end_markers != out_len / 4u) return -1;
    // Final AXI beat must close both the final scalar and the full Conv job.
    const uint8_t *last = buf + in_len - 16u;
    uint32_t w = (uint32_t)last[0] | ((uint32_t)last[1] << 8) |
                 ((uint32_t)last[2] << 16) | ((uint32_t)last[3] << 24);
    return (w & (1u << 16)) ? 0 : -1;
}

static int handle_client(int cfd, int dma_fd, uint8_t *tx, uint8_t *rx)
{
    struct req_hdr_wire h;
    if (recv_all(cfd, &h, sizeof(h)) < 0) return -1;

    uint32_t reqid = ntohl(h.request_id_be);
    if (memcmp(h.magic, "SNPU", 4) || ntohs(h.version_be) != 1) {
        send_reply_header(cfd, reqid, -10, 0); return -1;
    }

    unsigned opcode = ntohs(h.opcode_be);
    unsigned M = ntohs(h.m_be), N = ntohs(h.n_be), K = ntohs(h.k_be);
    unsigned flags = ntohs(h.flags_be);
    int32_t qmul = (int32_t)ntohl(h.qmul_be);
    unsigned qshift = h.qshift;
    int8_t zp = h.zero_point;
    unsigned in_len = ntohl(h.input_bytes_be);
    unsigned out_len = ntohl(h.output_bytes_be);

    if (opcode == OP_INFO) {
        if (in_len || out_len) { send_reply_header(cfd, reqid, -11, 0); return -1; }
        return send_info(cfd, reqid);
    }

    if ((flags & ~(FLAG_RELU | FLAG_MATMUL_BIAS)) ||
        ((flags & FLAG_MATMUL_BIAS) && opcode != OP_MATMUL) ||
        opcode < OP_MATMUL || opcode > OP_ADD ||
        !in_len || !out_len || in_len > BUF_BYTES || out_len > BUF_BYTES ||
        qshift > 63 || (opcode == OP_MATMUL && (!M || !N || !K)) ||
        (in_len & 0xFu) != 0 || (out_len & 0x3u) != 0) {
        send_reply_header(cfd, reqid, -11, 0); return -1;
    }
    /* Refuse requests the attached hardware does not advertise. This catches
     * software/bitstream version skew before a DMA transfer can deadlock. */
    uint32_t caps = rd(REG_CAPS);
    unsigned cap_bit = opcode == OP_MATMUL ? 0u : opcode == OP_CONV ? 1u :
                       opcode == OP_MAXPOOL ? 2u : 3u;
    if (!(caps & (1u << cap_bit)) ||
        ((flags & FLAG_MATMUL_BIAS) && !(caps & (1u << 7)))) {
        send_reply_header(cfd, reqid, -14, 0); return -1;
    }

    if (opcode == OP_MATMUL) {
        uint64_t mt = ((uint64_t)M + 7u) / 8u;
        uint64_t nt = ((uint64_t)N + 7u) / 8u;
        uint64_t per_tile = ((uint64_t)K + 7u) * 16u;
        if (flags & FLAG_MATMUL_BIAS) per_tile += 32u; /* 8 x INT32 bias */
        uint64_t expected_in = mt * nt * per_tile;
        uint64_t expected_out = (uint64_t)M * (uint64_t)N * 4u;
        if (expected_in != in_len || expected_out != out_len) {
            send_reply_header(cfd, reqid, -12, 0); return -1;
        }
    } else if (opcode == OP_MAXPOOL) {
        // Four 128-bit input beats produce one 32-bit sign-extended result.
        if ((uint64_t)in_len != (uint64_t)out_len * 16u) {
            send_reply_header(cfd, reqid, -12, 0); return -1;
        }
    } else if (opcode == OP_ADD) {
        // One 128-bit pair beat produces one 32-bit sign-extended result.
        if ((uint64_t)in_len != (uint64_t)out_len * 4u) {
            send_reply_header(cfd, reqid, -12, 0); return -1;
        }
    }

    if (recv_all(cfd, tx, in_len) < 0) return -1;
    if (opcode == OP_CONV && validate_conv_payload(tx, in_len, out_len) < 0) {
        send_reply_header(cfd, reqid, -13, 0); return -1;
    }
    memset(rx, 0, out_len);

    /* Hardware silently ignores configuration/START writes while BUSY (config
     * lock, no error flag), and a stale sticky DONE would end the next wait
     * immediately.  Start only from an idle, acknowledged state. */
    if (rd(REG_CTRL) & 1u) {
        abort_job(dma_fd);
        if (rd(REG_CTRL) & 1u) { send_reply_header(cfd, reqid, -15, 0); return -1; }
    }
    wr(REG_CMD, (rd(REG_CMD) & CMD_IRQ_EN) | CMD_ACK_DONE | CMD_ACK_ERROR);

    wr(REG_M, M); wr(REG_N, N); wr(REG_K, K);
    wr(REG_ACT, !!(flags & FLAG_RELU));
    wr(REG_QMUL, (uint32_t)qmul);
    wr(REG_QSHIFT, qshift);
    wr(REG_ZP, (uint8_t)zp);

    unsigned l = out_len;
    if (ioctl(dma_fd, NPU_DMA_RX_START, &l) < 0) {
        perror("RX_START"); send_reply_header(cfd, reqid, -20, 0); return -1;
    }
    l = in_len;
    if (ioctl(dma_fd, NPU_DMA_TX_START, &l) < 0) {
        perror("TX_START"); abort_job(dma_fd); send_reply_header(cfd, reqid, -21, 0); return -1;
    }

    uint32_t mode = 0;
    if (opcode == OP_CONV) mode = 1u << 1;
    else if (opcode == OP_MAXPOOL) mode = 1u << 2;
    else if (opcode == OP_ADD) mode = 1u << 3;
    if (opcode == OP_MATMUL && (flags & FLAG_MATMUL_BIAS)) mode |= 1u << 4;
    wr(REG_CTRL, 1u | mode);

    if (ioctl(dma_fd, NPU_DMA_TX_WAIT) < 0) {
        perror("TX_WAIT"); abort_job(dma_fd); send_reply_header(cfd, reqid, -22, 0); return -1;
    }
    int st = npu_wait_done_ms(5000);
    if (st) {
        fprintf(stderr, "NPU wait failed: %d\n", st);
        abort_job(dma_fd); send_reply_header(cfd, reqid, st == -2 ? -30 : -31, 0); return -1;
    }
    if (ioctl(dma_fd, NPU_DMA_RX_WAIT) < 0) {
        perror("RX_WAIT"); abort_job(dma_fd); send_reply_header(cfd, reqid, -23, 0); return -1;
    }

    fprintf(stdout, "req=%u op=%u bytes=%u->%u last_job_cycles=%u\n",
            reqid, opcode, in_len, out_len, rd(REG_LASTJOB));

    /* Hardware serializes MatMul one output tile at a time.  Expose a stable
     * network ABI by reordering those 32-bit sign-extended INT8 words into
     * ordinary row-major MxN order before replying.  MM2S has completed, so
     * the TX coherent buffer is safe scratch space here. */
    const uint8_t *reply_data = rx;
    if (opcode == OP_MATMUL) {
        sam_npu_matmul_tile_to_row_major(tx, rx, M, N, 8u);
        reply_data = tx;
    }

    if (send_reply_header(cfd, reqid, 0, out_len) < 0) return -1;
    if (send_all(cfd, reply_data, out_len) < 0) return -1;
    return 0;
}

int main(int argc, char **argv)
{
    int port = argc > 1 ? atoi(argv[1]) : DEFAULT_PORT;
    const char *uio_dev = argc > 2 ? argv[2] : "/dev/uio0";
    const char *dma_dev = argc > 3 ? argv[3] : "/dev/npu_dma";
    /* The protocol has no authentication. Optional 4th argument restricts the
     * listening address (e.g. 192.168.50.2 for the direct PC link). */
    const char *bind_ip = argc > 4 ? argv[4] : NULL;

    if (install_signal_handlers() < 0) { perror("sigaction"); return 1; }

    int uio_fd = open(uio_dev, O_RDWR | O_SYNC);
    if (uio_fd < 0) { perror("open uio"); return 1; }
    regs = mmap(NULL, UIO_MAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, uio_fd, 0);
    if (regs == MAP_FAILED) { perror("mmap uio"); return 1; }

    int dma_fd = open(dma_dev, O_RDWR);
    if (dma_fd < 0) { perror("open dma"); return 1; }
    uint8_t *tx = mmap(NULL, BUF_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, dma_fd, 0);
    uint8_t *rx = mmap(NULL, BUF_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, dma_fd, BUF_BYTES);
    if (tx == MAP_FAILED || rx == MAP_FAILED) { perror("mmap dma"); return 1; }

    uint32_t ver = rd(REG_VERSION), caps = rd(REG_CAPS);
    printf("Sam NPU hw version=%u.%u caps=0x%08x\n", ver >> 16, ver & 0xffffu, caps);

    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) { perror("socket"); return 1; }
    int one = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET; a.sin_port = htons((uint16_t)port); a.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind_ip && inet_pton(AF_INET, bind_ip, &a.sin_addr) != 1) {
        fprintf(stderr, "invalid bind address: %s\n", bind_ip); return 1;
    }
    if (bind(s, (struct sockaddr *)&a, sizeof(a)) < 0) { perror("bind"); return 1; }
    if (listen(s, 4) < 0) { perror("listen"); return 1; }

    printf("Sam NPU TCP server listening on %s:%d\n", bind_ip ? bind_ip : "0.0.0.0", port);
    printf("UIO=%s DMA=%s max_payload=%u bytes\n", uio_dev, dma_dev, BUF_BYTES);
    while (keep_running) {
        struct sockaddr_in peer; socklen_t plen = sizeof(peer);
        int c = accept(s, (struct sockaddr *)&peer, &plen);
        if (c < 0) { if (errno == EINTR) continue; perror("accept"); break; }
        struct timeval io_to = { .tv_sec = 15, .tv_usec = 0 };
        (void)setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &io_to, sizeof(io_to));
        (void)setsockopt(c, SOL_SOCKET, SO_SNDTIMEO, &io_to, sizeof(io_to));
        char ip[INET_ADDRSTRLEN] = "?";
        inet_ntop(AF_INET, &peer.sin_addr, ip, sizeof(ip));
        printf("client %s:%u\n", ip, ntohs(peer.sin_port));
        while (keep_running && handle_client(c, dma_fd, tx, rx) == 0) {}
        close(c);
    }

    abort_job(dma_fd);
    close(s);
    munmap(tx, BUF_BYTES); munmap(rx, BUF_BYTES); close(dma_fd);
    munmap((void *)regs, UIO_MAP_SIZE); close(uio_fd);
    return 0;
}
