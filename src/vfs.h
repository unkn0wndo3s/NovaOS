#pragma once
#include <stddef.h>
#include <stdint.h>

struct vfs_node {
    const char *path;           /* NUL-terminated path (owned by VFS) */
    const uint8_t *data;        /* Points into initrd memory */
    size_t size;
    uint32_t mode;              /* POSIX mode bits */
    uint32_t uid;               /* owner uid */
    uint32_t gid;               /* owner gid */
};

void vfs_init(void);
/* Mount files from a CPIO newc archive */
void vfs_mount_cpio_newc(const void *base, size_t size);

/* Lookup by path; returns NULL if not found */
const struct vfs_node *vfs_get(const char *path);

/* Collect all files whose path starts with prefix. Returns count, and allocates
 * an array of node pointers in out_list (caller must kfree the array, not nodes). */
size_t vfs_find_prefix(const char *prefix, const struct vfs_node ***out_list);


