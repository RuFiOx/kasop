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
-- Description:    Debouncer with Posedge Detection
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (11.10.2019)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity debouncer is
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;

        -- Input data
        input   : in  std_logic;

        -- Output data - pulse on positive edge
        output  : out std_logic
    );
end debouncer;

architecture rtl of debouncer is

    ------------------------------------------------------------------------------------------------
    -- synchronization input signal into clock domain
    signal input_q    : std_logic_vector(2 downto 0);

    ------------------------------------------------------------------------------------------------
    -- counter, 100us @ 50MHz -> 13 bits
    signal cnt_d      : unsigned(12 downto 0);
    signal cnt_q      : unsigned(12 downto 0);

    -- FSM type and signals declaration
    type fsm_type_t is (st_low, st_high);
    signal fsm_d      : fsm_type_t;
    signal fsm_q      : fsm_type_t;

    -- Output register
    signal output_d   : std_logic;
    signal output_q   : std_logic;

begin

    ------------------------------------------------------------------------------------------------
    -- synchronization input signal into clock domain
    p_input_sync: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                input_q <= (others => '1');
            else
                input_q <= input & input_q(2 downto 1);
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- sequential part of FSM (state register)
    p_fsm_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                fsm_q <= st_low;
                cnt_q <= (others => '0');
                output_q <= '0';
            else
                fsm_q <= fsm_d;
                cnt_q <= cnt_d;
                output_q <= output_d;
            end if;
        end if;
    end process;

    -- combinational part of FSM (next-state logic)
    p_fsm_cmb: process (fsm_q, input_q, cnt_q) begin

        -- default assignment to registers and signals
        fsm_d <= fsm_q;
        cnt_d <= cnt_q;

        output_d <= '0';

        -- state machine
        case fsm_q is
            when st_low =>
                if (input_q(0) = '1') then
                    cnt_d <= cnt_q + 1;
                    if (cnt_q = 4999) then
                        fsm_d <= st_high;
                        output_d <= '1';
                        cnt_d <= (others => '0');
                    end if;
                else
                    cnt_d <= (others => '0');
                end if;

            when st_high =>
                if (input_q(0) = '0') then
                    cnt_d <= cnt_q + 1;
                    if (cnt_q = 4999) then
                        fsm_d <= st_low;
                        cnt_d <= (others => '0');
                    end if;
                else
                    cnt_d <= (others => '0');
                end if;
        end case;
    end process;

    ------------------------------------------------------------------------------------------------
    -- output signals
    output <= output_q;

end rtl;
