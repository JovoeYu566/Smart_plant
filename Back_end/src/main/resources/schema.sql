CREATE DATABASE IF NOT EXISTS smart_plant DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE smart_plant;

CREATE TABLE IF NOT EXISTS sys_user (
    id            BIGINT PRIMARY KEY AUTO_INCREMENT,
    username      VARCHAR(64)  NOT NULL UNIQUE,
    password_hash VARCHAR(128) NOT NULL,
    display_name  VARCHAR(64)  NULL,
    enabled       TINYINT(1)   NOT NULL DEFAULT 1,
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS plant_snapshot (
    id               BIGINT PRIMARY KEY AUTO_INCREMENT,
    source           VARCHAR(16)  NOT NULL COMMENT 'mqtt | http',
    topic            VARCHAR(255) NULL,
    agv_temperature  DOUBLE       NULL,
    agv_humidity     DOUBLE       NULL,
    agv_flame        TINYINT(1)   NULL,
    agv_online       TINYINT(1)   NULL,
    agv_dist_front   INT          NULL,
    agv_dist_back    INT          NULL,
    agv_dist_left    INT          NULL,
    agv_dist_right   INT          NULL,
    agv_smoke        TINYINT(1)   NULL COMMENT '从节点烟雾(预留)',
    agv_gas_adc      INT          NULL COMMENT '从节点气体ADC(预留)',
    gateway_online   TINYINT(1)   NULL COMMENT '主节点在线',
    gas_temperature  DOUBLE       NULL,
    gas_humidity     DOUBLE       NULL,
    gas_adc          INT          NULL,
    gas_voltage      DOUBLE       NULL,
    alarm            TINYINT(1)   NULL,
    flame_alarm      TINYINT(1)   NULL,
    dark             TINYINT(1)   NULL COMMENT 'true=黑暗 false=明亮',
    light_lux        DOUBLE       NULL COMMENT '光照强度lux(预留)',
    pir              TINYINT(1)   NULL,
    smoke            TINYINT(1)   NULL COMMENT '主节点烟雾(预留)',
    cargo_count      INT          NULL,
    raw_json         TEXT         NULL,
    created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_created_at (created_at),
    INDEX idx_source (source)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS device_latest (
    id               BIGINT PRIMARY KEY AUTO_INCREMENT,
    device_key       VARCHAR(64)  NOT NULL UNIQUE COMMENT '默认 plant',
    source           VARCHAR(16)  NOT NULL,
    topic            VARCHAR(255) NULL,
    agv_temperature  DOUBLE       NULL,
    agv_humidity     DOUBLE       NULL,
    agv_flame        TINYINT(1)   NULL,
    agv_online       TINYINT(1)   NULL,
    agv_dist_front   INT          NULL,
    agv_dist_back    INT          NULL,
    agv_dist_left    INT          NULL,
    agv_dist_right   INT          NULL,
    agv_smoke        TINYINT(1)   NULL COMMENT '从节点烟雾(预留)',
    agv_gas_adc      INT          NULL COMMENT '从节点气体ADC(预留)',
    gateway_online   TINYINT(1)   NULL COMMENT '主节点在线',
    gas_temperature  DOUBLE       NULL,
    gas_humidity     DOUBLE       NULL,
    gas_adc          INT          NULL,
    gas_voltage      DOUBLE       NULL,
    alarm            TINYINT(1)   NULL,
    flame_alarm      TINYINT(1)   NULL,
    dark             TINYINT(1)   NULL COMMENT 'true=黑暗 false=明亮',
    light_lux        DOUBLE       NULL COMMENT '光照强度lux(预留)',
    pir              TINYINT(1)   NULL,
    smoke            TINYINT(1)   NULL COMMENT '主节点烟雾(预留)',
    cargo_count      INT          NULL,
    raw_json         TEXT         NULL,
    snapshot_id      BIGINT       NULL,
    updated_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS alarm_event (
    id            BIGINT PRIMARY KEY AUTO_INCREMENT,
    alarm_type    VARCHAR(32)  NOT NULL COMMENT 'FLAME|GAS|OFFLINE|GATEWAY_OFFLINE|COLLISION',
    message       VARCHAR(255) NOT NULL,
    active        TINYINT(1)   NOT NULL DEFAULT 1,
    snapshot_id   BIGINT       NULL,
    triggered_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    recovered_at  DATETIME     NULL,
    INDEX idx_alarm_active (active),
    INDEX idx_alarm_type (alarm_type),
    INDEX idx_triggered_at (triggered_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS control_command_log (
    id            BIGINT PRIMARY KEY AUTO_INCREMENT,
    request_id    VARCHAR(64)  NOT NULL,
    action        VARCHAR(64)  NOT NULL,
    params_json   TEXT         NULL,
    operator      VARCHAR(64)  NOT NULL,
    topic         VARCHAR(255) NOT NULL,
    payload_json  TEXT         NOT NULL,
    success       TINYINT(1)   NOT NULL DEFAULT 0,
    error_message VARCHAR(512) NULL,
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_ctrl_created (created_at),
    INDEX idx_ctrl_action (action),
    INDEX idx_ctrl_operator (operator)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 默认管理员由应用启动时 DataInitializer 写入（密码 BCrypt）
