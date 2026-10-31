#ifndef SHT20_H
#define SHT20_H

#include <stdint.h>

/**
 * SHT20 温湿度传感器（I2C 地址 0x40）
 * 本板：与 OLED 共用 I2C0，GPIO13=SDA、GPIO14=SCL
 */

uint32_t SHT20_Init(void);
uint32_t SHT20_ReadTempHumidity(float *temp, float *humi);

#endif /* SHT20_H */
