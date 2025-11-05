#include <stdint.h>
#include <stddef.h>
#include "vfs.h"
#include "serial.h"
#include "vmm.h"
#include "elf64.h"
#include "gdt_tss2.h"
#include "limine_requests.h"
#include "proc.h"
#include "../mm/pmm.h"
#include "../mm/heap.h"

extern void enter_userland(uint64_t rip, uint64_t rsp);

task_t *current_task = 0;
static task_t init_task;

static void build_initial_user_stack(uint64_t pml4_phys, uint64_t stack_top, const char *progname, uint64_t *out_rsp) {
	/* Very small argv/envp/auxv: argc=1, argv=[progname, NULL], envp=[NULL], auxv empty */
	/* Place strings just below stack_top */
	const char *name = progname ? progname : "init";
	/* Copy progname into one page near top */
	uint64_t str_va = (stack_top & ~0xFFFull) - 0x1000; /* string page */
	(void)pml4_phys;
	/* Map string page if not mapped */
	uint64_t phys = pmm_alloc_page();
	if (phys) (void)vmm_map_pages_user(pml4_phys, str_va, phys, 1, VMM_FLAG_USER | VMM_FLAG_WRITE | VMM_FLAG_NX);
	/* Write the string */
	char *dst = (char *)(phys + get_hhdm_offset());
	uint64_t i = 0; while (name[i]) { dst[i] = name[i]; i++; } dst[i++]='\0';

	/* Now build stack */
	uint64_t sp = stack_top;
	/* Align to 16 bytes */
	sp &= ~0xFull;
	/* Place envp NULL */
	sp -= 8; *(uint64_t *)(sp + get_hhdm_offset()) = 0;
	/* Place argv[1]=NULL */
	sp -= 8; *(uint64_t *)(sp + get_hhdm_offset()) = 0;
	/* Place argv[0]=pointer to string */
	sp -= 8; *(uint64_t *)(sp + get_hhdm_offset()) = str_va;
	/* Place argc=1 */
	sp -= 8; *(uint64_t *)(sp + get_hhdm_offset()) = 1;
	*out_rsp = sp;
}

void proc_spawn_init_from_vfs(void) {
    const struct vfs_node *node = vfs_get("/bin/init");
    if (!node) node = vfs_get("bin/init");
    if (!node) node = vfs_get("init");
    if (!node) {
        /* Debug: list bin/ entries to help diagnose path mismatch */
        const struct vfs_node **list = 0; size_t cnt = vfs_find_prefix("/bin/", &list);
        serial_write("[proc] bin/ entries: "); serial_write_hex64((uint64_t)cnt); serial_write("\n");
        for (size_t i = 0; i < cnt; i++) {
            serial_write("  - "); serial_write(list[i]->path); serial_write(" (size="); serial_write_hex64((uint64_t)list[i]->size); serial_write(")\n");
        }
    }
	if (!node) {
		serial_write("[proc] /bin/init not found; skipping userland\n");
		return;
	}
	serial_write("[proc] loading /bin/init (size="); serial_write_hex64((uint64_t)node->size); serial_write(")\n");
	uint64_t pml4 = vmm_new_user_pml4();
	if (!pml4) { serial_write("[proc] pml4 alloc failed\n"); return; }
	uint64_t entry = 0;
	if (elf64_load_image(node->data, node->size, pml4, &entry) != 0) { serial_write("[proc] ELF load failed\n"); return; }
	/* Map a user stack of 8 pages at 0x00000040000000 */
	uint64_t user_stack_top = 0x00000040000000ull + (8ull << 12);
	for (int i = 0; i < 8; i++) {
		uint64_t phys = pmm_alloc_page();
		if (!phys) { serial_write("[proc] stack alloc failed\n"); return; }
		if (vmm_map_pages_user(pml4, 0x00000040000000ull + (i << 12), phys, 1, VMM_FLAG_USER | VMM_FLAG_WRITE | VMM_FLAG_NX) != 0) {
			serial_write("[proc] stack map failed\n"); return;
		}
	}
	uint64_t user_rsp = 0;
	build_initial_user_stack(pml4, user_stack_top, "init", &user_rsp);

	/* Prepare kernel stack for ring3 -> ring0 transitions */
	uint8_t *kstack = (uint8_t *)kmalloc(16 * 1024);
	if (!kstack) { serial_write("[proc] kernel stack alloc failed\n"); return; }
	uint64_t kstack_top = (uint64_t)(kstack + 16 * 1024);
	tss_set_rsp0(kstack_top);

	/* Populate current_task */
	init_task.cr3 = pml4;
	init_task.kernel_stack_top = kstack_top;
	init_task.pid = 1;
	init_task.uid = 0;
	init_task.gid = 0;
	current_task = &init_task;

	/* Switch to user address space and jump */
	vmm_switch(pml4);
	enter_userland(entry, user_rsp);
}


