#include "pcf8574.h"

#include <stdio.h>

#include "iot_errno.h"
#include "iot_gpio.h"
#include "iot_i2c.h"
#include "hi_io.h"

/* 与 OLED/SHT20 共用 I2C0：SDA=GPIO13，SCL=GPIO14。
 * PCF8574 最高标准速率为 100 kHz；共享总线必须按最慢设备配置。
 */
#define PCF_I2C_IDX        0
#define PCF_I2C_BAUDRATE   (100 * 1000)
#define OLED_ADDR_7BIT     0x3C   /* 扫描时跳过，避免误当作 PCF */

/* 板1：输入=火焰/烟雾/燃气 + Echo1/2；P3 空闲拉高；Trig1/2 空闲低 */
#define PCF0_INPUT_MASK  ((1u << PCF_PIN_FLAME) | (1u << PCF_PIN_SMOKE) | (1u << PCF_PIN_GAS) | \
                          (1u << PCF_PIN_US1_ECHO) | (1u << PCF_PIN_US2_ECHO))
#define PCF0_INIT_PORT   ((uint8_t)(PCF0_INPUT_MASK | (1u << 3)))

/* 板2：输入=Echo3+Echo4；Trig3/4 空闲低；其余空闲高 */
#define PCF1_INPUT_MASK  ((1u << PCF_PIN_US3_ECHO) | (1u << PCF_PIN_US4_ECHO))
#define PCF1_INIT_PORT   ((uint8_t)(PCF1_INPUT_MASK | (1u << 4) | (1u << 5) | (1u << 6) | (1u << 7)))

static uint8_t g_pcfAddr[PCF_DEV_NUM];
static const uint8_t g_pcfInputMask[PCF_DEV_NUM] = { PCF0_INPUT_MASK, PCF1_INPUT_MASK };
static const uint8_t g_pcfInitPort[PCF_DEV_NUM] = { PCF0_INIT_PORT, PCF1_INIT_PORT };

static uint8_t g_pcfShadow[PCF_DEV_NUM];
static int g_pcfReady[PCF_DEV_NUM];
static int g_i2cReady = 0;

static uint32_t PcfWriteAddr(uint8_t addr7, uint8_t val)
{
    uint8_t buf = val;
    unsigned short waddr = (unsigned short)((addr7 << 1) | 0);
    return IoTI2cWrite(PCF_I2C_IDX, waddr, &buf, 1);
}

static uint32_t PcfWrite(int dev, uint8_t val)
{
    return PcfWriteAddr(g_pcfAddr[dev], val);
}

static uint32_t PcfRead(int dev, uint8_t *val)
{
    unsigned short raddr = (unsigned short)((g_pcfAddr[dev] << 1) | 1);
    return IoTI2cRead(PCF_I2C_IDX, raddr, val, 1);
}

/* 探测：写 0xFF 成功即认为该地址有应答 */
static int PcfProbe(uint8_t addr7)
{
    return (PcfWriteAddr(addr7, 0xFF) == IOT_SUCCESS) ? 1 : 0;
}

static int PcfScan(uint8_t found[], int maxFound)
{
    int n = 0;
    uint8_t a;

    printf("[PCF8574] I2C scan PCF range...\r\n");

    /* PCF8574: 0x20~0x27 */
    for (a = 0x20; a <= 0x27 && n < maxFound; a++) {
        if (PcfProbe(a)) {
            printf("  found 0x%02X\r\n", a);
            found[n++] = a;
        }
    }
    /* PCF8574A: 0x38~0x3F，跳过 OLED 0x3C */
    for (a = 0x38; a <= 0x3F && n < maxFound; a++) {
        if (a == OLED_ADDR_7BIT) {
            continue;
        }
        if (PcfProbe(a)) {
            printf("  found 0x%02X (PCF8574A?)\r\n", a);
            found[n++] = a;
        }
    }
    return n;
}

static uint32_t PcfInitOne(int dev)
{
    g_pcfShadow[dev] = g_pcfInitPort[dev];
    uint32_t ret = PcfWrite(dev, g_pcfShadow[dev]);
    if (ret != IOT_SUCCESS) {
        printf("[PCF8574] init fail dev%d addr=0x%02X ret=%u\r\n",
               dev, g_pcfAddr[dev], ret);
        g_pcfReady[dev] = 0;
        return ret;
    }
    g_pcfReady[dev] = 1;
    printf("[PCF8574] ok dev%d addr=0x%02X\r\n", dev, g_pcfAddr[dev]);
    return IOT_SUCCESS;
}

uint32_t Pcf8574Init(void)
{
    int i;
    uint8_t found[8];
    int nFound;
    uint32_t ret0 = IOT_FAILURE;

    if (!g_i2cReady) {
        IoTGpioInit(HI_IO_NAME_GPIO_13);
        hi_io_set_func(HI_IO_NAME_GPIO_13, HI_IO_FUNC_GPIO_13_I2C0_SDA);
        hi_io_set_pull(HI_IO_NAME_GPIO_13, HI_IO_PULL_UP);

        IoTGpioInit(HI_IO_NAME_GPIO_14);
        hi_io_set_func(HI_IO_NAME_GPIO_14, HI_IO_FUNC_GPIO_14_I2C0_SCL);
        hi_io_set_pull(HI_IO_NAME_GPIO_14, HI_IO_PULL_UP);

        IoTI2cInit(PCF_I2C_IDX, PCF_I2C_BAUDRATE);
        g_i2cReady = 1;
    }

    for (i = 0; i < PCF_DEV_NUM; i++) {
        g_pcfReady[i] = 0;
        g_pcfAddr[i] = 0;
    }

    nFound = PcfScan(found, (int)(sizeof(found) / sizeof(found[0])));
    if (nFound < 1) {
        printf("[PCF8574] 未扫描到拓展板，检查 SDA/SCL/供电\r\n");
        return IOT_FAILURE;
    }

    /* 优先把 0x20 分给 DEV0；其余第一块给 DEV1 */
    g_pcfAddr[PCF_DEV0] = found[0];
    for (i = 0; i < nFound; i++) {
        if (found[i] == 0x20) {
            g_pcfAddr[PCF_DEV0] = 0x20;
            break;
        }
    }
    g_pcfAddr[PCF_DEV1] = 0;
    for (i = 0; i < nFound; i++) {
        if (found[i] != g_pcfAddr[PCF_DEV0]) {
            g_pcfAddr[PCF_DEV1] = found[i];
            break;
        }
    }

    ret0 = PcfInitOne(PCF_DEV0);
    if (g_pcfAddr[PCF_DEV1] != 0) {
        (void)PcfInitOne(PCF_DEV1);
    } else {
        printf("[PCF8574] 只找到 1 块板(0x%02X)。第二块须改地址跳线！\r\n",
               g_pcfAddr[PCF_DEV0]);
        printf("  -> 板2: 将 A0 接高得到 0x21（或 A1->0x22），两板地址不能相同\r\n");
        printf("  -> 若板2已跳线仍扫不到：检查是否并到同一 I2C(GPIO10/9) 且共地\r\n");
    }

    printf("[PCF8574] map: DEV0 flame/US-F(P4/5)+US-B(P6/7); DEV1 US-L(P0/1)+US-R(P2/3)\r\n");
    return ret0;
}

void Pcf8574SetPin(int dev, unsigned int pin, int high)
{
    uint8_t mask;
    if (dev < 0 || dev >= PCF_DEV_NUM || !g_pcfReady[dev] || pin > 7) {
        return;
    }
    mask = (uint8_t)(1u << pin);
    if (high) {
        g_pcfShadow[dev] |= mask;
    } else {
        g_pcfShadow[dev] &= (uint8_t)~mask;
    }
    g_pcfShadow[dev] |= g_pcfInputMask[dev];
    (void)PcfWrite(dev, g_pcfShadow[dev]);
}

void Pcf8574UpdateBits(int dev, uint8_t clearMask, uint8_t setMask)
{
    if (dev < 0 || dev >= PCF_DEV_NUM || !g_pcfReady[dev]) {
        return;
    }
    g_pcfShadow[dev] &= (uint8_t)~clearMask;
    g_pcfShadow[dev] |= setMask;
    g_pcfShadow[dev] |= g_pcfInputMask[dev];
    (void)PcfWrite(dev, g_pcfShadow[dev]);
}

int Pcf8574GetPin(int dev, unsigned int pin)
{
    uint8_t val = 0xFF;
    if (dev < 0 || dev >= PCF_DEV_NUM || !g_pcfReady[dev] || pin > 7) {
        return 1;
    }
    g_pcfShadow[dev] |= g_pcfInputMask[dev];
    (void)PcfWrite(dev, g_pcfShadow[dev]);
    if (PcfRead(dev, &val) != IOT_SUCCESS) {
        return 1;
    }
    return (val & (1u << pin)) ? 1 : 0;
}

int Pcf8574ReadPin(int dev, unsigned int pin)
{
    uint8_t val = 0xFF;
    if (dev < 0 || dev >= PCF_DEV_NUM || !g_pcfReady[dev] || pin > 7) {
        return 1;
    }
    if (PcfRead(dev, &val) != IOT_SUCCESS) {
        return 1;
    }
    return (val & (1u << pin)) ? 1 : 0;
}
