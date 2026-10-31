-- 已有库升级：主节点在线 + 主/从预留传感器字段
-- 若列已存在会报 Duplicate column，可忽略对应语句后继续
USE smart_plant;

ALTER TABLE plant_snapshot ADD COLUMN agv_smoke TINYINT(1) NULL COMMENT '从节点烟雾(预留)' AFTER agv_dist_right;
ALTER TABLE plant_snapshot ADD COLUMN agv_gas_adc INT NULL COMMENT '从节点气体ADC(预留)' AFTER agv_smoke;
ALTER TABLE plant_snapshot ADD COLUMN gateway_online TINYINT(1) NULL COMMENT '主节点在线' AFTER agv_gas_adc;
ALTER TABLE plant_snapshot ADD COLUMN light_lux DOUBLE NULL COMMENT '光照强度lux(预留)' AFTER dark;
ALTER TABLE plant_snapshot ADD COLUMN smoke TINYINT(1) NULL COMMENT '主节点烟雾(预留)' AFTER pir;

ALTER TABLE device_latest ADD COLUMN agv_smoke TINYINT(1) NULL COMMENT '从节点烟雾(预留)' AFTER agv_dist_right;
ALTER TABLE device_latest ADD COLUMN agv_gas_adc INT NULL COMMENT '从节点气体ADC(预留)' AFTER agv_smoke;
ALTER TABLE device_latest ADD COLUMN gateway_online TINYINT(1) NULL COMMENT '主节点在线' AFTER agv_gas_adc;
ALTER TABLE device_latest ADD COLUMN light_lux DOUBLE NULL COMMENT '光照强度lux(预留)' AFTER dark;
ALTER TABLE device_latest ADD COLUMN smoke TINYINT(1) NULL COMMENT '主节点烟雾(预留)' AFTER pir;
