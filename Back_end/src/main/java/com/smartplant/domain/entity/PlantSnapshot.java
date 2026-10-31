package com.smartplant.domain.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@TableName("plant_snapshot")
public class PlantSnapshot {

    @TableId(type = IdType.AUTO)
    private Long id;
    private String source;
    private String topic;
    private Double agvTemperature;
    private Double agvHumidity;
    private Boolean agvFlame;
    private Boolean agvOnline;
    private Integer agvDistFront;
    private Integer agvDistBack;
    private Integer agvDistLeft;
    private Integer agvDistRight;
    private Boolean agvSmoke;
    private Integer agvGasAdc;
    private Boolean gatewayOnline;
    private Double gasTemperature;
    private Double gasHumidity;
    private Integer gasAdc;
    private Double gasVoltage;
    private Boolean alarm;
    private Boolean flameAlarm;
    private Boolean dark;
    private Double lightLux;
    private Boolean pir;
    private Boolean smoke;
    private Integer cargoCount;
    private String rawJson;
    private LocalDateTime createdAt;
}
