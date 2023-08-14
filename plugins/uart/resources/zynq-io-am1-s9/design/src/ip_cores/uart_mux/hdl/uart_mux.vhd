----------------------------------------------------------------------------------------------------
-- Copyright (C) 2019  Braiins Systems s.r.o.
--
-- This file is part of Braiins Open-Source Initiative (BOSI).
--
-- BOSI is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
--
-- Please, keep in mind that we may also license BOSI or any part thereof
-- under a proprietary license. For more information on the terms and conditions
-- of such proprietary license or if you have any other questions, please
-- contact us at opensource@braiins.com.
----------------------------------------------------------------------------------------------------
-- Project Name:   Braiins OS
-- Description:    UART Multiplexer with Fan Inputs
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (30.11.2019)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_mux is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;

        -- FPGA IO
        io_rxd    : in  std_logic;
        io_txd    : inout std_logic;

        -- Control signal
        uart_ctrl : in  std_logic;

        -- UART interface
        rxd       : in  std_logic;
        txd       : out std_logic;

        -- Fan sense outputs
        fan       : out std_logic_vector(1 downto 0)
    );
end uart_mux;

architecture rtl of uart_mux is

    ------------------------------------------------------------------------------------------------
    -- synchronization input signal into clock domain
    signal io_rxd_q : std_logic_vector(2 downto 0);
    signal io_txd_q : std_logic_vector(2 downto 0);

begin

    ------------------------------------------------------------------------------------------------
    -- synchronization input signal into clock domain
    p_input_sync: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                io_rxd_q <= (others => '1');
                io_txd_q <= (others => '1');
            else
                io_rxd_q <= io_rxd & io_rxd_q(2 downto 1);
                io_txd_q <= io_txd & io_txd_q(2 downto 1);
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- Fan Multiplexer
    fan <= io_txd_q(0) & io_rxd_q(0) when (uart_ctrl = '0') else (others => '0');

    -- UART Multiplexer
    txd <= io_rxd_q(0) when (uart_ctrl = '1') else '1';

    -- FPGA IO driver
    io_txd <= rxd when (uart_ctrl = '1') else 'Z';

end rtl;
