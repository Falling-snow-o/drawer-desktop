/*
 * test-vram.c —— 验证 boxrun-vram.so 的拦截是否真的生效
 *
 * 直接调用 cuMemAlloc_v2（链接期绑定），这样 LD_PRELOAD 的符号才会被用上；
 * 如果改成 dlopen + dlsym(handle, ...)，拿到的会是 libcuda 自己的符号，绕开闸门。
 *
 * WSL 里 cuMemAlloc 需要当前上下文，所以要先 retain 主上下文，否则返回 201。
 *
 * 构建：gcc -O2 -o test-vram test-vram.c -L/usr/lib/wsl/lib -lcuda -Wl,-rpath,/usr/lib/wsl/lib
 */
#include <stddef.h>
#include <stdio.h>

extern int cuInit(unsigned int);
extern int cuDeviceGet(int *, int);
extern int cuDevicePrimaryCtxRetain(void **, int);
extern int cuCtxSetCurrent(void *);
extern int cuMemAlloc_v2(void **, size_t);

int main(void)
{
    const size_t chunk = 256UL * 1024 * 1024; /* 256 MiB */
    void *ctx = NULL;
    int dev = 0;
    int i;
    int r;

    printf("cuInit=%d\n", cuInit(0));
    printf("cuDeviceGet=%d\n", cuDeviceGet(&dev, 0));
    printf("cuDevicePrimaryCtxRetain=%d\n", cuDevicePrimaryCtxRetain(&ctx, dev));
    printf("cuCtxSetCurrent=%d\n", cuCtxSetCurrent(ctx));

    for (i = 0; i < 8; i++) {
        void *p = NULL;
        r = cuMemAlloc_v2(&p, chunk);
        printf("alloc[%d] 256 MiB -> r=%d\n", i, r);
        if (r != 0)
            break;
    }
    return 0;
}
