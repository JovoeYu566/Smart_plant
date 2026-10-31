package com.smartplant.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.smartplant.config.SmartPlantProperties;
import com.smartplant.domain.entity.AlarmEvent;
import com.smartplant.domain.entity.PlantSnapshot;
import com.smartplant.mapper.AlarmEventMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

@Slf4j
@Service
@RequiredArgsConstructor
public class AlarmService {

    public static final String TYPE_FLAME = "FLAME";
    public static final String TYPE_GAS = "GAS";
    public static final String TYPE_OFFLINE = "OFFLINE";
    public static final String TYPE_GATEWAY_OFFLINE = "GATEWAY_OFFLINE";
    public static final String TYPE_COLLISION = "COLLISION";

    private final AlarmEventMapper alarmEventMapper;
    private final SmartPlantProperties properties;

    @Transactional
    public void evaluate(PlantSnapshot snapshot) {
        Set<String> activeNow = new HashSet<>();

        if (Boolean.TRUE.equals(snapshot.getFlameAlarm()) || Boolean.TRUE.equals(snapshot.getAgvFlame())) {
            activeNow.add(TYPE_FLAME);
            ensureActive(TYPE_FLAME, "检测到火焰告警", snapshot.getId());
        }

        SmartPlantProperties.Alarm cfg = properties.getAlarm();
        // 气体异常：旧 alarm，或新版 gate_alarm_active / gate_gas_alarm（已在 payload 归一）
        if (Boolean.TRUE.equals(snapshot.getAlarm())) {
            activeNow.add(TYPE_GAS);
            ensureActive(TYPE_GAS, "气体异常（gate_gas_alarm/alarm）", snapshot.getId());
        }

        if (Boolean.FALSE.equals(snapshot.getAgvOnline())) {
            activeNow.add(TYPE_OFFLINE);
            ensureActive(TYPE_OFFLINE, "从节点 AGV 离线", snapshot.getId());
        }

        if (Boolean.FALSE.equals(snapshot.getGatewayOnline())) {
            activeNow.add(TYPE_GATEWAY_OFFLINE);
            ensureActive(TYPE_GATEWAY_OFFLINE, "主节点网关离线", snapshot.getId());
        }

        int minDist = cfg.getMinDistanceCm();
        List<String> nearSides = new ArrayList<>();
        if (isTooClose(snapshot.getAgvDistFront(), minDist)) {
            nearSides.add("前=" + snapshot.getAgvDistFront());
        }
        if (isTooClose(snapshot.getAgvDistBack(), minDist)) {
            nearSides.add("后=" + snapshot.getAgvDistBack());
        }
        if (isTooClose(snapshot.getAgvDistLeft(), minDist)) {
            nearSides.add("左=" + snapshot.getAgvDistLeft());
        }
        if (isTooClose(snapshot.getAgvDistRight(), minDist)) {
            nearSides.add("右=" + snapshot.getAgvDistRight());
        }
        if (!nearSides.isEmpty()) {
            activeNow.add(TYPE_COLLISION);
            ensureActive(TYPE_COLLISION, "碰撞风险: " + String.join(",", nearSides) + "cm", snapshot.getId());
        }

        recoverMissing(activeNow);
    }

    private boolean isTooClose(Integer dist, int minDist) {
        return dist != null && dist >= 0 && dist < minDist;
    }

    private void ensureActive(String type, String message, Long snapshotId) {
        AlarmEvent existing = alarmEventMapper.selectOne(new LambdaQueryWrapper<AlarmEvent>()
                .eq(AlarmEvent::getAlarmType, type)
                .eq(AlarmEvent::getActive, true)
                .last("LIMIT 1"));
        if (existing != null) {
            return;
        }
        AlarmEvent event = new AlarmEvent();
        event.setAlarmType(type);
        event.setMessage(message);
        event.setActive(true);
        event.setSnapshotId(snapshotId);
        event.setTriggeredAt(LocalDateTime.now());
        alarmEventMapper.insert(event);
        log.warn("告警触发 type={} msg={}", type, message);
    }

    private void recoverMissing(Set<String> activeNow) {
        List<AlarmEvent> actives = alarmEventMapper.selectList(new LambdaQueryWrapper<AlarmEvent>()
                .eq(AlarmEvent::getActive, true));
        LocalDateTime now = LocalDateTime.now();
        for (AlarmEvent event : actives) {
            if (!activeNow.contains(event.getAlarmType())) {
                event.setActive(false);
                event.setRecoveredAt(now);
                alarmEventMapper.updateById(event);
                log.info("告警恢复 type={}", event.getAlarmType());
            }
        }
    }

    public List<AlarmEvent> list(Boolean activeOnly, int limit) {
        return list(activeOnly, null, limit);
    }

    public List<AlarmEvent> list(Boolean activeOnly, String keyword, int limit) {
        LambdaQueryWrapper<AlarmEvent> qw = new LambdaQueryWrapper<AlarmEvent>()
                .orderByDesc(AlarmEvent::getTriggeredAt)
                .last("LIMIT " + Math.max(1, Math.min(limit, 10000)));
        if (Boolean.TRUE.equals(activeOnly)) {
            qw.eq(AlarmEvent::getActive, true);
        }
        if (keyword != null && !keyword.isBlank()) {
            String kw = keyword.trim();
            qw.and(w -> w.like(AlarmEvent::getAlarmType, kw).or().like(AlarmEvent::getMessage, kw));
        }
        return alarmEventMapper.selectList(qw);
    }
}
