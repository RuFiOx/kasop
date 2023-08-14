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
-- Description:    PWM Generator for Fan with Fixed Frequency
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (16.10.2019)
-- Comments:       Frequency 25kHz, resolution 1%, duty cycle 0..100%, glitch-free output
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_gen is
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;

        -- Input value in range 0..100%
        value : in  std_logic_vector(6 downto 0);

        -- Output PWM signal
        pwm   : out std_logic
    );
end pwm_gen;

architecture rtl of pwm_gen is

    ------------------------------------------------------------------------------------------------
    -- latch for value to avoid glitches in output signal
    signal value_d   : unsigned(6 downto 0);
    signal value_q   : unsigned(6 downto 0);

    -- counter - base resolution, 2.5MHz = 0.4us @ 50MHz -> 5 bits
    signal cnt_d      : unsigned(4 downto 0);
    signal cnt_q      : unsigned(4 downto 0);

    signal cnt_done_d : std_logic;
    signal cnt_done_q : std_logic;

    -- counter - duty cycle, range 0..99 -> 7 bits
    signal cnt_dc_d   : unsigned(6 downto 0);
    signal cnt_dc_q   : unsigned(6 downto 0);

    -- Output register
    signal pwm_d      : std_logic;
    signal pwm_q      : std_logic;

begin

    ------------------------------------------------------------------------------------------------
    -- sequential part of modulo counter: 0.4us @ 50MHz
    -- latch for value to avoid glitches in output signal
    p_cnt_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                cnt_q <= (others => '0');
                cnt_done_q <= '0';
                value_q <= (others => '0');
            else
                cnt_q <= cnt_d;
                cnt_done_q <= cnt_done_d;
                value_q <= value_d;
            end if;
        end if;
    end process;

    -- combinational part of modulo counter (next-state logic)
    p_cnt_cmb: process (cnt_q, value_q, value) begin
        cnt_d <= cnt_q + 1;
        cnt_done_d <= '0';
        value_d <= value_q;

        if (cnt_q = 19) then
            cnt_d <= (others => '0');
            cnt_done_d <= '1';
            value_d <= unsigned(value);
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- sequential part of modulo counter: 0..99
    p_cnt_dc_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                cnt_dc_q <= (others => '0');
                pwm_q <= '0';
            else
                cnt_dc_q <= cnt_dc_d;
                pwm_q <= pwm_d;
            end if;
        end if;
    end process;

    -- combinational part of modulo counter (next-state logic)
    p_cnt_dc_cmb: process (cnt_dc_q, cnt_done_q) begin
        cnt_dc_d <= cnt_dc_q;

        if (cnt_done_q = '1') then
            cnt_dc_d <= cnt_dc_q + 1;
            if (cnt_dc_q = 99) then
                cnt_dc_d <= (others => '0');
            end if;
        end if;
    end process;

    -- PWM comparator
    pwm_d <= '1' when (cnt_dc_q < value_q) else '0';

    ------------------------------------------------------------------------------------------------
    -- output signals
    pwm <= pwm_q;

end rtl;
