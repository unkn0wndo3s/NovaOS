// Nova OS — Boot video (3-stage animated GIFs via Limine, no external deps) — C99
// Stage1: once, Stage2: loop, Stage3: once

#include <stdint.h>
#include <stddef.h>
#include <limine.h>

// -------- Limine requests --------
static volatile struct limine_framebuffer_request fb_req = {
    .id = LIMINE_FRAMEBUFFER_REQUEST, .revision = 0
};
static volatile struct limine_module_request mod_req = {
    .id = LIMINE_MODULE_REQUEST, .revision = 0
};

// -------- libc mini --------
static void *memcpy(void *d, const void *s, size_t n){ uint8_t*D=(uint8_t*)d; const uint8_t*S=(const uint8_t*)s; for(size_t i=0;i<n;i++) D[i]=S[i]; return d; }
static int memcmp(const void *a, const void *b, size_t n){ const uint8_t*A=(const uint8_t*)a,*B=(const uint8_t*)b; for(size_t i=0;i<n;i++){ if(A[i]!=B[i]) return A[i]<B[i]?-1:1; } return 0; }
static void hcf(void){ __asm__ __volatile__("cli"); for(;;) __asm__ __volatile__("hlt"); }

// ==================== Framebuffer helpers (bpp-safe) ====================
static inline uint32_t fb_pack_u32(struct limine_framebuffer *fb, uint8_t r, uint8_t g, uint8_t b){
    uint32_t R = (fb->red_mask_size   >= 8) ? r : (r >> (8 - fb->red_mask_size));
    uint32_t G = (fb->green_mask_size >= 8) ? g : (g >> (8 - fb->green_mask_size));
    uint32_t B = (fb->blue_mask_size  >= 8) ? b : (b >> (8 - fb->blue_mask_size));
    if (fb->red_mask_size   != 32) R &= ((1u << fb->red_mask_size)   - 1u);
    if (fb->green_mask_size != 32) G &= ((1u << fb->green_mask_size) - 1u);
    if (fb->blue_mask_size  != 32) B &= ((1u << fb->blue_mask_size)  - 1u);
    return (R << fb->red_mask_shift) | (G << fb->green_mask_shift) | (B << fb->blue_mask_shift);
}

static inline void put_px_rgb(struct limine_framebuffer *fb, uint64_t x, uint64_t y, uint8_t r, uint8_t g, uint8_t b){
    if (x >= fb->width || y >= fb->height) return;
    const uint32_t packed = fb_pack_u32(fb, r, g, b);
    const uint32_t bpp_bytes = (fb->bpp + 7) / 8; // 2, 3, ou 4
    if (bpp_bytes < 2 || bpp_bytes > 4) return;
    uint8_t *base = (uint8_t *)fb->address + y * fb->pitch + x * bpp_bytes;
    // little-endian : LSB -> MSB
    base[0] = (uint8_t)(packed >> 0);
    base[1] = (uint8_t)(packed >> 8);
    if (bpp_bytes >= 3) base[2] = (uint8_t)(packed >> 16);
    if (bpp_bytes == 4) base[3] = (uint8_t)(packed >> 24);
}

static void clear_fb(struct limine_framebuffer *fb, uint8_t r, uint8_t g, uint8_t b){
    const uint32_t bpp_bytes = (fb->bpp + 7) / 8;
    if (bpp_bytes < 2 || bpp_bytes > 4) return;
    const uint32_t packed = fb_pack_u32(fb, r, g, b);
    uint8_t px4[4] = {
        (uint8_t)(packed >> 0),
        (uint8_t)(packed >> 8),
        (uint8_t)(packed >> 16),
        (uint8_t)(packed >> 24),
    };
    for (uint64_t y = 0; y < fb->height; y++) {
        uint8_t *row = (uint8_t *)fb->address + y * fb->pitch;
        for (uint64_t x = 0; x < fb->width; x++) {
            uint8_t *p = row + x * bpp_bytes;
            for (uint32_t i = 0; i < bpp_bytes; i++) p[i] = px4[i];
        }
    }
}

static void blit_center(struct limine_framebuffer *fb, const uint8_t *rgba, int w, int h){
    if (!rgba || w<=0 || h<=0) return;
    int dx = (fb->width  > (uint64_t)w) ? (int)((fb->width  - (uint64_t)w)/2) : 0;
    int dy = (fb->height > (uint64_t)h) ? (int)((fb->height - (uint64_t)h)/2) : 0;
    for (int y=0; y<h; y++){
        int py = dy + y; if (py<0 || (uint64_t)py>=fb->height) continue;
        const uint8_t *src = rgba + (size_t)y*(size_t)w*4u;
        for (int x=0; x<w; x++){
            int px = dx + x; if (px<0 || (uint64_t)px>=fb->width) continue;
            uint8_t R=src[4u*(size_t)x+0], G=src[4u*(size_t)x+1], B=src[4u*(size_t)x+2];
            put_px_rgb(fb,(uint64_t)px,(uint64_t)py, R, G, B);
        }
    }
}

static void spin_ms(uint32_t ms){ volatile uint64_t spins=(uint64_t)ms*250000ull; for(uint64_t i=0;i<spins;i++){ __asm__ __volatile__("":::"memory"); } }
static void flash(struct limine_framebuffer *fb, uint8_t r, uint8_t g, uint8_t b, int times){
    for(int i=0;i<times;i++){ clear_fb(fb,r,g,b); spin_ms(150); clear_fb(fb,0,0,0); spin_ms(150); }
}

// -------- Limine modules helper (match path OR cmdline suffix) --------
typedef struct { const uint8_t *data; size_t size; } file_t;
static int ends_with(const char *s, const char *suffix){ size_t i=0,j=0; while(s[i]) i++; while(suffix[j]) j++; while(i&&j&&s[i-1]==suffix[j-1]){i--;j--;} return j==0; }
static file_t find_module(const char *suffix){
    const struct limine_module_response *resp = mod_req.response;
    if(!resp) return (file_t){0,0};
    for(uint64_t i=0;i<resp->module_count;i++){
        struct limine_file *f = resp->modules[i];
        if(!f) continue;
        const char *p = f->path    ? f->path    : "";
        const char *c = f->cmdline ? f->cmdline : "";
        if (ends_with(p, suffix) || ends_with(c, suffix))
            return (file_t){ (const uint8_t*)f->address, (size_t)f->size };
    }
    return (file_t){0,0};
}

// ==================== Tiny GIF decoder (C99) ====================
// Support: GIF87a/89a, palette globale/locale, transparence, délais, interlace OK.
// Sortie: RGBA interleaved (w*h*4*count) + delays_ms[count].
typedef struct { int w,h,count; uint8_t *frames; int *delays_ms; } gif_t;

// --- reader ---
typedef struct { const uint8_t *p, *e; } rd_t;
static int ru8(rd_t *r, uint8_t *v){ if(r->p>=r->e) return 0; *v=*r->p++; return 1; }
static int ru16(rd_t *r, uint16_t *v){ uint8_t a,b; if(!ru8(r,&a)||!ru8(r,&b)) return 0; *v=(uint16_t)(a|(b<<8)); return 1; }
static int rblk(rd_t *r, uint8_t *d, size_t n){ if((size_t)(r->e-r->p)<n) return 0; memcpy(d,r->p,n); r->p+=n; return 1; }
static int skip_sub(rd_t *r){ for(;;){ uint8_t sz; if(!ru8(r,&sz)) return 0; if(sz==0) return 1; if((size_t)(r->e-r->p)<sz) return 0; r->p+=sz; } }

// --- simple arena (32 MiB) ---
static uint8_t ARENA[32*1024*1024]; static size_t AOFF=0;
static void* AALLOC(size_t n){ n=(n+7)&~7u; if(AOFF+n>sizeof(ARENA)) return (void*)0; { void* p=ARENA+AOFF; AOFF+=n; return p; } }

// --- interlace stepper (C99) ---
static inline void next_px(int *x, int *y, int w, int h, int *pass, int interlace){
    if (!interlace){ (*x)++; if (*x>=w){ *x=0; (*y)++; } }
    else {
        static const int start[4]={0,4,2,1};
        static const int step [4]={8,8,4,2};
        (*x)++;
        if (*x>=w){
            *x=0; *y += step[*pass];
            if (*y>=h){ (*pass)++; if (*pass<4) *y = start[*pass]; }
        }
    }
}

// --- LZW decode to index buffer ---
static int lzw_to_idx(rd_t *r, uint8_t *out, int w, int h, int interlace){
    uint8_t min_code_size; if(!ru8(r,&min_code_size)) return 0;
    static uint8_t sbuf[1<<21]; size_t so=0;
    for(;;){ uint8_t sz; if(!ru8(r,&sz)) return 0; if(sz==0) break; if(so+sz>sizeof(sbuf)) return 0; if(!rblk(r,sbuf+so,sz)) return 0; so+=sz; }
    const uint8_t *bp=sbuf; size_t bl=so; uint32_t bitpos=0;
    #define RD_BITS(n, outv) do{ uint32_t _v=0; int _i; for(_i=0; _i<(n); _i++){ if((bitpos>>3)>=bl){ _v=0xFFFFFFFFu; break; } _v |= ((bp[bitpos>>3]>>(bitpos&7))&1u)<<_i; bitpos++; } (outv)=_v; }while(0)
    int clear = 1<<min_code_size, stop = clear+1, code_size = min_code_size+1, next_code = stop+1;
    static uint16_t prefix[4096]; static uint8_t suffix[4096]; static uint8_t stack[4096]; int sp=0;
    for(int i=0;i<clear;i++){ prefix[i]=0xFFFFu; suffix[i]=(uint8_t)i; }
    int pass=0,y=0,x=0, prev=-1;
    for(;;){
        uint32_t code; RD_BITS(code_size, code);
        if(code==0xFFFFFFFFu) break;
        if((int)code==clear){ code_size=min_code_size+1; next_code=stop+1; prev=-1; continue; }
        if((int)code==stop) break;
        uint8_t first; int cur=(int)code;
        if(cur<next_code && (prefix[cur]!=0xFFFFu || cur<clear)){
            int t=cur; sp=0; while(t>=clear){ stack[sp++]=suffix[t]; t=prefix[t]; if(sp>=4096) break; }
            first=(uint8_t)t; stack[sp++]=first;
        } else if(cur==next_code && prev!=-1){
            int t=prev; sp=0; while(t>=clear){ stack[sp++]=suffix[t]; t=prefix[t]; if(sp>=4096) break; }
            first=(uint8_t)t; stack[sp++]=first;
        } else break;
        while(sp){
            uint8_t idx=stack[--sp];
            if(x>=0 && x<w && y>=0 && y<h) out[y*w + x]=idx;
            next_px(&x,&y,w,h,&pass,interlace);
            if(y>=h) break;
        }
        if(y>=h) break;
        if(prev!=-1 && next_code<4096){
            prefix[next_code]=(uint16_t)prev; suffix[next_code]=first; next_code++;
            if(next_code==(1<<code_size) && code_size<12) code_size++;
        }
        prev=cur;
    }
    return 1;
}

// --- Full GIF decode (frames RGBA + delays) ---
typedef struct { uint8_t r,g,b,a; } rgba_t;

static int gif_decode(const uint8_t *data, size_t size, gif_t *out){
    *out=(gif_t){0};
    rd_t r={data, data+size};
    uint8_t sig[6]; if(!rblk(&r,sig,6)) return 0;
    if(memcmp(sig,"GIF87a",6)!=0 && memcmp(sig,"GIF89a",6)!=0) return 0;

    uint16_t W,H; if(!ru16(&r,&W)||!ru16(&r,&H)) return 0;
    uint8_t pf; if(!ru8(&r,&pf)) return 0;
    uint8_t bg; if(!ru8(&r,&bg)) return 0;
    uint8_t aspect; if(!ru8(&r,&aspect)) return 0; (void)aspect;

    int gct_flag = (pf & 0x80)?1:0;
    int gct_pow  = (pf & 0x07);
    int gct_n    = 1<<(gct_pow+1);
    uint8_t gct[256*3];
    if (gct_flag){ if(!rblk(&r,gct,(size_t)gct_n*3u)) return 0; }

    AOFF=0;
    uint8_t *canvas = (uint8_t*)AALLOC((size_t)W*(size_t)H); if(!canvas) return 0;
    size_t pixels = (size_t)W*(size_t)H;
    for (size_t i=0;i<pixels;i++) canvas[i]=bg;

    rgba_t *pal = (rgba_t*)AALLOC(sizeof(rgba_t)*256); if(!pal) return 0;

    enum{MAXF=128};
    uint8_t *frames = (uint8_t*)AALLOC(pixels*4u*MAXF);
    int *delays = (int*)AALLOC(sizeof(int)*MAXF);
    if(!frames || !delays) return 0;
    int fcount=0;

    int have_gce=0; int delay_cs=3; uint8_t transp=0, transp_idx=0; uint8_t disposal=0;

    for(;;){
        uint8_t b; if(!ru8(&r,&b)) break;
        if(b==0x21){
            uint8_t label; if(!ru8(&r,&label)) break;
            if(label==0xF9){
                uint8_t sz; if(!ru8(&r,&sz)) break;
                uint8_t pck; uint16_t dcs; uint8_t tr; uint8_t zero;
                if(!ru8(&r,&pck) || !ru16(&r,&dcs) || !ru8(&r,&tr) || !ru8(&r,&zero)) break;
                disposal = (uint8_t)((pck>>2)&7);
                transp = (uint8_t)(pck & 1);
                transp_idx = tr;
                delay_cs = dcs;
                have_gce=1;
            }else{
                if(!skip_sub(&r)) break;
            }
        }else if(b==0x2C){
            uint16_t ix,iy,iw,ih; if(!ru16(&r,&ix)||!ru16(&r,&iy)||!ru16(&r,&iw)||!ru16(&r,&ih)) break;
            uint8_t ipf; if(!ru8(&r,&ipf)) break;
            int lct_flag=(ipf&0x80)?1:0;
            int interlace=(ipf&0x40)?1:0;
            int lct_pow=(ipf&0x07);
            int lct_n=1<<(lct_pow+1);

            uint8_t lct[256*3];
            int i;
            if(lct_flag){
                if(!rblk(&r,lct,(size_t)lct_n*3u)) break;
                for(i=0;i<256;i++){
                    if(i<lct_n){ pal[i].r=lct[i*3+0]; pal[i].g=lct[i*3+1]; pal[i].b=lct[i*3+2]; pal[i].a=255; }
                    else       { pal[i].r=pal[i].g=pal[i].b=0; pal[i].a=255; }
                }
            }else{
                for(i=0;i<256;i++){
                    if(gct_flag && i<gct_n){ pal[i].r=gct[i*3+0]; pal[i].g=gct[i*3+1]; pal[i].b=gct[i*3+2]; pal[i].a=255; }
                    else { pal[i].r=pal[i].g=pal[i].b=0; pal[i].a=255; }
                }
            }
            if(transp) pal[transp_idx].a=0;

            if(disposal==2){ // restore to bg in rect
                int yy,xx;
                for(yy=iy; yy<iy+ih && yy<(int)H; yy++)
                    for(xx=ix; xx<ix+iw && xx<(int)W; xx++)
                        canvas[(size_t)yy*(size_t)W + (size_t)xx] = bg;
            }

            uint8_t *tmp=(uint8_t*)AALLOC((size_t)iw*(size_t)ih); if(!tmp) break;
            if(!lzw_to_idx(&r,tmp,(int)iw,(int)ih,interlace)) break;

            { // composite
                int yy,xx;
                for(yy=0; yy<(int)ih; yy++){
                    int y=(int)iy+yy; if(y<0 || y>=(int)H) continue;
                    for(xx=0; xx<(int)iw; xx++){
                        int x=(int)ix+xx; if(x<0 || x>=(int)W) continue;
                        uint8_t pi = tmp[(size_t)yy*(size_t)iw + (size_t)xx];
                        if(!(transp && pi==transp_idx)){
                            canvas[(size_t)y*(size_t)W + (size_t)x] = pi;
                        }
                    }
                }
            }

            if(fcount<MAXF){
                uint8_t *dst = frames + (size_t)fcount*pixels*4u;
                for(size_t k=0;k<pixels;k++){
                    rgba_t c = pal[ canvas[k] ];
                    dst[k*4+0]=c.r; dst[k*4+1]=c.g; dst[k*4+2]=c.b; dst[k*4+3]= (c.a?255:0);
                }
                { int ms = have_gce ? (delay_cs*10) : 33; if(ms<=0) ms=33; delays[fcount]=ms; }
                fcount++;
            }
            have_gce=0; transp=0; delay_cs=3; disposal=0;
        }else if(b==0x3B){
            break; // trailer
        }else{
            break;
        }
    }

    if(fcount==0) return 0;
    out->w=(int)W; out->h=(int)H; out->count=fcount; out->frames=frames; out->delays_ms=delays;
    return 1;
}

// -------- Playback helpers --------
static void play_once(struct limine_framebuffer *fb, const gif_t *g){
    for(int i=0;i<g->count;i++){
        const uint8_t *fr = g->frames + (size_t)g->w*(size_t)g->h*4u*(size_t)i;
        blit_center(fb, fr, g->w, g->h);
        int d = g->delays_ms[i]>0? g->delays_ms[i] : 33;
        spin_ms((uint32_t)d);
    }
}
static void play_loop(struct limine_framebuffer *fb, const gif_t *g, uint32_t min_ms){
    uint32_t t=0; int i=0;
    while(t<min_ms){
        const uint8_t *fr = g->frames + (size_t)g->w*(size_t)g->h*4u*(size_t)i;
        blit_center(fb, fr, g->w, g->h);
        int d = g->delays_ms[i]>0? g->delays_ms[i] : 33;
        spin_ms((uint32_t)d); t += (uint32_t)d;
        i = (i+1) % g->count;
    }
}

// -------- Boot init stub --------
static int boot_init_step(void){ return 1; } // remplace par ta vraie init

// -------- Entry --------
void _start(void){
    if(!fb_req.response || fb_req.response->framebuffer_count<1) hcf();
    struct limine_framebuffer *fb = fb_req.response->framebuffers[0];
    clear_fb(fb,0,0,0);

    // modules: /loader/stage{1,2,3}.gif
    file_t m1 = find_module("/loader/stage1.gif");
    file_t m2 = find_module("/loader/stage2.gif");
    file_t m3 = find_module("/loader/stage3.gif");

    gif_t g1={0}, g2={0}, g3={0};
    int ok1=0, ok2=0, ok3=0;

    if(m1.data) ok1 = gif_decode(m1.data, m1.size, &g1);
    if(m2.data) ok2 = gif_decode(m2.data, m2.size, &g2);
    if(m3.data) ok3 = gif_decode(m3.data, m3.size, &g3);

    // Diagnostics visuels (rouge=manquant, orange=decode fail)
    if(!m1.data) flash(fb, 0x80,0x00,0x00, 3); else if(!ok1) flash(fb, 0x80,0x40,0x00, 3);
    if(!m2.data) flash(fb, 0x80,0x00,0x00, 2); else if(!ok2) flash(fb, 0x80,0x40,0x00, 2);
    if(!m3.data) flash(fb, 0x80,0x00,0x00, 1); else if(!ok3) flash(fb, 0x80,0x40,0x00, 1);

    if(ok1) play_once(fb, &g1);            // Stage 1: une fois
    if(ok2){                                // Stage 2: boucle pendant l'init (min 3.5s)
        uint32_t shown=0; int done=boot_init_step();
        while(!done || shown<3500u){
            play_loop(fb, &g2, 3500u);
            shown += 3500u;
            if(!done) done=boot_init_step();
        }
    }
    if(ok3) play_once(fb, &g3);            // Stage 3: une fois

    hcf();
}
