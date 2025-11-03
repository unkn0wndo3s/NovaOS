#pragma once
#include <stddef.h>
#include <stdint.h>

/* Iterate "newc" CPIO archive and call cb for each regular file found.
 * Returns 1 on success, 0 on parse error. */
typedef void (*cpio_file_cb)(const char *path, const void *data, size_t size, void *user);
int cpio_newc_foreach_file(const void *base, size_t size, cpio_file_cb cb, void *user);


