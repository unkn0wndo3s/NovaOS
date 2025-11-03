#pragma once
#include <stdint.h>

typedef struct task_t {
	uint64_t cr3;
	uint64_t kernel_stack_top;
	int pid;
	int uid;
	int gid;
} task_t;

extern task_t *current_task;

/* Try to load and enter userland from /bin/init if present. */
void proc_spawn_init_from_vfs(void);


