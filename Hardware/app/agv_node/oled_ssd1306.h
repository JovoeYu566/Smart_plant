#ifndef OLED_SSD1306_H
#define OLED_SSD1306_H

#include <stdint.h>

/* QST-HM-1.1：0.91 寸 SSD1306 128x32，I2C0 在 GPIO9/10 */

uint32_t OledInit(void);
void OledSetPosition(uint8_t x, uint8_t y);
void OledFillScreen(uint8_t fillData);

enum Font {
    FONT6x8 = 1,
    FONT8x16
};
typedef enum Font Font;

void OledShowChar(uint8_t x, uint8_t y, uint8_t ch, Font font);
void OledShowString(uint8_t x, uint8_t y, const char *str, Font font);

#endif /* OLED_SSD1306_H */
