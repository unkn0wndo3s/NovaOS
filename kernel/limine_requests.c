#include <limine.h>

__attribute__((used, section(".limine_requests")))
static volatile struct limine_memmap_request memmap_request = {
    .id = LIMINE_MEMMAP_REQUEST,
    .revision = 0
};

__attribute__((used, section(".limine_requests")))
static volatile struct limine_hhdm_request hhdm_request = {
    .id = LIMINE_HHDM_REQUEST,
    .revision = 0
};

__attribute__((used, section(".limine_requests")))
static volatile struct limine_executable_address_request exec_addr_request = {
    .id = LIMINE_EXECUTABLE_ADDRESS_REQUEST,
    .revision = 0
};

/* Request boot modules (for initrd) */
__attribute__((used, section(".limine_requests")))
static volatile struct limine_module_request module_request = {
    .id = LIMINE_MODULE_REQUEST,
    .revision = 0
};

__attribute__((used, section(".limine_requests_start")))
static volatile LIMINE_REQUESTS_START_MARKER;
__attribute__((used, section(".limine_requests_end")))
static volatile LIMINE_REQUESTS_END_MARKER;

/* Framebuffer request for global access */
__attribute__((used, section(".limine_requests")))
static volatile struct limine_framebuffer_request framebuffer_request = {
    .id = LIMINE_FRAMEBUFFER_REQUEST,
    .revision = 0
};

volatile struct limine_memmap_response *get_memmap_response(void) {
    return memmap_request.response;
}

uint64_t get_hhdm_offset(void) {
    return hhdm_request.response ? hhdm_request.response->offset : 0;
}

void get_kernel_phys_range(uint64_t *phys_base, uint64_t *virt_base) {
    if (!exec_addr_request.response) { *phys_base = 0; *virt_base = 0; return; }
    *phys_base = exec_addr_request.response->physical_base;
    *virt_base = exec_addr_request.response->virtual_base;
}

volatile struct limine_module_response *get_module_response(void) {
    return module_request.response;
}

static int kstrcmp(const char *a, const char *b) {
    if (!a || !b) return (a==b)?0:(a?1:-1);
    while (*a && *b) { if (*a != *b) return (unsigned char)*a - (unsigned char)*b; a++; b++; }
    return (unsigned char)*a - (unsigned char)*b;
}

int get_module_by_string(const char *string, void **ptr, uint64_t *size) {
    volatile struct limine_module_response *resp = module_request.response;
    if (!resp || !resp->module_count) return 0;
    for (uint64_t i = 0; i < resp->module_count; i++) {
        struct limine_file *f = resp->modules[i];
#if LIMINE_API_REVISION >= 3
        const char *s = f->string;
#else
        const char *s = f->cmdline;
#endif
        if (string && s && kstrcmp(s, string) == 0) {
            if (ptr) *ptr = f->address;
            if (size) *size = f->size;
            return 1;
        }
    }
    return 0;
}

struct limine_framebuffer *get_framebuffer0(void) {
    if (!framebuffer_request.response) return 0;
    if (framebuffer_request.response->framebuffer_count < 1) return 0;
    return framebuffer_request.response->framebuffers[0];
}


