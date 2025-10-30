#include <stdint.h>
#include "idt.h"
#include "../drivers/serial.h"
#include "../kernel/panic.h"

static const char *exc_names[32] = {
    "DE", "DB", "NMI", "BP", "OF", "BR", "UD", "NM",
    "DF", "CSO", "TS", "NP", "SS", "GP", "PF", "RES",
    "MF", "AC", "MC", "XM", "VE", "CP21", "CP22", "CP23",
    "CP24", "CP25", "CP26", "CP27", "CP28", "CP29", "CP30", "CP31"
};

void isr_common_handler(struct isr_regs *r) {
    uint64_t no = r->int_no;
    if (no < 32) {
        serial_write("EXC ");
        serial_write_hex64(no);
        serial_write(" (");
        serial_write(exc_names[no]);
        serial_write(") err=");
        serial_write_hex64(r->err_code);
        serial_write(" RIP="); serial_write_hex64(r->rip);
        serial_write(" RSP="); serial_write_hex64(r->rsp);
        serial_write(" RFLAGS="); serial_write_hex64(r->rflags);
        serial_write("\n");
        panic("CPU exception");
    }
}


