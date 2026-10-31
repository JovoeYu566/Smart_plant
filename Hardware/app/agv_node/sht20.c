#include "sht20.h"

#include <stdio.h>
#include <unistd.h>

#include "iot_errno.h"
#include "iot_i2c.h"
#include "iot_gpio.h"
#include "hi_io.h"

#define SHT20_I2C_IDX           0
#define SHT20_DEVICE_ADDR       0x40
#define SHT20_WRITE_ADDR        ((SHT20_DEVICE_ADDR << 1) | 0x0) /* 0x80 */
#define SHT20_READ_ADDR         ((SHT20_DEVICE_ADDR << 1) | 0x1) /* 0x81 */

/* No Hold Master 模式，不占用 I2C 总线，方便与 OLED 共享 */
#define SHT20_CMD_TRIG_TEMP_NH  0xF3
#define SHT20_CMD_TRIG_HUMI_NH  0xF5
#define SHT20_CMD_SOFT_RESET    0xFE

#define SHT20_TEMP_DELAY_US     (85 * 1000)
#define SHT20_HUMI_DELAY_US     (30 * 1000)
#define SHT20_RESET_DELAY_US    (20 * 1000)

static uint32_t SHT20_WriteCmd(uint8_t cmd)
{
    return IoTI2cWrite(SHT20_I2C_IDX, SHT20_WRITE_ADDR, &cmd, 1);
}

static uint32_t SHT20_ReadRaw(uint16_t *raw)
{
    uint8_t buf[3] = {0};
    uint32_t ret = IoTI2cRead(SHT20_I2C_IDX, SHT20_READ_ADDR, buf, sizeof(buf));
    if (ret != IOT_SUCCESS) {
        return ret;
    }
    /* 低两位为状态位，测量数据需清零 */
    *raw = ((uint16_t)buf[0] << 8) | (buf[1] & 0xFC);
    return IOT_SUCCESS;
}

uint32_t SHT20_Init(void)
{
    IoTGpioInit(HI_IO_NAME_GPIO_13);
    hi_io_set_func(HI_IO_NAME_GPIO_13, HI_IO_FUNC_GPIO_13_I2C0_SDA);
    hi_io_set_pull(HI_IO_NAME_GPIO_13, HI_IO_PULL_UP);
    IoTGpioInit(HI_IO_NAME_GPIO_14);
    hi_io_set_func(HI_IO_NAME_GPIO_14, HI_IO_FUNC_GPIO_14_I2C0_SCL);
    hi_io_set_pull(HI_IO_NAME_GPIO_14, HI_IO_PULL_UP);
    IoTI2cInit(SHT20_I2C_IDX, 100 * 1000);

    uint32_t ret = SHT20_WriteCmd(SHT20_CMD_SOFT_RESET);
    if (ret != IOT_SUCCESS) {
        printf("[SHT20] soft reset failed: 0x%X\r\n", ret);
        return ret;
    }
    usleep(SHT20_RESET_DELAY_US);
    printf("[SHT20] init ok (addr=0x%02X)\r\n", SHT20_DEVICE_ADDR);
    return IOT_SUCCESS;
}

uint32_t SHT20_ReadTempHumidity(float *temp, float *humi)
{
    uint16_t raw = 0;

    if (temp == NULL || humi == NULL) {
        return IOT_FAILURE;
    }

    /* 温度 */
    if (SHT20_WriteCmd(SHT20_CMD_TRIG_TEMP_NH) != IOT_SUCCESS) {
        printf("[SHT20] trig temp failed\r\n");
        return IOT_FAILURE;
    }
    usleep(SHT20_TEMP_DELAY_US);
    if (SHT20_ReadRaw(&raw) != IOT_SUCCESS) {
        printf("[SHT20] read temp failed\r\n");
        return IOT_FAILURE;
    }
    *temp = -46.85f + 175.72f * ((float)raw / 65536.0f);

    /* 湿度 */
    if (SHT20_WriteCmd(SHT20_CMD_TRIG_HUMI_NH) != IOT_SUCCESS) {
        printf("[SHT20] trig humi failed\r\n");
        return IOT_FAILURE;
    }
    usleep(SHT20_HUMI_DELAY_US);
    if (SHT20_ReadRaw(&raw) != IOT_SUCCESS) {
        printf("[SHT20] read humi failed\r\n");
        return IOT_FAILURE;
    }
    *humi = -6.0f + 125.0f * ((float)raw / 65536.0f);
    if (*humi < 0.0f) {
        *humi = 0.0f;
    } else if (*humi > 100.0f) {
        *humi = 100.0f;
    }

    return IOT_SUCCESS;
}
