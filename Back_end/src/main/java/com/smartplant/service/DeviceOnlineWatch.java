package com.smartplant.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 启动时不信任库里旧的 online=true；运行中按心跳超时把假在线打成离线。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class DeviceOnlineWatch {

    private final PlantService plantService;

    @EventListener(ApplicationReadyEvent.class)
    public void onReady() {
        // 后端刚起来：在收到新 MQTT 前一律按离线展示，避免假在线
        plantService.forceOfflineOnStartup();
    }

    @Scheduled(fixedDelayString = "${smart-plant.ingest.online-check-interval-ms:2000}")
    public void checkHeartbeat() {
        plantService.markStaleOnlineAsOffline();
    }
}
