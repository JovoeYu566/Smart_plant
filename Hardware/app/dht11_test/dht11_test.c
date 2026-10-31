#include <stdio.h>
#include <unistd.h>
#include "ohos_init.h"
#include "cmsis_os2.h"
#include "iot_gpio.h"
#include "hi_io.h"
#include "hi_time.h"

#define DHT11_GPIO              0
#define DHT11_MAX_WAIT_US       200
#define DHT11_BIT_THRESHOLD_US  40
#define DHT11_FRAME_BYTES       5
#define DHT11_START_LOW_US      20000
#define DHT11_START_HIGH_US     30

static void Dht11_Init(void)
{
    IoTGpioInit(DHT11_GPIO);
    hi_io_set_func(HI_IO_NAME_GPIO_0, HI_IO_FUNC_GPIO_0_GPIO);
    IoTGpioSetDir(DHT11_GPIO, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(DHT11_GPIO, IOT_GPIO_VALUE1);
}

static void Dht11_SetInput(void)
{
    IoTGpioSetDir(DHT11_GPIO, IOT_GPIO_DIR_IN);
    hi_io_set_pull(HI_IO_NAME_GPIO_0, HI_IO_PULL_UP);
}

static void Dht11_SetOutput(void)
{
    IoTGpioSetDir(DHT11_GPIO, IOT_GPIO_DIR_OUT);
    IoTGpioSetOutputVal(DHT11_GPIO, IOT_GPIO_VALUE1);
}

static int Dht11_ReadLevel(void)
{
    IotGpioValue value = IOT_GPIO_VALUE0;
    if (IoTGpioGetInputVal(DHT11_GPIO, &value) != HI_ERR_SUCCESS) {
        return -1;
    }
    return (value == IOT_GPIO_VALUE0) ? 0 : 1;
}

static int Dht11_WaitLevel(int level, unsigned int timeoutUs)
{
    while (timeoutUs > 0) {
        int cur = Dht11_ReadLevel();
        if (cur < 0) {
            return -1;
        }
        if (cur == level) {
            return 0;
        }
        hi_udelay(1);
        timeoutUs--;
    }
    return -1;
}

static int Dht11_Read(int *temperature, int *humidity)
{
    unsigned char data[DHT11_FRAME_BYTES] = {0};
    hi_u64 tStart;
    unsigned int highUs;
    int i;

    if (temperature == NULL || humidity == NULL) {
        return -1;
    }

    Dht11_SetOutput();
    IoTGpioSetOutputVal(DHT11_GPIO, IOT_GPIO_VALUE0);
    hi_udelay(DHT11_START_LOW_US);
    IoTGpioSetOutputVal(DHT11_GPIO, IOT_GPIO_VALUE1);
    hi_udelay(DHT11_START_HIGH_US);
    Dht11_SetInput();

    if (Dht11_WaitLevel(0, DHT11_MAX_WAIT_US) != 0) {
        return -1;
    }
    if (Dht11_WaitLevel(1, DHT11_MAX_WAIT_US) != 0) {
        return -1;
    }
    if (Dht11_WaitLevel(0, DHT11_MAX_WAIT_US) != 0) {
        return -1;
    }

    for (i = 0; i < 40; i++) {
        if (Dht11_WaitLevel(1, DHT11_MAX_WAIT_US) != 0) {
            return -1;
        }
        tStart = hi_get_us();
        if (Dht11_WaitLevel(0, DHT11_MAX_WAIT_US) != 0) {
            return -1;
        }
        highUs = (unsigned int)(hi_get_us() - tStart);
        data[i / 8] <<= 1;
        if (highUs > DHT11_BIT_THRESHOLD_US) {
            data[i / 8] |= 0x01;
        }
    }

    if (((data[0] + data[1] + data[2] + data[3]) & 0xFF) != data[4]) {
        return -1;
    }

    *humidity = data[0];
    *temperature = data[2];
    return 0;
}

static void Dht11Task(void *arg)
{
    (void)arg;
    usleep(2000000);
    while (1) {
        int temperature = 0;
        int humidity = 0;
        int retry;
        int ok = 0;
        for (retry = 0; retry < 3; retry++) {
            if (Dht11_Read(&temperature, &humidity) == 0) {
                ok = 1;
                break;
            }
            hi_udelay(20000);
        }
        if (ok) {
            printf("[DHT11] humidity=%d%% temperature=%dC (GPIO%d)\r\n",
                   humidity, temperature, DHT11_GPIO);
        } else {
            printf("[DHT11] read failed (GPIO%d)\r\n", DHT11_GPIO);
        }
        sleep(2);
    }
}


static void Dht11Entry(void)
{
    osThreadAttr_t attr = {0};
    attr.name = "Dht11Task";
    attr.stack_size = 4096;
    attr.priority = osPriorityNormal;

    Dht11_Init();
    printf("[DHT11] test start, GPIO%d\r\n", DHT11_GPIO);
    if (osThreadNew(Dht11Task, NULL, &attr) == NULL) {
        printf("[DHT11] task create failed\r\n");
    }
}

APP_FEATURE_INIT(Dht11Entry);
