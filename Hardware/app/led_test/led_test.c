#include <unistd.h>

#include "iot_gpio.h"
#include "ohos_init.h"
#include "hi_io.h"

#define GPIO_LED 9

void ledTask(void)
{
    IoTGpioInit(GPIO_LED);
    hi_io_set_func(GPIO_LED, HI_IO_FUNC_GPIO_9_GPIO);
    IoTGpioSetDir(GPIO_LED, IOT_GPIO_DIR_OUT);
    while (1) {
        IoTGpioSetOutputVal(GPIO_LED, IOT_GPIO_VALUE0);
        usleep(1000 * 1000);
        IoTGpioSetOutputVal(GPIO_LED, IOT_GPIO_VALUE1);
        usleep(1000 * 1000);
    }
}

APP_FEATURE_INIT(ledTask);
