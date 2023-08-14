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
 * Description:    UART Bus Functional Model
 *
 * Engineer:       Marian Pristach
 * Revision:       1.0.0 (23.09.2018)
 *
 * Comments:       Buadrate fixed to 3.125M
 **************************************************************************************************/

`timescale 1ns / 1ps

module uart_bfm(input logic rx, output logic tx);

    // Simulation parameters
    parameter VERBOSE_LEVEL = 0;
    time UART_PERIOD = 320ns;

    // local signals and registers
    int drive_tx = 0;
    logic tx_int = 1'b1;
    logic[7:0] rcv_data;
    event ev_uart_rx;

    task send_frame_tx(logic[7:0] tx_data);
        drive_tx = 1;
        tx_int = 1'b0;
        # UART_PERIOD;

        for (int i = 0; i < 8; i++) begin
            tx_int = tx_data [i];
            # UART_PERIOD;
        end

        tx_int = 1'b1;      // stop bit
        # UART_PERIOD;
        drive_tx = 0;
    endtask

    assign tx = drive_tx ? tx_int : 1'b1;

    // receiver
    always begin
        @(negedge(rx));     // wait for start bit
        #(UART_PERIOD/2);

        if (rx != 1'b0) begin
            $display(" UART monitor: ERROR: Start bit is too short!");
        end

        for (int cnt = 0; cnt < 8; ++cnt) begin
            #(UART_PERIOD)
            rcv_data[cnt]= rx;
        end

        #(UART_PERIOD);

        if (rx != 1'b1) begin
            $display(" UART monitor: ERROR: Missing stop bit!");
        end else begin
            if (VERBOSE_LEVEL > 0) begin
                $display(" UART monitor: received data 0x%h", rcv_data);
            end
            -> ev_uart_rx;
        end
    end

endmodule
