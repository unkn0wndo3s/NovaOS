#pragma once

void thread_log(void);
void thread_idle(void);
void thread_anim(void);

#include <stddef.h>
struct vfs_node;
struct limine_framebuffer;
void threads_configure_animation(const struct vfs_node **frames, size_t count, struct limine_framebuffer *fb);


