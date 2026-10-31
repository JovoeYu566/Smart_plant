#include <stdio.h>
#include <stddef.h>
#include <unistd.h>

#include "iot_gpio.h"
#include "iot_i2c.h"
#include "iot_errno.h"
#include "hi_io.h"

#include "oled_fonts.h"
#include "oled_ssd1306.h"

#define OLED_I2C_IDX        0
#define OLED_I2C_BAUDRATE   (100 * 1000)
#define OLED_I2C_ADDR       0x78   /* 7bit 0x3C << 1 */
#define OLED_I2C_CMD        0x00
#define OLED_I2C_DATA       0x40

/* 与主节点同款 OLED：128x64，共 8 页 */
#define OLED_PAGES          8

/* 从节点与主节点一致：I2C0 = GPIO14(SCL) + GPIO13(SDA) */
#define OLED_I2C_SCL_GPIO   HI_IO_NAME_GPIO_14
#define OLED_I2C_SDA_GPIO   HI_IO_NAME_GPIO_13
#define OLED_I2C_SCL_FUNC   HI_IO_FUNC_GPIO_14_I2C0_SCL
#define OLED_I2C_SDA_FUNC   HI_IO_FUNC_GPIO_13_I2C0_SDA

static uint32_t I2cWriteByte(uint8_t regAddr, uint8_t byte)
{
    uint8_t buffer[] = {regAddr, byte};
    return IoTI2cWrite(OLED_I2C_IDX, OLED_I2C_ADDR, buffer, sizeof(buffer));
}

static uint32_t WriteCmd(uint8_t cmd)
{
    return I2cWriteByte(OLED_I2C_CMD, cmd);
}

static uint32_t WriteCmdChecked(uint8_t cmd)
{
    uint32_t ret = WriteCmd(cmd);
    if (ret != IOT_SUCCESS) {
        printf("[OLED] write cmd 0x%02X failed: %u\r\n", cmd, ret);
    }
    return ret;
}

static uint32_t WriteData(uint8_t data)
{
    return I2cWriteByte(OLED_I2C_DATA, data);
}

uint32_t OledInit(void)
{
    uint32_t ret;

    IoTGpioInit(OLED_I2C_SDA_GPIO);
    hi_io_set_func(OLED_I2C_SDA_GPIO, OLED_I2C_SDA_FUNC);
    hi_io_set_pull(OLED_I2C_SDA_GPIO, HI_IO_PULL_UP);

    IoTGpioInit(OLED_I2C_SCL_GPIO);
    hi_io_set_func(OLED_I2C_SCL_GPIO, OLED_I2C_SCL_FUNC);
    hi_io_set_pull(OLED_I2C_SCL_GPIO, HI_IO_PULL_UP);

    IoTI2cInit(OLED_I2C_IDX, OLED_I2C_BAUDRATE);
    usleep(100 * 1000);

    /* 与主节点同款屏保持一致：SSD1306 128x64 初始化序列。 */
    if ((ret = WriteCmdChecked(0xAE)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x00)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x10)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x40)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xB0)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x81)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xFF)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xA1)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xA6)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xA8)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x3F)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xC8)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xD3)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x00)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xD5)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x80)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xD8)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x05)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xD9)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xF1)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xDA)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x12)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xDB)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x30)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x8D)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0x14)) != IOT_SUCCESS) return ret;
    if ((ret = WriteCmdChecked(0xAF)) != IOT_SUCCESS) return ret;

    usleep(100 * 1000);
    printf("[OLED] init ok (128x64, I2C0 GPIO13/14)\r\n");
    return IOT_SUCCESS;
}

void OledSetPosition(uint8_t x, uint8_t y)
{
    WriteCmd(0xB0 + y);
    WriteCmd(x & 0x0F);
    WriteCmd(((x & 0xF0) >> 4) | 0x10);
}

void OledFillScreen(uint8_t fillData)
{
    uint8_t m;
    uint8_t n;

    for (m = 0; m < OLED_PAGES; m++) {
        WriteCmd(0xB0 + m);
        WriteCmd(0x00);
        WriteCmd(0x10);
        for (n = 0; n < 128; n++) {
            WriteData(fillData);
        }
    }
}

void OledShowChar(uint8_t x, uint8_t y, uint8_t ch, Font font)
{
    uint8_t c = ch - ' ';
    uint8_t i;

    if (font == FONT8x16) {
        OledSetPosition(x, y);
        for (i = 0; i < 8; i++) {
            WriteData(F8X16[c * 16 + i]);
        }
        OledSetPosition(x, y + 1);
        for (i = 0; i < 8; i++) {
            WriteData(F8X16[c * 16 + 8 + i]);
        }
    } else {
        OledSetPosition(x, y);
        for (i = 0; i < 6; i++) {
            WriteData(F6x8[c][i]);
        }
    }
}

void OledShowString(uint8_t x, uint8_t y, const char *str, Font font)
{
    uint8_t j = 0;

    if (str == NULL) {
        return;
    }

    while (str[j] != '\0') {
        OledShowChar(x, y, (uint8_t)str[j], font);
        x += (font == FONT8x16) ? 8 : 6;
        if (x > 120) {
            x = 0;
            y += (font == FONT8x16) ? 2 : 1;
        }
        j++;
    }
}
