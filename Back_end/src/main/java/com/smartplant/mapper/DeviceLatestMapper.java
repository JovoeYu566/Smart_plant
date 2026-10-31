package com.smartplant.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.smartplant.domain.entity.DeviceLatest;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;

@Mapper
public interface DeviceLatestMapper extends BaseMapper<DeviceLatest> {

    /**
     * 单条 UPSERT，避免先 SELECT 再 UPDATE 的延迟与并发问题
     */
    @Insert("""
            INSERT INTO device_latest (
              device_key, source, topic,
              agv_temperature, agv_humidity, agv_flame, agv_online,
              agv_dist_front, agv_dist_back, agv_dist_left, agv_dist_right,
              agv_smoke, agv_gas_adc, gateway_online,
              gas_temperature, gas_humidity, gas_adc, gas_voltage,
              alarm, flame_alarm, dark, light_lux, pir, smoke, cargo_count,
              raw_json, snapshot_id, updated_at
            ) VALUES (
              #{deviceKey}, #{source}, #{topic},
              #{agvTemperature}, #{agvHumidity}, #{agvFlame}, #{agvOnline},
              #{agvDistFront}, #{agvDistBack}, #{agvDistLeft}, #{agvDistRight},
              #{agvSmoke}, #{agvGasAdc}, #{gatewayOnline},
              #{gasTemperature}, #{gasHumidity}, #{gasAdc}, #{gasVoltage},
              #{alarm}, #{flameAlarm}, #{dark}, #{lightLux}, #{pir}, #{smoke}, #{cargoCount},
              #{rawJson}, #{snapshotId}, NOW()
            )
            ON DUPLICATE KEY UPDATE
              source=VALUES(source),
              topic=VALUES(topic),
              agv_temperature=VALUES(agv_temperature),
              agv_humidity=VALUES(agv_humidity),
              agv_flame=VALUES(agv_flame),
              agv_online=VALUES(agv_online),
              agv_dist_front=VALUES(agv_dist_front),
              agv_dist_back=VALUES(agv_dist_back),
              agv_dist_left=VALUES(agv_dist_left),
              agv_dist_right=VALUES(agv_dist_right),
              agv_smoke=VALUES(agv_smoke),
              agv_gas_adc=VALUES(agv_gas_adc),
              gateway_online=VALUES(gateway_online),
              gas_temperature=VALUES(gas_temperature),
              gas_humidity=VALUES(gas_humidity),
              gas_adc=VALUES(gas_adc),
              gas_voltage=VALUES(gas_voltage),
              alarm=VALUES(alarm),
              flame_alarm=VALUES(flame_alarm),
              dark=VALUES(dark),
              light_lux=VALUES(light_lux),
              pir=VALUES(pir),
              smoke=VALUES(smoke),
              cargo_count=VALUES(cargo_count),
              raw_json=VALUES(raw_json),
              snapshot_id=VALUES(snapshot_id),
              updated_at=NOW()
            """)
    int upsertByDeviceKey(DeviceLatest latest);

    /** 仅改在线标志，不刷新 updated_at（保留最后真实报文时间） */
    @Update("""
            UPDATE device_latest
            SET gateway_online=#{gatewayOnline}, agv_online=#{agvOnline}
            WHERE device_key=#{deviceKey}
            """)
    int updateOnlineFlags(@Param("deviceKey") String deviceKey,
                          @Param("gatewayOnline") boolean gatewayOnline,
                          @Param("agvOnline") boolean agvOnline);

    /** 同步修正 raw_json 里的在线字段，避免前端优先解析 rawJson 时读到旧 true */
    @Update("""
            UPDATE device_latest
            SET raw_json = REPLACE(
                  REPLACE(
                    REPLACE(
                      REPLACE(IFNULL(raw_json, '{}'), '"gateway_online":true', '"gateway_online":false'),
                      '"agv_online":true', '"agv_online":false'
                    ),
                    '"gateway_online": true', '"gateway_online": false'
                  ),
                  '"agv_online": true', '"agv_online": false'
                )
            WHERE device_key=#{deviceKey}
            """)
    int patchRawJsonOffline(@Param("deviceKey") String deviceKey);
}
