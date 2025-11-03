#include "cpio.h"

static int is_hex(char c){ return (c>='0'&&c<='9')||(c>='a'&&c<='f')||(c>='A'&&c<='F'); }
static uint32_t hexval(char c){ if(c>='0'&&c<='9')return (uint32_t)(c-'0'); if(c>='a'&&c<='f')return (uint32_t)(10+c-'a'); return (uint32_t)(10+c-'A'); }
static uint32_t parse_hex32(const char *s, size_t n){ uint32_t v=0; for(size_t i=0;i<n;i++){ if(!is_hex(s[i])) return 0; v=(v<<4)|hexval(s[i]); } return v; }
static uint64_t parse_hex64(const char *s, size_t n){ uint64_t v=0; for(size_t i=0;i<n;i++){ if(!is_hex(s[i])) return 0; v=(v<<4)|hexval(s[i]); } return v; }

static size_t align_up(size_t v, size_t a){ size_t r = (v + (a-1)) & ~(a-1); return r; }

int cpio_newc_foreach_file(const void *base, size_t size, cpio_file_cb cb, void *user){
    const char *p = (const char*)base;
    const char *end = p + size;
    const size_t HDR = 110;
    if (!base || size < HDR) return 0;

    while (p + HDR <= end) {
        /* Header */
        const char *h = p;
        if (!(h[0]=='0' && h[1]=='7' && h[2]=='0' && h[3]=='7' && h[4]=='0' && (h[5]=='1' || h[5]=='2'))) {
            return 0; /* bad magic */
        }
        uint32_t inode     = (uint32_t)parse_hex32(h+6, 8);
        uint32_t mode      = (uint32_t)parse_hex32(h+14, 8);
        uint32_t uid       = (uint32_t)parse_hex32(h+22, 8);
        uint32_t gid       = (uint32_t)parse_hex32(h+30, 8);
        uint64_t filesize  =           parse_hex64(h+54, 8);
        uint32_t namesize  = (uint32_t)parse_hex32(h+94, 8);

        p += HDR;
        if (p + namesize > end) return 0;
        const char *name = p;
        /* namesize includes trailing NUL */
        const char *name_end = name + namesize - 1;
        /* Align name to 4 */
        p += align_up(namesize, 4);
        if (p > end) return 0;

        /* End marker: namesize includes the trailing NUL ("TRAILER!!!\0" => 11) */
        if (namesize >= 11 && name[0]=='T'&&name[1]=='R'&&name[2]=='A'&&name[3]=='I'&&name[4]=='L'&&name[5]=='E'&&name[6]=='R'&&name[7]=='!'&&name[8]=='!'&&name[9]=='!'){
            break;
        }

        /* Skip directories (mode bits: S_IFDIR = 0040000) */
        if ((mode & 0170000) == 0040000) {
            /* No file payload */
            /* still need to skip payload (should be 0) */
        } else {
            /* File payload */
            if (p + filesize > end) return 0;
            if (filesize > 0 && cb) {
                /* Normalize leading "./" if present */
                const char *normalized = name;
                if (normalized[0]=='.' && normalized[1]=='/') normalized += 2;
                /* Build a clean C-string for path (namesize includes NUL) */
                (void)inode;
                cb(normalized, p, (size_t)filesize, mode, uid, gid, user);
            }
        }

        /* Advance past file data, align to 4 */
        p += align_up((size_t)filesize, 4);
    }
    return 1;
}


