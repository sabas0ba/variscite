/* Stop-and-wait UART loader. No allocation, library calls or writable globals. */
#include <stdint.h>
#include "sd_boot.h"

#define IMAGE_BASE 0x80000000u
#define IMAGE_LIMIT 0x02000000u
#define DTB_BASE 0x87e00000u
#define DTB_LIMIT 0x00010000u
#define MAGIC 0x314c4256u /* "VBL1", little endian */
#define MAX_PAYLOAD 256u
#define UART ((volatile uint32_t *)0x10000000u)
#ifndef WITH_LCD
#define WITH_LCD 0
#endif
#ifndef WITH_SD
#define WITH_SD 0
#endif

struct boot_source { struct sd_file *file; unsigned failed; };

extern void boot_jump(void) __attribute__((noreturn));

static void put_byte(uint8_t c)
{
    while (!(UART[5] & 0x20u)) {}
    UART[0] = c;
}

static uint8_t get_byte(struct boot_source *source)
{
    if (WITH_SD && source->file) {
        int value = source->failed ? -1 : sd_file_byte(source->file);
        if (value < 0) { source->failed = 1; return 0; }
        return (uint8_t)value;
    }
    while (!(UART[5] & 1u)) {}
    return UART[0];
}

static uint32_t get_word(struct boot_source *source)
{
    uint32_t word = 0;
    for (unsigned i = 0; i < 32; i += 8)
        word |= (uint32_t)get_byte(source) << i;
    return word;
}

static uint32_t crc_byte(uint32_t crc, uint8_t byte)
{
    crc ^= byte;
    for (unsigned i = 0; i < 8; ++i)
        crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
    return crc;
}

static uint32_t crc_word(uint32_t crc, uint32_t word)
{
    for (unsigned i = 0; i < 32; i += 8)
        crc = crc_byte(crc, word >> i);
    return crc;
}

static uint32_t memory_crc(uint32_t address, uint32_t length)
{
    const volatile uint8_t *data = (const volatile uint8_t *)address;
    uint32_t crc = ~0u;
    while (length--) crc = crc_byte(crc, *data++);
    return ~crc;
}

static int within(uint32_t address, uint32_t length, uint32_t base, uint32_t size)
{
    return address >= base && address - base < size && length <= size - (address - base);
}

static void message(const char *text)
{
    while (*text) put_byte((uint8_t)*text++);
}

static void reject(struct boot_source *source)
{
    if (WITH_SD && source->file) {
        source->file = 0;
        source->failed = 0;
        message("SD failed\nVBL1\n");
    } else put_byte('E');
}

void boot_main(void)
{
    /* Word alignment also permits reading the 16-byte boot manifest. */
    uint32_t buffer[MAX_PAYLOAD / 4];
    uint8_t *bytes = (uint8_t *)buffer;
    struct boot_source source;
    source.file = 0;
    source.failed = 0;
    if (WITH_LCD) {
        static const uint16_t colors[8] = {
            0xffff, 0xffe0, 0x07ff, 0x07e0, 0xf81f, 0xf800, 0x001f, 0
        };
        volatile uint32_t *fb = (volatile uint32_t *)0x87c00000u;
        for (unsigned y = 0; y < 480; ++y)
            for (unsigned bar = 0; bar < 8; ++bar)
                for (unsigned x = 0; x < 50; ++x)
                    *fb++ = colors[bar] | ((uint32_t)colors[bar] << 16);
        __asm__ volatile ("fence iorw, iorw" ::: "memory");
        /* Standalone loading must not compete with continuous LCD DMA for
         * the CPU's DDR stack while receiving a back-to-back UART packet. */
        if (!WITH_SD) *(volatile uint32_t *)0x11200000u = 1;
    }
    message("VBL1\n");
#if WITH_SD
    struct sd_file file;
    /* A UART sender can take ownership before autonomous SD loading starts. */
    uint32_t start = *(volatile uint32_t *)0x1100bff8u;
    while (!(UART[5] & 1u) &&
           (uint32_t)(*(volatile uint32_t *)0x1100bff8u - start) < 250000u) {}
    if (!(UART[5] & 1u)) {
        if (sd_card_init(&file.card) == 0 && sd_file_open(&file) == 0) {
            source.file = &file;
            message("SD boot\n");
        } else message("SD unavailable\nVBL1\n");
    }
#endif
    for (;;) {
        uint32_t sync = 0;
        while (sync != MAGIC && !source.failed)
            sync = (sync >> 8) | ((uint32_t)get_byte(&source) << 24);
        uint32_t command = get_word(&source);
        uint32_t address = get_word(&source);
        uint32_t length = get_word(&source);
        uint32_t expected_crc = get_word(&source);
        if (source.failed || !length || length > MAX_PAYLOAD) { reject(&source); continue; }
        uint32_t crc = crc_word(crc_word(crc_word(crc_word(~0u, MAGIC), command), address), length);
        for (uint32_t i = 0; i < length; ++i) {
            bytes[i] = get_byte(&source);
            crc = crc_byte(crc, bytes[i]);
        }
        if (source.failed || ~crc != expected_crc) { reject(&source); continue; }
        if (command == 'W' &&
            (within(address, length, IMAGE_BASE, IMAGE_LIMIT) ||
             within(address, length, DTB_BASE, DTB_LIMIT))) {
            volatile uint8_t *dest = (volatile uint8_t *)address;
            for (uint32_t i = 0; i < length; ++i) dest[i] = bytes[i];
            if (!source.file) put_byte('K');
        } else if (command == 'B' && address == IMAGE_BASE && length == 16 &&
                   buffer[0] && buffer[0] <= IMAGE_LIMIT &&
                   buffer[1] >= 40 && buffer[1] <= DTB_LIMIT &&
                   (!source.file || source.file->remaining == 0) &&
                   *(volatile uint32_t *)DTB_BASE == 0xedfe0dd0u &&
                   memory_crc(IMAGE_BASE, buffer[0]) == buffer[2] &&
                   memory_crc(DTB_BASE, buffer[1]) == buffer[3]) {
            if (WITH_SD && WITH_LCD) {
                __asm__ volatile ("fence iorw, iorw" ::: "memory");
                *(volatile uint32_t *)0x11200000u = 1;
            }
            if (source.file) message("SD verified\n");
            else put_byte('K');
            while (!(UART[5] & 0x40u)) {} /* Drain the final ACK before Linux. */
            boot_jump();
        } else {
            reject(&source);
        }
    }
}
