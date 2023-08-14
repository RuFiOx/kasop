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
-- Description:    Fan Controller with Speed Monitoring
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (11.10.2019)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fan_ctrl_core is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;

        -- Input data from sensors
        fan_sense : in std_logic_vector(3 downto 0);

        -- Output data with speed
        fan1_rps  : out std_logic_vector(7 downto 0);
        fan2_rps  : out std_logic_vector(7 downto 0);
        fan3_rps  : out std_logic_vector(7 downto 0);
        fan4_rps  : out std_logic_vector(7 downto 0);

        -- Fan duty cycle input value
        pwm_value : in  std_logic_vector(6 downto 0);

        -- Fan PWM output signal
        pwm       : out std_logic
    );
end fan_ctrl_core;

architecture rtl of fan_ctrl_core is

    ------------------------------------------------------------------------------------------------
    -- definition of memory type
    type freq_array_t is array(0 to 3) of unsigned(7 downto 0);

    ------------------------------------------------------------------------------------------------
    -- output signals from debouncer with detected positive edge
    signal fan_posedge  : std_logic_vector(3 downto 0);

    -- counter, 500ms @ 50MHz -> 25 bits
    signal cnt_d        : unsigned(24 downto 0);
    signal cnt_q        : unsigned(24 downto 0);

    signal cnt_done_d   : std_logic;
    signal cnt_done_q   : std_logic;

    -- frequency counters - max. 15300 rpm
    signal freq_cnt_d   : freq_array_t;
    signal freq_cnt_q   : freq_array_t;

    -- frequency latch registers
    signal freq_q       : freq_array_t;

begin

    ------------------------------------------------------------------------------------------------
    -- sequential part of modulo counter: 500ms @ 50MHz
    p_cnt_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                cnt_q <= (others => '0');
                cnt_done_q <= '0';
            else
                cnt_q <= cnt_d;
                cnt_done_q <= cnt_done_d;
            end if;
        end if;
    end process;

    -- combinational part of modulo counter (next-state logic)
    p_cnt_cmb: process (cnt_q) begin
        cnt_d <= cnt_q + 1;
        cnt_done_d <= '0';
        if (cnt_q = 24999999) then
            cnt_d <= (others => '0');
            cnt_done_d <= '1';
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- debouncers
    g_debouncers: for i in 0 to 3 generate
        i_debouncer: entity work.debouncer
            port map (
                clk     => clk,
                rst     => rst,
                -- Input data
                input   => fan_sense(i),
                -- Output data - pulse on positive edge
                output  => fan_posedge(i)
            );
    end generate g_debouncers;

    ------------------------------------------------------------------------------------------------
    -- sequential part of counters
    p_counters_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                freq_cnt_q <= (others => (others => '0'));
            else
                freq_cnt_q <= freq_cnt_d;
            end if;
        end if;
    end process;

    -- combinational part of counters
    p_counters_cmb: process (cnt_done_q, fan_posedge, freq_cnt_q) begin
        freq_cnt_d <= freq_cnt_q;

        l_incr: for i in 0 to 3 loop
            if (fan_posedge(i) = '1') then
                freq_cnt_d(i) <= freq_cnt_q(i) + 1;
            end if;
        end loop;

        if (cnt_done_q = '1') then
            freq_cnt_d <= (others => (others => '0'));
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- latch registers
    p_latch_reg: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                freq_q <= (others => (others => '0'));
            elsif (cnt_done_q = '1' ) then
                freq_q <= freq_cnt_q;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- PWM generator
    i_pwm_gen: entity work.pwm_gen
        port map (
            clk   => clk,
            rst   => rst,

            -- Input value in range 0..100%
            value => pwm_value,

            -- Output PWM signal
            pwm   => pwm
        );


    ------------------------------------------------------------------------------------------------
    -- output signals
    fan1_rps <= std_logic_vector(freq_q(0));
    fan2_rps <= std_logic_vector(freq_q(1));
    fan3_rps <= std_logic_vector(freq_q(2));
    fan4_rps <= std_logic_vector(freq_q(3));

end rtl;
