#include "pcf8574.h"

#include <stdio.h>

#include "cmsis_os2.h"
#include "iot_errno.h"
#include "iot_gpio.h"
#include "iot_i2c.h"
#include "hi_io.h"

#define PCF_I2C_IDX        0
#define PCF_I2C_BAUDRATE   (100 * 1000)
#define PCF_WRITE_ADDR     ((PCF8574_ADDR_7BIT << 1) | 0)
#define PCF_READ_ADDR      ((PCF8574_ADDR_7BIT << 1) | 1)

/* 输入高 + 灯灭(P3/P4/P5=0) + 空闲脚高(含原 P1) */
#define PCF_INIT_PORT  ((uint8_t)(PCF_INPUT_MASK | (1u << 1) | (1u << 2) | (1u << 6) | (1u << 7)))

static osMutexId_t g_i2c0Mutex = NULL;
static uint8_t g_pcfShadow = PCF_INIT_PORT;
static int g_pcfReady = 0;

void Pcf8574SetI2cMutex(osMutexId_t mutex)
{
    g_i2c0Mutex = mutex;
}

static uint32_t PcfWrite(uint8_t val)
{
    uint8_t buf = val;
    uint32_t ret;
    if (g_i2c0Mutex != NULL && osMutexAcquire(g_i2c0Mutex, 10) != osOK) {
        return 1;
    }
    ret = IoTI2cWrite(PCF_I2C_IDX, PCF_WRITE_ADDR, &buf, 1);
    if (g_i2c0Mutex != NULL) {
        osMutexRelease(g_i2c0Mutex);
    }
    return ret;
}

static uint32_t PcfRead(uint8_t *val)
{
    uint32_t ret;
    if (g_i2c0Mutex != NULL && osMutexAcquire(g_i2c0Mutex, 100) != osOK) {
        return 1;
    }
    ret = IoTI2cRead(PCF_I2C_IDX, PCF_READ_ADDR, val, 1);
    if (g_i2c0Mutex != NULL) {
        osMutexRelease(g_i2c0Mutex);
    }
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

    g_pcfShadow = PCF_INIT_PORT;
    uint32_t ret = PcfWrite(g_pcfShadow);
    if (ret != IOT_SUCCESS) {
        printf("[PCF8574] init fail addr=0x%02X ret=%u\r\n",
               PCF8574_ADDR_7BIT, ret);
        g_pcfReady = 0;
        return ret;
    }

    g_pcfReady = 1;
    printf("[PCF8574] ok P0=Flame P3=White P4=Green P5=Yellow\r\n");
    return IOT_SUCCESS;
}

void Pcf8574UpdateBits(uint8_t clearMask, uint8_t setMask)
{
    uint8_t next;
    if (!g_pcfReady) {
        return;
    }
    next = (uint8_t)((g_pcfShadow & (uint8_t)~clearMask) | setMask);
    next |= (uint8_t)PCF_INPUT_MASK;
    if (next == g_pcfShadow) {
        return;
    }
    if (PcfWrite(next) == IOT_SUCCESS) {
        g_pcfShadow = next;
    } else {
        osDelay(2);
        if (PcfWrite(next) == IOT_SUCCESS) {
            g_pcfShadow = next;
        }
    }
}

void Pcf8574SetPin(unsigned int pin, int high)
{
    uint8_t mask;
    uint8_t next;
    if (!g_pcfReady || pin > 7) {
        return;
    }
    mask = (uint8_t)(1u << pin);
    next = g_pcfShadow;
    if (high) {
        next |= mask;
    } else {
        next &= (uint8_t)~mask;
    }
    next |= (uint8_t)PCF_INPUT_MASK;
    if (next == g_pcfShadow) {
        return; /* 无变化不写，减轻 I2C 负担 */
    }
    if (PcfWrite(next) == IOT_SUCCESS) {
        g_pcfShadow = next;
    } else {
        osDelay(2);
        if (PcfWrite(next) == IOT_SUCCESS) {
            g_pcfShadow = next;
        }
    }
}

int Pcf8574GetPin(unsigned int pin)
{
    uint8_t val = 0xFF;
    if (!g_pcfReady || pin > 7) {
        return 1;
    }
    /* 只读：输入脚已在 Init/SetPin 时置 1，避免计数任务每 10ms 写总线 */
    if (PcfRead(&val) != IOT_SUCCESS) {
        return 1;
    }
    return (val & (1u << pin)) ? 1 : 0;
}

int Pcf8574TryReadPort(uint8_t *value)
{
    if (!g_pcfReady || value == NULL) {
        return -1;
    }
    return (PcfRead(value) == IOT_SUCCESS) ? 0 : -1;
}

int Pcf8574TryGetPin(unsigned int pin)
{
    uint8_t val = 0xFF;
    if (!g_pcfReady || pin > 7) {
        return -1;
    }
    if (PcfRead(&val) != IOT_SUCCESS) {
        return -1;
    }
    return (val & (1u << pin)) ? 1 : 0;
}
