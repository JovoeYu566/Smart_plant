#include <stdio.h>      // 标准输入输出
#include "ohos_init.h"  // 用于初始化服务(services)和功能(features)
#include "cmsis_os2.h"  // CMSIS-RTOS API V2

// 海思SDK接口：IoT硬件设备操作接口-IO / GPIO
// OpenHarmony 轻量级设备上，引脚复用(hi_io_set_func)和 GPIO 中断只能调用海思 SDK 接口
#include "hi_io.h"
#include "hi_gpio.h"

/*
 * 引脚定义（换板子时只需要改这一组宏）
 * 注意：每个引脚“切回普通 GPIO”的枚举值都不同，必须成对修改
 *       GPIO5 -> HI_IO_FUNC_GPIO_5_GPIO
 *       GPIO7 -> HI_IO_FUNC_GPIO_7_GPIO
 *       GPIO9 -> HI_IO_FUNC_GPIO_9_GPIO
 */
#define LED_GPIO        HI_IO_NAME_GPIO_7
#define LED_GPIO_FUNC   HI_IO_FUNC_GPIO_7_GPIO

#define KEY_GPIO        HI_IO_NAME_GPIO_5
#define KEY_GPIO_FUNC   HI_IO_FUNC_GPIO_5_GPIO

// 中断服务函数只置标志，真正的处理放到线程里做
// 原因：中断上下文禁止长时间阻塞，printf 一行的耗时远大于中断响应要求
static volatile int g_key_pressed_flag = 0;

// 安装中断处理函数
void keyPressedFunc(void *arg)
{
    (void)arg;
    g_key_pressed_flag = 1;
    return;
}

void led_init(void)
{
    // 初始化GPIO（hi_gpio_init 只允许调用一次，全系统统一在 led_init 里调用）
    hi_gpio_init();

    // 设置io引脚为通用IO (因为芯片引脚少 功能多 所以先设置该引脚是干什么作用的)
    hi_io_set_func(LED_GPIO, LED_GPIO_FUNC);

    // 输出引脚不需要上下拉
    hi_io_set_pull(LED_GPIO, HI_IO_PULL_NONE);

    // 设置GPIO为输出
    hi_gpio_set_dir(LED_GPIO, HI_GPIO_DIR_OUT);

    // 上电默认输出高电平，板载LED为低电平点亮，所以此时是熄灭状态
    hi_gpio_set_ouput_val(LED_GPIO, HI_GPIO_VALUE1);

    return ;
}

void key_init(void)
{
    hi_u32 ret;

    // 设置io引脚为通用IO (因为芯片引脚少 功能多 所以先设置该引脚是干什么作用的)
    hi_io_set_func(KEY_GPIO, KEY_GPIO_FUNC);

    // 关键：按键空闲时引脚必须有确定电平。
    // 不配上拉时引脚处于高阻悬空状态，环境噪声会让引脚电平乱跳，
    // 配合下降沿触发就会出现“不按键也疯狂进中断”的现象。
    // 按键一端接地时用上拉（空闲高、按下低）；按键一端接VCC时用下拉。
    ret = hi_io_set_pull(KEY_GPIO, HI_IO_PULL_UP);
    printf("[key] hi_io_set_pull ret = %u\n", ret);

    // 设置GPIO为输入
    hi_gpio_set_dir(KEY_GPIO, HI_GPIO_DIR_IN);

    // 注册GPIO中断处理函数
    ret = hi_gpio_register_isr_function(KEY_GPIO,   /* GPIO引脚 */
        HI_INT_TYPE_EDGE,                           /* 边沿触发 */
        HI_GPIO_EDGE_FALL_LEVEL_LOW,                /* 下降沿触发 */
        keyPressedFunc,                             /* 中断处理函数 */
        NULL
    );
    printf("[key] hi_gpio_register_isr_function ret = %u\n", ret);

    return;
}

/*
 * 按键处理线程：
 * 1. 只在线程里做消抖和 LED 翻转，避免在中断里 printf；
 * 2. 200ms 内的重复触发全部丢弃，机械抖动和噪声都不会造成连击；
 * 3. 万一只写了一行 printf 也只会按住一次输出一次，便于观察。
 */
static void key_task(void *arg)
{
    static hi_gpio_value led_val = HI_GPIO_VALUE1;
    hi_u32 last_tick = 0;

    (void)arg;

    while (1) {
        if (g_key_pressed_flag != 0) {
            g_key_pressed_flag = 0;

            hi_u32 now = osKernelGetTickCount();
            if ((now - last_tick) >= 20) {          /* 20 * 10ms = 200ms 消抖窗口 */
                last_tick = now;
                led_val = (led_val == HI_GPIO_VALUE0) ? HI_GPIO_VALUE1 : HI_GPIO_VALUE0;
                hi_gpio_set_ouput_val(LED_GPIO, led_val);
                printf("key pressed, led_val %d\n", led_val);
            }
        }
        osDelay(5);
    }

    return;
}

static void led_switch(void)
{
    osThreadAttr_t attr = {0};         // 线程属性必须清零，未赋值成员是随机值会导致创建失败

    led_init();
    key_init();

    attr.name = "KeyTask";             // 设置任务名
    attr.stack_size = 2048;            // 线程里有 printf，栈给足
    attr.priority = osPriorityNormal;  // 设置线程优先级

    if (osThreadNew(key_task, NULL, &attr) == NULL) {
        printf("[led_switch] Create KeyTask failed!\n");
    }
}

// ohos_init.h 中定义的宏，让函数在系统启动时执行
SYS_RUN(led_switch);
