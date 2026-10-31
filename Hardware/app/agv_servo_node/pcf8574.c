#include "pcf8574.h"
#include <stdio.h>
#include "iot_errno.h"
#include "iot_gpio.h"
#include "iot_i2c.h"
#include "hi_io.h"

#define PCF_I2C_IDX 0
#define PCF_I2C_BAUDRATE (100 * 1000)
#define PCF_READ_ADDR ((PCF8574_ADDR_7BIT << 1) | 1)
#define PCF_WRITE_ADDR ((PCF8574_ADDR_7BIT << 1) | 0)

static osMutexId_t g_i2cMutex = NULL;
static uint8_t g_shadow = 0xFF;
static int g_ready = 0;

void Pcf8574SetI2cMutex(osMutexId_t mutex) { g_i2cMutex = mutex; }

static uint32_t PcfWrite(uint8_t v)
{
    uint32_t ret;
    if (g_i2cMutex && osMutexAcquire(g_i2cMutex, 10) != osOK) return IOT_FAILURE;
    ret = IoTI2cWrite(PCF_I2C_IDX, PCF_WRITE_ADDR, &v, 1);
    if (g_i2cMutex) osMutexRelease(g_i2cMutex);
    return ret;
}

static uint32_t PcfRead(uint8_t *v)
{
    uint32_t ret;
    if (g_i2cMutex && osMutexAcquire(g_i2cMutex, 10) != osOK) return IOT_FAILURE;
    ret = IoTI2cRead(PCF_I2C_IDX, PCF_READ_ADDR, v, 1);
    if (g_i2cMutex) osMutexRelease(g_i2cMutex);
    return ret;
}

uint32_t Pcf8574Init(void)
{
    IoTGpioInit(HI_IO_NAME_GPIO_13);
    hi_io_set_func(HI_IO_NAME_GPIO_13, HI_IO_FUNC_GPIO_13_I2C0_SDA);
    hi_io_set_pull(HI_IO_NAME_GPIO_13, HI_IO_PULL_UP);
    IoTGpioInit(HI_IO_NAME_GPIO_14);
    hi_io_set_func(HI_IO_NAME_GPIO_14, HI_IO_FUNC_GPIO_14_I2C0_SCL);
    hi_io_set_pull(HI_IO_NAME_GPIO_14, HI_IO_PULL_UP);
    IoTI2cInit(PCF_I2C_IDX, PCF_I2C_BAUDRATE);
    g_shadow = 0xFF;
    if (PcfWrite(g_shadow) != IOT_SUCCESS) {
        printf("[PCF8574] init failed\r\n");
        g_ready = 0;
        return IOT_FAILURE;
    }
    g_ready = 1;
    printf("[PCF8574] ok P1=Flame P2=Gas P3=Smoke P4=DHT11\r\n");
    return IOT_SUCCESS;
}

void Pcf8574SetPin(int dev, unsigned int pin, int high)
{
    (void)dev;
    if (!g_ready || pin > 7) return;
    if (high) g_shadow |= (uint8_t)(1u << pin);
    else g_shadow &= (uint8_t)~(1u << pin);
    g_shadow |= 0xFF; /* input pins stay high; no-op for outputs on this compact board */
    (void)PcfWrite(g_shadow);
}

void Pcf8574UpdateBits(int dev, uint8_t clearMask, uint8_t setMask)
{
    (void)dev;
    g_shadow &= (uint8_t)~clearMask;
    g_shadow |= setMask;
    (void)PcfWrite(g_shadow);
}

int Pcf8574GetPin(int dev, unsigned int pin)
{
    uint8_t v = 0xFF;
    (void)dev;
    if (!g_ready || pin > 7) return 1;
    if (PcfRead(&v) != IOT_SUCCESS) return 1;
    return (v & (1u << pin)) ? 1 : 0;
}

int Pcf8574ReadPin(int dev, unsigned int pin)
{
    return Pcf8574GetPin(dev, pin);
}
