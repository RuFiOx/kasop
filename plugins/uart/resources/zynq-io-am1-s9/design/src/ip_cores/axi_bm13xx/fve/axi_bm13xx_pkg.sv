/***************************************************************************************************
 * Copyright (C) 2019  Braiins Systems s.r.o.
 *
 * This file is part of Braiins Open-Source Initiative (BOSI).
 *
 * BOSI is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * Please, keep in mind that we may also license BOSI or any part thereof
 * under a proprietary license. For more information on the terms and conditions
 * of such proprietary license or if you have any other questions, please
 * contact us at opensource@braiins.com.
 ***************************************************************************************************
 * Project Name:   Braiins OS
 * Description:    Package with AXI BM13xx IP core parameters
 *
 * Engineer:       Marian Pristach
 * Revision:       1.1.0 (22.07.2019)
 *
 * Comments:
 **************************************************************************************************/

`timescale 1ns / 1ps

package axi_bm13xx_pkg;

    // ---------------------------------------------------------------------------------------------
    // clock parameter
    time CLK_PERIOD = 20ns;

    // ---------------------------------------------------------------------------------------------
    // Definition of IP core AXI interface
    // ---------------------------------------------------------------------------------------------

    // IP Core Version Register, read-only
    parameter VERSION          = 32'h0000;
    // Build ID Register, read-only
    parameter BUILD_ID         = 32'h0004;
    // Control Register, read/write
    parameter CTRL_REG         = 32'h0008;
    // Status Register - reserved, read-only
    parameter STAT_REG         = 32'h000C;
    // Baudrate Divisor Register, read/write
    parameter BAUD_REG         = 32'h0010;
    // Work Time Delay Register, read/write
    parameter WORK_TIME        = 32'h0014;
    // Error Counter Register, read-only
    parameter ERR_COUNTER      = 32'h0018;
    // Command Receive Interface FIFO, read-only
    parameter CMD_RX_FIFO      = 32'h1000;
    // Command Transmit Interface FIFO, write-only
    parameter CMD_TX_FIFO      = 32'h1004;
    // Command Control Register, read/write
    parameter CMD_CTRL_REG     = 32'h1008;
    // Command Status Register, read-only
    parameter CMD_STAT_REG     = 32'h100C;
    // Work Receive Interface FIFO, read-only
    parameter WORK_RX_FIFO     = 32'h2000;
    // Work Receive Control Register, read/write
    parameter WORK_RX_CTRL_REG = 32'h2008;
    // Work Receive Status Register, read-only
    parameter WORK_RX_STAT_REG = 32'h200C;
    // Work Transmit Interface FIFO, write-only
    parameter WORK_TX_FIFO     = 32'h3004;
    // Work Transmit Control Register, read/write
    parameter WORK_TX_CTRL_REG = 32'h3008;
    // Work Transmit Status Register, read-only
    parameter WORK_TX_STAT_REG = 32'h300C;
    // Work Transmit IRQ Threshold, read/write
    parameter WORK_TX_IRQ_THR  = 32'h3010;
    // Work Transmit Last Work ID, read-only
    parameter WORK_TX_LAST_ID  = 32'h3014;

    // ---------------------------------------------------------------------------------------------
    // Control Registers
    // ---------------------------------------------------------------------------------------------
    // Enable support for chips BM1391, BM1397
    parameter CTRL_BM139X = 32'h10;
    // Enable, read/write
    parameter CTRL_ENABLE = 32'h8;
    // Number of midstates per work, encoded as log2 of values: 1, 2, 4, read/write
    parameter CTRL_MIDSTATE_1 = 32'h0;
    parameter CTRL_MIDSTATE_2 = 32'h2;
    parameter CTRL_MIDSTATE_4 = 32'h4;
    // Clear error counter, write-only
    parameter CTRL_ERR_CNT_CLEAR = 32'h1;
    // Enable interrupt, read/write
    parameter CTRL_IRQ_EN = 32'h4;
    // Reset/clear Transmit FIFO, write-only
    parameter CTRL_RST_TX_FIFO = 32'h2;
    // Reset/clear Receive FIFO, write-only
    parameter CTRL_RST_RX_FIFO = 32'h1;

    // ---------------------------------------------------------------------------------------------
    // Status Registers - read-only
    // ---------------------------------------------------------------------------------------------
    // Interrupt pending for Work Receive FIFO
    parameter STAT_IRQ_PEND = 32'h10;
    // Work Interface Transmit FIFO Full
    parameter STAT_TX_FULL  = 32'h08;
    // Work Interface Transmit FIFO Empty
    parameter STAT_TX_EMPTY = 32'h04;
    // Work Interface Receive FIFO Full
    parameter STAT_RX_FULL  = 32'h02;
    // Work Interface Receive FIFO Empty
    parameter STAT_RX_EMPTY = 32'h01;

endpackage : axi_bm13xx_pkg
