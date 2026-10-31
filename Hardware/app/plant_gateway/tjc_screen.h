#ifndef TJC_SCREEN_H
#define TJC_SCREEN_H

#include <stdint.h>

/**
 * 淘晶驰串口屏（USART HMI 协议）
 * 接线：板子 GPIO6(UART1_TX) → 屏 RX，共地；屏 5V 供电
 * GPIO8 已从绿灯释放，留给串口屏相关扩展；GPIO9 暂空
 * OLED 代码仍保留并行显示
 */

uint32_t TjcInit(void);
void TjcSendCmd(const char *cmd);
void TjcSetText(const char *obj, const char *text);
void TjcSetNumber(const char *obj, int value);

#endif /* TJC_SCREEN_H */
