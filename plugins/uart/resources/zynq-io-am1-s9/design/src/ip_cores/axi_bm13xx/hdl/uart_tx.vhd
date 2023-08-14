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
-- Description:    UART Interface Transmitter Module
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (18.08.2018)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
    generic (
        DB  : integer := 8;    -- number of data bits
        SPB : integer := 16    -- number of samples per one bit
    );
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;

        -- clock enable signal from baud rate generator
        clk_en   : in  std_logic;

        -- UART interface
        txd      : out std_logic;

        -- internal interface
        tx_start : in  std_logic;
        tx_ready : out std_logic;
        tx_done  : out std_logic;
        tx_data  : in  std_logic_vector(DB-1 downto 0)
    );
end uart_tx ;

architecture rtl of uart_tx is

    -- bits counter, size depends on number of data bits
    signal bits_cnt_q    : unsigned(2 downto 0);
    signal bits_cnt_d    : unsigned(2 downto 0);

    -- samples counter, size depends on number of samples per one bit and number of stop bits
    signal samples_cnt_q : unsigned(3 downto 0);
    signal samples_cnt_d : unsigned(3 downto 0);

    -- data shift register, size depends on number of data bits
    signal data_q        : std_logic_vector(DB-1 downto 0);
    signal data_d        : std_logic_vector(DB-1 downto 0);

    -- register for output TxD signal
    signal txd_q         : std_logic;
    signal txd_d         : std_logic;

    -- FSM type and signals declaration
    type fsm_type_t is (st_idle, st_start, st_data, st_stop);
    signal fsm_d         : fsm_type_t;
    signal fsm_q         : fsm_type_t;

begin

    ------------------------------------------------------------------------------------------------
    -- sequential part of FSM (state register)
    p_fsm_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                fsm_q <= st_idle;
                bits_cnt_q <= (others => '0');
                samples_cnt_q <= (others => '0');
                data_q <= (others => '0');
            else
                fsm_q <= fsm_d;
                bits_cnt_q <= bits_cnt_d;
                samples_cnt_q <= samples_cnt_d;
                data_q <= data_d;
            end if;
        end if;
    end process;

    -- combinational part of FSM (next-state logic)
    p_fsm_cmb: process (fsm_q, bits_cnt_q, samples_cnt_q, data_q, tx_start, tx_data, clk_en) begin

        -- default assignment to registers and signals
        fsm_d <= fsm_q;
        bits_cnt_d <= bits_cnt_q;
        samples_cnt_d <= samples_cnt_q;
        data_d <= data_q;
        tx_done <= '0';
        tx_ready <= '0';

        -- state machine
        case fsm_q is
            when st_idle =>
                tx_ready <= '1';
                if (tx_start = '1') then
                    fsm_d <= st_start;
                    samples_cnt_d <= (others => '0');
                    data_d <= tx_data;
                end if;

            when st_start =>
                if (clk_en = '1') then
                    if (samples_cnt_q = (SPB-1)) then
                        fsm_d <= st_data;
                        samples_cnt_d <= (others => '0');
                        bits_cnt_d <= (others => '0');
                    else
                        samples_cnt_d <= samples_cnt_q + 1;
                    end if;
                end if;

            when st_data =>
                if (clk_en = '1') then
                    if (samples_cnt_q = (SPB-1)) then
                        samples_cnt_d <= (others => '0');
                        data_d <= '0' & data_q(DB-1 downto 1);
                        if (bits_cnt_q = (DB-1)) then
                            fsm_d <= st_stop;
                        else
                            bits_cnt_d <= bits_cnt_q + 1;
                        end if;
                    else
                        samples_cnt_d <= samples_cnt_q + 1;
                    end if;
                end if;

            when st_stop =>
                if (clk_en = '1') then
                    if (samples_cnt_q = (SPB-1)) then
                        fsm_d <= st_idle;
                        tx_done <= '1';
                    else
                        samples_cnt_d <= samples_cnt_q + 1;
                    end if;
                end if;
        end case;
    end process;

    ------------------------------------------------------------------------------------------------
    -- TxD signal value - next-state logic
    txd_d <= data_q(0) when (fsm_q = st_data) else
             '0' when (fsm_q = st_start) else
             '1';

    -- TxD signal value - register; idle state on signal is high
    p_txd_reg: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                txd_q <= '1';
            else
                txd_q <= txd_d;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- output signals
    txd <= txd_q;

end rtl;
