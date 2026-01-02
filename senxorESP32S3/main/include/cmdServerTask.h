/*****************************************************************************
 * @file     cmdServerTask.h
 * @version  1.0
 * @brief    Command server for handling WREG/RREG/RRSE commands
 * @date     31 Dec 2024
 *****************************************************************************/
#ifndef MAIN_INCLUDE_CMDSERVERTASK_H_
#define MAIN_INCLUDE_CMDSERVERTASK_H_

#include <stdint.h>
#include <stdbool.h>

#define CMD_SERVER_PORT         3334
#define CMD_SERVER_STACK_SIZE   4096
#define POLL_MAX_FREQ_HZ        25   // Camera max frame rate

void cmdServerTask(void *pvParameters);
bool cmdServerGetIsClientConnected(void);
uint8_t cmdServerGetPollFreqHz(void);
void cmdServerSetPollFreqHz(uint8_t freqHz);

#endif /* MAIN_INCLUDE_CMDSERVERTASK_H_ */
