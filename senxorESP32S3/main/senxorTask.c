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

//public:
EXT_RAM_BSS_ATTR uint16_t CalibData_BufferData[CALIBDATA_FLASH_SIZE];			//Array to hold the calibration data
EXT_RAM_BSS_ATTR QueueHandle_t senxorFrameQueue = NULL;

TaskHandle_t senxorTaskHandle = NULL;
//private:
EXT_RAM_BSS_ATTR static senxorFrame mSenxorFrameObj;
static quadrantData_t mQuadrantData;  // Quadrant analysis data
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

	for(;;)
	{
		bool framePortConnected = tcpServerGetIsClientConnected();
		bool cmdPortConnected = cmdServerGetIsClientConnected();
		uint8_t pollFreq = cmdServerGetPollFreqHz();

		// Mode 1: Frame streaming port (3333) connected - normal streaming behavior
		if (framePortConnected)
		{
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
		// Mode 2: Only command port (3334) connected with polling enabled
		else if (cmdPortConnected && pollFreq > 0)
		{
			// Calculate delay based on poll frequency
			TickType_t pollDelayMs = 1000 / pollFreq;
			TickType_t currentTime = xTaskGetTickCount();

			if ((currentTime - lastPollTime) >= pdMS_TO_TICKS(pollDelayMs))
			{
				lastPollTime = currentTime;

				// Start capture temporarily if not already capturing
				uint8_t prevB1 = Acces_Read_Reg(0xB1);
				if (!(prevB1 & B1_SINGLE_CONT) && !(prevB1 & B1_START_CAPTURE))
				{
					Acces_Write_Reg(0xB1, 0x03);  // Start capture
				}

				DataFrameReceiveSenxor();
				const uint16_t* senxorData = DataFrameGetPointer();

				if (senxorData != 0)
				{
					quadrant_Calculate(senxorData);  // Update quadrant registers only
				}
				DataFrameProcess();

				// Stop capture if we started it
				if (!(prevB1 & B1_SINGLE_CONT) && !(prevB1 & B1_START_CAPTURE))
				{
					Acces_Write_Reg(0xB1, 0x00);  // Stop capture
				}
			}
			vTaskDelay(1);
		}
		// Mode 3: Neither port connected, or cmd port connected but pollFreq = 0
		else
		{
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

	ESP_LOGI(SXRTAG, "Quadrant analysis initialized: Xsplit=%d, Ysplit=%d",
			 mQuadrantData.Xsplit, mQuadrantData.Ysplit);
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
}

/*
 * ***********************************************************************
 * @brief       quadrant_ReadRegister
 * @param       regAddr - Register address (0xC0-0xC9)
 * @return      Register value (16-bit for max/center, 8-bit for split)
 * @details     Read quadrant register value
 **************************************************************************/
uint16_t quadrant_ReadRegister(uint8_t regAddr)
{
	switch (regAddr) {
		case REG_XSPLIT:  return mQuadrantData.Xsplit;
		case REG_YSPLIT:  return mQuadrantData.Ysplit;
		case REG_AMAX:    return mQuadrantData.Amax;
		case REG_ACENTER: return mQuadrantData.Acenter;
		case REG_BMAX:    return mQuadrantData.Bmax;
		case REG_BCENTER: return mQuadrantData.Bcenter;
		case REG_CMAX:    return mQuadrantData.Cmax;
		case REG_CCENTER: return mQuadrantData.Ccenter;
		case REG_DMAX:    return mQuadrantData.Dmax;
		case REG_DCENTER: return mQuadrantData.Dcenter;
		default:          return 0;
	}
}

/*
 * ***********************************************************************
 * @brief       quadrant_WriteRegister
 * @param       regAddr - Register address (0xC0 or 0xC1 only)
 * @param       value - Value to write
 * @return      None
 * @details     Write quadrant register (only Xsplit and Ysplit are writable)
 **************************************************************************/
void quadrant_WriteRegister(uint8_t regAddr, uint8_t value)
{
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
		default:
			// Other registers are read-only
			break;
	}
}
