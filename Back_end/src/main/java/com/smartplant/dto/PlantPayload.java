package com.smartplant.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

/**
 * MQTT / HTTP 上报载荷。
 * 兼容旧字段（gas_* / alarm / flame_alarm …）与新字段（gate_* / agv_gas）。
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class PlantPayload {

    // —— 从节点 AGV ——
    @JsonProperty("agv_temperature")
    private Double agvTemperature;

    @JsonProperty("agv_humidity")
    private Double agvHumidity;

    @JsonProperty("agv_flame")
    private Boolean agvFlame;

    @JsonProperty("agv_online")
    private Boolean agvOnline;

    @JsonProperty("agv_dist_front")
    private Integer agvDistFront;

    @JsonProperty("agv_dist_back")
    private Integer agvDistBack;

    @JsonProperty("agv_dist_left")
    private Integer agvDistLeft;

    @JsonProperty("agv_dist_right")
    private Integer agvDistRight;

    @JsonProperty("agv_smoke")
    private Boolean agvSmoke;

    /** 旧版：从节点可燃气体 ADC */
    @JsonProperty("agv_gas_adc")
    private Integer agvGasAdc;

    /** 新版：从节点可燃气体告警布尔 */
    @JsonProperty("agv_gas")
    @JsonAlias({"agv_gas_alarm"})
    private Boolean agvGas;

    // —— 主节点网关 ——
    @JsonProperty("gateway_online")
    @JsonAlias({"master_online", "gas_online", "gatewayOnline", "masterOnline"})
    private Boolean gatewayOnline;

    @JsonProperty("gas_temperature")
    @JsonAlias({"gate_temperature"})
    private Double gasTemperature;

    @JsonProperty("gas_humidity")
    @JsonAlias({"gate_humidity"})
    private Double gasHumidity;

    @JsonProperty("gas_adc")
    @JsonAlias({"gate_gas_adc"})
    private Integer gasAdc;

    @JsonProperty("gas_voltage")
    @JsonAlias({"gate_gas_voltage"})
    private Double gasVoltage;

    /** 旧版总告警；新版由 gate_alarm_active / gate_gas_alarm 归一 */
    @JsonProperty("alarm")
    private Boolean alarm;

    @JsonProperty("gate_alarm_active")
    private Boolean gateAlarmActive;

    @JsonProperty("gate_gas_alarm")
    private Boolean gateGasAlarm;

    /** 新版：网关告警类型编码（0=无） */
    @JsonProperty("gate_alarm_type")
    private Integer gateAlarmType;

    @JsonProperty("flame_alarm")
    @JsonAlias({"gate_flame_alarm"})
    private Boolean flameAlarm;

    @JsonProperty("dark")
    @JsonAlias({"gate_dark"})
    private Boolean dark;

    /** 光照强度 lux（新版 gate_lux；旧版 light_lux / 光敏 dark） */
    @JsonProperty("light_lux")
    @JsonAlias({"gate_lux", "lux", "light_intensity"})
    private Double lightLux;

    @JsonProperty("pir")
    @JsonAlias({"gate_pir"})
    private Boolean pir;

    @JsonProperty("smoke")
    @JsonAlias({"smoke_alarm", "gateway_smoke", "gate_smoke"})
    private Boolean smoke;

    @JsonProperty("cargo_count")
    @JsonAlias({"gate_cargo_count"})
    private Integer cargoCount;

    /**
     * 将新版 gate_* / agv_gas 归一到内部统一字段，便于入库与告警评估。
     */
    public void normalizeNewSchema() {
        if (alarm == null) {
            if (gateAlarmActive != null || gateGasAlarm != null) {
                alarm = Boolean.TRUE.equals(gateAlarmActive) || Boolean.TRUE.equals(gateGasAlarm);
            }
        }
    }
}
