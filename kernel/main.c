// Nova OS — Boot stages with animated GIFs via Limine modules

#include <stdint.h>
#include <stddef.h>
#include <limine.h>

// ----------------- Limine requests -----------------
static volatile struct limine_framebuffer_request framebuffer_request = {
	.id = LIMINE_FRAMEBUFFER_REQUEST,
	.revision = 0
};

static volatile struct limine_module_request module_request = {
	.id = LIMINE_MODULE_REQUEST,
	.revision = 0
};

// ----------------- libc minis -----------------
void *memcpy(void *dest, const void *src, size_t n) {
	uint8_t *d = (uint8_t *)dest; const uint8_t *s = (const uint8_t *)src;
	for (size_t i = 0; i < n; i++) d[i] = s[i];
	return dest;
}
void *memset(void *s, int c, size_t n) {
	uint8_t *p = (uint8_t *)s; for (size_t i = 0; i < n; i++) p[i] = (uint8_t)c; return s;
}
void *memmove(void *dest, const void *src, size_t n) {
	uint8_t *d = (uint8_t *)dest; const uint8_t *s = (const uint8_t *)src;
	if (s > d) for (size_t i = 0; i < n; i++) d[i] = s[i];
	else if (s < d) for (size_t i = n; i > 0; i--) d[i-1] = s[i-1];
	return dest;
}
int memcmp(const void *s1, const void *s2, size_t n) {
	const uint8_t *a = (const uint8_t *)s1, *b = (const uint8_t *)s2;
	for (size_t i = 0; i < n; i++) if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
	return 0;
}

// ----------------- Halt -----------------
static void hcf(void) { asm ("cli"); for (;;) asm ("hlt"); }

// ----------------- Simple heap for stb_image -----------------
typedef struct { size_t size; } blk_header;
static unsigned char STBI_HEAP[32 * 1024 * 1024]; // 32 MiB arena for image decode
static size_t STBI_OFF = 0;
static void *kmalloc(size_t sz) {
	// allocate with header storing size for naive realloc
	sz = (sz + 7) & ~((size_t)7);
	if (sz > (sizeof(STBI_HEAP) - STBI_OFF - sizeof(blk_header))) return NULL;
	blk_header *h = (blk_header *)(STBI_HEAP + STBI_OFF);
	STBI_OFF += sizeof(blk_header);
	h->size = sz;
	void *p = (void *)(STBI_HEAP + STBI_OFF);
	STBI_OFF += sz;
	return p;
}
static void *krealloc(void *p, size_t new_sz) {
	if (!p) return kmalloc(new_sz);
	// naive: allocate new and memcpy min(old, new)
	blk_header *h = (blk_header *)((uint8_t *)p - sizeof(blk_header));
	void *np = kmalloc(new_sz);
	if (!np) return NULL;
	size_t copy = h->size < new_sz ? h->size : new_sz;
	memcpy(np, p, copy);
	return np;
}
static void kfree(void *p) { (void)p; }

// ----------------- stb_image (GIF only) -----------------
#define STBI_NO_STDIO
#define STBI_ONLY_GIF
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STBI_ASSERT(x) ((void)0)
#define STBI_MALLOC(sz) kmalloc(sz)
#define STBI_REALLOC(p,nsz) krealloc((p),(nsz))
#define STBI_FREE(p) kfree(p)
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

// ----------------- FB helpers -----------------
static inline uint32_t fb_pack_rgb(struct limine_framebuffer *fb,
				   uint8_t r, uint8_t g, uint8_t b) {
	uint32_t r_mask = (fb->red_mask_size   >= 8) ? (uint32_t)r : ((uint32_t)r >> (8 - fb->red_mask_size));
	uint32_t g_mask = (fb->green_mask_size >= 8) ? (uint32_t)g : ((uint32_t)g >> (8 - fb->green_mask_size));
	uint32_t b_mask = (fb->blue_mask_size  >= 8) ? (uint32_t)b : ((uint32_t)b >> (8 - fb->blue_mask_size));
	r_mask &= (fb->red_mask_size   == 32 ? 0xFFFFFFFFu : ((1u << fb->red_mask_size)   - 1u));
	g_mask &= (fb->green_mask_size == 32 ? 0xFFFFFFFFu : ((1u << fb->green_mask_size) - 1u));
	b_mask &= (fb->blue_mask_size  == 32 ? 0xFFFFFFFFu : ((1u << fb->blue_mask_size)  - 1u));
	return (r_mask << fb->red_mask_shift) |
	       (g_mask << fb->green_mask_shift) |
	       (b_mask << fb->blue_mask_shift);
}

static inline void put_px(struct limine_framebuffer *fb, uint64_t x, uint64_t y, uint32_t c) {
	if (x >= fb->width || y >= fb->height) return;
	((uint32_t *)fb->address)[(fb->pitch/4) * y + x] = c;
}

static void clear_fb(struct limine_framebuffer *fb, uint8_t r, uint8_t g, uint8_t b) {
	uint32_t c = fb_pack_rgb(fb, r, g, b);
	for (uint64_t y = 0; y < fb->height; y++) {
		uint32_t *row = (uint32_t *)((uint8_t *)fb->address + y * fb->pitch);
		for (uint64_t x = 0; x < fb->width; x++) row[x] = c;
	}
}

static void blit_rgba_center(struct limine_framebuffer *fb, const uint8_t *rgba,
			       int w, int h) {
	if (!rgba || w <= 0 || h <= 0) return;
	// center
	int dst_x = 0;
	int dst_y = 0;
	if ((uint64_t)w < fb->width) dst_x = (int)((fb->width - (uint64_t)w) / 2);
	if ((uint64_t)h < fb->height) dst_y = (int)((fb->height - (uint64_t)h) / 2);
	for (int y = 0; y < h; y++) {
		int64_t py = (int64_t)dst_y + y;
		if (py < 0 || (uint64_t)py >= fb->height) continue;
		const uint8_t *src = rgba + (size_t)y * (size_t)w * 4u;
		for (int x = 0; x < w; x++) {
			int64_t px = (int64_t)dst_x + x;
			if (px < 0 || (uint64_t)px >= fb->width) continue;
			uint8_t R = src[4u * (size_t)x + 0];
			uint8_t G = src[4u * (size_t)x + 1];
			uint8_t B = src[4u * (size_t)x + 2];
			// ignore alpha for now (opaque blit)
			put_px(fb, (uint64_t)px, (uint64_t)py, fb_pack_rgb(fb, R, G, B));
		}
	}
}

// ----------------- Limine modules -----------------
typedef struct {
    const unsigned char *data;
    size_t size;
} file_view;

static file_view find_module_by_suffix(const char *suffix) {
	const struct limine_module_response *resp = module_request.response;
	if (!resp) return (file_view){0};
	for (uint64_t i = 0; i < resp->module_count; i++) {
		struct limine_file *f = resp->modules[i];
		if (!f || !f->path) continue;
		const char *p = f->path;
		size_t j = 0; while (suffix[j]) j++;
		size_t k = 0; while (p[k]) k++;
		while (j && k && suffix[j-1] == p[k-1]) { j--; k--; }
		if (j == 0) return (file_view){ (const unsigned char *)f->address, (size_t)f->size };
	}
	return (file_view){0};
}

// ----------------- GIF helpers -----------------
// Forward decl for fallback delay used in gif_load_from_module
static void busy_sleep_ms(uint32_t ms);

typedef struct {
	unsigned char *frames; // RGBA interleaved frames, size: w*h*4*count
	int *delays_ms;        // length = count
	int w, h, count;
} gif_image;

static int gif_load_from_module(const char *suffix, gif_image *out) {
	*out = (gif_image){0};
	file_view v = find_module_by_suffix(suffix);
    if (!v.data || v.size == 0) return 0;
	int comp = 4;
	int x = 0, y = 0, z = 0;
	int *delays = NULL;
	unsigned char *frames = stbi_load_gif_from_memory((const unsigned char *)v.data, (int)v.size,
							    &delays, &x, &y, &z, &comp, 4);
    if (!frames || x <= 0 || y <= 0 || z <= 0) {
        // Fallback: fill screen with color to indicate failure
        clear_fb(framebuffer_request.response->framebuffers[0], 0x40, 0x00, 0x00);
        busy_sleep_ms(300);
        return 0;
    }
	out->frames = frames;
	out->delays_ms = delays;
	out->w = x;
	out->h = y;
	out->count = z;
	return 1;
}

static void busy_sleep_ms(uint32_t ms) {
    // crude busy-wait; timing varies by CPU speed; bump factor for visibility in QEMU
    volatile uint64_t spins = (uint64_t)ms * 250000ull;
	for (uint64_t i = 0; i < spins; i++) {
		__asm__ __volatile__("" ::: "memory");
	}
}

static void play_gif_once(struct limine_framebuffer *fb, const gif_image *g) {
	if (!g || !g->frames || g->w <= 0 || g->h <= 0 || g->count <= 0) return;
	for (int i = 0; i < g->count; i++) {
		const uint8_t *frame = g->frames + (size_t)g->w * (size_t)g->h * 4u * (size_t)i;
		blit_rgba_center(fb, frame, g->w, g->h);
		int d = (g->delays_ms && g->delays_ms[i] > 0) ? g->delays_ms[i] : 33;
		busy_sleep_ms((uint32_t)d);
	}
}

static int boot_init_step(void) {
	// Réaliste: effectuer ici les initialisations noyau/services.
	// Actuellement, aucune initialisation longue n'est nécessaire.
	return 1; // déjà prêt
}

// ----------------- Entry -----------------
void _start(void) {
	if (framebuffer_request.response == NULL
	 || framebuffer_request.response->framebuffer_count < 1) {
		hcf();
	}

	struct limine_framebuffer *fb = framebuffer_request.response->framebuffers[0];
	clear_fb(fb, 0x00, 0x00, 0x00);

	gif_image g1, g2, g3;
	gif_load_from_module("/assets/loader/stage1.gif", &g1);
	gif_load_from_module("/assets/loader/stage2.gif", &g2);
	gif_load_from_module("/assets/loader/stage3.gif", &g3);

    // Stage 1: play once if present and keep on screen a moment
    if (g1.frames) { play_gif_once(fb, &g1); busy_sleep_ms(1500u); }

    // Stage 2: animate during init; if init is instant, still show ~2s
    if (g2.frames) {
        int idx = 0;
        uint32_t shown = 0;
        int init_done = boot_init_step();
        while (!init_done || shown < 3500u) {
            const uint8_t *frame = g2.frames + (size_t)g2.w * (size_t)g2.h * 4u * (size_t)idx;
            blit_rgba_center(fb, frame, g2.w, g2.h);
            int d = (g2.delays_ms && g2.delays_ms[idx] > 0) ? g2.delays_ms[idx] : 33;
            busy_sleep_ms((uint32_t)d);
            shown += (uint32_t)d;
            idx = (idx + 1) % (g2.count > 0 ? g2.count : 1);
            if (!init_done) init_done = boot_init_step();
        }
    }

    // Stage 3: final image/animation once, keep visible
    if (g3.frames) { play_gif_once(fb, &g3); busy_sleep_ms(4000u); }

	hcf();
}
