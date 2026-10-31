package com.smartplant.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.smartplant.common.exception.BizException;
import com.smartplant.config.SmartPlantProperties;
import com.smartplant.domain.entity.DeviceLatest;
import com.smartplant.domain.entity.PlantSnapshot;
import com.smartplant.dto.PlantPayload;
import com.smartplant.mapper.DeviceLatestMapper;
import com.smartplant.mapper.PlantSnapshotMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.BeanUtils;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.concurrent.atomic.AtomicLong;

@Slf4j
@Service
@RequiredArgsConstructor
public class PlantService {

    public static final String DEVICE_KEY_PLANT = "plant";

    private final PlantSnapshotMapper plantSnapshotMapper;
    private final DeviceLatestMapper deviceLatestMapper;
    private final AlarmService alarmService;
    private final ObjectMapper objectMapper;
    private final SmartPlantProperties properties;

    private final AtomicLong lastSnapshotAt = new AtomicLong(0);
    private final AtomicLong lastAlarmAt = new AtomicLong(0);
    /** 上次看到的在线状态，用于离线/上线边沿立刻告警，不受节流影响 */
    private volatile Boolean lastAgvOnline = null;
    private volatile Boolean lastGatewayOnline = null;

    /**
     * 实时路径：每条 MQTT 立刻刷新 device_latest；
     * 历史快照按间隔节流；告警默认节流，但主/从在线状态变化或已离线时立刻判定。
     */
    public PlantSnapshot ingest(PlantPayload payload, String source, String topic, String rawJson) {
        if (payload == null) {
            throw new BizException("工况数据为空");
        }
        payload.normalizeNewSchema();

        String json = rawJson != null ? rawJson : toJsonQuiet(payload);
        long now = System.currentTimeMillis();

        // 1) 先写 latest（最快路径，不包大事务）
        DeviceLatest latest = buildLatest(payload, source, topic, json, null);
        deviceLatestMapper.upsertByDeviceKey(latest);

        PlantSnapshot snapshot = null;
        long snapshotInterval = properties.getIngest().getSnapshotIntervalMs();
        long lastSnap = lastSnapshotAt.get();
        if (now - lastSnap >= snapshotInterval && lastSnapshotAt.compareAndSet(lastSnap, now)) {
            snapshot = insertSnapshot(payload, source, topic, json);
            // 回写 snapshotId
            latest.setSnapshotId(snapshot.getId());
            deviceLatestMapper.upsertByDeviceKey(latest);
            log.debug("历史快照入库 id={}", snapshot.getId());
        }

        boolean forceAlarm = shouldForceAlarmEvaluate(payload);
        long alarmInterval = properties.getIngest().getAlarmIntervalMs();
        long lastAlarm = lastAlarmAt.get();
        boolean due = now - lastAlarm >= alarmInterval;
        if ((forceAlarm || due) && lastAlarmAt.compareAndSet(lastAlarm, now)) {
            PlantSnapshot forAlarm = snapshot != null ? snapshot : toEphemeralSnapshot(payload, source, topic, json);
            alarmService.evaluate(forAlarm);
            if (forceAlarm) {
                log.info("紧急告警评估 agvOnline={} gatewayOnline={}",
                        payload.getAgvOnline(), payload.getGatewayOnline());
            }
        } else if (forceAlarm) {
            // CAS 失败时再补一次，避免边沿丢失
            PlantSnapshot forAlarm = snapshot != null ? snapshot : toEphemeralSnapshot(payload, source, topic, json);
            alarmService.evaluate(forAlarm);
            lastAlarmAt.set(now);
        }

        lastAgvOnline = payload.getAgvOnline();
        lastGatewayOnline = payload.getGatewayOnline();

        log.debug("latest 已刷新 source={} adc={} cargo={}", source, payload.getGasAdc(), payload.getCargoCount());
        return snapshot;
    }

    /** 在线状态边沿变化，或首次看到离线：立刻评估，不等待节流 */
    private boolean shouldForceAlarmEvaluate(PlantPayload payload) {
        Boolean agv = payload.getAgvOnline();
        Boolean gw = payload.getGatewayOnline();
        boolean agvChanged = agv != null && lastAgvOnline != null && !agv.equals(lastAgvOnline);
        boolean gwChanged = gw != null && lastGatewayOnline != null && !gw.equals(lastGatewayOnline);
        boolean firstSeenOffline = (Boolean.FALSE.equals(agv) && lastAgvOnline == null)
                || (Boolean.FALSE.equals(gw) && lastGatewayOnline == null);
        return firstSeenOffline || agvChanged || gwChanged;
    }

    @Transactional
    protected PlantSnapshot insertSnapshot(PlantPayload payload, String source, String topic, String json) {
        PlantSnapshot snapshot = toEphemeralSnapshot(payload, source, topic, json);
        snapshot.setCreatedAt(LocalDateTime.now());
        plantSnapshotMapper.insert(snapshot);
        return snapshot;
    }

    private PlantSnapshot toEphemeralSnapshot(PlantPayload payload, String source, String topic, String json) {
        PlantSnapshot snapshot = new PlantSnapshot();
        BeanUtils.copyProperties(payload, snapshot);
        snapshot.setSource(source);
        snapshot.setTopic(topic);
        snapshot.setRawJson(json);
        return snapshot;
    }

    private DeviceLatest buildLatest(PlantPayload payload, String source, String topic, String json, Long snapshotId) {
        DeviceLatest latest = new DeviceLatest();
        latest.setDeviceKey(DEVICE_KEY_PLANT);
        latest.setSource(source);
        latest.setTopic(topic);
        latest.setAgvTemperature(payload.getAgvTemperature());
        latest.setAgvHumidity(payload.getAgvHumidity());
        latest.setAgvFlame(payload.getAgvFlame());
        latest.setAgvOnline(payload.getAgvOnline());
        latest.setAgvDistFront(payload.getAgvDistFront());
        latest.setAgvDistBack(payload.getAgvDistBack());
        latest.setAgvDistLeft(payload.getAgvDistLeft());
        latest.setAgvDistRight(payload.getAgvDistRight());
        latest.setAgvSmoke(payload.getAgvSmoke());
        latest.setAgvGasAdc(payload.getAgvGasAdc());
        latest.setGatewayOnline(payload.getGatewayOnline());
        latest.setGasTemperature(payload.getGasTemperature());
        latest.setGasHumidity(payload.getGasHumidity());
        latest.setGasAdc(payload.getGasAdc());
        latest.setGasVoltage(payload.getGasVoltage());
        latest.setAlarm(payload.getAlarm());
        latest.setFlameAlarm(payload.getFlameAlarm());
        latest.setDark(payload.getDark());
        latest.setLightLux(payload.getLightLux());
        latest.setPir(payload.getPir());
        latest.setSmoke(payload.getSmoke());
        latest.setCargoCount(payload.getCargoCount());
        latest.setRawJson(json);
        latest.setSnapshotId(snapshotId);
        latest.setUpdatedAt(LocalDateTime.now());
        return latest;
    }

    public DeviceLatest getLatest() {
        DeviceLatest latest = deviceLatestMapper.selectOne(new LambdaQueryWrapper<DeviceLatest>()
                .eq(DeviceLatest::getDeviceKey, DEVICE_KEY_PLANT)
                .last("LIMIT 1"));
        if (latest == null) {
            PlantSnapshot snap = plantSnapshotMapper.selectOne(new LambdaQueryWrapper<PlantSnapshot>()
                    .orderByDesc(PlantSnapshot::getCreatedAt)
                    .last("LIMIT 1"));
            if (snap == null) {
                return null;
            }
            latest = fromSnapshot(snap);
            // 用快照时间，避免把旧数据当成“刚刚更新”
            latest.setUpdatedAt(snap.getCreatedAt() != null ? snap.getCreatedAt() : LocalDateTime.now());
            deviceLatestMapper.upsertByDeviceKey(latest);
        }
        return applyOnlineTimeoutView(latest);
    }

    /**
     * 后端启动：在收到新工况前，把库里残留的 online=true 清掉，前端立即显示离线。
     */
    public void forceOfflineOnStartup() {
        DeviceLatest latest = loadRawLatest();
        if (latest == null) {
            log.info("启动在线校正：尚无 device_latest，跳过");
            return;
        }
        boolean wasGw = Boolean.TRUE.equals(latest.getGatewayOnline());
        boolean wasAgv = Boolean.TRUE.equals(latest.getAgvOnline());
        if (!wasGw && !wasAgv
                && Boolean.FALSE.equals(latest.getGatewayOnline())
                && Boolean.FALSE.equals(latest.getAgvOnline())) {
            log.info("启动在线校正：库中已是离线");
            return;
        }
        latest.setGatewayOnline(false);
        latest.setAgvOnline(false);
        // 不刷新 updatedAt：保留最后真实报文时间，便于超时逻辑
        deviceLatestMapper.updateOnlineFlags(DEVICE_KEY_PLANT, false, false);
        deviceLatestMapper.patchRawJsonOffline(DEVICE_KEY_PLANT);
        lastGatewayOnline = false;
        lastAgvOnline = false;
        alarmService.evaluate(toAlarmSnapshot(latest));
        log.info("启动在线校正：已将主/从标为离线（wasGw={} wasAgv={}）", wasGw, wasAgv);
    }

    /**
     * 运行中心跳：超过 onlineTimeoutMs 未收到工况，且仍显示在线 → 落库为离线并告警。
     */
    public void markStaleOnlineAsOffline() {
        DeviceLatest latest = loadRawLatest();
        if (latest == null) {
            return;
        }
        if (!isStale(latest)) {
            return;
        }
        boolean needGw = !Boolean.FALSE.equals(latest.getGatewayOnline());
        boolean needAgv = !Boolean.FALSE.equals(latest.getAgvOnline());
        if (!needGw && !needAgv) {
            return;
        }
        latest.setGatewayOnline(false);
        latest.setAgvOnline(false);
        deviceLatestMapper.updateOnlineFlags(DEVICE_KEY_PLANT, false, false);
        deviceLatestMapper.patchRawJsonOffline(DEVICE_KEY_PLANT);
        lastGatewayOnline = false;
        lastAgvOnline = false;
        alarmService.evaluate(toAlarmSnapshot(latest));
        log.warn("工况心跳超时：已将主/从标为离线 updatedAt={} timeoutMs={}",
                latest.getUpdatedAt(), properties.getIngest().getOnlineTimeoutMs());
    }

    private DeviceLatest loadRawLatest() {
        return deviceLatestMapper.selectOne(new LambdaQueryWrapper<DeviceLatest>()
                .eq(DeviceLatest::getDeviceKey, DEVICE_KEY_PLANT)
                .last("LIMIT 1"));
    }

    /** API 返回视图：超时则强制离线（即使库尚未被定时任务写回） */
    private DeviceLatest applyOnlineTimeoutView(DeviceLatest latest) {
        if (latest == null || !isStale(latest)) {
            return latest;
        }
        latest.setGatewayOnline(false);
        latest.setAgvOnline(false);
        return latest;
    }

    private boolean isStale(DeviceLatest latest) {
        long timeoutMs = properties.getIngest().getOnlineTimeoutMs();
        if (timeoutMs <= 0) {
            return false;
        }
        LocalDateTime updated = latest.getUpdatedAt();
        if (updated == null) {
            return true;
        }
        long ageMs = Duration.between(updated, LocalDateTime.now()).toMillis();
        return ageMs > timeoutMs;
    }

    private PlantSnapshot toAlarmSnapshot(DeviceLatest latest) {
        PlantSnapshot snap = new PlantSnapshot();
        BeanUtils.copyProperties(latest, snap);
        return snap;
    }

    private DeviceLatest fromSnapshot(PlantSnapshot snap) {
        DeviceLatest created = new DeviceLatest();
        created.setDeviceKey(DEVICE_KEY_PLANT);
        created.setSource(snap.getSource());
        created.setTopic(snap.getTopic());
        created.setAgvTemperature(snap.getAgvTemperature());
        created.setAgvHumidity(snap.getAgvHumidity());
        created.setAgvFlame(snap.getAgvFlame());
        created.setAgvOnline(snap.getAgvOnline());
        created.setAgvDistFront(snap.getAgvDistFront());
        created.setAgvDistBack(snap.getAgvDistBack());
        created.setAgvDistLeft(snap.getAgvDistLeft());
        created.setAgvDistRight(snap.getAgvDistRight());
        created.setAgvSmoke(snap.getAgvSmoke());
        created.setAgvGasAdc(snap.getAgvGasAdc());
        created.setGatewayOnline(snap.getGatewayOnline());
        created.setGasTemperature(snap.getGasTemperature());
        created.setGasHumidity(snap.getGasHumidity());
        created.setGasAdc(snap.getGasAdc());
        created.setGasVoltage(snap.getGasVoltage());
        created.setAlarm(snap.getAlarm());
        created.setFlameAlarm(snap.getFlameAlarm());
        created.setDark(snap.getDark());
        created.setLightLux(snap.getLightLux());
        created.setPir(snap.getPir());
        created.setSmoke(snap.getSmoke());
        created.setCargoCount(snap.getCargoCount());
        created.setRawJson(snap.getRawJson());
        created.setSnapshotId(snap.getId());
        return created;
    }

    public Page<PlantSnapshot> history(LocalDateTime from, LocalDateTime to, long page, long size) {
        return history(from, to, page, size, null);
    }

    public Page<PlantSnapshot> history(LocalDateTime from, LocalDateTime to, long page, long size, String keyword) {
        LambdaQueryWrapper<PlantSnapshot> qw = new LambdaQueryWrapper<PlantSnapshot>()
                .orderByDesc(PlantSnapshot::getCreatedAt);
        // 列表不带 raw_json：单条 MQTT 原文很大，500 条会把接口拖死
        qw.select(PlantSnapshot.class, info -> !"raw_json".equals(info.getColumn()));
        if (from != null) {
            qw.ge(PlantSnapshot::getCreatedAt, from);
        }
        if (to != null) {
            qw.le(PlantSnapshot::getCreatedAt, to);
        }
        if (keyword != null && !keyword.isBlank()) {
            String kw = keyword.trim();
            // 不用 LIKE raw_json（全表扫大字段极慢），只搜结构化列
            qw.and(w -> w.like(PlantSnapshot::getSource, kw)
                    .or().like(PlantSnapshot::getTopic, kw)
                    .or().apply("CAST(gas_adc AS CHAR) LIKE CONCAT('%',{0},'%')", kw)
                    .or().apply("CAST(cargo_count AS CHAR) LIKE CONCAT('%',{0},'%')", kw)
                    .or().apply("CAST(gas_temperature AS CHAR) LIKE CONCAT('%',{0},'%')", kw)
                    .or().apply("CAST(agv_dist_front AS CHAR) LIKE CONCAT('%',{0},'%')", kw)
                    .or().apply("DATE_FORMAT(created_at,'%Y-%m-%d %H:%i:%s') LIKE CONCAT('%',{0},'%')", kw));
        }
        long safeSize = Math.max(1, Math.min(size, 500));
        long safePage = Math.max(1, page);
        return plantSnapshotMapper.selectPage(new Page<>(safePage, safeSize), qw);
    }

    private String toJsonQuiet(PlantPayload payload) {
        try {
            return objectMapper.writeValueAsString(payload);
        } catch (Exception e) {
            return null;
        }
    }
}
