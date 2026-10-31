#ifndef AGV_SERVO_OLED_SSD1306_H
#define AGV_SERVO_OLED_SSD1306_H

#include <stdint.h>

uint32_t OledInit(void);
void OledShowLines(const char *line1, const char *line2);
void OledTestPattern(void);

#endif
