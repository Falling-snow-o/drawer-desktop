/*
 * boxrun-vram.c —— 把 gpu.vram 从"账本"变成"闸"
 *
 * 原理：LD_PRELOAD 拦 libcuda 的显存分配入口，累计本进程申请到的字节数，
 *       超过 BOXRUN_VRAM_MB 就从这里直接返回 CUDA_ERROR_OUT_OF_MEMORY，
 *       让 PyTorch / 任何框架照常走它们自己的 OOM 处理，而不是把整卡吃满。
 *
 * 覆盖：cuMemAlloc / cuMemAlloc_v2 / cuMemAllocManaged / cuMemAllocAsync /
 *       cuMemAllocPitch / cuMemAllocPitch_v2，以及对应的 Free / FreeAsync。
 *
 * 不覆盖（故意的）：
 *   - cuMemCreate / cuMemMap（VMM API）：那里只是预留虚拟地址，真正占用发生在 map，
 *     拦它会把正常框架拦死，而且语义完全不同；
 *   - CUDA graph、驱动内部池、别的进程：这是"进程内软闸"，不是 MIG。
 *   GeForce 上本来就没有显存硬切分，别指望这个能防住所有路径。
 *
 * 构建：gcc -O2 -fPIC -shared -o boxrun-vram.so boxrun-vram.c -ldl -lpthread
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int CUresult;
typedef void *CUstream;

#define BOXRUN_CUDA_SUCCESS 0
#define BOXRUN_CUDA_ERROR_OUT_OF_MEMORY 2
#define BOXRUN_CUDA_ERROR_NOT_SUPPORTED 801

#define NBUCKETS 1024

typedef struct entry {
    void *ptr;
    size_t size;
    struct entry *next;
} entry;

static entry *g_buckets[NBUCKETS];
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static size_t g_limit = 0;   /* 0 = 不限制 */
static size_t g_used = 0;
static int g_ready = 0;

static size_t bucket_of(void *p)
{
    return ((uintptr_t)p >> 4) % NBUCKETS;
}

static void init_once(void)
{
    const char *s;

    if (g_ready)
        return;
    g_ready = 1;

    s = getenv("BOXRUN_VRAM_MB");
    if (s && *s) {
        long long mb = atoll(s);
        if (mb > 0)
            g_limit = (size_t)mb * 1024ULL * 1024ULL;
    }
}

static void track(void *p, size_t size)
{
    entry *e;
    size_t b;

    if (!p)
        return;
    e = (entry *)malloc(sizeof(*e));
    if (!e)
        return;
    e->ptr = p;
    e->size = size;
    b = bucket_of(p);
    e->next = g_buckets[b];
    g_buckets[b] = e;
}

static size_t untrack(void *p)
{
    entry **pp;
    size_t b;

    if (!p)
        return 0;
    b = bucket_of(p);
    for (pp = &g_buckets[b]; *pp; pp = &(*pp)->next) {
        if ((*pp)->ptr == p) {
            entry *e = *pp;
            size_t size = e->size;
            *pp = e->next;
            free(e);
            return size;
        }
    }
    return 0;
}

/* 分配前判断：超了就拒绝，并留一行可读日志 */
static int would_exceed(size_t size)
{
    int deny;

    pthread_mutex_lock(&g_lock);
    init_once();
    deny = (g_limit != 0 && g_used + size > g_limit);
    if (deny)
        fprintf(stderr,
                "[boxrun-vram] 拒绝分配 %zu MiB：已用 %zu / 上限 %zu MiB\n",
                size >> 20, g_used >> 20, g_limit >> 20);
    pthread_mutex_unlock(&g_lock);
    return deny;
}

static void account(void *p, size_t size)
{
    if (!p)
        return;
    pthread_mutex_lock(&g_lock);
    track(p, size);
    g_used += size;
    pthread_mutex_unlock(&g_lock);
}

static void release(void *p)
{
    size_t size;

    pthread_mutex_lock(&g_lock);
    size = untrack(p);
    if (size <= g_used)
        g_used -= size;
    else
        g_used = 0;
    pthread_mutex_unlock(&g_lock);
}

/* ---------------- 真实符号 ---------------- */

static void *real_of(const char *name)
{
    return dlsym(RTLD_NEXT, name);
}

static CUresult (*real_mem_alloc)(void **, size_t);
static CUresult (*real_mem_alloc_pitch)(void **, size_t *, size_t, size_t, unsigned int);

static CUresult (*resolve_alloc(void))(void **, size_t)
{
    CUresult (*fn)(void **, size_t) = NULL;

    fn = (CUresult (*)(void **, size_t))real_of("cuMemAlloc_v2");
    if (!fn)
        fn = (CUresult (*)(void **, size_t))real_of("cuMemAlloc");
    return fn;
}

static CUresult guarded_alloc(void **dptr, size_t size)
{
    CUresult r;

    if (!real_mem_alloc)
        real_mem_alloc = resolve_alloc();
    if (!real_mem_alloc)
        return BOXRUN_CUDA_ERROR_NOT_SUPPORTED;

    if (would_exceed(size))
        return BOXRUN_CUDA_ERROR_OUT_OF_MEMORY;

    r = real_mem_alloc(dptr, size);
    if (r == BOXRUN_CUDA_SUCCESS)
        account(*dptr, size);
    return r;
}

/* ---------------- 导出符号 ---------------- */

CUresult cuMemAlloc(void **dptr, size_t bytesize)
{
    return guarded_alloc(dptr, bytesize);
}

CUresult cuMemAlloc_v2(void **dptr, size_t bytesize)
{
    return guarded_alloc(dptr, bytesize);
}

CUresult cuMemAllocManaged(void **dptr, size_t bytesize, unsigned int flags)
{
    static CUresult (*real)(void **, size_t, unsigned int);
    CUresult r;

    if (!real)
        real = (CUresult (*)(void **, size_t, unsigned int))real_of("cuMemAllocManaged");
    if (!real)
        return BOXRUN_CUDA_ERROR_NOT_SUPPORTED;
    if (would_exceed(bytesize))
        return BOXRUN_CUDA_ERROR_OUT_OF_MEMORY;

    r = real(dptr, bytesize, flags);
    if (r == BOXRUN_CUDA_SUCCESS)
        account(*dptr, bytesize);
    return r;
}

CUresult cuMemAllocAsync(void **dptr, size_t bytesize, CUstream stream)
{
    static CUresult (*real)(void **, size_t, CUstream);
    CUresult r;

    if (!real)
        real = (CUresult (*)(void **, size_t, CUstream))real_of("cuMemAllocAsync");
    if (!real)
        return BOXRUN_CUDA_ERROR_NOT_SUPPORTED;
    if (would_exceed(bytesize))
        return BOXRUN_CUDA_ERROR_OUT_OF_MEMORY;

    r = real(dptr, bytesize, stream);
    if (r == BOXRUN_CUDA_SUCCESS)
        account(*dptr, bytesize);
    return r;
}

CUresult cuMemAllocPitch_v2(void **dptr, size_t *pPitch, size_t width, size_t height,
                            unsigned int elem)
{
    CUresult r;
    size_t want = width * height;

    if (!real_mem_alloc_pitch)
        real_mem_alloc_pitch = (CUresult (*)(void **, size_t *, size_t, size_t, unsigned int))
                               real_of("cuMemAllocPitch_v2");
    if (!real_mem_alloc_pitch)
        real_mem_alloc_pitch = (CUresult (*)(void **, size_t *, size_t, size_t, unsigned int))
                               real_of("cuMemAllocPitch");
    if (!real_mem_alloc_pitch)
        return BOXRUN_CUDA_ERROR_NOT_SUPPORTED;
    if (would_exceed(want))
        return BOXRUN_CUDA_ERROR_OUT_OF_MEMORY;

    r = real_mem_alloc_pitch(dptr, pPitch, width, height, elem);
    if (r == BOXRUN_CUDA_SUCCESS && pPitch)
        account(*dptr, *pPitch * height);
    return r;
}

CUresult cuMemAllocPitch(void **dptr, size_t *pPitch, size_t width, size_t height,
                         unsigned int elem)
{
    return cuMemAllocPitch_v2(dptr, pPitch, width, height, elem);
}

static CUresult guarded_free(void *dptr, const char *name)
{
    CUresult (*fn)(void *) = (CUresult (*)(void *))real_of(name);
    CUresult r;

    if (!fn) {
        fn = (CUresult (*)(void *))real_of("cuMemFree_v2");
        if (!fn)
            fn = (CUresult (*)(void *))real_of("cuMemFree");
    }
    if (!fn)
        return BOXRUN_CUDA_ERROR_NOT_SUPPORTED;

    r = fn(dptr);
    if (r == BOXRUN_CUDA_SUCCESS)
        release(dptr);
    return r;
}

CUresult cuMemFree(void *dptr)
{
    return guarded_free(dptr, "cuMemFree_v2");
}

CUresult cuMemFree_v2(void *dptr)
{
    return guarded_free(dptr, "cuMemFree_v2");
}

CUresult cuMemFreeAsync(void *dptr, CUstream stream)
{
    static CUresult (*real)(void *, CUstream);
    CUresult r;

    if (!real)
        real = (CUresult (*)(void *, CUstream))real_of("cuMemFreeAsync");
    if (!real)
        return BOXRUN_CUDA_ERROR_NOT_SUPPORTED;

    r = real(dptr, stream);
    if (r == BOXRUN_CUDA_SUCCESS)
        release(dptr);
    return r;
}
