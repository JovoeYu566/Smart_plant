#ifndef OLED_SSD1306_H
#define OLED_SSD1306_H

#include <stdint.h>

#include "cmsis_os2.h"

void OledSetI2cMutex(osMutexId_t mutex);
uint32_t OledInit(void);
void OledSetPosition(uint8_t x, uint8_t y);
void OledFillScreen(uint8_t fillData);
uint32_t WriteData(uint8_t data);

enum Font {
    FONT6x8 = 1,
    FONT8x16
};
typedef enum Font Font;

void OledShowChar(uint8_t x, uint8_t y, uint8_t ch, Font font);
void OledShowString(uint8_t x, uint8_t y, const char* str, Font font);
void OledShowChinese(uint8_t x, uint8_t y, uint8_t index);
void OledShowName(uint8_t x, uint8_t y);

#endif // OLED_SSD1306_H