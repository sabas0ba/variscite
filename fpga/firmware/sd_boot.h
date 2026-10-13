#ifndef VARISCITE_SD_BOOT_H
#define VARISCITE_SD_BOOT_H
#include <stdint.h>
struct sd_card { unsigned block_addressing, clock_mode; };
struct sd_file {
    struct sd_card card;
    uint32_t volume_end, fat_start, fat_sectors, data_start, clusters;
    uint32_t cluster, remaining, traversed;
    unsigned sectors_per_cluster, fat32, sector_in_cluster, position, contiguous;
    uint8_t sector[512];
};
int sd_card_init(struct sd_card *card);
int sd_read_sector(struct sd_card *card, uint32_t sector, uint8_t *data);
/* Read-only FAT16/FAT32/exFAT root lookup of TANGBOOT.VBL. */
int sd_file_open(struct sd_file *file);
int sd_file_byte(struct sd_file *file);
#endif
