package com.smartplant.mqtt;

import com.smartplant.config.SmartPlantProperties;
import com.smartplant.dto.PlantPayload;
import com.smartplant.service.PlantService;
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.eclipse.paho.client.mqttv3.IMqttDeliveryToken;
import org.eclipse.paho.client.mqttv3.MqttCallbackExtended;
import org.eclipse.paho.client.mqttv3.MqttClient;
import org.eclipse.paho.client.mqttv3.MqttConnectOptions;
import org.eclipse.paho.client.mqttv3.MqttException;
import org.eclipse.paho.client.mqttv3.MqttMessage;
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence;
import org.springframework.stereotype.Component;

import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManagerFactory;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.concurrent.atomic.AtomicReference;

/**
 * 统一 MQTT 连接：订阅传感器数据 + 发布控制指令。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class MqttClientManager {

    private final SmartPlantProperties properties;
    private final PayloadParser payloadParser;
    private final PlantService plantService;

    private final AtomicReference<MqttClient> clientRef = new AtomicReference<>();

    @PostConstruct
    public void start() {
        SmartPlantProperties.Mqtt mqtt = properties.getMqtt();
        if (!mqtt.isEnabled()) {
            log.info("MQTT 已禁用");
            return;
        }
        try {
            String brokerUri = "ssl://" + mqtt.getBroker() + ":" + mqtt.getPort();
            MqttClient client = new MqttClient(brokerUri, mqtt.getClientId(), new MemoryPersistence());
            client.setCallback(new MqttCallbackExtended() {
                @Override
                public void connectComplete(boolean reconnect, String serverURI) {
                    log.info("MQTT 已连接 reconnect={} uri={}", reconnect, serverURI);
                    subscribeAll(client);
                }

                @Override
                public void connectionLost(Throwable cause) {
                    log.warn("MQTT 断开: {}", cause == null ? "unknown" : cause.getMessage());
                }

                @Override
                public void messageArrived(String topic, MqttMessage message) {
                    String payload = new String(message.getPayload(), StandardCharsets.UTF_8);
                    // 忽略自身下发的 command topic，避免误入库
                    if (topic.equals(properties.getMqtt().getCommandTopic())) {
                        return;
                    }
                    try {
                        PlantPayload plantPayload = payloadParser.parse(payload);
                        plantService.ingest(plantPayload, "mqtt", topic, payload);
                    } catch (Exception e) {
                        log.error("处理 MQTT 消息失败 topic={} payload={}", topic, payload, e);
                    }
                }

                @Override
                public void deliveryComplete(IMqttDeliveryToken token) {
                    // no-op
                }
            });

            MqttConnectOptions options = new MqttConnectOptions();
            options.setCleanSession(true);
            options.setAutomaticReconnect(true);
            options.setKeepAliveInterval(60);
            options.setConnectionTimeout(30);
            if (mqtt.getUsername() != null) {
                options.setUserName(mqtt.getUsername());
            }
            if (mqtt.getPassword() != null) {
                options.setPassword(mqtt.getPassword().toCharArray());
            }
            options.setSocketFactory(defaultSslSocketFactory());

            log.info("MQTT 连接中... {} clientId={}", brokerUri, mqtt.getClientId());
            client.connect(options);
            clientRef.set(client);
        } catch (Exception e) {
            log.error("MQTT 启动失败，应用将继续运行", e);
        }
    }

    private void subscribeAll(MqttClient client) {
        SmartPlantProperties.Mqtt mqtt = properties.getMqtt();
        for (String topic : mqtt.getTopics()) {
            try {
                client.subscribe(topic, mqtt.getQos());
                log.info("MQTT 已订阅: {}", topic);
            } catch (MqttException e) {
                log.error("订阅失败 topic={}", topic, e);
            }
        }
    }

    public synchronized void publish(String topic, String payload, int qos) throws MqttException {
        MqttClient client = clientRef.get();
        if (client == null || !client.isConnected()) {
            throw new MqttException(MqttException.REASON_CODE_CLIENT_NOT_CONNECTED);
        }
        MqttMessage message = new MqttMessage(payload.getBytes(StandardCharsets.UTF_8));
        message.setQos(qos);
        message.setRetained(false);
        client.publish(topic, message);
        log.info("MQTT 已发布 topic={} payload={}", topic, payload);
    }

    public boolean isConnected() {
        MqttClient client = clientRef.get();
        return client != null && client.isConnected();
    }

    private SSLSocketFactory defaultSslSocketFactory() throws Exception {
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init((KeyStore) null);
        SSLContext context = SSLContext.getInstance("TLS");
        context.init(null, tmf.getTrustManagers(), null);
        return context.getSocketFactory();
    }

    @PreDestroy
    public void stop() {
        MqttClient client = clientRef.getAndSet(null);
        if (client != null && client.isConnected()) {
            try {
                client.disconnect();
                client.close();
                log.info("MQTT 已关闭");
            } catch (MqttException e) {
                log.warn("关闭 MQTT 异常", e);
            }
        }
    }
}
