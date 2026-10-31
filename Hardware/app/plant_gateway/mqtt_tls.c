#include "mqtt_tls.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "mbedtls/ssl.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/certs.h"
#include "mbedtls/error.h"

/* 全局 TLS 上下文（Hi3861 内存有限，只用一个连接） */
static MqttTlsContext g_tlsCtx;

/*
 * 无论成功/失败都释放 mbedtls 资源。
 * 旧逻辑：Connect 中途失败时 initialized=0，Disconnect 不释放 → 反复重连把堆耗尽。
 */
static void TlsFreeAll(void)
{
    if (g_tlsCtx.initialized) {
        (void)mbedtls_ssl_close_notify(&g_tlsCtx.ssl);
    }
    mbedtls_net_free(&g_tlsCtx.net_ctx);
    mbedtls_ssl_free(&g_tlsCtx.ssl);
    mbedtls_ssl_config_free(&g_tlsCtx.conf);
    mbedtls_x509_crt_free(&g_tlsCtx.cacert);
    mbedtls_ctr_drbg_free(&g_tlsCtx.ctr_drbg);
    mbedtls_entropy_free(&g_tlsCtx.entropy);
    memset(&g_tlsCtx, 0, sizeof(g_tlsCtx));
}

static int tls_read(Network *n, unsigned char *buf, int len, int timeout_ms)
{
    (void)n;
    if (!g_tlsCtx.initialized) {
        return -1;
    }

    int total_waited = 0;
    int ret;
    while (total_waited < timeout_ms) {
        ret = mbedtls_ssl_read(&g_tlsCtx.ssl, buf, len);
        if (ret >= 0) {
            return ret;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ ||
            ret == MBEDTLS_ERR_SSL_WANT_WRITE ||
            ret == MBEDTLS_ERR_NET_RECV_FAILED ||
            ret == MBEDTLS_ERR_NET_CONN_RESET) {
            usleep(20000);
            total_waited += 20;
            continue;
        }
        printf("[MQTT-TLS] read 致命错误: -0x%04x\r\n", (unsigned int)(-ret));
        return -1;
    }
    return 0;
}

static int tls_write(Network *n, unsigned char *buf, int len, int timeout_ms)
{
    (void)n;
    (void)timeout_ms;
    if (!g_tlsCtx.initialized) {
        return -1;
    }

    int total_waited = 0;
    int max_wait = 3000;
    int ret;
    while (total_waited < max_wait) {
        ret = mbedtls_ssl_write(&g_tlsCtx.ssl, buf, len);
        if (ret >= 0) {
            return ret;
        }
        if (ret == MBEDTLS_ERR_SSL_WANT_READ ||
            ret == MBEDTLS_ERR_SSL_WANT_WRITE ||
            ret == MBEDTLS_ERR_NET_SEND_FAILED ||
            ret == MBEDTLS_ERR_NET_CONN_RESET) {
            usleep(20000);
            total_waited += 20;
            continue;
        }
        printf("[MQTT-TLS] write 致命错误: -0x%04x\r\n", (unsigned int)(-ret));
        return -1;
    }
    printf("[MQTT-TLS] write 超时，连接可能已断开\r\n");
    return -1;
}

int MqttTlsConnect(Network *n, const char *host, int port)
{
    int ret;
    char port_str[8];
    snprintf(port_str, sizeof(port_str), "%d", port);

    /* 先清掉上次残留（含失败半初始化） */
    TlsFreeAll();

    printf("[MQTT-TLS] 初始化 TLS...\r\n");

    mbedtls_net_init(&g_tlsCtx.net_ctx);
    mbedtls_ssl_init(&g_tlsCtx.ssl);
    mbedtls_ssl_config_init(&g_tlsCtx.conf);
    mbedtls_x509_crt_init(&g_tlsCtx.cacert);
    mbedtls_ctr_drbg_init(&g_tlsCtx.ctr_drbg);
    mbedtls_entropy_init(&g_tlsCtx.entropy);

    ret = mbedtls_ctr_drbg_seed(&g_tlsCtx.ctr_drbg,
                                 mbedtls_entropy_func,
                                 &g_tlsCtx.entropy,
                                 NULL, 0);
    if (ret != 0) {
        printf("[MQTT-TLS] RNG 初始化失败: -0x%04x\r\n", (unsigned int)(-ret));
        goto fail;
    }

    ret = mbedtls_ssl_config_defaults(&g_tlsCtx.conf,
                                       MBEDTLS_SSL_IS_CLIENT,
                                       MBEDTLS_SSL_TRANSPORT_STREAM,
                                       MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        printf("[MQTT-TLS] SSL 配置失败: -0x%04x\r\n", (unsigned int)(-ret));
        goto fail;
    }

    mbedtls_ssl_conf_rng(&g_tlsCtx.conf, mbedtls_ctr_drbg_random, &g_tlsCtx.ctr_drbg);
    mbedtls_ssl_conf_authmode(&g_tlsCtx.conf, MBEDTLS_SSL_VERIFY_NONE);

    ret = mbedtls_ssl_setup(&g_tlsCtx.ssl, &g_tlsCtx.conf);
    if (ret != 0) {
        printf("[MQTT-TLS] SSL setup 失败: -0x%04x\r\n", (unsigned int)(-ret));
        goto fail;
    }

    ret = mbedtls_ssl_set_hostname(&g_tlsCtx.ssl, host);
    if (ret != 0) {
        printf("[MQTT-TLS] SNI 设置失败: -0x%04x\r\n", (unsigned int)(-ret));
        goto fail;
    }
    printf("[MQTT-TLS] SNI 已设置: %s\r\n", host);

    printf("[MQTT-TLS] 连接 %s:%s ...\r\n", host, port_str);
    ret = mbedtls_net_connect(&g_tlsCtx.net_ctx, host, port_str, MBEDTLS_NET_PROTO_TCP);
    if (ret != 0) {
        printf("[MQTT-TLS] TCP 连接失败: -0x%04x\r\n", (unsigned int)(-ret));
        goto fail;
    }
    printf("[MQTT-TLS] TCP 连接成功\r\n");

    mbedtls_ssl_set_bio(&g_tlsCtx.ssl, &g_tlsCtx.net_ctx,
                         mbedtls_net_send, mbedtls_net_recv, NULL);

    printf("[MQTT-TLS] TLS 握手中...\r\n");
    while ((ret = mbedtls_ssl_handshake(&g_tlsCtx.ssl)) != 0) {
        if (ret != MBEDTLS_ERR_SSL_WANT_READ &&
            ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            printf("[MQTT-TLS] TLS 握手失败: -0x%04x\r\n", (unsigned int)(-ret));
            goto fail;
        }
    }
    printf("[MQTT-TLS] TLS 握手成功\r\n");

    mbedtls_net_set_nonblock(&g_tlsCtx.net_ctx);
    printf("[MQTT-TLS] socket 已设为非阻塞模式\r\n");

    n->my_socket = g_tlsCtx.net_ctx.fd;
    n->mqttread = tls_read;
    n->mqttwrite = tls_write;

    g_tlsCtx.initialized = 1;
    return 0;

fail:
    TlsFreeAll();
    return -1;
}

void MqttTlsDisconnect(Network *n)
{
    (void)n;
    if (g_tlsCtx.initialized) {
        printf("[MQTT-TLS] 连接已断开\r\n");
    }
    TlsFreeAll();
}
