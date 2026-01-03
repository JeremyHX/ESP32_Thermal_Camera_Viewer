/*****************************************************************************
 * @file     Drv_CombustionBle.c
 * @version  1.0
 * @brief    Combustion-compatible BLE temperature broadcasting
 * @date     2 Jan 2025
 ******************************************************************************/
#include "Drv_CombustionBle.h"
#include "esp_log.h"
#include "esp_bt.h"
#include "esp_gap_ble_api.h"
#include "esp_gatts_api.h"
#include "esp_bt_main.h"
#include "esp_gatt_common_api.h"
#include "esp_mac.h"
#include <string.h>
#include <math.h>

// GATT database indices
enum {
    COMBUSTION_IDX_SVC,
    COMBUSTION_IDX_CHAR_DECL,
    COMBUSTION_IDX_CHAR_VAL,
    COMBUSTION_IDX_CHAR_CCCD,
    COMBUSTION_IDX_NB,
};

// Client connection state
typedef struct {
    uint16_t conn_id;
    bool active;
    bool notifications_enabled;
    esp_bd_addr_t remote_bda;
} combustion_client_t;

// Driver state
typedef struct {
    // GATT handles
    esp_gatt_if_t gatts_if;
    uint16_t service_handle;
    uint16_t char_handle;
    uint16_t cccd_handle;

    // Connection management
    combustion_client_t clients[COMBUSTION_MAX_CONNECTIONS];
    uint8_t connected_count;

    // Temperature data (in millikelvin)
    uint16_t temps[COMBUSTION_NUM_TEMPS];

    // Device identity
    uint32_t serial_number;

    // State flags
    bool initialized;
    bool advertising;
} combustion_state_t;

static combustion_state_t mState = {0};

// GATT attribute table
static const uint16_t primary_service_uuid = ESP_GATT_UUID_PRI_SERVICE;
static const uint16_t char_decl_uuid = ESP_GATT_UUID_CHAR_DECLARE;
static const uint16_t char_cccd_uuid = ESP_GATT_UUID_CHAR_CLIENT_CONFIG;
static const uint8_t char_prop_read_notify = ESP_GATT_CHAR_PROP_BIT_READ | ESP_GATT_CHAR_PROP_BIT_NOTIFY;

static const uint8_t combustion_service_uuid128[16] = COMBUSTION_SERVICE_UUID_128;
static const uint8_t combustion_char_uuid128[16] = COMBUSTION_CHAR_UUID_128;

// Probe status value buffer (20 bytes as per Combustion spec)
static uint8_t probe_status_value[20] = {0};
static uint16_t cccd_value = 0x0000;

// GATT database
static const esp_gatts_attr_db_t combustion_gatt_db[COMBUSTION_IDX_NB] = {
    // Service Declaration
    [COMBUSTION_IDX_SVC] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&primary_service_uuid,
            ESP_GATT_PERM_READ,
            sizeof(combustion_service_uuid128),
            sizeof(combustion_service_uuid128),
            (uint8_t *)combustion_service_uuid128
        }
    },
    // Characteristic Declaration
    [COMBUSTION_IDX_CHAR_DECL] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&char_decl_uuid,
            ESP_GATT_PERM_READ,
            1,
            1,
            (uint8_t *)&char_prop_read_notify
        }
    },
    // Characteristic Value
    [COMBUSTION_IDX_CHAR_VAL] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_128,
            (uint8_t *)combustion_char_uuid128,
            ESP_GATT_PERM_READ,
            sizeof(probe_status_value),
            sizeof(probe_status_value),
            probe_status_value
        }
    },
    // Client Characteristic Configuration Descriptor (CCCD)
    [COMBUSTION_IDX_CHAR_CCCD] = {
        {ESP_GATT_AUTO_RSP},
        {
            ESP_UUID_LEN_16,
            (uint8_t *)&char_cccd_uuid,
            ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE,
            sizeof(uint16_t),
            sizeof(cccd_value),
            (uint8_t *)&cccd_value
        }
    },
};

// Advertising data with manufacturer specific data
static uint8_t adv_manufacturer_data[24] = {0};

static esp_ble_adv_data_t adv_data = {
    .set_scan_rsp = false,
    .include_name = false,
    .include_txpower = false,
    .min_interval = 0x0006,
    .max_interval = 0x0010,
    .appearance = 0x00,
    .manufacturer_len = sizeof(adv_manufacturer_data),
    .p_manufacturer_data = adv_manufacturer_data,
    .service_data_len = 0,
    .p_service_data = NULL,
    .service_uuid_len = 0,
    .p_service_uuid = NULL,
    .flag = (ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT),
};

static esp_ble_adv_params_t adv_params = {
    .adv_int_min = COMBUSTION_ADV_INTERVAL_NORMAL,
    .adv_int_max = COMBUSTION_ADV_INTERVAL_NORMAL,
    .adv_type = ADV_TYPE_IND,  // Connectable
    .own_addr_type = BLE_ADDR_TYPE_PUBLIC,
    .channel_map = ADV_CHNL_ALL,
    .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
};

// Forward declarations
static void combustionBle_GattsEventHandler(esp_gatts_cb_event_t event,
                                             esp_gatt_if_t gatts_if,
                                             esp_ble_gatts_cb_param_t *param);
static void combustionBle_GapEventHandler(esp_gap_ble_cb_event_t event,
                                          esp_ble_gap_cb_param_t *param);
static uint16_t combustionBle_EncodeTemp(uint16_t temp_mk);
static void combustionBle_PackTemps(const uint16_t encoded_temps[8], uint8_t output[13]);
static void combustionBle_UpdateAdvData(void);
static void combustionBle_StartAdvertising(void);
static void combustionBle_SendNotifications(void);

/*****************************************************************************
 * @brief  Encode millikelvin temperature to Combustion 13-bit format
 *****************************************************************************/
static uint16_t combustionBle_EncodeTemp(uint16_t temp_mk)
{
    // Convert millikelvin to Celsius: (temp_mk / 1000.0) - 273.15
    float celsius = (temp_mk / 1000.0f) - 273.15f;

    // Apply Combustion encoding: (celsius + 20.0) / 0.05
    float raw_float = (celsius + COMBUSTION_TEMP_OFFSET_C) / COMBUSTION_TEMP_SCALE_C;

    // Clamp to valid range
    if (raw_float < 0) raw_float = 0;
    if (raw_float > COMBUSTION_TEMP_MAX_RAW) raw_float = COMBUSTION_TEMP_MAX_RAW;

    return (uint16_t)raw_float & COMBUSTION_TEMP_MAX_RAW;
}

/*****************************************************************************
 * @brief  Pack 8 encoded temperatures (13-bit each) into 13 bytes
 *****************************************************************************/
static void combustionBle_PackTemps(const uint16_t encoded_temps[8], uint8_t output[13])
{
    // Pack 8 x 13-bit values (104 bits) into 13 bytes
    // Bit layout:
    // Byte 0:  T1[12:5]
    // Byte 1:  T1[4:0] | T2[12:10]
    // Byte 2:  T2[9:2]
    // Byte 3:  T2[1:0] | T3[12:7]
    // ... etc

    memset(output, 0, 13);

    int bit_pos = 0;
    for (int i = 0; i < 8; i++) {
        uint16_t val = encoded_temps[i];

        // Write 13 bits starting at bit_pos
        for (int b = 12; b >= 0; b--) {
            int byte_idx = bit_pos / 8;
            int bit_in_byte = 7 - (bit_pos % 8);

            if (val & (1 << b)) {
                output[byte_idx] |= (1 << bit_in_byte);
            }
            bit_pos++;
        }
    }
}

/*****************************************************************************
 * @brief  Update advertising data with current temperatures
 *****************************************************************************/
static void combustionBle_UpdateAdvData(void)
{
    // Encode temperatures
    uint16_t encoded[8];
    for (int i = 0; i < 8; i++) {
        encoded[i] = combustionBle_EncodeTemp(mState.temps[i]);
    }

    // Pack into manufacturer data
    // Offset 0-1: Vendor ID (little endian)
    adv_manufacturer_data[0] = COMBUSTION_VENDOR_ID & 0xFF;
    adv_manufacturer_data[1] = (COMBUSTION_VENDOR_ID >> 8) & 0xFF;

    // Offset 2: Product Type
    adv_manufacturer_data[2] = COMBUSTION_PRODUCT_TYPE_THERMOHOOD;

    // Offset 3-6: Serial Number (4 bytes from MAC)
    adv_manufacturer_data[3] = (mState.serial_number >> 0) & 0xFF;
    adv_manufacturer_data[4] = (mState.serial_number >> 8) & 0xFF;
    adv_manufacturer_data[5] = (mState.serial_number >> 16) & 0xFF;
    adv_manufacturer_data[6] = (mState.serial_number >> 24) & 0xFF;

    // Offset 7-19: Raw temperature data (13 bytes)
    combustionBle_PackTemps(encoded, &adv_manufacturer_data[7]);

    // Offset 20: Mode/ID
    adv_manufacturer_data[20] = 0x00;  // Normal mode

    // Offset 21: Battery/Virtual sensors
    adv_manufacturer_data[21] = 0xFF;  // Full battery, no virtual sensors

    // Offset 22: Network info
    adv_manufacturer_data[22] = 0x00;

    // Offset 23: Overheating sensors
    adv_manufacturer_data[23] = 0x00;  // No overheating

    // Update advertising data if we're advertising
    if (mState.advertising) {
        esp_ble_gap_config_adv_data(&adv_data);
    }
}

/*****************************************************************************
 * @brief  Start or restart BLE advertising
 *****************************************************************************/
static void combustionBle_StartAdvertising(void)
{
    // Determine advertising type based on connection count
    if (mState.connected_count >= COMBUSTION_MAX_CONNECTIONS) {
        // At max connections, stop advertising
        if (mState.advertising) {
            esp_ble_gap_stop_advertising();
            mState.advertising = false;
            ESP_LOGI(COMBUSTION_TAG, "Max connections reached, stopped advertising");
        }
        return;
    }

    // Connectable advertising
    adv_params.adv_type = ADV_TYPE_IND;

    // Configure and start
    esp_ble_gap_config_adv_data(&adv_data);
}

/*****************************************************************************
 * @brief  Send notifications to all connected clients with notifications enabled
 *****************************************************************************/
static void combustionBle_SendNotifications(void)
{
    if (mState.gatts_if == ESP_GATT_IF_NONE || mState.char_handle == 0) {
        return;
    }

    // Build probe status packet (simplified - just temps for now)
    // Real Combustion probe status is more complex, but temps in advertising
    // is the primary data path

    for (int i = 0; i < COMBUSTION_MAX_CONNECTIONS; i++) {
        if (mState.clients[i].active && mState.clients[i].notifications_enabled) {
            esp_ble_gatts_send_indicate(
                mState.gatts_if,
                mState.clients[i].conn_id,
                mState.char_handle,
                sizeof(probe_status_value),
                probe_status_value,
                false  // false = notification, true = indication
            );
        }
    }
}

/*****************************************************************************
 * @brief  Find free client slot
 *****************************************************************************/
static int combustionBle_FindFreeClientSlot(void)
{
    for (int i = 0; i < COMBUSTION_MAX_CONNECTIONS; i++) {
        if (!mState.clients[i].active) {
            return i;
        }
    }
    return -1;
}

/*****************************************************************************
 * @brief  Find client by connection ID
 *****************************************************************************/
static int combustionBle_FindClientByConnId(uint16_t conn_id)
{
    for (int i = 0; i < COMBUSTION_MAX_CONNECTIONS; i++) {
        if (mState.clients[i].active && mState.clients[i].conn_id == conn_id) {
            return i;
        }
    }
    return -1;
}

/*****************************************************************************
 * @brief  GAP event handler for advertising management
 *****************************************************************************/
static void combustionBle_GapEventHandler(esp_gap_ble_cb_event_t event,
                                          esp_ble_gap_cb_param_t *param)
{
    switch (event) {
        case ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT:
            ESP_LOGD(COMBUSTION_TAG, "Advertising data set complete");
            esp_ble_gap_start_advertising(&adv_params);
            break;

        case ESP_GAP_BLE_ADV_START_COMPLETE_EVT:
            if (param->adv_start_cmpl.status == ESP_BT_STATUS_SUCCESS) {
                mState.advertising = true;
                ESP_LOGI(COMBUSTION_TAG, "Advertising started");
            } else {
                ESP_LOGE(COMBUSTION_TAG, "Advertising start failed: %d",
                         param->adv_start_cmpl.status);
            }
            break;

        case ESP_GAP_BLE_ADV_STOP_COMPLETE_EVT:
            mState.advertising = false;
            ESP_LOGI(COMBUSTION_TAG, "Advertising stopped");
            break;

        default:
            break;
    }
}

/*****************************************************************************
 * @brief  GATT Server event handler
 *****************************************************************************/
static void combustionBle_GattsEventHandler(esp_gatts_cb_event_t event,
                                             esp_gatt_if_t gatts_if,
                                             esp_ble_gatts_cb_param_t *param)
{
    switch (event) {
        case ESP_GATTS_REG_EVT:
            if (param->reg.status == ESP_GATT_OK) {
                mState.gatts_if = gatts_if;
                ESP_LOGI(COMBUSTION_TAG, "GATT app registered, app_id %d", param->reg.app_id);

                // Create attribute table
                esp_ble_gatts_create_attr_tab(combustion_gatt_db, gatts_if,
                                               COMBUSTION_IDX_NB, 0);
            } else {
                ESP_LOGE(COMBUSTION_TAG, "GATT app register failed: %d", param->reg.status);
            }
            break;

        case ESP_GATTS_CREAT_ATTR_TAB_EVT:
            if (param->add_attr_tab.status == ESP_GATT_OK) {
                if (param->add_attr_tab.num_handle == COMBUSTION_IDX_NB) {
                    mState.service_handle = param->add_attr_tab.handles[COMBUSTION_IDX_SVC];
                    mState.char_handle = param->add_attr_tab.handles[COMBUSTION_IDX_CHAR_VAL];
                    mState.cccd_handle = param->add_attr_tab.handles[COMBUSTION_IDX_CHAR_CCCD];

                    ESP_LOGI(COMBUSTION_TAG, "Attribute table created, handles: svc=%d char=%d cccd=%d",
                             mState.service_handle, mState.char_handle, mState.cccd_handle);

                    // Start the service
                    esp_ble_gatts_start_service(mState.service_handle);
                }
            } else {
                ESP_LOGE(COMBUSTION_TAG, "Create attr table failed: %d", param->add_attr_tab.status);
            }
            break;

        case ESP_GATTS_START_EVT:
            if (param->start.status == ESP_GATT_OK) {
                ESP_LOGI(COMBUSTION_TAG, "Service started");
                mState.initialized = true;

                // Start advertising
                combustionBle_StartAdvertising();
            }
            break;

        case ESP_GATTS_CONNECT_EVT: {
            int slot = combustionBle_FindFreeClientSlot();
            if (slot >= 0) {
                mState.clients[slot].active = true;
                mState.clients[slot].conn_id = param->connect.conn_id;
                mState.clients[slot].notifications_enabled = false;
                memcpy(mState.clients[slot].remote_bda, param->connect.remote_bda,
                       sizeof(esp_bd_addr_t));
                mState.connected_count++;

                ESP_LOGI(COMBUSTION_TAG, "Client connected, conn_id=%d, slot=%d, total=%d",
                         param->connect.conn_id, slot, mState.connected_count);

                // Update connection parameters for better latency
                esp_ble_conn_update_params_t conn_params = {0};
                memcpy(conn_params.bda, param->connect.remote_bda, sizeof(esp_bd_addr_t));
                conn_params.latency = 0;
                conn_params.max_int = 0x50;  // 100ms
                conn_params.min_int = 0x30;  // 60ms
                conn_params.timeout = 400;   // 4s
                esp_ble_gap_update_conn_params(&conn_params);

                // Restart advertising if we have room for more clients
                combustionBle_StartAdvertising();
            }
            break;
        }

        case ESP_GATTS_DISCONNECT_EVT: {
            int slot = combustionBle_FindClientByConnId(param->disconnect.conn_id);
            if (slot >= 0) {
                mState.clients[slot].active = false;
                mState.clients[slot].notifications_enabled = false;
                mState.connected_count--;

                ESP_LOGI(COMBUSTION_TAG, "Client disconnected, conn_id=%d, remaining=%d",
                         param->disconnect.conn_id, mState.connected_count);
            }

            // Restart advertising
            combustionBle_StartAdvertising();
            break;
        }

        case ESP_GATTS_WRITE_EVT:
            // Handle CCCD writes for notification enable/disable
            if (param->write.handle == mState.cccd_handle) {
                int slot = combustionBle_FindClientByConnId(param->write.conn_id);
                if (slot >= 0 && param->write.len == 2) {
                    uint16_t cccd_val = param->write.value[0] | (param->write.value[1] << 8);
                    mState.clients[slot].notifications_enabled = (cccd_val & 0x0001) != 0;
                    ESP_LOGI(COMBUSTION_TAG, "Client %d notifications %s",
                             slot, mState.clients[slot].notifications_enabled ? "enabled" : "disabled");
                }
            }
            break;

        case ESP_GATTS_READ_EVT:
            ESP_LOGD(COMBUSTION_TAG, "Read request, handle=%d", param->read.handle);
            break;

        default:
            break;
    }
}

/*****************************************************************************
 * @brief  Initialize Combustion BLE broadcasting
 *****************************************************************************/
esp_err_t combustionBle_Init(void)
{
    ESP_LOGI(COMBUSTION_TAG, "Initializing Combustion BLE...");

    // Get MAC address for serial number
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_BT);
    mState.serial_number = (mac[2] << 24) | (mac[3] << 16) | (mac[4] << 8) | mac[5];
    ESP_LOGI(COMBUSTION_TAG, "Serial number: 0x%08lX", (unsigned long)mState.serial_number);

    // Initialize state
    memset(mState.clients, 0, sizeof(mState.clients));
    mState.connected_count = 0;
    mState.initialized = false;
    mState.advertising = false;
    mState.gatts_if = ESP_GATT_IF_NONE;

    // Initialize temperatures to 0 (will be updated on first frame)
    for (int i = 0; i < COMBUSTION_NUM_TEMPS; i++) {
        mState.temps[i] = 0;
    }

    // Update advertising data with initial values
    combustionBle_UpdateAdvData();

    // Register GAP callback (note: may conflict with BluFi's GAP handler)
    // We handle this by checking event types we care about
    esp_err_t ret = esp_ble_gap_register_callback(combustionBle_GapEventHandler);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(COMBUSTION_TAG, "GAP callback register failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // Register GATT server callback
    ret = esp_ble_gatts_register_callback(combustionBle_GattsEventHandler);
    if (ret != ESP_OK && ret != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(COMBUSTION_TAG, "GATTS callback register failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // Register GATT application
    ret = esp_ble_gatts_app_register(COMBUSTION_GATTS_APP_ID);
    if (ret != ESP_OK) {
        ESP_LOGE(COMBUSTION_TAG, "GATTS app register failed: %s", esp_err_to_name(ret));
        return ret;
    }

    // Set MTU
    esp_ble_gatt_set_local_mtu(500);

    ESP_LOGI(COMBUSTION_TAG, "Initialization started (async completion via callbacks)");
    return ESP_OK;
}

/*****************************************************************************
 * @brief  Update temperatures for BLE broadcast
 *****************************************************************************/
void combustionBle_UpdateTemps(const uint16_t temps[8])
{
    if (!mState.initialized) {
        return;
    }

    // Copy new temperature values
    memcpy(mState.temps, temps, sizeof(mState.temps));

    // Update advertising data
    combustionBle_UpdateAdvData();

    // Send notifications to connected clients
    combustionBle_SendNotifications();
}

/*****************************************************************************
 * @brief  Check if Combustion BLE is initialized
 *****************************************************************************/
bool combustionBle_IsInitialized(void)
{
    return mState.initialized;
}

/*****************************************************************************
 * @brief  Get number of connected BLE clients
 *****************************************************************************/
uint8_t combustionBle_GetConnectionCount(void)
{
    return mState.connected_count;
}
