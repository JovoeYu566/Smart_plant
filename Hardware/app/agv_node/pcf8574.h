#ifndef PCF8574_H
#define PCF8574_H

#include <stdint.h>

/* 两块板地址须不同。启动时会扫描 0x20~0x27 / 0x38~0x3F(跳过OLED 0x3C) 自动分配。
 * 推荐：板1 A0/A1/A2 全低=0x20；板2 仅 A0 接高=0x21。
 */
#define PCF_DEV0  0   /* 第一块：火焰/超声前+后 */
#define PCF_DEV1  1   /* 第二块：超声左+右 */
#define PCF_DEV_NUM 2

/* ---- 板1 (DEV0) ----
 * P0 火焰
 * P1 烟雾传感器
 * P2 可燃气体传感器
 * P3 按键1
 * P6/P7 右超声 Trig/Echo；P4/P5 后超声 Trig/Echo
 * 说明：右/后超声的 Echo/Trig 分别接到 P7/P6、P5/P4
 */
#define PCF_PIN_FLAME     0
#define PCF_PIN_SMOKE     1
#define PCF_PIN_GAS       2
#define PCF_PIN_BUTTON1   3
#define PCF_PIN_US1_TRIG  6
#define PCF_PIN_US1_ECHO  7
#define PCF_PIN_US2_TRIG  4
#define PCF_PIN_US2_ECHO  5

/* ---- 板2 (DEV1) ----
 * P0/P1 左超声 Trig/Echo  P2/P3 右超声 Trig/Echo
 * 说明：你当前接线为 Echo/Trig 分别接到 P1/P0、P3/P2
 */
#define PCF_PIN_US3_TRIG  0
#define PCF_PIN_US3_ECHO  1
#define PCF_PIN_US4_TRIG  2
#define PCF_PIN_US4_ECHO  3

uint32_t Pcf8574Init(void);
void Pcf8574SetPin(int dev, unsigned int pin, int high);
/* 一次 I2C 写更新多位：clearMask 清 0 的位，setMask 置 1 的位（电机驱动必须原子写） */
void Pcf8574UpdateBits(int dev, uint8_t clearMask, uint8_t setMask);
int Pcf8574GetPin(int dev, unsigned int pin);
int Pcf8574ReadPin(int dev, unsigned int pin);

#endif /* PCF8574_H */
