#ifndef PCF8574_H
#define PCF8574_H

#include <stdint.h>
#include "cmsis_os2.h"

#ifndef PCF8574_ADDR_7BIT
#define PCF8574_ADDR_7BIT  0x20
#endif

#define PCF_DEV0 0
#define PCF_DEV_NUM 1

#define PCF_PIN_FLAME   1
#define PCF_PIN_GAS     2
#define PCF_PIN_SMOKE   3
#define PCF_PIN_DHT11   4
#define PCF_PIN_BUTTON1 0

void Pcf8574SetI2cMutex(osMutexId_t mutex);
uint32_t Pcf8574Init(void);
void Pcf8574SetPin(int dev, unsigned int pin, int high);
void Pcf8574UpdateBits(int dev, uint8_t clearMask, uint8_t setMask);
int Pcf8574GetPin(int dev, unsigned int pin);
int Pcf8574ReadPin(int dev, unsigned int pin);

#endif
