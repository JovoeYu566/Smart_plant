#include <unistd.h>
#include <stddef.h>

#include "iot_errno.h"
#include "iot_gpio.h"
#include "iot_i2c.h"
#include "hi_io.h"

#include "oled_ssd1306.h"

#define OLED_I2C_IDX 0
#define OLED_I2C_ADDR 0x78
#define OLED_WIDTH 128
#define OLED_PAGES 8

static uint32_t OledWrite(uint8_t control, uint8_t value)
{
    uint8_t data[2] = { control, value };
    return IoTI2cWrite(OLED_I2C_IDX, OLED_I2C_ADDR, data, sizeof(data));
}

static uint32_t OledCmd(uint8_t cmd)
{
    return OledWrite(0x00, cmd);
}

static void OledSetPosition(uint8_t x, uint8_t page)
{
    (void)OledCmd(0xB0 + page);
    (void)OledCmd(x & 0x0F);
    (void)OledCmd(0x10 | (x >> 4));
}

static void OledClear(void)
{
    uint8_t page;
    uint8_t column;
    for (page = 0; page < OLED_PAGES; page++) {
        OledSetPosition(0, page);
        for (column = 0; column < OLED_WIDTH; column++) {
            (void)OledWrite(0x40, 0x00);
        }
    }
}

uint32_t OledInit(void)
{
    uint32_t ret;
    IoTGpioInit(HI_IO_NAME_GPIO_13);
    hi_io_set_func(HI_IO_NAME_GPIO_13, HI_IO_FUNC_GPIO_13_I2C0_SDA);
    hi_io_set_pull(HI_IO_NAME_GPIO_13, HI_IO_PULL_UP);
    IoTGpioInit(HI_IO_NAME_GPIO_14);
    hi_io_set_func(HI_IO_NAME_GPIO_14, HI_IO_FUNC_GPIO_14_I2C0_SCL);
    hi_io_set_pull(HI_IO_NAME_GPIO_14, HI_IO_PULL_UP);
    IoTI2cInit(OLED_I2C_IDX, 100 * 1000);
    usleep(100 * 1000);

    ret = OledCmd(0xAE); if (ret != IOT_SUCCESS) return ret;
    (void)OledCmd(0x00); (void)OledCmd(0x10); (void)OledCmd(0x40);
    (void)OledCmd(0x81); (void)OledCmd(0xFF);
    (void)OledCmd(0xA1); (void)OledCmd(0xA6);
    (void)OledCmd(0xA8); (void)OledCmd(0x3F);
    (void)OledCmd(0xC8); (void)OledCmd(0xD3); (void)OledCmd(0x00);
    (void)OledCmd(0xD5); (void)OledCmd(0x80);
    (void)OledCmd(0xDA); (void)OledCmd(0x12);
    (void)OledCmd(0xDB); (void)OledCmd(0x30);
    (void)OledCmd(0x8D); (void)OledCmd(0x14);
    ret = OledCmd(0xAF); if (ret != IOT_SUCCESS) return ret;
    OledClear();
    return IOT_SUCCESS;
}

static const uint8_t g_fontDigits[10][5] = {
    { 0x3E, 0x51, 0x49, 0x45, 0x3E }, { 0x00, 0x42, 0x7F, 0x40, 0x00 },
    { 0x42, 0x61, 0x51, 0x49, 0x46 }, { 0x21, 0x41, 0x45, 0x4B, 0x31 },
    { 0x18, 0x14, 0x12, 0x7F, 0x10 }, { 0x27, 0x45, 0x45, 0x45, 0x39 },
    { 0x3C, 0x4A, 0x49, 0x49, 0x30 }, { 0x01, 0x71, 0x09, 0x05, 0x03 },
    { 0x36, 0x49, 0x49, 0x49, 0x36 }, { 0x06, 0x49, 0x49, 0x29, 0x1E },
};

static const uint8_t g_fontUpper[26][5] = {
    { 0x7E, 0x11, 0x11, 0x11, 0x7E }, { 0x7F, 0x49, 0x49, 0x49, 0x36 },
    { 0x3E, 0x41, 0x41, 0x41, 0x22 }, { 0x7F, 0x41, 0x41, 0x22, 0x1C },
    { 0x7F, 0x49, 0x49, 0x49, 0x41 }, { 0x7F, 0x09, 0x09, 0x09, 0x01 },
    { 0x3E, 0x41, 0x49, 0x49, 0x7A }, { 0x7F, 0x08, 0x08, 0x08, 0x7F },
    { 0x00, 0x41, 0x7F, 0x41, 0x00 }, { 0x20, 0x40, 0x41, 0x3F, 0x01 },
    { 0x7F, 0x08, 0x14, 0x22, 0x41 }, { 0x7F, 0x40, 0x40, 0x40, 0x40 },
    { 0x7F, 0x02, 0x0C, 0x02, 0x7F }, { 0x7F, 0x04, 0x08, 0x10, 0x7F },
    { 0x3E, 0x41, 0x41, 0x41, 0x3E }, { 0x7F, 0x09, 0x09, 0x09, 0x06 },
    { 0x3E, 0x41, 0x51, 0x21, 0x5E }, { 0x7F, 0x09, 0x19, 0x29, 0x46 },
    { 0x46, 0x49, 0x49, 0x49, 0x31 }, { 0x01, 0x01, 0x7F, 0x01, 0x01 },
    { 0x3F, 0x40, 0x40, 0x40, 0x3F }, { 0x1F, 0x20, 0x40, 0x20, 0x1F },
    { 0x3F, 0x40, 0x38, 0x40, 0x3F }, { 0x63, 0x14, 0x08, 0x14, 0x63 },
    { 0x07, 0x08, 0x70, 0x08, 0x07 }, { 0x61, 0x51, 0x49, 0x45, 0x43 },
};

static void OledWriteChar(uint8_t x, uint8_t page, char ch)
{
    const uint8_t *glyph = NULL;
    uint8_t i;
    if (ch >= '0' && ch <= '9') glyph = g_fontDigits[ch - '0'];
    if (ch >= 'A' && ch <= 'Z') glyph = g_fontUpper[ch - 'A'];
    OledSetPosition(x, page);
    for (i = 0; i < 5; i++) {
        (void)OledWrite(0x40, glyph == NULL ? 0x00 : glyph[i]);
    }
    (void)OledWrite(0x40, 0x00);
}

static void OledWriteLine(uint8_t page, const char *text)
{
    uint8_t x = 0;
    if (text == NULL) return;
    while (*text != '\0' && x <= OLED_WIDTH - 6) {
        OledWriteChar(x, page, *text++);
        x += 6;
    }
}

void OledShowLines(const char *line1, const char *line2)
{
    OledClear();
    OledWriteLine(1, line1);
    OledWriteLine(4, line2);
}

void OledTestPattern(void)
{
    uint8_t page;
    uint8_t column;
    for (page = 0; page < OLED_PAGES; page++) {
        OledSetPosition(0, page);
        for (column = 0; column < OLED_WIDTH; column++) {
            (void)OledWrite(0x40, 0xAA);
        }
    }
}
