/*****************************************************************************
 * @file     Drv_CombustionBle.h
 * @version  1.0
 * @brief    Combustion-compatible BLE temperature broadcasting
 * @date     2 Jan 2025
 ******************************************************************************/
#ifndef COMPONENTS_DRIVERS_INCLUDE_DRV_COMBUSTIONBLE_H_
#define COMPONENTS_DRIVERS_INCLUDE_DRV_COMBUSTIONBLE_H_

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"

// Combustion Inc. Vendor ID
#define COMBUSTION_VENDOR_ID                0x09C7

// Product type for Thermohood thermal camera
#define COMBUSTION_PRODUCT_TYPE_THERMOHOOD  0x04

// Maximum simultaneous BLE connections
#define COMBUSTION_MAX_CONNECTIONS          3

// Number of temperature values (8 thermistors)
#define COMBUSTION_NUM_TEMPS                8

// Advertising intervals (in 0.625ms units)
#define COMBUSTION_ADV_INTERVAL_NORMAL      400   // 250ms
#define COMBUSTION_ADV_INTERVAL_FAST        160   // 100ms

// Temperature encoding constants
// Formula: raw = ((celsius + 20.0) / 0.05)
// Range: -20C to +388.95C with 0.05C resolution
#define COMBUSTION_TEMP_OFFSET_C            20.0f
#define COMBUSTION_TEMP_SCALE_C             0.05f
#define COMBUSTION_TEMP_BITS                13
#define COMBUSTION_TEMP_MAX_RAW             0x1FFF  // 13-bit max

// Combustion Service UUID: 00000100-CAAB-3792-3D44-97AE51C1407A
// (128-bit, LSB first for ESP32)
#define COMBUSTION_SERVICE_UUID_128 { \
    0x7A, 0x40, 0xC1, 0x51, 0xAE, 0x97, 0x44, 0x3D, \
    0x92, 0x37, 0xAB, 0xCA, 0x00, 0x01, 0x00, 0x00  \
}

// Probe Status Characteristic UUID: 00000101-CAAB-3792-3D44-97AE51C1407A
#define COMBUSTION_CHAR_UUID_128 { \
    0x7A, 0x40, 0xC1, 0x51, 0xAE, 0x97, 0x44, 0x3D, \
    0x92, 0x37, 0xAB, 0xCA, 0x01, 0x01, 0x00, 0x00  \
}

// GATT Application ID (separate from BluFi's app ID)
#define COMBUSTION_GATTS_APP_ID             1

// Log tag
#define COMBUSTION_TAG                      "[COMBUSTION_BLE]"

/**
 * @brief Initialize Combustion BLE broadcasting
 * @details Registers GATT service, configures advertising, starts broadcasting.
 *          Must be called after Drv_BT_Init() completes.
 * @return ESP_OK on success, error code otherwise
 */
esp_err_t combustionBle_Init(void);

/**
 * @brief Update temperature values for BLE broadcast
 * @details Called from senxorTask after quadrant_Calculate() to update
 *          both advertising data and connected client notifications.
 * @param temps Array of 8 temperatures in millikelvin (mK)
 *              [0-3]: Amax, Bmax, Cmax, Dmax (quadrant max temps)
 *              [4-7]: Aburnert, Bburnert, Cburnert, Dburnert (burner temps)
 */
void combustionBle_UpdateTemps(const uint16_t temps[8]);

/**
 * @brief Check if Combustion BLE is initialized
 * @return true if initialized and advertising
 */
bool combustionBle_IsInitialized(void);

/**
 * @brief Get number of connected BLE clients
 * @return Number of active connections (0-3)
 */
uint8_t combustionBle_GetConnectionCount(void);

#endif /* COMPONENTS_DRIVERS_INCLUDE_DRV_COMBUSTIONBLE_H_ */
