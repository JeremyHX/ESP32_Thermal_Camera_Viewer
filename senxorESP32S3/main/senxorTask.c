/*****************************************************************************
 * @file     senxorTask.c
 * @version  2.01
 * @brief    FreeRTOS task for interfacing with SenXor
 * @date	 11 Jul 2022
 ******************************************************************************/
#include <esp_log.h>				//ESP logger
#include "Customer_Interface.h"
#include "DrvLED.h"
#include "DrvNVS.h"
#include "MCU_Dependent.h"
#include "esp_err.h"
#include "esp_mac.h"
#include "esp_system.h"
#include "msg.h"					//Messages
#include "SenXorLib.h"				//SenXor library
#include "SenXor_Capturedata.h"		//Interrupt handler
#include "senxorTask.h"
#include "tcpServerTask.h"
#include "cmdServerTask.h"
#include "util.h"
#include "ledCtrlTask.h"			//LED control task
#include "Drv_CombustionBle.h"		//Combustion-compatible BLE

//public:
EXT_RAM_BSS_ATTR uint16_t CalibData_BufferData[CALIBDATA_FLASH_SIZE];			//Array to hold the calibration data
EXT_RAM_BSS_ATTR QueueHandle_t senxorFrameQueue = NULL;

TaskHandle_t senxorTaskHandle = NULL;
//private:
EXT_RAM_BSS_ATTR static senxorFrame mSenxorFrameObj;
static quadrantData_t mQuadrantData;  // Quadrant analysis data
static uint8_t mDeviceId[6] = {0};    // BT MAC address for device identification
static void senxorTask_Init(void);


/*
 * ***********************************************************************
 * @brief       senxorInit
 * @param       None
 * @return      None
 * @details     Initialise SenXor
 **************************************************************************/
uint8_t senxorInit(void)
{

	Initialize_McuRegister();																//Initialise SenXor software registers

	Power_On_Senxor(1);																//Power up SenXor and determine its model

	if(Initialize_SenXor(1))													//Initialise SenXor peripherals.
	{
#ifdef CONFIG_MI_LCD_EN
		drawIcon(96,76,ICON_ERROR);
		drawText(1,76+48,"Failed to initialise \nSenXor. Program halted.");
#endif
		return 1; 																			//Exit program immediately if failed.
	}//End if

	Read_CalibrationData();																	//Load calibration data from flash
	ESP_LOGI(SXRTAG,SXR_PROCESS_CALI);
	Process_CalibrationData(1,(uint16_t*)CalibData_BufferData);		//Process calibration data
	ESP_LOGI(SXRTAG,SXR_FITLER_INIT);
	Initialize_Filter();																	//Initialise filters
	Read_AGC_LUT();																			//Read auto gain

	/*
	 * If TCP server is used, TCP server should be started BEFORE SenXor starting capture.
	 */
	Acces_Write_Reg(0xB1,0);													//Stop capturing

	ESP_LOGI(SXRTAG,SXR_INIT_DONE);

	return 0;
}

/*
 * ***********************************************************************
 * @brief       senxorTask
 * @param       pvParameters - Task arguments
 * @return      None
 * @details     SenXor task
 **************************************************************************/
void senxorTask(void * pvParameters)
{
	//uint8_t tOpMode = MCU_getOpMode();
	ESP_LOGI(SXRTAG,SXR_TASK_INFO,xPortGetCoreID());
	ESP_LOGI(SXRTAG,MAIN_FREE_RAM " / " MAIN_TOTAL_RAM,heap_caps_get_free_size(MALLOC_CAP_INTERNAL), heap_caps_get_total_size(MALLOC_CAP_INTERNAL));				//Display the total amount of DRAM
	ESP_LOGI(SXRTAG,MAIN_FREE_SPIRAM " / " MAIN_TOTAL_SPIRAM,heap_caps_get_free_size(MALLOC_CAP_SPIRAM), heap_caps_get_total_size(MALLOC_CAP_SPIRAM));				//Display the total amount of PSRAM

	senxorTask_Init();																																					//Initialise queue

	TickType_t lastPollTime = 0;
	bool pollCaptureStarted = false;  // Track if we started capture for polling mode

	for(;;)
	{
		bool framePortConnected = tcpServerGetIsClientConnected();
		bool cmdPortConnected = cmdServerGetIsClientConnected();
		uint8_t pollFreq = cmdServerGetPollFreqHz();
		bool bleConnected = combustionBle_GetConnectionCount() > 0;

		// Mode 1: Frame streaming port (3333) connected - normal streaming behavior
		if (framePortConnected)
		{
			// If we had started capture for polling, frame streaming will take over
			pollCaptureStarted = false;

			if ( (Acces_Read_Reg(0xB1) & B1_SINGLE_CONT) || (Acces_Read_Reg(0xB1) & B1_START_CAPTURE) )
			{
				DataFrameReceiveSenxor();													//Receive frame from SenXor
				const uint16_t* senxorData = DataFrameGetPointer();							//Get processed frame

				if (senxorData != 0)
				{
#ifdef CONFIG_MI_SENXOR_DBG
					printSenXorLog(senxorData);
#endif
					memcpy(mSenxorFrameObj.mFrame,senxorData,sizeof(mSenxorFrameObj.mFrame));	//Get a copy of thermal frame
					quadrant_Calculate(senxorData);												//Calculate quadrant analysis values
					senxorFrame* pSenxorFrameObj = &mSenxorFrameObj;							//Create a pointer to the copy of thermal frame  for sending to queue
					xQueueSend(senxorFrameQueue, (void *)&pSenxorFrameObj, 0);					//Send to queue and do not wait for queue
				}//End if
				DataFrameProcess();															//Thermal frame post-processing
			}//End if
			vTaskDelay(1);
		}
		// Mode 2: Command port (3334) connected with polling enabled, OR BLE clients connected
		else if ((cmdPortConnected && pollFreq > 0) || bleConnected)
		{
			// Start continuous capture if not already running
			if (!pollCaptureStarted)
			{
				if (bleConnected) {
					ESP_LOGI(SXRTAG, "Starting capture for BLE mode (%d clients)", combustionBle_GetConnectionCount());
				} else {
					ESP_LOGI(SXRTAG, "Starting capture for polling mode at %d Hz", pollFreq);
				}
				Acces_Write_Reg(0xB1, 0x03);  // Start continuous capture
				pollCaptureStarted = true;
				lastPollTime = xTaskGetTickCount();  // Reset timer
				vTaskDelay(pdMS_TO_TICKS(50));  // Give sensor time to start
			}

			// Calculate delay based on poll frequency (use 25Hz for BLE if no poll freq set)
			uint8_t effectiveFreq = (pollFreq > 0) ? pollFreq : 25;
			TickType_t pollDelayMs = 1000 / effectiveFreq;
			TickType_t currentTime = xTaskGetTickCount();

			if (1 || (currentTime - lastPollTime) >= pdMS_TO_TICKS(pollDelayMs))
			{
				lastPollTime = currentTime;

				DataFrameReceiveSenxor();
				const uint16_t* senxorData = DataFrameGetPointer();

				if (senxorData != 0)
				{
					quadrant_Calculate(senxorData);  // Update quadrant registers and BLE
					ESP_LOGD(SXRTAG, "Poll update: Amax=%u Dmax=%u",
							 quadrant_ReadRegister(0xC2), quadrant_ReadRegister(0xC8));
				}
				DataFrameProcess();
			}
			vTaskDelay(1);
		}
		// Mode 3: Neither port connected and no BLE clients
		else
		{
			// Stop capture if we started it for polling/BLE
			if (pollCaptureStarted)
			{
				ESP_LOGI(SXRTAG, "Stopping capture (no active clients)");
				Acces_Write_Reg(0xB1, 0x00);  // Stop capture
				pollCaptureStarted = false;
			}
			vTaskDelay(pdMS_TO_TICKS(100));  // Sleep longer when idle
		}
	}//End for
}//End senxorTask


/*
 * ***********************************************************************
 * @brief       DataFrameReceiveError
 * @param       None
 * @return      None
 * @details     Frame receive error handler
 **************************************************************************/
void DataFrameReceiveError(void)
{
	if(SenXorError)
    {
	  ESP_LOGE(SXRTAG,SXR_ERR,SenXorError);
	  ESP_LOGW(SXRTAG,SXR_WARN_RECR);
      SenXorError = 0;                                                    //Clear error flag
      Acces_Write_Reg(0xB1,0);                                            //Stop capturing
      Acces_Write_Reg(0xB0,3);                                            //Reinitialise SenXor
    }//End if
}


/*
 * ***********************************************************************
 * @brief       senxorTask_Init
 * @param       None
 * @return      None
 * @details     Initialise SenXorTask
 **************************************************************************/
static void senxorTask_Init(void)
{
	ESP_LOGI(MTAG,MAIN_INIT_QUEUE);

	senxorFrameQueue = xQueueCreate(THERMAL_FRAME_BUFFER_NO, sizeof(uint16_t*));
	if( senxorFrameQueue == 0 )
	{
		vTaskDelete(NULL);
	}

}

/*
 * ***********************************************************************
 * @brief       quadrant_Init
 * @param       None
 * @return      None
 * @details     Initialize quadrant analysis, load split values from NVS
 **************************************************************************/
void quadrant_Init(void)
{
	// Load Xsplit and Ysplit from NVS, use defaults if not found
	mQuadrantData.Xsplit = NVS_ReadU8("xsplit", DEFAULT_XSPLIT);
	mQuadrantData.Ysplit = NVS_ReadU8("ysplit", DEFAULT_YSPLIT);

	// Validate ranges
	if (mQuadrantData.Xsplit > SENXOR_FRAME_WIDTH) {
		mQuadrantData.Xsplit = DEFAULT_XSPLIT;
	}
	if (mQuadrantData.Ysplit > SENXOR_FRAME_HEIGHT) {
		mQuadrantData.Ysplit = DEFAULT_YSPLIT;
	}

	// Initialize max/center values to 0
	mQuadrantData.Amax = 0;
	mQuadrantData.Acenter = 0;
	mQuadrantData.Bmax = 0;
	mQuadrantData.Bcenter = 0;
	mQuadrantData.Cmax = 0;
	mQuadrantData.Ccenter = 0;
	mQuadrantData.Dmax = 0;
	mQuadrantData.Dcenter = 0;

	// Calculate default burner coordinates (center of each quadrant)
	uint8_t defAx = DEFAULT_XSPLIT / 2;
	uint8_t defAy = DEFAULT_YSPLIT / 2;
	uint8_t defBx = DEFAULT_XSPLIT + (SENXOR_FRAME_WIDTH - DEFAULT_XSPLIT) / 2;
	uint8_t defBy = DEFAULT_YSPLIT / 2;
	uint8_t defCx = DEFAULT_XSPLIT / 2;
	uint8_t defCy = DEFAULT_YSPLIT + (SENXOR_FRAME_HEIGHT - DEFAULT_YSPLIT) / 2;
	uint8_t defDx = DEFAULT_XSPLIT + (SENXOR_FRAME_WIDTH - DEFAULT_XSPLIT) / 2;
	uint8_t defDy = DEFAULT_YSPLIT + (SENXOR_FRAME_HEIGHT - DEFAULT_YSPLIT) / 2;

	// Load burner coordinates from NVS, use defaults if not found
	mQuadrantData.Aburnerx = NVS_ReadU8("aburnerx", defAx);
	mQuadrantData.Aburnery = NVS_ReadU8("aburnery", defAy);
	mQuadrantData.Bburnerx = NVS_ReadU8("bburnerx", defBx);
	mQuadrantData.Bburnery = NVS_ReadU8("bburnery", defBy);
	mQuadrantData.Cburnerx = NVS_ReadU8("cburnerx", defCx);
	mQuadrantData.Cburnery = NVS_ReadU8("cburnery", defCy);
	mQuadrantData.Dburnerx = NVS_ReadU8("dburnerx", defDx);
	mQuadrantData.Dburnery = NVS_ReadU8("dburnery", defDy);

	// Initialize burner temperature values to 0
	mQuadrantData.Aburnert = 0;
	mQuadrantData.Bburnert = 0;
	mQuadrantData.Cburnert = 0;
	mQuadrantData.Dburnert = 0;

	// Read BT MAC address for device identification
	esp_read_mac(mDeviceId, ESP_MAC_BT);

	ESP_LOGI(SXRTAG, "Quadrant analysis initialized: Xsplit=%d, Ysplit=%d",
			 mQuadrantData.Xsplit, mQuadrantData.Ysplit);
	ESP_LOGI(SXRTAG, "Burner coords: A(%d,%d) B(%d,%d) C(%d,%d) D(%d,%d)",
			 mQuadrantData.Aburnerx, mQuadrantData.Aburnery,
			 mQuadrantData.Bburnerx, mQuadrantData.Bburnery,
			 mQuadrantData.Cburnerx, mQuadrantData.Cburnery,
			 mQuadrantData.Dburnerx, mQuadrantData.Dburnery);
	ESP_LOGI(SXRTAG, "Device ID (BT MAC): %02X:%02X:%02X:%02X:%02X:%02X",
			 mDeviceId[0], mDeviceId[1], mDeviceId[2],
			 mDeviceId[3], mDeviceId[4], mDeviceId[5]);
}

/*
 * ***********************************************************************
 * @brief       quadrant_Calculate
 * @param       frameData - Pointer to thermal frame data (80x64 pixels)
 * @return      None
 * @details     Calculate quadrant max and center values from frame data
 **************************************************************************/
void quadrant_Calculate(const uint16_t* frameData)
{
	if (frameData == NULL) {
		return;
	}

	uint8_t xsplit = mQuadrantData.Xsplit;
	uint8_t ysplit = mQuadrantData.Ysplit;

	// Reset max values
	uint16_t Amax = 0, Bmax = 0, Cmax = 0, Dmax = 0;

	// Skip first 2 header rows - image data starts at row 2 (index 160)
	const uint16_t* imageData = frameData + (2 * SENXOR_FRAME_WIDTH);

	// Scan all pixels and find max for each quadrant
	for (uint8_t y = 0; y < SENXOR_FRAME_HEIGHT; y++) {
		for (uint8_t x = 0; x < SENXOR_FRAME_WIDTH; x++) {
			uint16_t pixel = imageData[y * SENXOR_FRAME_WIDTH + x];

			if (x < xsplit && y < ysplit) {
				// Quadrant A (top-left)
				if (pixel > Amax) Amax = pixel;
			} else if (x >= xsplit && y < ysplit) {
				// Quadrant B (top-right)
				if (pixel > Bmax) Bmax = pixel;
			} else if (x < xsplit && y >= ysplit) {
				// Quadrant C (bottom-left)
				if (pixel > Cmax) Cmax = pixel;
			} else {
				// Quadrant D (bottom-right)
				if (pixel > Dmax) Dmax = pixel;
			}
		}
	}

	// Calculate center pixel coordinates for each quadrant
	uint8_t Acx = xsplit / 2;
	uint8_t Acy = ysplit / 2;
	uint8_t Bcx = xsplit + (SENXOR_FRAME_WIDTH - xsplit) / 2;
	uint8_t Bcy = ysplit / 2;
	uint8_t Ccx = xsplit / 2;
	uint8_t Ccy = ysplit + (SENXOR_FRAME_HEIGHT - ysplit) / 2;
	uint8_t Dcx = xsplit + (SENXOR_FRAME_WIDTH - xsplit) / 2;
	uint8_t Dcy = ysplit + (SENXOR_FRAME_HEIGHT - ysplit) / 2;

	// Clamp center coordinates to valid range
	if (Acx >= SENXOR_FRAME_WIDTH) Acx = SENXOR_FRAME_WIDTH - 1;
	if (Acy >= SENXOR_FRAME_HEIGHT) Acy = SENXOR_FRAME_HEIGHT - 1;
	if (Bcx >= SENXOR_FRAME_WIDTH) Bcx = SENXOR_FRAME_WIDTH - 1;
	if (Bcy >= SENXOR_FRAME_HEIGHT) Bcy = SENXOR_FRAME_HEIGHT - 1;
	if (Ccx >= SENXOR_FRAME_WIDTH) Ccx = SENXOR_FRAME_WIDTH - 1;
	if (Ccy >= SENXOR_FRAME_HEIGHT) Ccy = SENXOR_FRAME_HEIGHT - 1;
	if (Dcx >= SENXOR_FRAME_WIDTH) Dcx = SENXOR_FRAME_WIDTH - 1;
	if (Dcy >= SENXOR_FRAME_HEIGHT) Dcy = SENXOR_FRAME_HEIGHT - 1;

	// Store results (use imageData which is offset past headers)
	mQuadrantData.Amax = Amax;
	mQuadrantData.Acenter = imageData[Acy * SENXOR_FRAME_WIDTH + Acx];
	mQuadrantData.Bmax = Bmax;
	mQuadrantData.Bcenter = imageData[Bcy * SENXOR_FRAME_WIDTH + Bcx];
	mQuadrantData.Cmax = Cmax;
	mQuadrantData.Ccenter = imageData[Ccy * SENXOR_FRAME_WIDTH + Ccx];
	mQuadrantData.Dmax = Dmax;
	mQuadrantData.Dcenter = imageData[Dcy * SENXOR_FRAME_WIDTH + Dcx];

	// Read burner temperatures at stored coordinates
	mQuadrantData.Aburnert = imageData[mQuadrantData.Aburnery * SENXOR_FRAME_WIDTH + mQuadrantData.Aburnerx];
	mQuadrantData.Bburnert = imageData[mQuadrantData.Bburnery * SENXOR_FRAME_WIDTH + mQuadrantData.Bburnerx];
	mQuadrantData.Cburnert = imageData[mQuadrantData.Cburnery * SENXOR_FRAME_WIDTH + mQuadrantData.Cburnerx];
	mQuadrantData.Dburnert = imageData[mQuadrantData.Dburnery * SENXOR_FRAME_WIDTH + mQuadrantData.Dburnerx];

	// Update Combustion BLE with latest temperatures
	uint16_t combustion_temps[8] = {
		mQuadrantData.Amax, mQuadrantData.Bmax,
		mQuadrantData.Cmax, mQuadrantData.Dmax,
		mQuadrantData.Aburnert, mQuadrantData.Bburnert,
		mQuadrantData.Cburnert, mQuadrantData.Dburnert
	};
	combustionBle_UpdateTemps(combustion_temps);
}

/*
 * ***********************************************************************
 * @brief       quadrant_ReadRegister
 * @param       regAddr - Register address (0xC0-0xD5)
 * @return      Register value (16-bit for max/center/burnert, 8-bit for split/burnerxy)
 * @details     Read quadrant register value
 **************************************************************************/
uint16_t quadrant_ReadRegister(uint8_t regAddr)
{
	switch (regAddr) {
		case REG_XSPLIT:   return mQuadrantData.Xsplit;
		case REG_YSPLIT:   return mQuadrantData.Ysplit;
		case REG_AMAX:     return mQuadrantData.Amax;
		case REG_ACENTER:  return mQuadrantData.Acenter;
		case REG_BMAX:     return mQuadrantData.Bmax;
		case REG_BCENTER:  return mQuadrantData.Bcenter;
		case REG_CMAX:     return mQuadrantData.Cmax;
		case REG_CCENTER:  return mQuadrantData.Ccenter;
		case REG_DMAX:     return mQuadrantData.Dmax;
		case REG_DCENTER:  return mQuadrantData.Dcenter;
		case REG_ABURNERX: return mQuadrantData.Aburnerx;
		case REG_ABURNERY: return mQuadrantData.Aburnery;
		case REG_ABURNERT: return mQuadrantData.Aburnert;
		case REG_BBURNERX: return mQuadrantData.Bburnerx;
		case REG_BBURNERY: return mQuadrantData.Bburnery;
		case REG_BBURNERT: return mQuadrantData.Bburnert;
		case REG_CBURNERX: return mQuadrantData.Cburnerx;
		case REG_CBURNERY: return mQuadrantData.Cburnery;
		case REG_CBURNERT: return mQuadrantData.Cburnert;
		case REG_DBURNERX: return mQuadrantData.Dburnerx;
		case REG_DBURNERY: return mQuadrantData.Dburnery;
		case REG_DBURNERT: return mQuadrantData.Dburnert;
		// Device ID registers (BT MAC address)
		case REG_DEVID0:   return mDeviceId[0];
		case REG_DEVID1:   return mDeviceId[1];
		case REG_DEVID2:   return mDeviceId[2];
		case REG_DEVID3:   return mDeviceId[3];
		case REG_DEVID4:   return mDeviceId[4];
		case REG_DEVID5:   return mDeviceId[5];
		default:           return 0;
	}
}

/*
 * ***********************************************************************
 * @brief       quadrant_WriteRegister
 * @param       regAddr - Register address (0xC0, 0xC1, or burner coords)
 * @param       value - Value to write
 * @return      None
 * @details     Write quadrant register (split values and burner coordinates)
 **************************************************************************/
void quadrant_WriteRegister(uint8_t regAddr, uint8_t value)
{
	uint8_t xsplit = mQuadrantData.Xsplit;
	uint8_t ysplit = mQuadrantData.Ysplit;

	switch (regAddr) {
		case REG_XSPLIT:
			if (value <= SENXOR_FRAME_WIDTH) {
				mQuadrantData.Xsplit = value;
				NVS_WriteU8("xsplit", value);
				ESP_LOGI(SXRTAG, "Xsplit set to %d", value);
			}
			break;
		case REG_YSPLIT:
			if (value <= SENXOR_FRAME_HEIGHT) {
				mQuadrantData.Ysplit = value;
				NVS_WriteU8("ysplit", value);
				ESP_LOGI(SXRTAG, "Ysplit set to %d", value);
			}
			break;
		// Quadrant A burner (top-left): x in [0, xsplit-1], y in [0, ysplit-1]
		case REG_ABURNERX:
			if (value >= xsplit) value = xsplit > 0 ? xsplit - 1 : 0;
			mQuadrantData.Aburnerx = value;
			NVS_WriteU8("aburnerx", value);
			ESP_LOGI(SXRTAG, "Aburnerx set to %d", value);
			break;
		case REG_ABURNERY:
			if (value >= ysplit) value = ysplit > 0 ? ysplit - 1 : 0;
			mQuadrantData.Aburnery = value;
			NVS_WriteU8("aburnery", value);
			ESP_LOGI(SXRTAG, "Aburnery set to %d", value);
			break;
		// Quadrant B burner (top-right): x in [xsplit, 79], y in [0, ysplit-1]
		case REG_BBURNERX:
			if (value < xsplit) value = xsplit;
			if (value >= SENXOR_FRAME_WIDTH) value = SENXOR_FRAME_WIDTH - 1;
			mQuadrantData.Bburnerx = value;
			NVS_WriteU8("bburnerx", value);
			ESP_LOGI(SXRTAG, "Bburnerx set to %d", value);
			break;
		case REG_BBURNERY:
			if (value >= ysplit) value = ysplit > 0 ? ysplit - 1 : 0;
			mQuadrantData.Bburnery = value;
			NVS_WriteU8("bburnery", value);
			ESP_LOGI(SXRTAG, "Bburnery set to %d", value);
			break;
		// Quadrant C burner (bottom-left): x in [0, xsplit-1], y in [ysplit, 61]
		case REG_CBURNERX:
			if (value >= xsplit) value = xsplit > 0 ? xsplit - 1 : 0;
			mQuadrantData.Cburnerx = value;
			NVS_WriteU8("cburnerx", value);
			ESP_LOGI(SXRTAG, "Cburnerx set to %d", value);
			break;
		case REG_CBURNERY:
			if (value < ysplit) value = ysplit;
			if (value >= SENXOR_FRAME_HEIGHT) value = SENXOR_FRAME_HEIGHT - 1;
			mQuadrantData.Cburnery = value;
			NVS_WriteU8("cburnery", value);
			ESP_LOGI(SXRTAG, "Cburnery set to %d", value);
			break;
		// Quadrant D burner (bottom-right): x in [xsplit, 79], y in [ysplit, 61]
		case REG_DBURNERX:
			if (value < xsplit) value = xsplit;
			if (value >= SENXOR_FRAME_WIDTH) value = SENXOR_FRAME_WIDTH - 1;
			mQuadrantData.Dburnerx = value;
			NVS_WriteU8("dburnerx", value);
			ESP_LOGI(SXRTAG, "Dburnerx set to %d", value);
			break;
		case REG_DBURNERY:
			if (value < ysplit) value = ysplit;
			if (value >= SENXOR_FRAME_HEIGHT) value = SENXOR_FRAME_HEIGHT - 1;
			mQuadrantData.Dburnery = value;
			NVS_WriteU8("dburnery", value);
			ESP_LOGI(SXRTAG, "Dburnery set to %d", value);
			break;
		default:
			// Other registers are read-only
			break;
	}
}
