#include "tjc_screen.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "iot_uart.h"
#include "iot_errno.h"
#include "iot_gpio.h"
#include "hi_io.h"
#include "hi_uart.h"

/* UART1：TX=GPIO6（芯片固定复用）；RX 暂不接（只刷显示） */
#define TJC_UART_ID     HI_UART_IDX_1
#define TJC_UART_TX_GPIO HI_IO_NAME_GPIO_6
#define TJC_UART_TX_FUNC HI_IO_FUNC_GPIO_6_UART1_TXD
#define TJC_BAUDRATE    9600

static int g_tjcReady = 0;

static void TjcWriteRaw(const unsigned char *data, unsigned int len)
{
    if (!g_tjcReady || data == NULL || len == 0) {
        return;
    }
    (void)IoTUartWrite(TJC_UART_ID, data, len);
}

uint32_t TjcInit(void)
{
    /* 释放/配置 UART1 TX：GPIO6 */
    IoTGpioInit(TJC_UART_TX_GPIO);
    hi_io_set_func(TJC_UART_TX_GPIO, TJC_UART_TX_FUNC);

    /*
     * GPIO8 已空出给串口屏侧使用（不再做绿灯）。
     * 芯片 UART1 的 TX 脚是 GPIO6，请将屏 RX 接到 GPIO6。
     * GPIO9 按需求暂空。
     */
    IoTGpioInit(HI_IO_NAME_GPIO_8);
    hi_io_set_func(HI_IO_NAME_GPIO_8, HI_IO_FUNC_GPIO_8_GPIO);
    IoTGpioSetDir(HI_IO_NAME_GPIO_8, IOT_GPIO_DIR_IN);

    IotUartAttribute attr = {0};
    attr.baudRate = TJC_BAUDRATE;
    attr.dataBits = IOT_UART_DATA_BIT_8;
    attr.stopBits = IOT_UART_STOP_BIT_1;
    attr.parity = IOT_UART_PARITY_NONE;
    attr.rxBlock = IOT_UART_BLOCK_STATE_NONE_BLOCK;
    attr.txBlock = IOT_UART_BLOCK_STATE_NONE_BLOCK;

    unsigned int ret = IoTUartInit(TJC_UART_ID, &attr);
    if (ret != IOT_SUCCESS) {
        printf("[TJC] UART1 init fail: %u\r\n", ret);
        g_tjcReady = 0;
        return ret;
    }

    g_tjcReady = 1;
    printf("[TJC] UART1 ready: GPIO6=TX -> 屏RX, baud=%d\r\n", TJC_BAUDRATE);

    /* 上电稍等屏就绪，切到 page0（可按 HMI 工程改） */
    usleep(200 * 1000);
    TjcSendCmd("page 0");
    return IOT_SUCCESS;
}

void TjcSendCmd(const char *cmd)
{
    if (!g_tjcReady || cmd == NULL) {
        return;
    }

    unsigned char tail[3] = {0xFF, 0xFF, 0xFF};
    unsigned int len = (unsigned int)strlen(cmd);
    TjcWriteRaw((const unsigned char *)cmd, len);
    TjcWriteRaw(tail, 3);
}

void TjcSetText(const char *obj, const char *text)
{
    char cmd[96];
    if (obj == NULL || text == NULL) {
        return;
    }
    /* 例：t0.txt="25.1" */
    snprintf(cmd, sizeof(cmd), "%s.txt=\"%s\"", obj, text);
    TjcSendCmd(cmd);
}

void TjcSetNumber(const char *obj, int value)
{
    char cmd[64];
    if (obj == NULL) {
        return;
    }
    /* 例：n0.val=123 */
    snprintf(cmd, sizeof(cmd), "%s.val=%d", obj, value);
    TjcSendCmd(cmd);
}
