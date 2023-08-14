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
-- Description:    FIFO buffer with asynchronous read using distributed memory
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (18.08.2018)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_distr is
    generic(
        A : natural := 5;           -- number of address bits
        W : natural := 8            -- number of data bits
    );
    port(
        clk    : in  std_logic;
        rst    : in  std_logic;     -- asynchronous reset, active low

        -- synchronous clear of FIFO
        clear  : in  std_logic;

        -- write port
        wr     : in  std_logic;
        full   : out std_logic;
        data_w : in  std_logic_vector(W-1 downto 0);

        -- read port
        rd     : in  std_logic;
        empty  : out std_logic;
        data_r : out std_logic_vector(W-1 downto 0)
    );
end fifo_distr;

architecture rtl of fifo_distr is

    -- definition of memory type
    type ram_t is array(0 to (2**A)-1) of std_logic_vector(W-1 downto 0);
    signal ram       : ram_t;

    -- internal read/write signals
    signal rd_en     : std_logic;
    signal wr_en     : std_logic;

    -- FIFO flags
    signal full_d    : std_logic;
    signal full_q    : std_logic;
    signal empty_d   : std_logic;
    signal empty_q   : std_logic;

    -- read pointer and signal with incremented value
    signal w_ptr_d   : unsigned(A-1 downto 0);
    signal w_ptr_q   : unsigned(A-1 downto 0);
    signal w_ptr_inc : unsigned(A-1 downto 0);

    -- write pointer and signal with incremented value
    signal r_ptr_d   : unsigned(A-1 downto 0);
    signal r_ptr_q   : unsigned(A-1 downto 0);
    signal r_ptr_inc : unsigned(A-1 downto 0);

    -- type of operation of the FIFO
    signal wr_op     : std_logic_vector(1 downto 0);

    -- local signals for read data
    signal data_r_d  : std_logic_vector(W-1 downto 0);

begin

    ------------------------------------------------------------------------------------------------
    -- read enabled only when FIFO is not empty
    rd_en <= rd and (not empty_q);

    -- write enabled only when FIFO is not full
    wr_en <= wr and (not full_q);

    ------------------------------------------------------------------------------------------------
    -- access to memory - write port
    p_write: process (clk) begin
        if rising_edge(clk) then
            if (wr_en = '1') then
                ram(to_integer(w_ptr_q)) <= data_w;
            end if;
        end if;
    end process;

    -- access to memory - read port
    data_r_d <= ram(to_integer(r_ptr_q));

    ------------------------------------------------------------------------------------------------
    -- incremented pointer values
    w_ptr_inc <= w_ptr_q + 1;
    r_ptr_inc <= r_ptr_q + 1;

    ------------------------------------------------------------------------------------------------
    -- registers for read/write pointers and flags
    p_regs: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                r_ptr_q <= (others => '0');
                w_ptr_q <= (others => '0');
                empty_q <= '1';
                full_q <= '0';
            else
                r_ptr_q <= r_ptr_d;
                w_ptr_q <= w_ptr_d;
                empty_q <= empty_d;
                full_q <= full_d;
            end if;
        end if;
    end process;

    -- type of operation
    wr_op <= wr_en & rd_en;

    ------------------------------------------------------------------------------------------------
    -- control logic
    p_comb: process (r_ptr_q, w_ptr_q, empty_q, full_q, wr_op, r_ptr_inc, w_ptr_inc, clear) begin
        r_ptr_d <= r_ptr_q;
        w_ptr_d <= w_ptr_q;
        empty_d <= empty_q;
        full_d <= full_q;

        case wr_op is
            when "01" =>
                r_ptr_d <= r_ptr_inc;
                full_d <= '0';
                if (r_ptr_inc = w_ptr_q) then
                    empty_d <= '1';
                end if;

            when "10" =>
                w_ptr_d <= w_ptr_inc;
                empty_d <= '0';
                if (w_ptr_inc = r_ptr_q) then
                    full_d <= '1';
                end if;

            when "11" =>
                r_ptr_d <= r_ptr_inc;
                w_ptr_d <= w_ptr_inc;

            when others =>
        end case;

        -- synchronous clear of FIFO with higher priority then read/write operations
        if (clear = '1') then
            r_ptr_d <= (others => '0');
            w_ptr_d <= (others => '0');
            empty_d <= '1';
            full_d <= '0';
        end if;

    end process;

    ------------------------------------------------------------------------------------------------
    -- output signals
    full <= full_q;
    empty <= empty_q;
    data_r <= data_r_d;

end rtl;
