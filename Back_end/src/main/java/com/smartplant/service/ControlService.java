package com.smartplant.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.smartplant.common.exception.BizException;
import com.smartplant.config.SmartPlantProperties;
import com.smartplant.domain.entity.ControlCommandLog;
import com.smartplant.dto.ControlCommandRequest;
import com.smartplant.dto.ControlCommandResponse;
import com.smartplant.mapper.ControlCommandLogMapper;
import com.smartplant.mqtt.MqttClientManager;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.eclipse.paho.client.mqttv3.MqttException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class ControlService {

    private static final Set<String> ALLOWED_ACTIONS = Set.of(
            "LIGHT_ON", "LIGHT_OFF", "LIGHT_TOGGLE",
            "ALARM_ACK", "ALARM_MUTE", "ALARM_UNMUTE",
            "BUZZER_ON", "BUZZER_OFF",
            "AGV_ESTOP", "AGV_RESUME", "AGV_GOTO",
            "CARGO_RESET",
            "GATEWAY_REBOOT", "GATEWAY_STATUS_QUERY",
            "SENSOR_CALIBRATE", "DATA_SNAPSHOT_FORCE",
            "MAINTENANCE_MODE_ON", "MAINTENANCE_MODE_OFF"
    );

    private final MqttClientManager mqttClientManager;
    private final ControlCommandLogMapper controlCommandLogMapper;
    private final SmartPlantProperties properties;
    private final ObjectMapper objectMapper;

    @Transactional
    public ControlCommandResponse send(ControlCommandRequest request, String operator) {
        String action = request.getAction() == null ? "" : request.getAction().trim().toUpperCase();
        if (!ALLOWED_ACTIONS.contains(action)) {
            throw new BizException("不支持的控制指令: " + request.getAction());
        }

        String requestId = UUID.randomUUID().toString().replace("-", "");
        String topic = properties.getMqtt().getCommandTopic();
        Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("action", action);
        envelope.put("params", request.getParams() == null ? Map.of() : request.getParams());
        envelope.put("requestId", requestId);
        envelope.put("ts", System.currentTimeMillis());
        envelope.put("operator", operator);

        String payloadJson;
        String paramsJson;
        try {
            payloadJson = objectMapper.writeValueAsString(envelope);
            paramsJson = objectMapper.writeValueAsString(envelope.get("params"));
        } catch (Exception e) {
            throw new BizException("指令序列化失败");
        }

        ControlCommandLog logEntity = new ControlCommandLog();
        logEntity.setRequestId(requestId);
        logEntity.setAction(action);
        logEntity.setParamsJson(paramsJson);
        logEntity.setOperator(operator);
        logEntity.setTopic(topic);
        logEntity.setPayloadJson(payloadJson);
        logEntity.setCreatedAt(LocalDateTime.now());

        try {
            if (!mqttClientManager.isConnected()) {
                throw new MqttException(MqttException.REASON_CODE_CLIENT_NOT_CONNECTED);
            }
            mqttClientManager.publish(topic, payloadJson, properties.getMqtt().getQos());
            logEntity.setSuccess(true);
            controlCommandLogMapper.insert(logEntity);
            return ControlCommandResponse.builder()
                    .requestId(requestId)
                    .action(action)
                    .topic(topic)
                    .success(true)
                    .message("指令已下发")
                    .build();
        } catch (MqttException e) {
            logEntity.setSuccess(false);
            logEntity.setErrorMessage(e.getMessage());
            controlCommandLogMapper.insert(logEntity);
            log.error("控制指令发布失败 action={}", action, e);
            throw new BizException("MQTT 发布失败，请检查后端与 EMQX 连接: " + e.getMessage());
        }
    }

    public List<ControlCommandLog> history(int limit) {
        int safe = Math.max(1, Math.min(limit, 200));
        return controlCommandLogMapper.selectList(new LambdaQueryWrapper<ControlCommandLog>()
                .orderByDesc(ControlCommandLog::getCreatedAt)
                .last("LIMIT " + safe));
    }
}
