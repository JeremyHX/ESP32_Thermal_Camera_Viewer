/*****************************************************************************
 * @file     DrvUSB.c
 * @version  1.00
 * @brief    USB CDC Driver
 * @date	 23 Apr 2024
 ******************************************************************************/
#include "DrvUSB.h"

/******************************************************************************
 * @brief       Drv_USB_Init
 * @param       None
 * @return      None
 * @details     Initialise USB
 *****************************************************************************/
void Drv_USB_Init(void)
{
    const tinyusb_config_t tusb_cfg = {
        .port = TINYUSB_PORT_FULL_SPEED_0,
        .phy = {0},
        .task = {0},
        .descriptor = {0},
        .event_cb = NULL,
        .event_arg = NULL,
    };

    tinyusb_driver_install(&tusb_cfg);
}// Drv_USB_Init

/******************************************************************************
 * @brief       Drv_USB_Init
 * @param       pCfg - tiny USB configuration object
 * @return      None
 * @details     Initialise USB CDC
 *****************************************************************************/
void Drv_USB_CDC_Init(const tinyusb_config_cdcacm_t *pCfg)
{
    if(!pCfg)
    {
        return;
    }
    tinyusb_cdcacm_init(pCfg);
}// Drv_USB_CDC_Init
