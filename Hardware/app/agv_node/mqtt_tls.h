#ifndef MQTT_TLS_H
#define MQTT_TLS_H

#include "MQTTClient.h"
#include "mbedtls/ssl.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/x509_crt.h"

/* TLS 上下文 */
typedef struct {
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_net_context net_ctx;
    mbedtls_x509_crt cacert;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_entropy_context entropy;
    int initialized;
} MqttTlsContext;

/* 初始化 TLS 并连接到 MQTT Broker（替换 NetworkConnect） */
int MqttTlsConnect(Network *n, const char *host, int port);

/* 断开 TLS 连接 */
void MqttTlsDisconnect(Network *n);

#endif /* MQTT_TLS_H */
