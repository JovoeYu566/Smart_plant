#ifndef PCF8574_H
#define PCF8574_H

#include <stdint.h>

#ifndef PCF8574_ADDR_7BIT
#define PCF8574_ADDR_7BIT  0x20
#endif

/*
 * 拓展板：P0火焰 P3白灯 P4绿灯 P5黄灯
 * 光电计数已改接本板 GPIO6；烟雾数字量接 GPIO0（勿用 GPIO8）
 */
#define PCF_PIN_FLAME  0
#define PCF_PIN_WHITE  3
#define PCF_PIN_GREEN  4
#define PCF_PIN_YELLOW 5
#define PCF_INPUT_MASK  (1u << PCF_PIN_FLAME)

#include "cmsis_os2.h"

void Pcf8574SetI2cMutex(osMutexId_t mutex);
uint32_t Pcf8574Init(void);
void Pcf8574SetPin(unsigned int pin, int high);
void Pcf8574UpdateBits(uint8_t clearMask, uint8_t setMask);
int Pcf8574GetPin(unsigned int pin);
int Pcf8574TryGetPin(unsigned int pin);
int Pcf8574TryReadPort(uint8_t *value);

#endif /* PCF8574_H */
