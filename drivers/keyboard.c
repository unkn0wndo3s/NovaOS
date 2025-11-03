#include <stdint.h>
#include "../arch/x86_64/io.h"
#include "serial.h"
#include "tty.h"

#define PS2_DATA 0x60
#define PS2_STAT 0x64

static int shift_active = 0;

static const char scancode_set1_us[128] = {
    0,  27,'1','2','3','4','5','6','7','8','9','0','-','=', '\b',
    '\t','q','w','e','r','t','y','u','i','o','p','[',']','\n', 0,
    'a','s','d','f','g','h','j','k','l',';','\'', '`',  0,  '\\',
    'z','x','c','v','b','n','m',',','.','/',   0,  '*',  0,  ' ',
};

/* Minimal FR keymap overlay (AZERTY letters). For brevity, only letters/digits common cases */
static char map_fr(char us, int shift) {
    /* letters: qwerty->azerty swap */
    if (us=='q') us='a'; else if (us=='w') us='z'; else if (us=='a') us='q'; else if (us=='z') us='w';
    /* shift to uppercase for letters */
    if (shift && us>='a' && us<='z') us = (char)(us - 'a' + 'A');
    return us;
}

void keyboard_init(void) {
    /* Unmask IRQ1 on master PIC */
    uint8_t mask = inb(0x21);
    outb(0x21, (uint8_t)(mask & ~0x02));
}

void keyboard_irq1(void) {
    while (inb(PS2_STAT) & 1) {
        uint8_t sc = inb(PS2_DATA);
        if (sc == 0x2A || sc == 0x36) { shift_active = 1; continue; }
        if (sc == 0xAA || sc == 0xB6) { shift_active = 0; continue; }
        if (sc & 0x80) {
            /* key release, ignore */
            continue;
        }
        char ch = 0;
        if (sc < sizeof(scancode_set1_us)) ch = scancode_set1_us[sc];
        if (ch) ch = map_fr(ch, shift_active);
        if (ch) tty_put_key(ch);
    }
}


