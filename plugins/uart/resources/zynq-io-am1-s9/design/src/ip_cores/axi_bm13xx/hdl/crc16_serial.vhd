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
-- Description:    CRC-16 with Polynomial 0x1021, Serial Calculation per Bits
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (18.08.2018)
-- Comments:       Initial value 0xFFFF, no final xor
--                 MSB first of data_in, CRC results in direct order
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity crc16_serial is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;                        -- synchronous, active low
        clear   : in  std_logic;                        -- synchronous clear
        data_wr : in  std_logic;                        -- write enable
        data_in : in  std_logic_vector(7 downto 0);     -- input data
        ready   : out std_logic;                        -- crc engine is ready
        crc     : out std_logic_vector(15 downto 0)     -- crc-16 output
    );
end crc16_serial;


architecture rtl of crc16_serial is

    -- FSM type and signals declaration
    type fsm_type_t is (st_idle, st_calc);
    signal fsm_d        : fsm_type_t;
    signal fsm_q        : fsm_type_t;

    -- data shift register
    signal data_shift_d : std_logic_vector(7 downto 0);
    signal data_shift_q : std_logic_vector(7 downto 0);

    -- shift counter
    signal cnt_d        : unsigned(2 downto 0);
    signal cnt_q        : unsigned(2 downto 0);

    -- clock enable for CRC logic
    signal clk_en       : std_logic;

    -- input data xor MSB of crc_reg
    signal crc_in       : std_logic;

    -- internal register for calculation
    signal crc_reg      : std_logic_vector(15 downto 0);

begin

    ------------------------------------------------------------------------------------------------
    -- sequential part of FSM (state register)
    p_fsm_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                fsm_q <= st_idle;
                cnt_q <= (others => '0');
                data_shift_q <= (others => '0');
            else
                fsm_q <= fsm_d;
                cnt_q <= cnt_d;
                data_shift_q <= data_shift_d;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- combinational part of transmit FSM (next-state logic)
    p_fsm_cmb: process (fsm_q, cnt_q, data_shift_q, data_wr, data_in) begin

        -- default assignment to registers and signals
        fsm_d <= fsm_q;
        cnt_d <= cnt_q;
        data_shift_d <= data_shift_q;
        ready <= '0';
        clk_en <= '0';

        -- state machine
        case fsm_q is
            when st_idle =>
                ready <= '1';
                if (data_wr = '1') then
                    fsm_d <= st_calc;
                    cnt_d <= "111";
                    data_shift_d <= data_in;
                end if;

            when st_calc =>
                data_shift_d <= data_shift_q(6 downto 0) & '0';
                cnt_d <= cnt_q - 1;
                clk_en <= '1';
                if (cnt_q = "000") then
                    fsm_d <= st_idle;
                end if;

        end case;
    end process;


    ----------------------------------------------------------------------------------
    crc_in <= data_shift_q(7) xor crc_reg(15);

    ----------------------------------------------------------------------------------
    -- sequential part
    process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                crc_reg <= (others => '1');
            elsif (clear = '1') then
                crc_reg <= (others => '1');
            elsif (clk_en = '1') then
                crc_reg <= crc_reg(14 downto 0) & crc_in;       -- universal shift
                crc_reg(5) <= crc_reg(4) xor crc_in;            -- update bit based on crc polynom
                crc_reg(12) <= crc_reg(11) xor crc_in;          -- update bit based on crc polynom
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------------
    -- direct order
    crc <= crc_reg;

end rtl;

