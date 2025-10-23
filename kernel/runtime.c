// Minimal freestanding runtime for kernel mode (no libc)
// Provides the small set of libc symbols libnsgif expects.

#include <stdint.h>
#include <stddef.h>

void *memcpy(void *dest, const void *src, size_t n){
    uint8_t *d = (uint8_t*)dest; const uint8_t *s = (const uint8_t*)src;
    for (size_t i = 0; i < n; i++) d[i] = s[i];
    return dest;
}

void *memmove(void *dest, const void *src, size_t n){
    uint8_t *d = (uint8_t*)dest; const uint8_t *s = (const uint8_t*)src;
    if (d == s || n == 0) return dest;
    if (d < s){
        for (size_t i = 0; i < n; i++) d[i] = s[i];
    } else {
        for (size_t i = n; i > 0; i--) d[i-1] = s[i-1];
    }
    return dest;
}

void *memset(void *dest, int c, size_t n){
    uint8_t *d = (uint8_t*)dest; uint8_t v = (uint8_t)c;
    for (size_t i = 0; i < n; i++) d[i] = v;
    return dest;
}

int memcmp(const void *a, const void *b, size_t n){
    const uint8_t *A = (const uint8_t*)a, *B = (const uint8_t*)b;
    for (size_t i = 0; i < n; i++){
        if (A[i] != B[i]) return (A[i] < B[i]) ? -1 : 1;
    }
    return 0;
}

int strncmp(const char *a, const char *b, size_t n){
    for (size_t i = 0; i < n; i++){
        unsigned char ca = (unsigned char)a[i];
        unsigned char cb = (unsigned char)b[i];
        if (ca != cb) return (ca < cb) ? -1 : 1;
        if (ca == '\0') return 0;
    }
    return 0;
}

/* -------- Very simple bump allocator -------- */
#define KHEAP_SIZE (4u*1024u*1024u)
static uint8_t KHEAP[KHEAP_SIZE];
typedef struct HeapHeader { size_t size; } HeapHeader;
static size_t kheappos = 0;

static void *heap_alloc(size_t size){
    if (size == 0) size = 1;
    size = (size + 7u) & ~7u; // 8-byte align
    size_t total = size + sizeof(HeapHeader);
    if (kheappos + total > KHEAP_SIZE) return (void*)0;
    HeapHeader *h = (HeapHeader*)(KHEAP + kheappos);
    h->size = size;
    kheappos += total;
    return (void*)(h + 1);
}

void free(void *ptr){ (void)ptr; /* no-op */ }

void *malloc(size_t size){
    return heap_alloc(size);
}

void *calloc(size_t nmemb, size_t size){
    if (nmemb && size > ((size_t)-1) / nmemb) return (void*)0;
    size_t total = nmemb * size;
    void *p = heap_alloc(total);
    if (p) memset(p, 0, total);
    return p;
}

void *realloc(void *ptr, size_t new_size){
    if (ptr == (void*)0) return malloc(new_size);
    if (new_size == 0){ free(ptr); return (void*)0; }
    HeapHeader *h = (HeapHeader*)ptr - 1;
    size_t old_size = h->size;
    void *np = heap_alloc(new_size);
    if (!np) return (void*)0;
    size_t copy = (old_size < new_size) ? old_size : new_size;
    memmove(np, ptr, copy);
    return np;
}

/* -------- assert handler -------- */
void __assert_fail(const char *expr, const char *file, int line, const char *func){
    (void)expr; (void)file; (void)line; (void)func;
    for(;;){ __asm__ __volatile__("hlt"); }
}
