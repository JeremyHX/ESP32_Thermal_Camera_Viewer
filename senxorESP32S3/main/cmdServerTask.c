/*****************************************************************************
 * @file     cmdServerTask.c
 * @version  1.0
 * @brief    Command server for handling WREG/RREG/RRSE commands on separate port
 * @date     31 Dec 2024
 *****************************************************************************/
#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <sys/param.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_system.h>
#include <esp_log.h>

#include <lwip/err.h>
#include <lwip/sockets.h>
#include <lwip/sys.h>
#include <lwip/netdb.h>

#include "cmdServerTask.h"
#include "cmdParser.h"

#define CMDTAG "[CMD_SERVER]"

// Buffers
static uint8_t mRxBuff[128];
static uint8_t mAckBuff[64];
static cmdPhaser mCmdPhaserObj;

// Socket file descriptors
static int cmd_server_sock = -1;
static int cmd_client_sock = -1;

// Flags
static volatile bool isClientConnected = false;
static volatile uint8_t pollFreqHz = 0;  // Poll frequency in Hz (0 = stopped)

// TCP keepalive settings
static int keepAlive = 1;
static int keepIdle = 5;
static int keepInterval = 5;
static int keepCount = 3;

/******************************************************************************
 * @brief       cmdServerGetIsClientConnected
 * @return      true if command client is connected
 *****************************************************************************/
bool cmdServerGetIsClientConnected(void)
{
    return isClientConnected;
}

/******************************************************************************
 * @brief       cmdServerGetPollFreqHz
 * @return      Current poll frequency in Hz (0 = stopped)
 *****************************************************************************/
uint8_t cmdServerGetPollFreqHz(void)
{
    return pollFreqHz;
}

/******************************************************************************
 * @brief       cmdServerSetPollFreqHz
 * @param       freqHz - Poll frequency in Hz (0 = stop, capped at 25)
 *****************************************************************************/
void cmdServerSetPollFreqHz(uint8_t freqHz)
{
    if (freqHz > POLL_MAX_FREQ_HZ) {
        freqHz = POLL_MAX_FREQ_HZ;
    }
    pollFreqHz = freqHz;
    ESP_LOGI(CMDTAG, "Poll frequency set to %d Hz", pollFreqHz);
}

/******************************************************************************
 * @brief       cmdServerStart
 * @details     Initialize and bind the command server socket
 *****************************************************************************/
static void cmdServerStart(void)
{
    struct sockaddr_in dest_addr;
    dest_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    dest_addr.sin_family = AF_INET;
    dest_addr.sin_port = htons(CMD_SERVER_PORT);

    cmd_server_sock = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
    if (cmd_server_sock < 0) {
        ESP_LOGE(CMDTAG, "Failed to create socket: errno %d", errno);
        return;
    }

    int opt = 1;
    setsockopt(cmd_server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    if (bind(cmd_server_sock, (struct sockaddr *)&dest_addr, sizeof(dest_addr)) != 0) {
        ESP_LOGE(CMDTAG, "Socket bind failed: errno %d", errno);
        close(cmd_server_sock);
        cmd_server_sock = -1;
        return;
    }

    ESP_LOGI(CMDTAG, "Command server bound to port %d", CMD_SERVER_PORT);
}

/******************************************************************************
 * @brief       cmdServerAccept
 * @details     Wait for a client to connect
 *****************************************************************************/
static void cmdServerAccept(void)
{
    if (cmd_server_sock < 0) {
        ESP_LOGE(CMDTAG, "Server socket not initialized");
        return;
    }

    if (listen(cmd_server_sock, 1) != 0) {
        ESP_LOGE(CMDTAG, "Listen failed: errno %d", errno);
        return;
    }

    ESP_LOGI(CMDTAG, "Waiting for command client on port %d...", CMD_SERVER_PORT);

    struct sockaddr_storage source_addr;
    socklen_t addr_len = sizeof(source_addr);

    // Close existing client connection if any
    if (cmd_client_sock >= 0) {
        close(cmd_client_sock);
        cmd_client_sock = -1;
    }

    cmd_client_sock = accept(cmd_server_sock, (struct sockaddr *)&source_addr, &addr_len);

    if (cmd_client_sock >= 0) {
        isClientConnected = true;

        // Set TCP keepalive
        setsockopt(cmd_client_sock, SOL_SOCKET, SO_KEEPALIVE, &keepAlive, sizeof(int));
        setsockopt(cmd_client_sock, IPPROTO_TCP, TCP_KEEPIDLE, &keepIdle, sizeof(int));
        setsockopt(cmd_client_sock, IPPROTO_TCP, TCP_KEEPINTVL, &keepInterval, sizeof(int));
        setsockopt(cmd_client_sock, IPPROTO_TCP, TCP_KEEPCNT, &keepCount, sizeof(int));

        char addr_str[32];
        if (source_addr.ss_family == PF_INET) {
            inet_ntoa_r(((struct sockaddr_in *)&source_addr)->sin_addr, addr_str, sizeof(addr_str) - 1);
        }
        ESP_LOGI(CMDTAG, "Command client connected from %s", addr_str);
    } else {
        ESP_LOGE(CMDTAG, "Accept failed: errno %d", errno);
        isClientConnected = false;
    }
}

/******************************************************************************
 * @brief       cmdServerSend
 * @details     Send response to command client
 *****************************************************************************/
static int cmdServerSend(const uint8_t* data, size_t len)
{
    if (!isClientConnected || cmd_client_sock < 0) {
        return -1;
    }

    int err = write(cmd_client_sock, data, len);
    if (err < 0) {
        ESP_LOGE(CMDTAG, "Send failed: errno %d", errno);
        isClientConnected = false;
        pollFreqHz = 0;  // Reset poll frequency on disconnect
    }
    return err;
}

/******************************************************************************
 * @brief       cmdServerReceive
 * @details     Receive and process commands from client
 *****************************************************************************/
static int cmdServerReceive(void)
{
    if (!isClientConnected || cmd_client_sock < 0) {
        return -1;
    }

    memset(mRxBuff, 0, sizeof(mRxBuff));

    int len = read(cmd_client_sock, mRxBuff, sizeof(mRxBuff) - 1);

    if (len < 0) {
        ESP_LOGE(CMDTAG, "Receive failed: errno %d", errno);
        isClientConnected = false;
        pollFreqHz = 0;  // Reset poll frequency on disconnect
        return -1;
    } else if (len == 0) {
        ESP_LOGI(CMDTAG, "Command client disconnected");
        isClientConnected = false;
        pollFreqHz = 0;  // Reset poll frequency on disconnect
        return -1;
    }

    ESP_LOGI(CMDTAG, "Received command: %s", mRxBuff);

    // Parse and execute command
    cmdParser_PharseCmd(&mCmdPhaserObj, mRxBuff, len);
    uint16_t ackSize = cmdParser_CommitCmd(&mCmdPhaserObj, mAckBuff);

    if (ackSize > 0) {
        cmdServerSend(mAckBuff, ackSize);
    }

    cmdParser_Init(&mCmdPhaserObj);

    return len;
}

/******************************************************************************
 * @brief       cmdServerTask
 * @details     Main command server task
 *****************************************************************************/
void cmdServerTask(void *pvParameters)
{
    ESP_LOGI(CMDTAG, "Starting command server task...");

    cmdParser_Init(&mCmdPhaserObj);
    cmdServerStart();

    // Initial accept
    cmdServerAccept();

    for (;;) {
        if (!isClientConnected) {
            ESP_LOGI(CMDTAG, "Waiting for command client...");
            cmdServerAccept();
            continue;
        }

        // Receive and process commands
        if (cmdServerReceive() < 0) {
            // Client disconnected, will reconnect in next iteration
            continue;
        }

        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
