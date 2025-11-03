#include "vfs.h"
#include "cpio.h"
#include "../mm/heap.h"
#include "../drivers/serial.h"

struct vfs_node;

static struct vfs_node **vfs_nodes;
static size_t vfs_nodes_count;
static size_t vfs_nodes_cap;

static size_t str_len(const char *s){ size_t n=0; if(!s) return 0; while(s[n]) n++; return n; }
static int str_cmp(const char *a, const char *b){ if(!a||!b) return (a==b)?0:(a?1:-1); while(*a&&*b){ if(*a!=*b) return (unsigned char)*a-(unsigned char)*b; a++; b++; } return (unsigned char)*a-(unsigned char)*b; }
static int str_startswith(const char *s, const char *p){ size_t i=0; if(!s||!p) return 0; for(; p[i]; i++){ if(s[i]!=p[i]) return 0; } return 1; }
static char *str_dup(const char *s){ size_t n=str_len(s); char *d=(char*)kmalloc(n+1); if(!d) return 0; for(size_t i=0;i<=n;i++) d[i]=s[i]; return d; }

static void vfs_add_file(const char *path, const void *data, size_t size){
    struct vfs_node *node = (struct vfs_node*)kmalloc(sizeof(*node));
    if (!node) return;
    node->path = str_dup(path);
    node->data = (const uint8_t*)data;
    node->size = size;
    serial_write("[vfs] add "); serial_write(node->path); serial_write(" (size="); serial_write_hex64((uint64_t)size); serial_write(")\n");
    if (vfs_nodes_count == vfs_nodes_cap) {
        size_t new_cap = vfs_nodes_cap ? (vfs_nodes_cap * 2) : 16;
        struct vfs_node **new_arr = (struct vfs_node**)kmalloc(new_cap * sizeof(*new_arr));
        if (!new_arr) return; /* leak node on OOM, acceptable early boot */
        for (size_t i=0;i<vfs_nodes_count;i++) new_arr[i]=vfs_nodes[i];
        vfs_nodes = new_arr;
        vfs_nodes_cap = new_cap;
    }
    vfs_nodes[vfs_nodes_count++] = node;
}

static void cpio_collect(const char *path, const void *data, size_t size, void *user){
    (void)user;
    /* Skip directories and special names handled by parser already. */
    if (!path || !*path) return;
    /* Skip trailing slash names */
    size_t n = str_len(path);
    if (n && path[n-1] == '/') return;
    vfs_add_file(path, data, size);
}

void vfs_init(void){
    vfs_nodes = 0; vfs_nodes_count = 0; vfs_nodes_cap = 0;
}

void vfs_mount_cpio_newc(const void *base, size_t size){
    (void)cpio_newc_foreach_file(base, size, cpio_collect, 0);
}

const struct vfs_node *vfs_get(const char *path){
    for (size_t i=0;i<vfs_nodes_count;i++){
        if (str_cmp(vfs_nodes[i]->path, path) == 0) return vfs_nodes[i];
    }
    return 0;
}

/* Simple insertion sort for small lists to keep lexicographic order */
static void sort_nodes(const struct vfs_node **arr, size_t n){
    for (size_t i=1;i<n;i++){
        const struct vfs_node *key = arr[i];
        size_t j = i;
        while (j>0 && str_cmp(arr[j-1]->path, key->path) > 0){ arr[j] = arr[j-1]; j--; }
        arr[j] = key;
    }
}

size_t vfs_find_prefix(const char *prefix, const struct vfs_node ***out_list){
    if (!out_list) return 0;
    /* First pass: count */
    size_t cnt = 0;
    for (size_t i=0;i<vfs_nodes_count;i++){
        if (str_startswith(vfs_nodes[i]->path, prefix)) cnt++;
    }
    if (cnt == 0){ *out_list = 0; return 0; }
    /* Allocate array */
    const struct vfs_node **list = (const struct vfs_node**)kmalloc(cnt * sizeof(*list));
    if (!list){ *out_list = 0; return 0; }
    size_t k=0;
    for (size_t i=0;i<vfs_nodes_count;i++){
        if (str_startswith(vfs_nodes[i]->path, prefix)) list[k++] = vfs_nodes[i];
    }
    sort_nodes(list, cnt);
    *out_list = list;
    return cnt;
}


