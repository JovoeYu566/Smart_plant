package com.smartplant.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.ArrayList;
import java.util.List;

@Data
@ConfigurationProperties(prefix = "smart-plant")
public class SmartPlantProperties {

    private Jwt jwt = new Jwt();
    private Gateway gateway = new Gateway();
    private Mqtt mqtt = new Mqtt();
    private Alarm alarm = new Alarm();
    private Ingest ingest = new Ingest();

    @Data
    public static class Jwt {
        private String secret;
        private long expireHours = 24;
    }

    @Data
    public static class Gateway {
        private String apiKey;
    }

    @Data
    public static class Mqtt {
        private boolean enabled = true;
        private String broker;
        private int port = 8883;
        private String username;
        private String password;
        private String clientId = "smart-plant-backend-01";
        private List<String> topics = new ArrayList<>();
        private String commandTopic = "plant/gateway/command";
        private int qos = 0;
    }

    @Data
    public static class Alarm {
        private int gasAdcThreshold = 200;
        private double gasVoltageThreshold = 0.5;
        private int minDistanceCm = 20;
    }

    @Data
    public static class Ingest {
        /** 历史快照写入最小间隔（毫秒） */
        private long snapshotIntervalMs = 3000;
        /** 告警判定最小间隔（毫秒）；在线状态边沿变化会强制立刻评估 */
        private long alarmIntervalMs = 300;
        /**
         * 工况心跳超时（毫秒）：超过该时间未收到 MQTT/上报，则主从均视为离线。
         * 需明显大于设备正常上报周期，避免网络抖动导致频繁假离线（建议 ≥ 设备间隔 × 3）。
         */
        private long onlineTimeoutMs = 60000;
        /** 后台扫描假在线的间隔（毫秒） */
        private long onlineCheckIntervalMs = 5000;
    }
}
