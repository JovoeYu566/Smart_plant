-- 增量：远程控制指令审计表（若库已存在可单独执行本段）
USE smart_plant;

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
