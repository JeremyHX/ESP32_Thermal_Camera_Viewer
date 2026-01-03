/*****************************************************************************
 * @file     senxorTask.h
 * @version  2.01
 * @brief    Header file for senxorTask.c
 * @date	 21 Jul 2022
 ******************************************************************************/
#ifndef MAIN_INCLUDE_SENXORTASK_H_
#define MAIN_INCLUDE_SENXORTASK_H_
#include "esp_log.h"					//ESP logger
#include <stdlib.h>
#include <stdbool.h>

#include "MCU_Dependent.h"
#include "msg.h"						//Messages
#include "SenXorLib.h"					//Using SenXor library
#include "restServer.h"

#define SENXOR_TASK_STACK_SIZE	4096	//Task stack size
#define THERMAL_FRAME_BUFFER_NO 3		//Queue size

// Frame dimensions
#define SENXOR_FRAME_WIDTH  80
#define SENXOR_FRAME_HEIGHT 62

// Quadrant register addresses
#define REG_XSPLIT    0xC0
#define REG_YSPLIT    0xC1
#define REG_AMAX      0xC2
#define REG_ACENTER   0xC3
#define REG_BMAX      0xC4
#define REG_BCENTER   0xC5
#define REG_CMAX      0xC6
#define REG_CCENTER   0xC7
#define REG_DMAX      0xC8
#define REG_DCENTER   0xC9

// Burner register addresses
#define REG_ABURNERX  0xCA
#define REG_ABURNERY  0xCB
#define REG_ABURNERT  0xCC
#define REG_BBURNERX  0xCD
#define REG_BBURNERY  0xCE
#define REG_BBURNERT  0xCF
#define REG_CBURNERX  0xD0
#define REG_CBURNERY  0xD1
#define REG_CBURNERT  0xD2
#define REG_DBURNERX  0xD3
#define REG_DBURNERY  0xD4
#define REG_DBURNERT  0xD5

// Device ID registers (BT MAC address, read-only)
#define REG_DEVID0    0xE0
#define REG_DEVID1    0xE1
#define REG_DEVID2    0xE2
#define REG_DEVID3    0xE3
#define REG_DEVID4    0xE4
#define REG_DEVID5    0xE5

// Default split values
#define DEFAULT_XSPLIT 40
#define DEFAULT_YSPLIT 31

typedef struct senxorFrame{
	uint16_t mFrame[80*64];  // Full frame: 2 header rows + 62 image rows
}senxorFrame;

// Quadrant analysis data structure
typedef struct quadrantData {
	uint16_t Amax;      // Max value in quadrant A (top-left)
	uint16_t Acenter;   // Center pixel value in quadrant A
	uint16_t Bmax;      // Max value in quadrant B (top-right)
	uint16_t Bcenter;   // Center pixel value in quadrant B
	uint16_t Cmax;      // Max value in quadrant C (bottom-left)
	uint16_t Ccenter;   // Center pixel value in quadrant C
	uint16_t Dmax;      // Max value in quadrant D (bottom-right)
	uint16_t Dcenter;   // Center pixel value in quadrant D
	uint8_t Xsplit;     // X split point (0-80)
	uint8_t Ysplit;     // Y split point (0-62)
	// Burner coordinates (absolute image coordinates)
	uint8_t Aburnerx;   // Burner X in quadrant A
	uint8_t Aburnery;   // Burner Y in quadrant A
	uint16_t Aburnert;  // Temperature at burner in quadrant A
	uint8_t Bburnerx;   // Burner X in quadrant B
	uint8_t Bburnery;   // Burner Y in quadrant B
	uint16_t Bburnert;  // Temperature at burner in quadrant B
	uint8_t Cburnerx;   // Burner X in quadrant C
	uint8_t Cburnery;   // Burner Y in quadrant C
	uint16_t Cburnert;  // Temperature at burner in quadrant C
	uint8_t Dburnerx;   // Burner X in quadrant D
	uint8_t Dburnery;   // Burner Y in quadrant D
	uint16_t Dburnert;  // Temperature at burner in quadrant D
} quadrantData_t;

uint8_t senxorInit(void);

// Quadrant analysis functions
void quadrant_Init(void);
void quadrant_Calculate(const uint16_t* frameData);
uint16_t quadrant_ReadRegister(uint8_t regAddr);
void quadrant_WriteRegister(uint8_t regAddr, uint8_t value);

void senxorTask(void * pvParameters);

#endif /* MAIN_INCLUDE_SENXORTASK_H_ */
