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
 * Description:    Testbench for AXI BM13xx IP core
 *
 * Engineer:       Marian Pristach
 * Revision:       1.1.0 (22.07.2019)
 *
 * Comments:
 **************************************************************************************************/

`timescale 1ns / 1ps

import axi_vip_pkg::*;
import axi_bm13xx_pkg::*;
import axi_bm13xx_bfm_master_0_0_pkg::*;

module axi_bm13xx_tb();

    // Simulation parameters
    parameter VERBOSE_LEVEL = 0;

    // instance of AXI master BFM agent
    axi_bm13xx_bfm_master_0_0_mst_t mst_agent;

    // counter of errors
    integer err_counter = 0;

    // local signals
    bit clock;
    bit reset;

    logic uart_rx;
    logic uart_tx;
    logic irq_work_tx;
    logic irq_work_rx;
    logic irq_cmd_rx;

    // ---------------------------------------------------------------------------------------------
    // instance of DUT
    axi_bm13xx_bfm_wrapper DUT (
        .ACLK(clock),
        .ARESETN(reset),
        .rxd_0(uart_rx),
        .txd_0(uart_tx),
        .irq_work_tx_0(irq_work_tx),
        .irq_work_rx_0(irq_work_rx),
        .irq_cmd_rx_0(irq_cmd_rx)
    );

    // instance of UART BFM
    uart_bfm i_uart (
        .rx(uart_tx),
        .tx(uart_rx)
    );

    // ---------------------------------------------------------------------------------------------
    initial begin
        automatic xil_axi_uint mst_agent_verbosity = 0;

        mst_agent = new("master vip agent",DUT.axi_bm13xx_bfm_i.master_0.inst.IF);
        mst_agent.vif_proxy.set_dummy_drive_type(XIL_AXI_VIF_DRIVE_NONE);
        mst_agent.set_agent_tag("Master VIP");
        mst_agent.set_verbosity(mst_agent_verbosity);
        mst_agent.start_master();
        $timeformat (-9, 0, "ns", 1);
    end

    // ---------------------------------------------------------------------------------------------
    // clock and reset generation
    always #10 clock <= ~clock;

    initial begin
        reset <= 1'b0;
        #(3*CLK_PERIOD);
        reset <= 1'b1;
    end

    // ---------------------------------------------------------------------------------------------
    initial begin
        automatic int rdata = 0;

        // wait for reset is finished
        @(posedge reset);

        $display("############################################################");
        $display("Starting simulation");
        $display("############################################################");

        axi_read(BUILD_ID, rdata);
        $display("Build ID: %d", rdata);

        // configure IP core
        $display("Configuring IP core: work time 1us, UART baudrate 3.125M");
`ifdef BM139X
        $display(" - enabled BM139x mode");
`endif

        axi_write(BAUD_REG, 1);           // @50MHz -> 3.125 MBd
        axi_write(WORK_TIME, 50);         // @50MHz -> 1us
        enable_ip(CTRL_MIDSTATE_1);       // enable IP core, 1 midstate

        // checking status
        axi_read(STAT_REG, rdata);
        compare_data(32'h0, rdata, "STAT_REG");

        axi_read(CMD_STAT_REG, rdata);
        compare_data(STAT_TX_EMPTY | STAT_RX_EMPTY, rdata, "CMD_STAT_REG");

        axi_read(WORK_RX_STAT_REG, rdata);
        compare_data(STAT_RX_EMPTY, rdata, "WORK_RX_STAT_REG");

        axi_read(WORK_TX_STAT_REG, rdata);
        compare_data(STAT_TX_EMPTY | STAT_IRQ_PEND, rdata, "WORK_TX_STAT_REG");

        $display("############################################################");

        // -----------------------------------------------------------------------------------------
        // testcase 0 - read version register
        tc_read_version();

        // testcase 1 - test of send commands (5 and 9 bytes)
        tc_send_cmd5();
        tc_send_cmd9();

        // testcase 2 - test of work send (1 and 4 midstates)
        tc_send_work_midstate1();
        tc_send_work_midstate2();
        tc_send_work_midstate4();
        tc_send_cmd_after_work();

        // testcase 3 - test of receive of command and work response
        tc_cmd_response();
        tc_work_response();

        // testcase 4 - test of FIFOs (reset and flags)
        tc_fifo_cmd_rx();
        tc_fifo_cmd_tx();
        tc_fifo_work_rx();
        tc_fifo_work_tx();

        // testcase 5 - test of IRQs
        tc_irq_cmd_rx();
        tc_irq_work_rx();
        tc_irq_work_tx();

        // testcase 6 - test of last work ID
        tc_work_id_1();
        tc_work_id_2();
        tc_work_id_3();
        tc_work_id_4();
        tc_work_id_5();

        // Testcase 7 - test of IP core reset by enable flag
        tc_ip_core_reset_1();
        tc_ip_core_reset_2();
        tc_ip_core_reset_3();
        tc_ip_core_reset_4();

        // testcase 8 - test of error counter register and unexpected data
        tc_error_counter_1();
        tc_error_counter_2();
`ifdef BM139X
        tc_error_counter_3();
`endif

        // testcase 9 - test of baudrate speed change
        tc_baudrate_sync();

        // -----------------------------------------------------------------------------------------
        // final report
        $display("############################################################");
        if (err_counter == 0) begin
            $display("Simulation finished: PASSED");
        end else begin
            $display("Simulation finished: FAILED");
            $display("Number of errors: %0d", err_counter);
        end
        $display("############################################################");

        #1;
        $finish;
    end

    // simulation timeout check
    initial begin
        #20ms;
        $display("############################################################");
        $display("Simulation timeout");
        $display("############################################################");
        $finish;
    end


    // *********************************************************************************************
    //                                     TESTCASES
    // *********************************************************************************************

    // ---------------------------------------------------------------------------------------------
    // Testcase 0: Read version register
    // ---------------------------------------------------------------------------------------------
    task tc_read_version();
        automatic int rdata = 0;

        $display("Testcase 0a: read version register");

        axi_read(VERSION, rdata);
        compare_data(32'h00901000, rdata, "VERSION");
    endtask


    // ---------------------------------------------------------------------------------------------
    // Testcase 1: Test of send commands
    // ---------------------------------------------------------------------------------------------
    // send 5 bytes commands
    task tc_send_cmd5();
        // Tx FIFO data - BM1387
        static logic[31:0] fifo_data1[$] = {32'h00000554};
        static logic[31:0] fifo_data2[$] = {32'h00000555};
        static logic[31:0] fifo_data3[$] = {32'h00000541};
        static logic[31:0] fifo_data4[$] = {32'h00040541};
        static logic[31:0] fifo_data5[$] = {32'h00080541};
        static logic[31:0] fifo_data6[$] = {32'h000c0541};
        static logic[31:0] fifo_data7[$] = {32'h00f40541};
        static logic[31:0] fifo_data8[$] = {32'h00f80541};
        static logic[31:0] fifo_data9[$] = {32'h00fc0541};

        // Tx FIFO data - BM1391
        static logic[31:0] fifo_data10[$] = {32'h00000540};
        static logic[31:0] fifo_data11[$] = {32'h00030540};
        static logic[31:0] fifo_data12[$] = {32'h1C240542};
        static logic[31:0] fifo_data13[$] = {32'h18240542};
        static logic[31:0] fifo_data14[$] = {32'h1C330542};
        static logic[31:0] fifo_data15[$] = {32'h18330542};
        static logic[31:0] fifo_data16[$] = {32'h1C9F0542};
        static logic[31:0] fifo_data17[$] = {32'h00000552};
        static logic[31:0] fifo_data18[$] = {32'h00000553};

        // reference data send out through UART - BM1387
        static logic[7:0] uart_data1[$] = {8'h54, 8'h05, 8'h00, 8'h00, 8'h19};
        static logic[7:0] uart_data2[$] = {8'h55, 8'h05, 8'h00, 8'h00, 8'h10};
        static logic[7:0] uart_data3[$] = {8'h41, 8'h05, 8'h00, 8'h00, 8'h15};
        static logic[7:0] uart_data4[$] = {8'h41, 8'h05, 8'h04, 8'h00, 8'h0a};
        static logic[7:0] uart_data5[$] = {8'h41, 8'h05, 8'h08, 8'h00, 8'h0e};
        static logic[7:0] uart_data6[$] = {8'h41, 8'h05, 8'h0c, 8'h00, 8'h11};
        static logic[7:0] uart_data7[$] = {8'h41, 8'h05, 8'hf4, 8'h00, 8'h10};
        static logic[7:0] uart_data8[$] = {8'h41, 8'h05, 8'hf8, 8'h00, 8'h14};
        static logic[7:0] uart_data9[$] = {8'h41, 8'h05, 8'hfc, 8'h00, 8'h0b};

        // reference data send out through UART - BM1391
        static logic[7:0] uart_data10[$] = {8'h40, 8'h05, 8'h00, 8'h00, 8'h1C};
        static logic[7:0] uart_data11[$] = {8'h40, 8'h05, 8'h03, 8'h00, 8'h1D};
        static logic[7:0] uart_data12[$] = {8'h42, 8'h05, 8'h24, 8'h1C, 8'h11};
        static logic[7:0] uart_data13[$] = {8'h42, 8'h05, 8'h24, 8'h18, 8'h05};
        static logic[7:0] uart_data14[$] = {8'h42, 8'h05, 8'h33, 8'h1C, 8'h1C};
        static logic[7:0] uart_data15[$] = {8'h42, 8'h05, 8'h33, 8'h18, 8'h08};
        static logic[7:0] uart_data16[$] = {8'h42, 8'h05, 8'h9F, 8'h1C, 8'h17};
        static logic[7:0] uart_data17[$] = {8'h52, 8'h05, 8'h00, 8'h00, 8'h0A};
        static logic[7:0] uart_data18[$] = {8'h53, 8'h05, 8'h00, 8'h00, 8'h03};


        $display("Testcase 1a: send 5 bytes commands");

        // test sequences - BM1387
        fifo_write_cmd(fifo_data1);
        uart_read_and_compare(uart_data1);

        fifo_write_cmd(fifo_data2);
        uart_read_and_compare(uart_data2);

        fifo_write_cmd(fifo_data3);
        uart_read_and_compare(uart_data3);

        fifo_write_cmd(fifo_data4);
        uart_read_and_compare(uart_data4);

        fifo_write_cmd(fifo_data5);
        uart_read_and_compare(uart_data5);

        fifo_write_cmd(fifo_data6);
        uart_read_and_compare(uart_data6);

        fifo_write_cmd(fifo_data7);
        uart_read_and_compare(uart_data7);

        fifo_write_cmd(fifo_data8);
        uart_read_and_compare(uart_data8);

        fifo_write_cmd(fifo_data9);
        uart_read_and_compare(uart_data9);

        // test sequences - BM1391
        fifo_write_cmd(fifo_data10);
        uart_read_and_compare(uart_data10);

        fifo_write_cmd(fifo_data11);
        uart_read_and_compare(uart_data11);

        fifo_write_cmd(fifo_data12);
        uart_read_and_compare(uart_data12);

        fifo_write_cmd(fifo_data13);
        uart_read_and_compare(uart_data13);

        fifo_write_cmd(fifo_data14);
        uart_read_and_compare(uart_data14);

        fifo_write_cmd(fifo_data15);
        uart_read_and_compare(uart_data15);

        fifo_write_cmd(fifo_data16);
        uart_read_and_compare(uart_data16);

        fifo_write_cmd(fifo_data17);
        uart_read_and_compare(uart_data17);

        fifo_write_cmd(fifo_data18);
        uart_read_and_compare(uart_data18);
    endtask


    // ---------------------------------------------------------------------------------------------
    // send 9 bytes commands
    task tc_send_cmd9();
        // Tx FIFO data - BM1387
        static logic[31:0] fifo_data1[$]  = {32'h0c000948, 32'h21026800};
        static logic[31:0] fifo_data2[$]  = {32'h0c040948, 32'h21026800};
        static logic[31:0] fifo_data3[$]  = {32'h0c080948, 32'h21026800};
        static logic[31:0] fifo_data4[$]  = {32'h0c0c0948, 32'h21026800};
        static logic[31:0] fifo_data5[$]  = {32'h0ce80948, 32'h21026800};
        static logic[31:0] fifo_data6[$]  = {32'h0cec0948, 32'h21026800};
        static logic[31:0] fifo_data7[$]  = {32'h0cf00948, 32'h21026800};
        static logic[31:0] fifo_data8[$]  = {32'h0cf40948, 32'h21026800};
        static logic[31:0] fifo_data9[$]  = {32'h1c000958, 32'h809a2040};

        // Tx FIFO data - BM1391
        static logic[31:0] fifo_data10[$] = {32'h00000941, 32'hAB009313};
        static logic[31:0] fifo_data11[$] = {32'h08000941, 32'h1102B840};
        static logic[31:0] fifo_data12[$] = {32'h1C240941, 32'h00009801};
        static logic[31:0] fifo_data13[$] = {32'h08AB0941, 32'h1102B840};
        static logic[31:0] fifo_data14[$] = {32'h70AB0941, 32'h090F0F0F};
        static logic[31:0] fifo_data15[$] = {32'h14000951, 32'hFC000000};
        static logic[31:0] fifo_data16[$] = {32'h3C000951, 32'hAA84AA00};
        static logic[31:0] fifo_data17[$] = {32'h3C000951, 32'h04800080};
        static logic[31:0] fifo_data18[$] = {32'h60000951, 32'h773F1080};

        // reference data send out through UART - BM1387
        static logic[7:0] uart_data1[$]  = {8'h48, 8'h09, 8'h00, 8'h0c, 8'h00, 8'h68, 8'h02, 8'h21, 8'h02};
        static logic[7:0] uart_data2[$]  = {8'h48, 8'h09, 8'h04, 8'h0c, 8'h00, 8'h68, 8'h02, 8'h21, 8'h19};
        static logic[7:0] uart_data3[$]  = {8'h48, 8'h09, 8'h08, 8'h0c, 8'h00, 8'h68, 8'h02, 8'h21, 8'h11};
        static logic[7:0] uart_data4[$]  = {8'h48, 8'h09, 8'h0c, 8'h0c, 8'h00, 8'h68, 8'h02, 8'h21, 8'h0a};
        static logic[7:0] uart_data5[$]  = {8'h48, 8'h09, 8'he8, 8'h0c, 8'h00, 8'h68, 8'h02, 8'h21, 8'h03};
        static logic[7:0] uart_data6[$]  = {8'h48, 8'h09, 8'hec, 8'h0c, 8'h00, 8'h68, 8'h02, 8'h21, 8'h18};
        static logic[7:0] uart_data7[$]  = {8'h48, 8'h09, 8'hf0, 8'h0c, 8'h00, 8'h68, 8'h02, 8'h21, 8'h13};
        static logic[7:0] uart_data8[$]  = {8'h48, 8'h09, 8'hf4, 8'h0c, 8'h00, 8'h68, 8'h02, 8'h21, 8'h08};
        static logic[7:0] uart_data9[$]  = {8'h58, 8'h09, 8'h00, 8'h1c, 8'h40, 8'h20, 8'h9a, 8'h80, 8'h00};

        // reference data send out through UART - BM1391
        static logic[7:0] uart_data10[$] = {8'h41, 8'h09, 8'h00, 8'h00, 8'h13, 8'h93, 8'h00, 8'hAB, 8'h08};
        static logic[7:0] uart_data11[$] = {8'h41, 8'h09, 8'h00, 8'h08, 8'h40, 8'hB8, 8'h02, 8'h11, 8'h06};
        static logic[7:0] uart_data12[$] = {8'h41, 8'h09, 8'h24, 8'h1C, 8'h01, 8'h98, 8'h00, 8'h00, 8'h0B};
        static logic[7:0] uart_data13[$] = {8'h41, 8'h09, 8'hAB, 8'h08, 8'h40, 8'hB8, 8'h02, 8'h11, 8'h09};
        static logic[7:0] uart_data14[$] = {8'h41, 8'h09, 8'hAB, 8'h70, 8'h0F, 8'h0F, 8'h0F, 8'h09, 8'h16};
        static logic[7:0] uart_data15[$] = {8'h51, 8'h09, 8'h00, 8'h14, 8'h00, 8'h00, 8'h00, 8'hFC, 8'h07};
        static logic[7:0] uart_data16[$] = {8'h51, 8'h09, 8'h00, 8'h3C, 8'h00, 8'hAA, 8'h84, 8'hAA, 8'h00};
        static logic[7:0] uart_data17[$] = {8'h51, 8'h09, 8'h00, 8'h3C, 8'h80, 8'h00, 8'h80, 8'h04, 8'h1C};
        static logic[7:0] uart_data18[$] = {8'h51, 8'h09, 8'h00, 8'h60, 8'h80, 8'h10, 8'h3F, 8'h77, 8'h17};

        $display("Testcase 1b: send 9 bytes commands");
        // test sequences - BM1387
        fifo_write_cmd(fifo_data1);
        uart_read_and_compare(uart_data1);

        fifo_write_cmd(fifo_data2);
        uart_read_and_compare(uart_data2);

        fifo_write_cmd(fifo_data3);
        uart_read_and_compare(uart_data3);

        fifo_write_cmd(fifo_data4);
        uart_read_and_compare(uart_data4);

        fifo_write_cmd(fifo_data5);
        uart_read_and_compare(uart_data5);

        fifo_write_cmd(fifo_data6);
        uart_read_and_compare(uart_data6);

        fifo_write_cmd(fifo_data7);
        uart_read_and_compare(uart_data7);

        fifo_write_cmd(fifo_data8);
        uart_read_and_compare(uart_data8);

        fifo_write_cmd(fifo_data9);
        uart_read_and_compare(uart_data9);

        // test sequences - BM1391
        fifo_write_cmd(fifo_data10);
        uart_read_and_compare(uart_data10);

        fifo_write_cmd(fifo_data11);
        uart_read_and_compare(uart_data11);

        fifo_write_cmd(fifo_data12);
        uart_read_and_compare(uart_data12);

        fifo_write_cmd(fifo_data13);
        uart_read_and_compare(uart_data13);

        fifo_write_cmd(fifo_data14);
        uart_read_and_compare(uart_data14);

        fifo_write_cmd(fifo_data15);
        uart_read_and_compare(uart_data15);

        fifo_write_cmd(fifo_data16);
        uart_read_and_compare(uart_data16);

        fifo_write_cmd(fifo_data17);
        uart_read_and_compare(uart_data17);

        fifo_write_cmd(fifo_data18);
        uart_read_and_compare(uart_data18);
    endtask


    // ---------------------------------------------------------------------------------------------
    // Testcase 2: Test of send works
    // ---------------------------------------------------------------------------------------------
    // send 1 midstate work
    task tc_send_work_midstate1();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {
            32'h00000000, 32'hffffffff, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        static logic[31:0] fifo_data2[$] = {
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };
        static logic[31:0] fifo_data3[$] = {
            32'h00000001, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h36, 8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff,
            8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h5f, 8'hd3
        };
        static logic[7:0] uart_data2[$] = {
            8'h21, 8'h36, 8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h98, 8'h99
        };
        static logic[7:0] uart_data3[$] = {
            8'h21, 8'h36, 8'h01, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h8A, 8'hEF
        };

        $display("Testcase 2a: send 1 midstate work");

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_1);

        fifo_write_work(fifo_data1);
        uart_read_and_compare(uart_data1);

        fifo_write_work(fifo_data2);
        uart_read_and_compare(uart_data2);

        fifo_write_work(fifo_data3);
        uart_read_and_compare(uart_data3);
    endtask

    // ---------------------------------------------------------------------------------------------
    // send 2 midstates work
    task tc_send_work_midstate2();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {
            32'h00000000, 32'h1725FD03, 32'h5D0B7D52, 32'hDE474074, 32'h41E79803, 32'h634A932B,
            32'hD79AE784, 32'hFE7179A6, 32'h1FF0CCD2, 32'h07D0C195, 32'hC34829B3, 32'h8A307647,
            32'hBEB7E7F6, 32'h00DE500F, 32'h01E28ACF, 32'h7A97E115, 32'hA3893221, 32'h27B159FE,
            32'hDC0C2081, 32'h7294FEF6
        };
        static logic[31:0] fifo_data2[$] = {
            32'h00000002, 32'h1725FD03, 32'h5D0B7D52, 32'h7EF3CD65, 32'h9E003640, 32'hED70F53C,
            32'hC597ECC5, 32'h0B2E3408, 32'h326E5C9C, 32'hD36AF7C1, 32'h7FF0843B, 32'h9FC1E0B2,
            32'h4EEB0F38, 32'h238575B5, 32'h18DBE987, 32'h04C97447, 32'h790136AF, 32'h8C7B9D8B,
            32'h973A66E6, 32'h7BB43DD7
        };
        static logic[31:0] fifo_data3[$] = {
            32'h00000004, 32'h1725FD03, 32'h5D0B7D52, 32'hAF4FCB3F, 32'hE6CCA966, 32'hA3C8A9AD,
            32'h4C870CA0, 32'hF5936186, 32'h32537329, 32'hE312877B, 32'h823F4AB2, 32'hE0120430,
            32'h8A99E318, 32'h945A4E22, 32'h5E2CE432, 32'hFAF51137, 32'h4DCAE52C, 32'hF1820DAB,
            32'hDDC2D7CF, 32'h028E9504
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h56, 8'h00, 8'h02, 8'h00, 8'h00, 8'h00, 8'h00, 8'h03, 8'hFD, 8'h25, 8'h17,
            8'h52, 8'h7D, 8'h0B, 8'h5D, 8'h74, 8'h40, 8'h47, 8'hDE, 8'h41, 8'hE7, 8'h98, 8'h03,
            8'h63, 8'h4A, 8'h93, 8'h2B, 8'hD7, 8'h9A, 8'hE7, 8'h84, 8'hFE, 8'h71, 8'h79, 8'hA6,
            8'h1F, 8'hF0, 8'hCC, 8'hD2, 8'h07, 8'hD0, 8'hC1, 8'h95, 8'hC3, 8'h48, 8'h29, 8'hB3,
            8'h8A, 8'h30, 8'h76, 8'h47, 8'hBE, 8'hB7, 8'hE7, 8'hF6, 8'h00, 8'hDE, 8'h50, 8'h0F,
            8'h01, 8'hE2, 8'h8A, 8'hCF, 8'h7A, 8'h97, 8'hE1, 8'h15, 8'hA3, 8'h89, 8'h32, 8'h21,
            8'h27, 8'hB1, 8'h59, 8'hFE, 8'hDC, 8'h0C, 8'h20, 8'h81, 8'h72, 8'h94, 8'hFE, 8'hF6,
            8'hC1, 8'h18
        };
        static logic[7:0] uart_data2[$] = {
            8'h21, 8'h56, 8'h02, 8'h02, 8'h00, 8'h00, 8'h00, 8'h00, 8'h03, 8'hFD, 8'h25, 8'h17,
            8'h52, 8'h7D, 8'h0B, 8'h5D, 8'h65, 8'hCD, 8'hF3, 8'h7E, 8'h9E, 8'h00, 8'h36, 8'h40,
            8'hED, 8'h70, 8'hF5, 8'h3C, 8'hC5, 8'h97, 8'hEC, 8'hC5, 8'h0B, 8'h2E, 8'h34, 8'h08,
            8'h32, 8'h6E, 8'h5C, 8'h9C, 8'hD3, 8'h6A, 8'hF7, 8'hC1, 8'h7F, 8'hF0, 8'h84, 8'h3B,
            8'h9F, 8'hC1, 8'hE0, 8'hB2, 8'h4E, 8'hEB, 8'h0F, 8'h38, 8'h23, 8'h85, 8'h75, 8'hB5,
            8'h18, 8'hDB, 8'hE9, 8'h87, 8'h04, 8'hC9, 8'h74, 8'h47, 8'h79, 8'h01, 8'h36, 8'hAF,
            8'h8C, 8'h7B, 8'h9D, 8'h8B, 8'h97, 8'h3A, 8'h66, 8'hE6, 8'h7B, 8'hB4, 8'h3D, 8'hD7,
            8'h4F, 8'h35
        };
        static logic[7:0] uart_data3[$] = {
            8'h21, 8'h56, 8'h04, 8'h02, 8'h00, 8'h00, 8'h00, 8'h00, 8'h03, 8'hFD, 8'h25, 8'h17,
            8'h52, 8'h7D, 8'h0B, 8'h5D, 8'h3F, 8'hCB, 8'h4F, 8'hAF, 8'hE6, 8'hCC, 8'hA9, 8'h66,
            8'hA3, 8'hC8, 8'hA9, 8'hAD, 8'h4C, 8'h87, 8'h0C, 8'hA0, 8'hF5, 8'h93, 8'h61, 8'h86,
            8'h32, 8'h53, 8'h73, 8'h29, 8'hE3, 8'h12, 8'h87, 8'h7B, 8'h82, 8'h3F, 8'h4A, 8'hB2,
            8'hE0, 8'h12, 8'h04, 8'h30, 8'h8A, 8'h99, 8'hE3, 8'h18, 8'h94, 8'h5A, 8'h4E, 8'h22,
            8'h5E, 8'h2C, 8'hE4, 8'h32, 8'hFA, 8'hF5, 8'h11, 8'h37, 8'h4D, 8'hCA, 8'hE5, 8'h2C,
            8'hF1, 8'h82, 8'h0D, 8'hAB, 8'hDD, 8'hC2, 8'hD7, 8'hCF, 8'h02, 8'h8E, 8'h95, 8'h04,
            8'hA6, 8'h62
        };

        $display("Testcase 2b: send 2 midstates work");

        // set 2 midstates mode
        enable_ip(CTRL_MIDSTATE_2);

        fifo_write_work(fifo_data1);
        uart_read_and_compare(uart_data1);

        fifo_write_work(fifo_data2);
        uart_read_and_compare(uart_data2);

        fifo_write_work(fifo_data3);
        uart_read_and_compare(uart_data3);
    endtask

    // ---------------------------------------------------------------------------------------------
    // send 4 midstates work
    task tc_send_work_midstate4();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {
            32'h00000031, 32'h17365a17, 32'h5b51c8e6, 32'h66014b9d, 32'h1df9f7a3, 32'hba9aca03,
            32'hc42b0a8c, 32'hd89fc91a, 32'h1046e72e, 32'h46a47e9a, 32'hf01c1b8e, 32'hebc3c539,
            32'he578935d, 32'hc6419d97, 32'h1ff8d327, 32'h7bf6698e, 32'hd757b9eb, 32'h980317d2,
            32'heafd359f, 32'h9544a768, 32'h0e1d09af, 32'hc9316c84, 32'h89bbde77, 32'hcb13866a,
            32'h805beaaa, 32'hffbbfdb1, 32'ha1b617a9, 32'ha81b497c, 32'h93c5272d, 32'hcd1b2770,
            32'h96ab3905, 32'h7bfafae3, 32'hf1004cdb, 32'hb08d4078, 32'hd82c00af, 32'he75b218b
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h96, 8'h31, 8'h04, 8'h00, 8'h00, 8'h00, 8'h00, 8'h17, 8'h5a, 8'h36, 8'h17,
            8'he6, 8'hc8, 8'h51, 8'h5b, 8'h9d, 8'h4b, 8'h01, 8'h66, 8'h1d, 8'hf9, 8'hf7, 8'ha3,
            8'hba, 8'h9a, 8'hca, 8'h03, 8'hc4, 8'h2b, 8'h0a, 8'h8c, 8'hd8, 8'h9f, 8'hc9, 8'h1a,
            8'h10, 8'h46, 8'he7, 8'h2e, 8'h46, 8'ha4, 8'h7e, 8'h9a, 8'hf0, 8'h1c, 8'h1b, 8'h8e,
            8'heb, 8'hc3, 8'hc5, 8'h39, 8'he5, 8'h78, 8'h93, 8'h5d, 8'hc6, 8'h41, 8'h9d, 8'h97,
            8'h1f, 8'hf8, 8'hd3, 8'h27, 8'h7b, 8'hf6, 8'h69, 8'h8e, 8'hd7, 8'h57, 8'hb9, 8'heb,
            8'h98, 8'h03, 8'h17, 8'hd2, 8'hea, 8'hfd, 8'h35, 8'h9f, 8'h95, 8'h44, 8'ha7, 8'h68,
            8'h0e, 8'h1d, 8'h09, 8'haf, 8'hc9, 8'h31, 8'h6c, 8'h84, 8'h89, 8'hbb, 8'hde, 8'h77,
            8'hcb, 8'h13, 8'h86, 8'h6a, 8'h80, 8'h5b, 8'hea, 8'haa, 8'hff, 8'hbb, 8'hfd, 8'hb1,
            8'ha1, 8'hb6, 8'h17, 8'ha9, 8'ha8, 8'h1b, 8'h49, 8'h7c, 8'h93, 8'hc5, 8'h27, 8'h2d,
            8'hcd, 8'h1b, 8'h27, 8'h70, 8'h96, 8'hab, 8'h39, 8'h05, 8'h7b, 8'hfa, 8'hfa, 8'he3,
            8'hf1, 8'h00, 8'h4c, 8'hdb, 8'hb0, 8'h8d, 8'h40, 8'h78, 8'hd8, 8'h2c, 8'h00, 8'haf,
            8'he7, 8'h5b, 8'h21, 8'h8b, 8'h37, 8'h0a
        };

        $display("Testcase 2c: send 4 midstates work");

        // set 4 midstates mode
        enable_ip(CTRL_MIDSTATE_4);

        fifo_write_work(fifo_data1);
        uart_read_and_compare(uart_data1);
    endtask

    // ---------------------------------------------------------------------------------------------
    // send command immediate after work
    task tc_send_cmd_after_work();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {32'h00000540};
        static logic[31:0] fifo_data2[$] = {
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };
        static logic[31:0] fifo_data3[$] = {32'h00030540};

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {8'h40, 8'h05, 8'h00, 8'h00, 8'h1C};
        static logic[7:0] uart_data2[$] = {
            8'h21, 8'h36, 8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h98, 8'h99
        };
        static logic[7:0] uart_data3[$] = {8'h40, 8'h05, 8'h03, 8'h00, 8'h1D};

        $display("Testcase 2d: send command after work");

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_1);

        // first send command "to dirty" CRC engine
        fifo_write_cmd(fifo_data1);
        uart_read_and_compare(uart_data1);

        // next send work request and another command immediate after work
        fifo_write_work(fifo_data2);
        fifo_write_cmd(fifo_data3);
        uart_read_and_compare(uart_data2);
        uart_read_and_compare(uart_data3);
    endtask


    // ---------------------------------------------------------------------------------------------
    // Testcase 3: Test of receive and check work and commands responses
    // ---------------------------------------------------------------------------------------------
    // receive of command response
    task tc_cmd_response();
        // data send through UART - BM1387
        static logic[7:0] uart_data1[$] = {8'h13, 8'h87, 8'h90, 8'h00, 8'h00, 8'h00, 8'h07};
        static logic[7:0] uart_data2[$] = {8'h13, 8'h87, 8'h90, 8'h04, 8'h00, 8'h00, 8'h10};
        static logic[7:0] uart_data3[$] = {8'h13, 8'h87, 8'h90, 8'h08, 8'h00, 8'h00, 8'h0c};
        static logic[7:0] uart_data4[$] = {8'h13, 8'h87, 8'h90, 8'h0c, 8'h00, 8'h00, 8'h1b};
        static logic[7:0] uart_data5[$] = {8'h13, 8'h87, 8'h90, 8'he8, 8'h00, 8'h00, 8'h16};
        static logic[7:0] uart_data6[$] = {8'h13, 8'h87, 8'h90, 8'hec, 8'h00, 8'h00, 8'h01};
        static logic[7:0] uart_data7[$] = {8'h13, 8'h87, 8'h90, 8'hf0, 8'h00, 8'h00, 8'h0b};
        static logic[7:0] uart_data8[$] = {8'h13, 8'h87, 8'h90, 8'hf4, 8'h00, 8'h00, 8'h1c};

        // data send through UART - BM1391
        static logic[7:0] uart_data9[$]  = {8'h00, 8'h00, 8'h61, 8'h31, 8'h24, 8'h18, 8'h1F};
        static logic[7:0] uart_data10[$] = {8'h01, 8'h00, 8'h00, 8'h00, 8'h24, 8'h1C, 8'h00};
        static logic[7:0] uart_data11[$] = {8'h01, 8'h98, 8'h00, 8'h5C, 8'h33, 8'h1C, 8'h16};
        static logic[7:0] uart_data12[$] = {8'h01, 8'h98, 8'h09, 8'h00, 8'h24, 8'h1C, 8'h1B};
        static logic[7:0] uart_data13[$] = {8'h13, 8'h91, 8'h00, 8'h00, 8'h00, 8'h00, 8'h05};
        static logic[7:0] uart_data14[$] = {8'h81, 8'h98, 8'h00, 8'h00, 8'h24, 8'h1C, 8'h17};
        static logic[7:0] uart_data15[$] = {8'h81, 8'h98, 8'h00, 8'h5C, 8'h33, 8'h1C, 8'h08};
        static logic[7:0] uart_data16[$] = {8'h81, 8'h98, 8'h09, 8'h00, 8'h24, 8'h1C, 8'h05};

        // reference Rx FIFO data - BM1387
        static logic[31:0] fifo_data1[$] = {32'h00908713, 32'h07000000};
        static logic[31:0] fifo_data2[$] = {32'h04908713, 32'h10000000};
        static logic[31:0] fifo_data3[$] = {32'h08908713, 32'h0c000000};
        static logic[31:0] fifo_data4[$] = {32'h0c908713, 32'h1b000000};
        static logic[31:0] fifo_data5[$] = {32'he8908713, 32'h16000000};
        static logic[31:0] fifo_data6[$] = {32'hec908713, 32'h01000000};
        static logic[31:0] fifo_data7[$] = {32'hf0908713, 32'h0b000000};
        static logic[31:0] fifo_data8[$] = {32'hf4908713, 32'h1c000000};

        // reference Rx FIFO data - BM1391
        static logic[31:0] fifo_data9[$]  = {32'h31610000, 32'h1F001824};
        static logic[31:0] fifo_data10[$] = {32'h00000001, 32'h00001C24};
        static logic[31:0] fifo_data11[$] = {32'h5C009801, 32'h16001C33};
        static logic[31:0] fifo_data12[$] = {32'h00099801, 32'h1B001C24};
        static logic[31:0] fifo_data13[$] = {32'h00009113, 32'h05000000};
        static logic[31:0] fifo_data14[$] = {32'h00009881, 32'h17001C24};
        static logic[31:0] fifo_data15[$] = {32'h5C009881, 32'h08001C33};
        static logic[31:0] fifo_data16[$] = {32'h00099881, 32'h05001C24};

        $display("Testcase 3a: command response");

        // test sequences - BM1387
        uart_send_data(uart_data1);
        fifo_read_and_compare_cmd(fifo_data1);

        uart_send_data(uart_data2);
        fifo_read_and_compare_cmd(fifo_data2);

        uart_send_data(uart_data3);
        fifo_read_and_compare_cmd(fifo_data3);

        uart_send_data(uart_data4);
        fifo_read_and_compare_cmd(fifo_data4);

        uart_send_data(uart_data5);
        fifo_read_and_compare_cmd(fifo_data5);

        uart_send_data(uart_data6);
        fifo_read_and_compare_cmd(fifo_data6);

        uart_send_data(uart_data7);
        fifo_read_and_compare_cmd(fifo_data7);

        uart_send_data(uart_data8);
        fifo_read_and_compare_cmd(fifo_data8);

        // test sequences - BM1391
        uart_send_data(uart_data9);
        fifo_read_and_compare_cmd(fifo_data9);

        uart_send_data(uart_data10);
        fifo_read_and_compare_cmd(fifo_data10);

        uart_send_data(uart_data11);
        fifo_read_and_compare_cmd(fifo_data11);

        uart_send_data(uart_data12);
        fifo_read_and_compare_cmd(fifo_data12);

        uart_send_data(uart_data13);
        fifo_read_and_compare_cmd(fifo_data13);

        uart_send_data(uart_data14);
        fifo_read_and_compare_cmd(fifo_data14);

        uart_send_data(uart_data15);
        fifo_read_and_compare_cmd(fifo_data15);

        uart_send_data(uart_data16);
        fifo_read_and_compare_cmd(fifo_data16);
    endtask


    // ---------------------------------------------------------------------------------------------
    // receive of work response
    task tc_work_response();
        // data send through UART - BM1387
        static logic[7:0] uart_data1[$] = {8'h72, 8'h03, 8'hea, 8'h83, 8'h00, 8'h03, 8'h98};
        static logic[7:0] uart_data2[$] = {8'h72, 8'h03, 8'hea, 8'h83, 8'h00, 8'h04, 8'h9e};
        static logic[7:0] uart_data3[$] = {8'h72, 8'h03, 8'hea, 8'h83, 8'h00, 8'h05, 8'h93};
        static logic[7:0] uart_data4[$] = {8'h72, 8'h03, 8'hea, 8'h83, 8'h00, 8'h06, 8'h84};
        static logic[7:0] uart_data5[$] = {8'he1, 8'h6b, 8'hf8, 8'h09, 8'h01, 8'h6f, 8'h9c};
        static logic[7:0] uart_data6[$] = {8'h72, 8'h03, 8'hea, 8'h83, 8'h00, 8'h70, 8'h80};
        static logic[7:0] uart_data7[$] = {8'he1, 8'h6b, 8'hf8, 8'h09, 8'h01, 8'h70, 8'h93};
        static logic[7:0] uart_data8[$] = {8'h72, 8'h03, 8'hea, 8'h83, 8'h00, 8'h71, 8'h8d};
        static logic[7:0] uart_data9[$] = {8'h48, 8'h06, 8'h3c, 8'h08, 8'h00, 8'h12, 8'h99};

        // data send through UART - BM1391
        static logic[7:0] uart_data10[$] = {8'h01, 8'h51, 8'h37, 8'h82, 8'h00, 8'h2D, 8'h90};
        static logic[7:0] uart_data11[$] = {8'h1C, 8'h0D, 8'h4F, 8'h78, 8'h02, 8'h3D, 8'h93};
        static logic[7:0] uart_data12[$] = {8'h25, 8'h19, 8'hF7, 8'h93, 8'h00, 8'h31, 8'h9B};
        static logic[7:0] uart_data13[$] = {8'h45, 8'h74, 8'h06, 8'h89, 8'h00, 8'h70, 8'h90};
        static logic[7:0] uart_data14[$] = {8'h63, 8'hBD, 8'hC7, 8'hA3, 8'h03, 8'h7C, 8'h8E};
        static logic[7:0] uart_data15[$] = {8'h99, 8'h2E, 8'hE4, 8'hB2, 8'h01, 8'h22, 8'h99};
        static logic[7:0] uart_data16[$] = {8'hAB, 8'hA9, 8'h3B, 8'h2C, 8'h04, 8'h4F, 8'h92};
        static logic[7:0] uart_data17[$] = {8'hC9, 8'hB7, 8'h30, 8'hDA, 8'h01, 8'h12, 8'h8B};
        static logic[7:0] uart_data18[$] = {8'hD5, 8'h84, 8'hC3, 8'hE1, 8'h01, 8'h13, 8'h9D};

        // reference Rx FIFO data - BM1387 - the real value depends on the last work ID
        static logic[31:0] fifo_data1[$] = {32'h83ea0372, 32'h98000300};
        static logic[31:0] fifo_data2[$] = {32'h83ea0372, 32'h9e000400};
        static logic[31:0] fifo_data3[$] = {32'h83ea0372, 32'h93000500};
        static logic[31:0] fifo_data4[$] = {32'h83ea0372, 32'h84000600};
        static logic[31:0] fifo_data5[$] = {32'h09f86be1, 32'h9c006f01};
        static logic[31:0] fifo_data6[$] = {32'h83ea0372, 32'h80007000};
        static logic[31:0] fifo_data7[$] = {32'h09f86be1, 32'h93007001};
        static logic[31:0] fifo_data8[$] = {32'h83ea0372, 32'h8d007100};
        static logic[31:0] fifo_data9[$] = {32'h083c0648, 32'h99001200};

        // reference Rx FIFO data - BM1391 - the real value depends on the last work ID
        static logic[31:0] fifo_data10[$] = {32'h82375101, 32'h90002D00};
        static logic[31:0] fifo_data11[$] = {32'h784F0D1C, 32'h93003D02};
        static logic[31:0] fifo_data12[$] = {32'h93F71925, 32'h9B003100};
        static logic[31:0] fifo_data13[$] = {32'h89067445, 32'h90007000};
        static logic[31:0] fifo_data14[$] = {32'hA3C7BD63, 32'h8E007C03};
        static logic[31:0] fifo_data15[$] = {32'hB2E42E99, 32'h99002201};
        static logic[31:0] fifo_data16[$] = {32'h2C3BA9AB, 32'h92004F04};
        static logic[31:0] fifo_data17[$] = {32'hDA30B7C9, 32'h8B001201};
        static logic[31:0] fifo_data18[$] = {32'hE1C384D5, 32'h9D001301};

        $display("Testcase 3b: work response");

        // test sequences - BM1387

        // initialization of work ID to max. value
        init_work_id();

        uart_send_data(uart_data1);
        fifo_read_and_compare_work(fifo_data1);

        uart_send_data(uart_data2);
        fifo_read_and_compare_work(fifo_data2);

        uart_send_data(uart_data3);
        fifo_read_and_compare_work(fifo_data3);

        uart_send_data(uart_data4);
        fifo_read_and_compare_work(fifo_data4);

        uart_send_data(uart_data5);
        fifo_read_and_compare_work(fifo_data5);

        uart_send_data(uart_data6);
        fifo_read_and_compare_work(fifo_data6);

        uart_send_data(uart_data7);
        fifo_read_and_compare_work(fifo_data7);

        uart_send_data(uart_data8);
        fifo_read_and_compare_work(fifo_data8);

        uart_send_data(uart_data9);
        fifo_read_and_compare_work(fifo_data9);

        // test sequences - BM1391

        // initialization of work ID to max. value
        init_work_id();

        uart_send_data(uart_data10);
        fifo_read_and_compare_work(fifo_data10);

        uart_send_data(uart_data11);
        fifo_read_and_compare_work(fifo_data11);

        uart_send_data(uart_data12);
        fifo_read_and_compare_work(fifo_data12);

        uart_send_data(uart_data13);
        fifo_read_and_compare_work(fifo_data13);

        uart_send_data(uart_data14);
        fifo_read_and_compare_work(fifo_data14);

        uart_send_data(uart_data15);
        fifo_read_and_compare_work(fifo_data15);

        uart_send_data(uart_data16);
        fifo_read_and_compare_work(fifo_data16);

        uart_send_data(uart_data17);
        fifo_read_and_compare_work(fifo_data17);

        uart_send_data(uart_data18);
        fifo_read_and_compare_work(fifo_data18);
    endtask


    // ---------------------------------------------------------------------------------------------
    // Testcase 4: Test of FIFO reset/flags
    // ---------------------------------------------------------------------------------------------
    // test of FIFOs reset and flags, command RX FIFO
    task tc_fifo_cmd_rx();
        // data send through UART
        static logic[7:0] uart_data1[$] = {8'h13, 8'h87, 8'h90, 8'hf4, 8'h00, 8'h00, 8'h1c};

        $display("Testcase 4a: FIFO reset/flags, command RX FIFO");

        // check if FIFO is empty
        check_status(CMD_STAT_REG, STAT_RX_EMPTY, 1'b1, "FIFO is not empty");

        // send data
        uart_send_data(uart_data1);

        // check if FIFO is not empty
        check_status(CMD_STAT_REG, STAT_RX_EMPTY, 1'b0, "FIFO is empty after write");

        // reset of FIFO
        axi_write(CMD_CTRL_REG, CTRL_RST_RX_FIFO);

        // wait for work time
        #1us;

        // check if FIFO is empty
        check_status(CMD_STAT_REG, STAT_RX_EMPTY, 1'b1, "FIFO is not empty after reset");

        // check IRQ flags
        check_irq_flags(3'b001, "FIFO reset");
    endtask

    // ---------------------------------------------------------------------------------------------
    // test of FIFOs reset and flags, command TX FIFO
    task tc_fifo_cmd_tx();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {32'h00000554};
        static logic[31:0] fifo_data2[$] = {32'h00000555};

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {8'h54, 8'h05, 8'h00, 8'h00, 8'h19};

        $display("Testcase 4b: FIFO reset/flags, command TX FIFO");

        // check if FIFO is empty
        check_status(CMD_STAT_REG, STAT_TX_EMPTY, 1'b1, "FIFO is not empty");

        // send data
        fifo_write_cmd(fifo_data1);
        fifo_write_cmd(fifo_data2);

        // wait for work time
        #900ns;

        // check if FIFO is not empty
        check_status(CMD_STAT_REG, STAT_TX_EMPTY, 1'b0, "FIFO is empty after write");

        // reset of FIFO
        axi_write(CMD_CTRL_REG, CTRL_RST_TX_FIFO);

        // wait for work time
        #900ns;

        // check if FIFO is empty
        check_status(CMD_STAT_REG, STAT_TX_EMPTY, 1'b1, "FIFO is not empty after reset");

        // check IRQ flags
        check_irq_flags(3'b001, "FIFO reset");

        // first command is sent but the second is deleted, so we can read the first
        uart_read_and_compare(uart_data1);
    endtask


    // ---------------------------------------------------------------------------------------------
    // test of FIFOs reset and flags, work response RX FIFO
    task tc_fifo_work_rx();
        // data send through UART
        static logic[7:0] uart_data1[$] = {8'h48, 8'h06, 8'h3c, 8'h08, 8'h00, 8'h12, 8'h99};

        $display("Testcase 4c: FIFO reset/flags, work RX FIFO");

        // check if FIFO is empty
        check_status(WORK_RX_STAT_REG, STAT_RX_EMPTY, 1'b1, "FIFO is not empty");

        // send data
        uart_send_data(uart_data1);

        // check if FIFO is not empty
        check_status(WORK_RX_STAT_REG, STAT_RX_EMPTY, 1'b0, "FIFO is empty after write");

        // reset of FIFO
        axi_write(WORK_RX_CTRL_REG, CTRL_RST_RX_FIFO);

        // wait for work time
        #1us;

        // check if FIFO is empty
        check_status(WORK_RX_STAT_REG, STAT_RX_EMPTY, 1'b1, "FIFO is not empty after reset");

        // check IRQ flags
        check_irq_flags(3'b001, "FIFO reset");
    endtask

    // ---------------------------------------------------------------------------------------------
    // test of FIFOs reset and flags, work TX FIFO
    task tc_fifo_work_tx();
        // data are not complete - missing 6 words
        static logic[31:0] fifo_data1[$] = {
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        $display("Testcase 4d: FIFO reset/flags, work TX FIFO");

        // check if FIFO is empty
        check_status(WORK_TX_STAT_REG, STAT_TX_EMPTY, 1'b1, "FIFO is not empty");

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_1);

        // send data
        fifo_write_work(fifo_data1);

        // check if FIFO is not empty
        check_status(WORK_TX_STAT_REG, STAT_TX_EMPTY, 1'b0, "FIFO is empty after write");

        // reset of FIFO
        axi_write(WORK_TX_CTRL_REG, CTRL_RST_TX_FIFO);

        // wait for work time
        #1us;

        // check if FIFO is empty
        check_status(WORK_TX_STAT_REG, STAT_TX_EMPTY, 1'b1, "FIFO is not empty after reset");

        // check IRQ flags
        check_irq_flags(3'b001, "FIFO reset");
    endtask


    // ---------------------------------------------------------------------------------------------
    // Testcase 5: Test of IRQs and status flags
    // ---------------------------------------------------------------------------------------------
    // test of IRQs - command RX
    task tc_irq_cmd_rx();
        // data send through UART
        static logic[7:0] uart_data1[$] = {8'h13, 8'h87, 8'h90, 8'hf4, 8'h00, 8'h00, 8'h1c};
        // reference Rx FIFO data
        static logic[31:0] fifo_data1[$] = {32'hf4908713, 32'h1c000000};

        $display("Testcase 5a: IRQ RX command response");

        // check IRQ ports and flags
        check_irq(3'b000, 3'b001, "initial state");

        // send data through UART
        uart_send_data(uart_data1);

        // check IRQ ports and flags - IRQ should be zero because IRQ is disabled
        check_irq(3'b000, 3'b101, "IRQ is disabled");

        // read data
        fifo_read_and_compare_cmd(fifo_data1);

        // enable IRQ
        axi_write(CMD_CTRL_REG, CTRL_IRQ_EN);

         // check IRQ ports and flags
        check_irq(3'b000, 3'b001, "no data has been send yet");

        // send data through UART
        uart_send_data(uart_data1);

        // check IRQ ports and flags - should be one because IRQ is enabled
        check_irq(3'b100, 3'b101, "data has been send");

        // read data
        fifo_read_and_compare_cmd(fifo_data1);

        // check IRQ ports and flags
        check_irq(3'b000, 3'b001, "all data already read");

        // disable IRQ
        axi_write(CMD_CTRL_REG, 0);
    endtask

    // ---------------------------------------------------------------------------------------------
    // test of IRQs - work RX
    task tc_irq_work_rx();
        // data send through UART
        static logic[7:0] uart_data1[$] = {8'h48, 8'h06, 8'h3c, 8'h08, 8'h00, 8'h12, 8'h99};
        // reference Rx FIFO data - the real value depends on the last work ID !!!
        static logic[31:0] fifo_data1[$] = {32'h083c0648, 32'h99001200};

        $display("Testcase 5b: IRQ RX work response");

        // initialization of work ID to max. value
        init_work_id();

        // check IRQ ports
        check_irq(3'b000, 3'b001, "initial state");

        // send data through UART
        uart_send_data(uart_data1);

        // check IRQ ports and flags - IRQ should be zero because IRQ is disabled
        check_irq(3'b000, 3'b011, "IRQ is disabled");

        // read data
        fifo_read_and_compare_work(fifo_data1);

        // enable IRQ
        axi_write(WORK_RX_CTRL_REG, CTRL_IRQ_EN);

         // check IRQ ports
        check_irq(3'b000, 3'b001, "no data has been send yet");

        // send data through UART
        uart_send_data(uart_data1);

        // check IRQ ports - should be one because IRQ is enabled
        check_irq(3'b010, 3'b011, "data has been send");

        // read data
        fifo_read_and_compare_work(fifo_data1);

         // check IRQ ports
        check_irq(3'b000, 3'b001, "all data already read");

        // disable IRQ
        axi_write(WORK_RX_CTRL_REG, 0);
    endtask

    // ---------------------------------------------------------------------------------------------
    // test of IRQs - work TX
    task tc_irq_work_tx();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {
            32'h00000000, 32'hffffffff, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h36, 8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff,
            8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h5f, 8'hd3
        };

        // temporary unpacked array
        static logic[31:0] tmp[$];

        $display("Testcase 5c: IRQ TX work");

        // check IRQ ports
        check_irq(3'b000, 3'b001, "initial state");

        // set 1 midstate mode, IRQ enabled
        enable_ip(CTRL_MIDSTATE_1);
        axi_write(WORK_TX_CTRL_REG, CTRL_IRQ_EN);
        // set IRQ threshold in words
        axi_write(WORK_TX_IRQ_THR, 6);

        // check IRQ ports
        check_irq(3'b001, 3'b001, "IRQ enabled");

        // send first part of data
        fifo_write_work(fifo_data1[0:4]);

        // check IRQ ports
        check_irq(3'b001, 3'b001, "not enough data in FIFO");

        // send one word to switch IRQ threshold
        tmp.push_back(fifo_data1[5]);
        fifo_write_work(tmp);

        // check IRQ ports
        check_irq(3'b000, 3'b000, "enough data in FIFO");

        // send rest of data
        fifo_write_work(fifo_data1[6:fifo_data1.size-1]);

        // check IRQ ports
        check_irq(3'b000, 3'b000, "all data are in FIFO");

        // wait until send is completed + check data
        uart_read_and_compare(uart_data1);

        // check IRQ ports
        check_irq(3'b001, 3'b001, "FIFO is again empty");

        // disable IRQ
        axi_write(WORK_TX_CTRL_REG, 0);
    endtask

    // ---------------------------------------------------------------------------------------------
    // Testcase 6: Test of last work ID
    // ---------------------------------------------------------------------------------------------
    // response has the same work ID as last work
    task tc_work_id_1();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {
            32'h00000000, 32'hffffffff, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h36, 8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff,
            8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h5f, 8'hd3
        };

        // response send through UART
        static logic[7:0] uart_data2[$] = {8'h48, 8'h06, 8'h3c, 8'h08, 8'h00, 8'h00, 8'h8d};

        // reference Rx FIFO data
        static logic[31:0] fifo_data2[$] = {32'h083c0648, 32'h8d000000};

        $display("Testcase 6a: work ID, response with same ID");

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_1);

        fifo_write_work(fifo_data1);
        uart_read_and_compare(uart_data1);

        // send work response
        uart_send_data(uart_data2);
        fifo_read_and_compare_work(fifo_data2);
    endtask

    // ---------------------------------------------------------------------------------------------
    // response has the same work ID as last work, full range
    task tc_work_id_2();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {
            32'h0000cdef, 32'hffffffff, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h36, 8'h6f, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff,
            8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'ha7
        };

        // response send through UART
        static logic[7:0] uart_data2[$] = {8'h48, 8'h06, 8'h3c, 8'h08, 8'h00, 8'h6f, 8'h8d};

        // reference Rx FIFO data
        static logic[31:0] fifo_data2[$] = {32'h083c0648, 32'h8dcdef00};

        $display("Testcase 6b: work ID, response with same ID, full range");

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_1);

        fifo_write_work(fifo_data1);
        uart_read_and_compare(uart_data1);

        // send work response
        uart_send_data(uart_data2);
        fifo_read_and_compare_work(fifo_data2);
    endtask

    // ---------------------------------------------------------------------------------------------
    // response has smaller work ID then last work
    task tc_work_id_3();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {
            32'h00001234, 32'hffffffff, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h36, 8'h34, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff,
            8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h4f, 8'hc8
        };

        // response send through UART
        static logic[7:0] uart_data2[$] = {8'h48, 8'h06, 8'h3c, 8'h08, 8'h00, 8'h30, 8'h9f};

        // reference Rx FIFO data
        static logic[31:0] fifo_data2[$] = {32'h083c0648, 32'h9f123000};

        $display("Testcase 6c: work ID, response with smaller ID then last work");

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_1);

        fifo_write_work(fifo_data1);
        uart_read_and_compare(uart_data1);

        // send work response
        uart_send_data(uart_data2);
        fifo_read_and_compare_work(fifo_data2);
    endtask

    // ---------------------------------------------------------------------------------------------
    // response has higher work ID then last work (should not happen in real HW)
    task tc_work_id_4();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {
            32'h00001234, 32'hffffffff, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h36, 8'h34, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff,
            8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h4f, 8'hc8
        };

        // response send through UART
        static logic[7:0] uart_data2[$] = {8'h48, 8'h06, 8'h3c, 8'h08, 8'h00, 8'h40, 8'h90};

        // reference Rx FIFO data
        static logic[31:0] fifo_data2[$] = {32'h083c0648, 32'h9011c000};

        $display("Testcase 6d: work ID, response with higher ID then last work");

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_1);

        fifo_write_work(fifo_data1);
        uart_read_and_compare(uart_data1);

        // send work response
        uart_send_data(uart_data2);
        fifo_read_and_compare_work(fifo_data2);
    endtask

    // ---------------------------------------------------------------------------------------------
    // 4-midstates work with response with higher work ID (non-zero LSBs)
    task tc_work_id_5();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {
            32'h000001c8, 32'h1723792c, 32'h5d17465b, 32'h4333e7e0, 32'hd4bc85da, 32'h7863cc7f,
            32'h23f45071, 32'hf19935b9, 32'h0cbad1ee, 32'h34ddb024, 32'hf7cb2156, 32'h7cf30c02,
            32'h727b2484, 32'h2dbb3bfe, 32'h0bfe2494, 32'h1768bc7c, 32'h152c83c0, 32'hc815bc0e,
            32'had9fe9b6, 32'hcf2b40de, 32'hbad64745, 32'hf8d5f8b5, 32'hbfc7b016, 32'h24de8d40,
            32'hcef2fedb, 32'h71b9e01c, 32'hbbee9e79, 32'hfa07537f, 32'h319c9437, 32'he267d889,
            32'h8a4c93f0, 32'h0d4cb8d1, 32'h32357b3b, 32'h0842afd9, 32'h5483e2d9, 32'h3f751430
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h96, 8'h48, 8'h04, 8'h00, 8'h00, 8'h00, 8'h00, 8'h2c, 8'h79, 8'h23, 8'h17,
            8'h5b, 8'h46, 8'h17, 8'h5d, 8'he0, 8'he7, 8'h33, 8'h43, 8'hd4, 8'hbc, 8'h85, 8'hda,
            8'h78, 8'h63, 8'hcc, 8'h7f, 8'h23, 8'hf4, 8'h50, 8'h71, 8'hf1, 8'h99, 8'h35, 8'hb9,
            8'h0c, 8'hba, 8'hd1, 8'hee, 8'h34, 8'hdd, 8'hb0, 8'h24, 8'hf7, 8'hcb, 8'h21, 8'h56,
            8'h7c, 8'hf3, 8'h0c, 8'h02, 8'h72, 8'h7b, 8'h24, 8'h84, 8'h2d, 8'hbb, 8'h3b, 8'hfe,
            8'h0b, 8'hfe, 8'h24, 8'h94, 8'h17, 8'h68, 8'hbc, 8'h7c, 8'h15, 8'h2c, 8'h83, 8'hc0,
            8'hc8, 8'h15, 8'hbc, 8'h0e, 8'had, 8'h9f, 8'he9, 8'hb6, 8'hcf, 8'h2b, 8'h40, 8'hde,
            8'hba, 8'hd6, 8'h47, 8'h45, 8'hf8, 8'hd5, 8'hf8, 8'hb5, 8'hbf, 8'hc7, 8'hb0, 8'h16,
            8'h24, 8'hde, 8'h8d, 8'h40, 8'hce, 8'hf2, 8'hfe, 8'hdb, 8'h71, 8'hb9, 8'he0, 8'h1c,
            8'hbb, 8'hee, 8'h9e, 8'h79, 8'hfa, 8'h07, 8'h53, 8'h7f, 8'h31, 8'h9c, 8'h94, 8'h37,
            8'he2, 8'h67, 8'hd8, 8'h89, 8'h8a, 8'h4c, 8'h93, 8'hf0, 8'h0d, 8'h4c, 8'hb8, 8'hd1,
            8'h32, 8'h35, 8'h7b, 8'h3b, 8'h08, 8'h42, 8'haf, 8'hd9, 8'h54, 8'h83, 8'he2, 8'hd9,
            8'h3f, 8'h75, 8'h14, 8'h30, 8'h9b, 8'hc2
        };


        // response send through UART
        static logic[7:0] uart_data2[$] = {8'h20, 8'haa, 8'hd8, 8'he0, 8'h3f, 8'h49 , 8'h90};

        // reference Rx FIFO data
        static logic[31:0] fifo_data2[$] = {32'he0d8aa20, 32'h9001c93f};

        $display("Testcase 6e: work ID, 4-midstates work, response with non-zero work ID LSBs");

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_4);

        fifo_write_work(fifo_data1);
        uart_read_and_compare(uart_data1);

        // send work response
        uart_send_data(uart_data2);
        fifo_read_and_compare_work(fifo_data2);
    endtask


    // ---------------------------------------------------------------------------------------------
    // Testcase 7: Test of reset of IP core by enable flag
    // ---------------------------------------------------------------------------------------------
    // test of IP core reset, command RX FIFO
    task tc_ip_core_reset_1();
        // data send through UART - not complete!
        static logic[7:0] uart_data1[$] = {8'h13, 8'h87, 8'h90, 8'h00, 8'h00, 8'h00};
        // data send through UART - complete
        static logic[7:0] uart_data2[$] = {8'h13, 8'h87, 8'h90, 8'hf4, 8'h00, 8'h00, 8'h1c};

        // reference Rx FIFO data
        static logic[31:0] fifo_data2[$] = {32'hf4908713, 32'h1c000000};

        automatic int rdata = 0;

        $display("Testcase 7a: IP core reset, command RX FIFO");

        // check if FIFO is empty
        check_status(CMD_STAT_REG, STAT_RX_EMPTY, 1'b1, "FIFO is not empty");

        // send data
        uart_send_data(uart_data1);

        // check if FIFO is still empty
        check_status(CMD_STAT_REG, STAT_RX_EMPTY, 1'b1, "FIFO is not empty after partial write");

        // reset of IP core
        disable_ip();
        enable_ip(CTRL_MIDSTATE_1);

        // check if FIFO is empty
        check_status(CMD_STAT_REG, STAT_RX_EMPTY, 1'b1, "FIFO is not empty after IP core reset");

        // check IRQ flags
        check_irq_flags(3'b001, "IP core reset");

        // send and check new data
        uart_send_data(uart_data2);
        fifo_read_and_compare_cmd(fifo_data2);

        // check error counter - should be zero
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'h0, rdata, "ERR_COUNTER");
    endtask

    // ---------------------------------------------------------------------------------------------
    // test of IP core reset, command TX FIFO
    task tc_ip_core_reset_2();
        // Tx FIFO data - not complete!
        static logic[31:0] fifo_data1[$] = {32'h0c000948};
        // complete
        static logic[31:0] fifo_data2[$] = {32'h14000958, 32'h00000000};

        // reference data send out through UART
        static logic[7:0] uart_data2[$] = {8'h58, 8'h09, 8'h00, 8'h14, 8'h00, 8'h00, 8'h00, 8'h00, 8'h0a};

        automatic int rdata = 0;

        $display("Testcase 7b: IP core reset, command TX FIFO");

        // check if FIFO is empty
        check_status(CMD_STAT_REG, STAT_TX_EMPTY, 1'b1, "FIFO is not empty");

        // send data
        fifo_write_cmd(fifo_data1);

        // check if FIFO is still empty
        check_status(CMD_STAT_REG, STAT_TX_EMPTY, 1'b0, "FIFO is empty after partial write");

        // reset of IP core
        disable_ip();
        enable_ip(CTRL_MIDSTATE_1);

        // check if FIFO is empty
        check_status(CMD_STAT_REG, STAT_TX_EMPTY, 1'b1, "FIFO is not empty after IP core reset");

        // check IRQ flags
        check_irq_flags(3'b001, "IP core reset");

        // send and check new data
        fifo_write_cmd(fifo_data2);
        uart_read_and_compare(uart_data2);

        // check error counter - should be zero
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'h0, rdata, "ERR_COUNTER");
    endtask

    // ---------------------------------------------------------------------------------------------
    // test of IP core reset, work response RX FIFO
    task tc_ip_core_reset_3();
        // data send through UART - not complete
        static logic[7:0] uart_data1[$] = {8'h72, 8'h03, 8'hea, 8'h83, 8'h00, 8'h03};
        // complete
        static logic[7:0] uart_data2[$] = {8'h48, 8'h06, 8'h3c, 8'h08, 8'h00, 8'h12, 8'h99};

        // reference Rx FIFO data - the real value depends on the last work ID
        static logic[31:0] fifo_data2[$] = {32'h083c0648, 32'h99001200};

        automatic int rdata = 0;

        $display("Testcase 7c: IP core reset, work RX FIFO");

        // initialization of work ID to max. value
        init_work_id();

        // check if FIFO is empty
        check_status(WORK_RX_STAT_REG, STAT_RX_EMPTY, 1'b1, "FIFO is not empty");

        // send data
        uart_send_data(uart_data1);

        // check if FIFO is still empty
        check_status(WORK_RX_STAT_REG, STAT_RX_EMPTY, 1'b1, "FIFO is empty after partial write");

        // reset of IP core
        disable_ip();
        enable_ip(CTRL_MIDSTATE_1);

        // check if FIFO is empty
        check_status(WORK_RX_STAT_REG, STAT_RX_EMPTY, 1'b1, "FIFO is not empty after reset");

        // check IRQ flags
        check_irq_flags(3'b001, "IP core reset");

        // send and check new data
        uart_send_data(uart_data2);
        fifo_read_and_compare_work(fifo_data2);

        // check error counter - should be zero
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'h0, rdata, "ERR_COUNTER");
    endtask

    // ---------------------------------------------------------------------------------------------
    // test of IP core reset, work TX FIFO
    task tc_ip_core_reset_4();
        // data are not complete - missing 5 words
        static logic[31:0] fifo_data1[$] = {
            32'h00001234, 32'h11111111, 32'h22222222, 32'h33333333, 32'h44444444, 32'h55555555
        };

        // Tx FIFO data - complete
        static logic[31:0] fifo_data2[$] = {
            32'h00000000, 32'hffffffff, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        // reference data send out through UART
        static logic[7:0] uart_data2[$] = {
            8'h21, 8'h36, 8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff,
            8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h5f, 8'hd3
        };

        automatic int rdata = 0;

        $display("Testcase 7d: IP core reset, work TX FIFO");

        // check if FIFO is empty
        check_status(WORK_TX_STAT_REG, STAT_TX_EMPTY, 1'b1, "FIFO is not empty");

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_1);

        // send data
        fifo_write_work(fifo_data1);

        // check if FIFO is not empty
        check_status(WORK_TX_STAT_REG, STAT_TX_EMPTY, 1'b0, "FIFO is empty after write");

        // reset of IP core
        disable_ip();
        enable_ip(CTRL_MIDSTATE_1);

        // check if FIFO is empty
        check_status(WORK_TX_STAT_REG, STAT_TX_EMPTY, 1'b1, "FIFO is not empty after reset");

        // check IRQ flags
        check_irq_flags(3'b001, "IP core reset");

        // send and check new data
        fifo_write_work(fifo_data2);
        uart_read_and_compare(uart_data2);

        // check error counter - should be zero
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'h0, rdata, "ERR_COUNTER");
    endtask


    // ---------------------------------------------------------------------------------------------
    // Testcase 8: Test error counter register
    // ---------------------------------------------------------------------------------------------
    // test of frames woth wrong CRC
    task tc_error_counter_1();
        // data send through UART - command response, wrong CRC (should be 8'h1c)
        static logic[7:0] uart_data1[$] = {8'h13, 8'h87, 8'h90, 8'hf4, 8'h00, 8'h00, 8'h1d};

        // data send through UART - work response, wrong CRC (should be 8'h99)
        static logic[7:0] uart_data2[$] = {8'h48, 8'h06, 8'h3c, 8'h08, 8'h00, 8'h12, 8'h98};

        automatic int rdata = 0;

        $display("Testcase 8a: error counter register, wrong CRC");

        // check if register is zero
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'h0, rdata, "ERR_COUNTER");

        // clear error counter register
        clear_err_cnt();

        // send corrupted command response
        uart_send_data(uart_data1);

        // check if counter is incremented and FIFO is empty
        axi_read(ERR_COUNTER, rdata);
        // one wrong byte received - CRC byte
        compare_data(32'h1, rdata, "ERR_COUNTER");
        check_status(CMD_STAT_REG, STAT_RX_EMPTY, 1'b1, "RX command FIFO is not empty");

        // send corrupted work response
        uart_send_data(uart_data2);

        // check if counter is incremented and FIFO is empty
        axi_read(ERR_COUNTER, rdata);

        // number of errors depends on mode
`ifdef BM139X
        // nine wrong bytes received - whole message
        compare_data(32'd10, rdata, "ERR_COUNTER");
`else
        // seven wrong bytes received - whole message
        compare_data(32'd8, rdata, "ERR_COUNTER");
`endif

        check_status(WORK_RX_STAT_REG, STAT_RX_EMPTY, 1'b1, "RX work FIFO is not empty");

        // clear error counter register
        clear_err_cnt();

        // check if register is zero
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'h0, rdata, "ERR_COUNTER");

        // reset IP core
        disable_ip();
        enable_ip(CTRL_MIDSTATE_1);
    endtask

    // ---------------------------------------------------------------------------------------------
    // test of receiving incomplete frame
    task tc_error_counter_2();
        // data send through UART - unexpected data
        static logic[7:0] uart_data1[$] = {8'he1, 8'h40, 8'h00, 8'h00};

        // data send through UART - work response
        static logic[7:0] uart_data2[$] = {8'h72, 8'h03, 8'hea, 8'h83, 8'h00, 8'h39, 8'h97};

        automatic int rdata = 0;

        $display("Testcase 8b: error counter register, incomplete frame");

        // check if register is zero
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'h0, rdata, "ERR_COUNTER");

        // clear error counter register
        clear_err_cnt();

        // send unexpected data
        uart_send_data(uart_data1);

        // send correct work response
        uart_send_data(uart_data2);

        // check if counter is incremented and FIFO is not empty
        axi_read(ERR_COUNTER, rdata);

        // number of errors depends on mode
`ifdef BM139X
        compare_data(32'd6, rdata, "ERR_COUNTER");
`else
        compare_data(32'd4, rdata, "ERR_COUNTER");
`endif

        check_status(WORK_RX_STAT_REG, STAT_RX_EMPTY, 1'b0, "RX work FIFO is empty");

        // clear error counter register by reset of IP core
        disable_ip();
        enable_ip(CTRL_MIDSTATE_1);

        // check if register is zero
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'h0, rdata, "ERR_COUNTER");
    endtask

    // ---------------------------------------------------------------------------------------------
    // test of error frame header
    task tc_error_counter_3();
        // data send through UART - unexpected data after first correct frame
        static logic[7:0] uart_data1[$] = {
            8'h72, 8'h03, 8'hea, 8'h83, 8'h00, 8'h39, 8'h97,
            8'h00, 8'hAA, 8'h00, 8'h55, 8'hAA
        };

        // data send through UART - work response
        static logic[7:0] uart_data2[$] = {8'h72, 8'h03, 8'hea, 8'h83, 8'h00, 8'h39, 8'h97};

        automatic int rdata = 0;

        $display("Testcase 8c: error counter register, unexpected header bytes");

        // check if register is zero
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'h0, rdata, "ERR_COUNTER");

        // clear error counter register
        clear_err_cnt();

        // send unexpected data
        uart_send_data(uart_data1);

        // send correct work response
        uart_send_data(uart_data2);

        // check if counter is incremented and FIFO is not empty
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'd4, rdata, "ERR_COUNTER");
        check_status(WORK_RX_STAT_REG, STAT_RX_EMPTY, 1'b0, "RX work FIFO is empty");

        // clear error counter register
        clear_err_cnt();

        // check if register is zero
        axi_read(ERR_COUNTER, rdata);
        compare_data(32'h0, rdata, "ERR_COUNTER");

        // reset IP core
        disable_ip();
        enable_ip(CTRL_MIDSTATE_1);
    endtask


    // ---------------------------------------------------------------------------------------------
    // Testcase 9: Test of baudrate speed change
    // ---------------------------------------------------------------------------------------------
    // Test of baudrate speed change and synchronization
    task tc_baudrate_sync();
        // Tx FIFO data
        static logic[31:0] fifo_data1[$] = {
            32'h00000000, 32'hffffffff, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h36, 8'h00, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff,
            8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h5f, 8'hd3
        };

        $display("Testcase 9a: baudrate speed change and synchronization");

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_1);

        // send work
        fifo_write_work(fifo_data1);

        // wait some time and change UART baudrate speed to 1.5625 MBd (@50MHz)
        # 1us;
        axi_write(BAUD_REG, 3);

        // check reference data that should be at previous speed
        uart_read_and_compare(uart_data1);

        // change speed of UART BFM
        i_uart.UART_PERIOD = 640ns;

        // send work frame again
        fifo_write_work(fifo_data1);
        uart_read_and_compare(uart_data1);

        // revert UART baudrate speed to 3.125 MBd (@50MHz)
        axi_write(BAUD_REG, 1);
    endtask


    // ---------------------------------------------------------------------------------------------
    //                               Auxiliary Functions
    // ---------------------------------------------------------------------------------------------
    // enable IP core for defined number of midstates
    task enable_ip(input logic[31:0] midstate);
`ifdef BM139X
        // enable IP core with BM139x mode
        axi_write(CTRL_REG, CTRL_ENABLE | CTRL_BM139X | midstate);
`else
        // enable IP core without BM139x mode
        axi_write(CTRL_REG, CTRL_ENABLE | midstate);
`endif
    endtask

    // ---------------------------------------------------------------------------------------------
    // disable IP core
    task disable_ip();
        axi_write(CTRL_REG, 32'h0);
    endtask

    // ---------------------------------------------------------------------------------------------
    // clear error counter
    task clear_err_cnt();
        automatic int rdata = 0;

        // read content of control register
        axi_read(CTRL_REG, rdata);

        // write back data and clear error counter
        axi_write(CTRL_REG, rdata | CTRL_ERR_CNT_CLEAR);
    endtask

    // ---------------------------------------------------------------------------------------------
    // AXI write word
    task axi_read(input logic[31:0] addr, output logic[31:0] rdata);
        automatic xil_axi_prot_t protectionType = 3'b000;
        automatic xil_axi_resp_t bresp;

        mst_agent.AXI4LITE_READ_BURST(addr, protectionType, rdata, bresp);

        if (VERBOSE_LEVEL > 0) begin
            $display("  %t: AXI read: addr 0x%h, data 0x%h, bresp %d", $time, addr, rdata, bresp);
        end

        if (bresp != 0) begin
            $display("  %t: ERROR: AXI read failed: addr 0x%h, data 0x%h, bresp %d", $time, addr, rdata, bresp);
        end
    endtask

    // ---------------------------------------------------------------------------------------------
    // AXI write word
    task axi_write(input logic[31:0] addr, input logic[31:0] wdata);
        automatic xil_axi_prot_t protectionType = 3'b000;
        automatic xil_axi_resp_t bresp;

        mst_agent.AXI4LITE_WRITE_BURST(addr, protectionType, wdata, bresp);

        if (VERBOSE_LEVEL > 0) begin
            $display("  %t: AXI write: addr 0x%h, data 0x%h, bresp %d", $time, addr, wdata, bresp);
        end

        if (bresp != 0) begin
            $display("  %t: ERROR: AXI write failed: addr 0x%h, data 0x%h, bresp %d", $time, addr, wdata, bresp);
        end
    endtask

    // ---------------------------------------------------------------------------------------------
    task compare_data(input logic[31:0] expected, input logic[31:0] actual, string msg);
        if (expected === 'hx || actual === 'hx) begin
            $display("  %t: ERROR: %s: compare data cannot be performed - expected or actual data are 'x'", $time, msg);
            err_counter++;
        end else if (actual != expected) begin
            $display("  %t: ERROR: %s: data mismatch, expected = 0x%h, get = 0x%h", $time, msg, expected, actual);
            err_counter++;
        end
    endtask

    // ---------------------------------------------------------------------------------------------
    task uart_send_data(input logic[7:0] array[$]);
        // add header 0xAA, 0x55 if BM139x mode is enabled
`ifdef BM139X
        array.insert(0, 8'h55);
        array.insert(0, 8'hAA);
`endif

        for (int i = 0; i < array.size; i++) begin
            i_uart.send_frame_tx(array[i]);
        end
        // wait until CRC is calculated
        #(8 * array.size * CLK_PERIOD);
    endtask

    // ---------------------------------------------------------------------------------------------
    task uart_read_and_compare(input logic[7:0] expected[$]);
        automatic logic[7:0] rdata = 0;

        // add header 0x55, 0xAA if BM139x mode is enabled
`ifdef BM139X
        expected.insert(0, 8'hAA);
        expected.insert(0, 8'h55);
`endif

        for (int i = 0; i < expected.size; i++) begin
            // wait for trigger
            @(i_uart.ev_uart_rx.triggered);
            rdata = i_uart.rcv_data;
            compare_data(expected[i], rdata, "UART");
        end
    endtask

    // ---------------------------------------------------------------------------------------------
    task fifo_write_cmd(input logic[31:0] array[$]);
        for (int i = 0; i < array.size; i++) begin
            axi_write(CMD_TX_FIFO, array[i]);
        end
    endtask

    // ---------------------------------------------------------------------------------------------
    task fifo_write_work(input logic[31:0] array[$]);
        for (int i = 0; i < array.size; i++) begin
            axi_write(WORK_TX_FIFO, array[i]);
        end
    endtask

    // ---------------------------------------------------------------------------------------------
    task fifo_read_and_compare_cmd(input logic[31:0] expected[$]);
        automatic logic[31:0] rdata = 0;

        for (int i = 0; i < expected.size; i++) begin
            axi_read(CMD_RX_FIFO, rdata);
            if (VERBOSE_LEVEL > 0) begin
                $display("  %t: read cmd RX FIFO: 0x%h", $time, rdata);
            end
            compare_data(expected[i], rdata, "CMD_RX_FIFO");
        end
    endtask

    // ---------------------------------------------------------------------------------------------
    task fifo_read_and_compare_work(input logic[31:0] expected[$]);
        automatic logic[31:0] rdata = 0;

        for (int i = 0; i < expected.size; i++) begin
            axi_read(WORK_RX_FIFO, rdata);
            if (VERBOSE_LEVEL > 0) begin
                $display("  %t: read work RX FIFO: 0x%h", $time, rdata);
            end
            compare_data(expected[i], rdata, "WORK_RX_FIFO");
        end
    endtask

    // ---------------------------------------------------------------------------------------------
    // check of flag in status register
    task check_status(input logic[31:0] stat_reg, input logic[31:0] flag, bit expected, input string err_msg);
        static logic[31:0] rdata = 0;

        // read status register
        axi_read(stat_reg, rdata);

        // check flag
        if (((rdata & flag) != 0) != expected) begin
            $display("  %t: ERROR: %s", $time, err_msg);
            err_counter++;
        end
    endtask

    // ---------------------------------------------------------------------------------------------
    // check value of interrupt ports
    // expected value is concatenation of {irq_cmd_rx, irq_work_rx, irq_work_tx}
    task check_irq(logic[2:0] exp_ports, logic[2:0] exp_flags, string msg);
        if (irq_cmd_rx !== exp_ports[2]) begin
            $display("  %t: ERROR: irq_cmd_rx should be %d (%s)", $time, exp_ports[2], msg);
            err_counter++;
        end

        if (irq_work_rx !== exp_ports[1]) begin
            $display("  %t: ERROR: irq_work_rx should be %d (%s)", $time, exp_ports[1], msg);
            err_counter++;
        end

        if (irq_work_tx !== exp_ports[0]) begin
            $display("  %t: ERROR: irq_work_tx should be %d (%s)", $time, exp_ports[0], msg);
            err_counter++;
        end

        // check status flags
        check_irq_flags(exp_flags, msg);
    endtask

    // ---------------------------------------------------------------------------------------------
    // check interrupt flags in status register
    // expected value is concatenation of {irq_cmd_rx, irq_work_rx, irq_work_tx}
    task check_irq_flags(logic[2:0] exp_flags, string msg);
        static logic[31:0] rdata = 0;

        // read status register
        axi_read(CMD_STAT_REG, rdata);

        if (((rdata & STAT_IRQ_PEND) != 0) != exp_flags[2]) begin
            $display("  %t: ERROR: CMD_STAT_REG.IRQ_PEND flag should be %d (%s)", $time, exp_flags[2], msg);
            err_counter++;
        end

        // read status register
        axi_read(WORK_RX_STAT_REG, rdata);

        if (((rdata & STAT_IRQ_PEND) != 0) != exp_flags[1]) begin
            $display("  %t: ERROR: WORK_RX_STAT_REG.IRQ_PEND flag should be %d (%s)", $time, exp_flags[1], msg);
            err_counter++;
        end

        // read status register
        axi_read(WORK_TX_STAT_REG, rdata);

        if (((rdata & STAT_IRQ_PEND) != 0) != exp_flags[0]) begin
            $display("  %t: ERROR: WORK_TX_STAT_REG.IRQ_PEND flag should be %d (%s)", $time, exp_flags[0], msg);
            err_counter++;
        end
    endtask

    // ---------------------------------------------------------------------------------------------
    // initialization of work ID to max. value
    task init_work_id();
        // Tx FIFO data - to set correct work ID
        static logic[31:0] fifo_data1[$] = {
            32'h0000007f, 32'hffffffff, 32'hffffffff, 32'hffffffff, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000, 32'h00000000
        };

        // reference data send out through UART
        static logic[7:0] uart_data1[$] = {
            8'h21, 8'h36, 8'h7f, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'hff, 8'hff, 8'hff, 8'hff,
            8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'hff, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00,
            8'h00, 8'h00, 8'h00, 8'h00, 8'h37, 8'he6
        };

        // set 1 midstate mode
        enable_ip(CTRL_MIDSTATE_1);

        fifo_write_work(fifo_data1);
        uart_read_and_compare(uart_data1);
    endtask

endmodule
