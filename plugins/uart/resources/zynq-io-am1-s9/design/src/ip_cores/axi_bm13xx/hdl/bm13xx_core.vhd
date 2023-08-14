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
-- Description:    IP core for AXI BM13xx Interface
--
-- Engineer:       Marian Pristach
-- Revision:       1.1.0 (22.07.2019)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bm13xx_core is
    port (
        clk               : in  std_logic;
        rst               : in  std_logic;

        -- UART interface
        rxd               : in  std_logic;
        txd               : out std_logic;

        -- enable UART interface IO driver
        uart_en           : out std_logic;

        -- Interrupt Request
        irq_work_tx       : out std_logic;
        irq_work_rx       : out std_logic;
        irq_cmd_rx        : out std_logic;

        -- Signalization of work time delay
        work_time_ack     : out std_logic;

        -- Command FIFO read port
        cmd_rx_fifo_rd    : in  std_logic;
        cmd_rx_fifo_data  : out std_logic_vector(31 downto 0);

        -- Command FIFO write port
        cmd_tx_fifo_wr    : in  std_logic;
        cmd_tx_fifo_data  : in  std_logic_vector(31 downto 0);

        -- Work FIFO read port
        work_rx_fifo_rd   : in  std_logic;
        work_rx_fifo_data : out std_logic_vector(31 downto 0);

        -- Work FIFO write port
        work_tx_fifo_wr   : in  std_logic;
        work_tx_fifo_data : in  std_logic_vector(31 downto 0);

        -- Control Registers
        reg_ctrl          : in  std_logic_vector(4 downto 0);
        reg_ctrl_cmd      : in  std_logic_vector(2 downto 0);
        reg_ctrl_work_rx  : in  std_logic_vector(2 downto 0);
        reg_ctrl_work_tx  : in  std_logic_vector(2 downto 0);

        -- Status Registers
        reg_status_cmd     : out std_logic_vector(4 downto 0);
        reg_status_work_rx : out std_logic_vector(4 downto 0);
        reg_status_work_tx : out std_logic_vector(4 downto 0);

        -- UART baudrate divisor Register
        reg_uart_divisor   : in  std_logic_vector(11 downto 0);

        -- Work time delay Register
        reg_work_time      : in  std_logic_vector(23 downto 0);

        -- Threshold for Work Transmit FIFO IRQ
        reg_irq_fifo_thr   : in  std_logic_vector(10 downto 0);

        -- Error counter
        reg_err_counter    : out std_logic_vector(31 downto 0);

        -- Last Work ID send to ASICs
        reg_last_work_id   : out std_logic_vector(15 downto 0)
    );
end entity bm13xx_core;

architecture RTL of bm13xx_core is

    -- work delay counter
    signal work_time_cnt_d      : unsigned(23 downto 0);
    signal work_time_cnt_q      : unsigned(23 downto 0);

    -- buffered output signal
    signal work_time_out_clear  : std_logic;
    signal work_time_out_d      : std_logic;
    signal work_time_out_q      : std_logic;

    -- Tx FSM type and signals declaration
    type fsm_type_t is (
        st_idle, st_wait_sync, st_check,
        st_work_cmd_55, st_work_cmd_AA, st_work_cmd, st_work_length, st_work_id, st_work_optv,
        st_work_nonce, st_work_chunk2,
        st_work_midstate, st_work_crc16,
        st_cmd_read, st_cmd_check, st_cmd_check_1, st_cmd_55, st_cmd_AA, st_cmd_cmd, st_cmd_data,
        st_cmd_crc5
    );
    signal fsm_d                : fsm_type_t;
    signal fsm_q                : fsm_type_t;

    -- byte per word counter
    signal byte_cnt_d           : unsigned(1 downto 0);
    signal byte_cnt_q           : unsigned(1 downto 0);

    -- word counter
    signal word_cnt_d           : unsigned(4 downto 0);
    signal word_cnt_q           : unsigned(4 downto 0);

    -- value of rest bytes in the last word for commands
    signal byte_rest_d          : unsigned(1 downto 0);
    signal byte_rest_q          : unsigned(1 downto 0);

    -- extra work ID
    signal work_id              : std_logic_vector(15 downto 0);
    signal work_id_tx_d         : std_logic_vector(15 downto 0);
    signal work_id_tx_q         : std_logic_vector(15 downto 0);
    signal work_id_rx           : std_logic_vector(6 downto 0);
    signal work_id_rx_cmp       : std_logic_vector(6 downto 0);

    -- Rx FSM type and signals declaration
    type fsm_rx_type_t is (st_idle, st_wait, st_read_AA, st_read_55, st_read, st_calc_crc,
        st_check_crc, st_write_work1, st_write_work2, st_write_cmd1, st_write_cmd2, st_crc_err
    );
    signal fsm_rx_d             : fsm_rx_type_t;
    signal fsm_rx_q             : fsm_rx_type_t;

    -- definition of memory type
    type response_t is array(0 to 6) of std_logic_vector(7 downto 0);
    signal response_d           : response_t;
    signal response_q           : response_t;

    -- byte per word counter
    signal byte_cnt_rx_d        : unsigned(2 downto 0);
    signal byte_cnt_rx_q        : unsigned(2 downto 0);


    -- Control Register
    signal ctrl_bm139x          : std_logic;
    signal ctrl_enable          : std_logic;
    signal ctrl_midstate_cnt    : std_logic_vector(1 downto 0);
    signal ctrl_irq_en_work_rx  : std_logic;
    signal ctrl_irq_en_work_tx  : std_logic;
    signal ctrl_irq_en_cmd_rx   : std_logic;
    signal ctrl_err_cnt_clear   : std_logic;
    signal ctrl_rst_work_tx     : std_logic;
    signal ctrl_rst_work_rx     : std_logic;
    signal ctrl_rst_cmd_tx      : std_logic;
    signal ctrl_rst_cmd_rx      : std_logic;

    -- Command receive FIFO
    signal cmd_rx_fifo_wr       : std_logic;
    signal cmd_rx_fifo_full     : std_logic;
    signal cmd_rx_fifo_a_full   : std_logic;
    signal cmd_rx_fifo_data_w   : std_logic_vector(31 downto 0);
    signal cmd_rx_fifo_empty    : std_logic;

    -- Command transmit FIFO
    signal cmd_tx_fifo_full     : std_logic;
    signal cmd_tx_fifo_rd       : std_logic;
    signal cmd_tx_fifo_empty    : std_logic;
    signal cmd_tx_fifo_data_r   : std_logic_vector(31 downto 0);

    -- Work receive FIFO
    signal work_rx_fifo_wr      : std_logic;
    signal work_rx_fifo_full    : std_logic;
    signal work_rx_fifo_a_full  : std_logic;
    signal work_rx_fifo_data_w  : std_logic_vector(31 downto 0);
    signal work_rx_fifo_empty   : std_logic;

    -- Work transmit FIFO
    signal work_tx_fifo_full    : std_logic;
    signal work_tx_fifo_rd      : std_logic;
    signal work_tx_fifo_empty   : std_logic;
    signal work_tx_fifo_data_r  : std_logic_vector(31 downto 0);

    -- synchronous clear FIFOs
    signal uart_clear           : std_logic;

    -- UART FIFO read port
    signal uart_rx_read         : std_logic;
    signal uart_rx_empty        : std_logic;
    signal uart_rx_data_rd      : std_logic_vector(7 downto 0);

    -- UART FIFO write port
    signal uart_tx_write        : std_logic;
    signal uart_tx_full         : std_logic;
    signal uart_tx_data_wr      : std_logic_vector(7 downto 0);

    -- UART status
    signal uart_sync_busy       : std_logic;
    signal uart_frame_err       : std_logic;
    signal uart_over_err        : std_logic;

    -- Status Register
    signal irq_pending_work_rx_d : std_logic;
    signal irq_pending_work_rx_q : std_logic;
    signal irq_pending_work_tx   : std_logic;
    signal irq_pending_cmd_rx_d  : std_logic;
    signal irq_pending_cmd_rx_q  : std_logic;

    -- FIFO reset requests
    signal rst_fifo_work_tx     : std_logic;
    signal rst_fifo_work_rx     : std_logic;
    signal rst_fifo_cmd_tx      : std_logic;
    signal rst_fifo_cmd_rx      : std_logic;

    -- CRC5 signals for transmit
    signal crc5_tx_clear        : std_logic;
    signal crc5_tx_wr           : std_logic;
    signal crc5_tx_data         : std_logic_vector(7 downto 0);
    signal crc5_tx_ready        : std_logic;
    signal crc5_tx              : std_logic_vector(4 downto 0);

    -- CRC5 signals for receive
    signal crc5_rx_clear        : std_logic;
    signal crc5_rx_init         : std_logic_vector(4 downto 0);
    signal crc5_rx_wr           : std_logic;
    signal crc5_rx_data         : std_logic_vector(7 downto 0);
    signal crc5_rx_ready        : std_logic;
    signal crc5_rx_crc          : std_logic_vector(4 downto 0);

    -- CRC16 signals
    signal crc16_clear          : std_logic;
    signal crc16_wr             : std_logic;
    signal crc16_data           : std_logic_vector(7 downto 0);
    signal crc16_ready          : std_logic;
    signal crc16                : std_logic_vector(15 downto 0);

    -- check signals for FSM (uart_full/empty, crc_ready)
    signal work_ready           : std_logic;
    signal cmd_tx_ready         : std_logic;

    -- Rx header error (0xAA, 0x55), drop of result due to full FIFO
    signal receive_err          : std_logic;

    -- error counter
    signal err_cnt_q            : unsigned(31 downto 0);
    signal err_cnt_clear        : std_logic;

    -- work TX FIFO threshold for work send
    signal work_tx_fifo_thr_value : std_logic_vector(10 downto 0);
    signal work_tx_fifo_thr_ready : std_logic;

begin

    ------------------------------------------------------------------------------------------------
    -- sequential part of counter
    p_work_time_cnt: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                work_time_cnt_q <= (others => '0');
                work_time_out_q <= '0';
            else
                work_time_cnt_q <= work_time_cnt_d;
                work_time_out_q <= work_time_out_d;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- combinational part of counter
    process (work_time_cnt_q, work_time_out_q, reg_work_time, work_time_out_clear) begin
        work_time_cnt_d <= work_time_cnt_q - 1;
        work_time_out_d <= work_time_out_q;

        if (work_time_cnt_q = 0) then
            work_time_cnt_d <= unsigned(reg_work_time) - 1;
            work_time_out_d <= '1';
        end if;

        if (work_time_out_clear = '1') then
            work_time_out_d <= '0';
        end if;
    end process;


    ------------------------------------------------------------------------------------------------
    -- Control Registers
    ctrl_bm139x         <= reg_ctrl(4);
    ctrl_enable         <= reg_ctrl(3);
    ctrl_midstate_cnt   <= reg_ctrl(2 downto 1);
    ctrl_err_cnt_clear  <= reg_ctrl(0);

    ctrl_irq_en_cmd_rx  <= reg_ctrl_cmd(2);
    ctrl_rst_cmd_tx     <= reg_ctrl_cmd(1);
    ctrl_rst_cmd_rx     <= reg_ctrl_cmd(0);

    ctrl_irq_en_work_rx <= reg_ctrl_work_rx(2);
    ctrl_rst_work_rx    <= reg_ctrl_work_rx(0);

    ctrl_irq_en_work_tx <= reg_ctrl_work_tx(2);
    ctrl_rst_work_tx    <= reg_ctrl_work_tx(1);


    ------------------------------------------------------------------------------------------------
    work_ready   <= '1' when ((uart_tx_full = '0') and (crc16_ready = '1')) else '0';
    cmd_tx_ready <= '1' when ((uart_tx_full = '0') and (crc5_tx_ready = '1')) else '0';

    ------------------------------------------------------------------------------------------------
    -- sequential part of transmit FSM (state register)
    p_fsm_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                fsm_q <= st_idle;
                byte_cnt_q <= (others => '0');
                word_cnt_q <= (others => '0');
                byte_rest_q <= (others => '0');
                work_id_tx_q <= (others => '0');
            else
                fsm_q <= fsm_d;
                byte_cnt_q <= byte_cnt_d;
                word_cnt_q <= word_cnt_d;
                byte_rest_q <= byte_rest_d;
                work_id_tx_q <= work_id_tx_d;
            end if;
        end if;
    end process;

    -- combinational part of transmit FSM (next-state logic)
    p_fsm_cmb: process (fsm_q,
        ctrl_enable, ctrl_midstate_cnt,
        ctrl_rst_work_tx, ctrl_rst_work_rx, ctrl_rst_cmd_tx, ctrl_rst_cmd_rx,
        work_time_out_q, uart_sync_busy,
        work_tx_fifo_empty, work_tx_fifo_data_r, work_tx_fifo_thr_ready,
        cmd_tx_fifo_empty, cmd_tx_fifo_data_r,
        work_ready, cmd_tx_ready,
        byte_cnt_q, word_cnt_q, byte_rest_q, work_id_tx_q,
        crc5_tx, crc16, ctrl_bm139x
    ) begin

        -- default assignment to registers and signals
        fsm_d <= fsm_q;

        byte_cnt_d <= byte_cnt_q;
        word_cnt_d <= word_cnt_q;
        byte_rest_d <= byte_rest_q;
        work_id_tx_d <= work_id_tx_q;

        work_time_ack <= '0';
        err_cnt_clear <= '0';
        uart_clear <= '0';
        rst_fifo_work_tx <= '0';
        rst_fifo_work_rx <= '0';
        rst_fifo_cmd_tx  <= '0';
        rst_fifo_cmd_rx  <= '0';

        crc5_tx_clear <= '0';
        crc5_tx_wr <= '0';
        crc16_clear <= '0';
        crc16_wr <= '0';

        work_time_out_clear <= '0';
        work_tx_fifo_rd <= '0';
        cmd_tx_fifo_rd <= '0';
        uart_tx_write <= '0';
        uart_tx_data_wr <= (others => '0');

        -- state machine
        case fsm_q is
            when st_idle =>
                if (ctrl_enable = '1') then         -- wait for enable of IP core
                    fsm_d <= st_wait_sync;

                    -- reset error counter
                    err_cnt_clear <= '1';

                    -- reset UART FIFOs
                    uart_clear <= '1';

                    -- reset of all FIFOs
                    rst_fifo_work_tx <= '1';
                    rst_fifo_work_rx <= '1';
                    rst_fifo_cmd_tx  <= '1';
                    rst_fifo_cmd_rx  <= '1';
                end if;

            when st_wait_sync =>
                if ((work_time_out_q = '1') and (uart_sync_busy = '0')) then  -- wait for synchronization
                    fsm_d <= st_check;

                    work_time_ack <= '1';
                    work_time_out_clear <= '1';

                    -- reset of FIFOs if request
                    rst_fifo_work_tx <= ctrl_rst_work_tx;
                    rst_fifo_work_rx <= ctrl_rst_work_rx;
                    rst_fifo_cmd_tx  <= ctrl_rst_cmd_tx;
                    rst_fifo_cmd_rx  <= ctrl_rst_cmd_rx;
                end if;

            when st_check =>                        -- check of reset FIFOs, reload of baudrate, ...
                if (work_tx_fifo_thr_ready = '1') then    -- work has higher priority, start only when complete work is in FIFO
                    if (ctrl_bm139x = '1') then
                        fsm_d <= st_work_cmd_55;
                    else
                        fsm_d <= st_work_cmd;
                    end if;
                    crc16_clear <= '1';
                elsif (cmd_tx_fifo_empty = '0') then  -- control has lower priority
                    fsm_d <= st_cmd_read;
                else
                    fsm_d <= st_wait_sync;
                end if;

            when st_work_cmd_55 =>
                if (work_ready = '1') then
                    fsm_d <= st_work_cmd_AA;
                    uart_tx_write <= '1';
                    uart_tx_data_wr <= X"55";
                end if;

            when st_work_cmd_AA =>
                if (work_ready = '1') then
                    fsm_d <= st_work_cmd;
                    uart_tx_write <= '1';
                    uart_tx_data_wr <= X"AA";
                end if;

            when st_work_cmd =>
                if (work_ready = '1') then
                    fsm_d <= st_work_length;
                    uart_tx_write <= '1';
                    crc16_wr <= '1';
                    uart_tx_data_wr <= X"21";
                end if;

            when st_work_length =>
                if ((work_ready = '1') and (work_tx_fifo_empty = '0')) then
                    fsm_d <= st_work_id;
                    work_tx_fifo_rd <= '1';
                    uart_tx_write <= '1';
                    crc16_wr <= '1';
                    if (ctrl_midstate_cnt = "00") then
                        uart_tx_data_wr <= X"36";
                    elsif (ctrl_midstate_cnt = "01") then
                        uart_tx_data_wr <= X"56";
                    else
                        uart_tx_data_wr <= X"96";
                    end if;
                end if;

            when st_work_id =>
                if (work_ready = '1') then
                    fsm_d <= st_work_optv;
                    uart_tx_write <= '1';
                    crc16_wr <= '1';
                    uart_tx_data_wr <= '0' & work_tx_fifo_data_r(6 downto 0);
                    work_id_tx_d <= work_tx_fifo_data_r(15 downto 0);
                end if;

            when st_work_optv =>
                if (work_ready = '1') then
                    fsm_d <= st_work_nonce;
                    uart_tx_write <= '1';
                    crc16_wr <= '1';
                    byte_cnt_d <= "00";
                    if (ctrl_midstate_cnt = "00") then
                        uart_tx_data_wr <= X"01";
                    elsif (ctrl_midstate_cnt = "01") then
                        uart_tx_data_wr <= X"02";
                    else
                        uart_tx_data_wr <= X"04";
                    end if;
                end if;

            when st_work_nonce =>
                if ((work_ready = '1') and (work_tx_fifo_empty = '0')) then
                    uart_tx_write <= '1';
                    crc16_wr <= '1';
                    uart_tx_data_wr <= X"00";

                    byte_cnt_d <= byte_cnt_q + 1;

                    if (byte_cnt_q = "11") then
                        fsm_d <= st_work_chunk2;
                        work_tx_fifo_rd <= '1';
                        byte_cnt_d <= "00";
                        word_cnt_d <= "00010";    -- 3 words: nbits, ntime, merkle root[3..0]
                    end if;
                end if;

            when st_work_chunk2 =>
                if ((work_ready = '1') and (work_tx_fifo_empty = '0')) then
                    uart_tx_write <= '1';
                    crc16_wr <= '1';

                    byte_cnt_d <= byte_cnt_q + 1;

                    -- little endian
                    if (byte_cnt_q = "00") then
                        uart_tx_data_wr <= work_tx_fifo_data_r(7 downto 0);
                    elsif (byte_cnt_q = "01") then
                        uart_tx_data_wr <= work_tx_fifo_data_r(15 downto 8);
                    elsif (byte_cnt_q = "10") then
                        uart_tx_data_wr <= work_tx_fifo_data_r(23 downto 16);
                    else
                        uart_tx_data_wr <= work_tx_fifo_data_r(31 downto 24);
                    end if;

                    if (byte_cnt_q = "11") then
                        work_tx_fifo_rd <= '1';
                        word_cnt_d <= word_cnt_q - 1;
                    end if;

                    if ((byte_cnt_q = "11") and (word_cnt_q = "00000")) then
                        fsm_d <= st_work_midstate;

                        if (ctrl_midstate_cnt = "00") then
                            word_cnt_d <= "00111";    -- 1 midstate (32 bytes, 8 words)
                        elsif (ctrl_midstate_cnt = "01") then
                            word_cnt_d <= "01111";    -- 2 midstates (64 bytes, 16 words)
                        else
                            word_cnt_d <= "11111";    -- 4 midstates (128 bytes, 32 words)
                        end if;
                    end if;
                end if;

            when st_work_midstate =>
                if ((work_ready = '1') and ((work_tx_fifo_empty = '0') or (word_cnt_q = "00000"))) then
                    uart_tx_write <= '1';
                    crc16_wr <= '1';

                    byte_cnt_d <= byte_cnt_q + 1;

                    -- big endian
                    if (byte_cnt_q = "00") then
                        uart_tx_data_wr <= work_tx_fifo_data_r(31 downto 24);
                    elsif (byte_cnt_q = "01") then
                        uart_tx_data_wr <= work_tx_fifo_data_r(23 downto 16);
                    elsif (byte_cnt_q = "10") then
                        uart_tx_data_wr <= work_tx_fifo_data_r(15 downto 8);
                    else
                        uart_tx_data_wr <= work_tx_fifo_data_r(7 downto 0);
                    end if;

                    if ((byte_cnt_q = "11") and (word_cnt_q /= "00000")) then
                        work_tx_fifo_rd <= '1';
                        word_cnt_d <= word_cnt_q - 1;
                    end if;

                    if ((byte_cnt_q = "11") and (word_cnt_q = "00000")) then
                        fsm_d <= st_work_crc16;
                        byte_cnt_d <= "00";
                    end if;
                end if;

            when st_work_crc16 =>
                if (work_ready = '1') then
                    uart_tx_write <= '1';
                    byte_cnt_d <= byte_cnt_q + 1;

                    if (byte_cnt_q = "01") then
                        uart_tx_data_wr <= crc16(7 downto 0);

                        if (cmd_tx_fifo_empty = '0') then  -- check control buffer
                            fsm_d <= st_cmd_read;
                        else
                            fsm_d <= st_wait_sync;         -- otherwise wait for next sync;
                        end if;
                    else
                        uart_tx_data_wr <= crc16(15 downto 8);
                    end if;
                end if;

            when st_cmd_read =>
                fsm_d <= st_cmd_check;
                crc5_tx_clear <= '1';
                cmd_tx_fifo_rd <= '1';

            when st_cmd_check =>
                fsm_d <= st_cmd_check_1;
                byte_cnt_d <= "00";    -- first to send is command
                word_cnt_d <= resize(shift_right(unsigned(cmd_tx_fifo_data_r(15 downto 8)) - X"02", 2), 5);
                byte_rest_d <= unsigned(cmd_tx_fifo_data_r(9 downto 8)) - "10";  -- skip CRC

            when st_cmd_check_1 =>
                -- wait until all data are ready
                if ((cmd_tx_ready = '1') and ((cmd_tx_fifo_empty = '0') or (word_cnt_q = "00000"))) then
                    if (ctrl_bm139x = '1') then
                        fsm_d <= st_cmd_55;
                    else
                        fsm_d <= st_cmd_cmd;
                    end if;
                end if;

            when st_cmd_55 =>
                if (cmd_tx_ready = '1') then
                    fsm_d <= st_cmd_AA;
                    uart_tx_write <= '1';
                    uart_tx_data_wr <= X"55";
                end if;

            when st_cmd_AA =>
                if (cmd_tx_ready = '1') then
                    fsm_d <= st_cmd_cmd;
                    uart_tx_write <= '1';
                    uart_tx_data_wr <= X"AA";
                end if;

            when st_cmd_cmd =>
                if (cmd_tx_ready = '1') then
                    fsm_d <= st_cmd_data;

                    byte_cnt_d <= byte_cnt_q + 1;

                    uart_tx_write <= '1';
                    crc5_tx_wr <= '1';
                    uart_tx_data_wr <= cmd_tx_fifo_data_r(7 downto 0); -- send command
                end if;

            when st_cmd_data =>
                if ((cmd_tx_ready = '1') and ((cmd_tx_fifo_empty = '0') or (word_cnt_q = "00000"))) then
                    uart_tx_write <= '1';
                    crc5_tx_wr <= '1';

                    byte_cnt_d <= byte_cnt_q + 1;

                    -- little endian
                    if (byte_cnt_q = "00") then
                        uart_tx_data_wr <= cmd_tx_fifo_data_r(7 downto 0);
                    elsif (byte_cnt_q = "01") then
                        uart_tx_data_wr <= cmd_tx_fifo_data_r(15 downto 8);
                    elsif (byte_cnt_q = "10") then
                        uart_tx_data_wr <= cmd_tx_fifo_data_r(23 downto 16);
                    else
                        uart_tx_data_wr <= cmd_tx_fifo_data_r(31 downto 24);
                    end if;

                    if ((byte_cnt_q = "11") and (word_cnt_q /= "00000")) then
                        cmd_tx_fifo_rd <= '1';
                        word_cnt_d <= word_cnt_q - 1;
                    end if;

                    if ((byte_cnt_q = byte_rest_q) and (word_cnt_q = "00000")) then
                        fsm_d <= st_cmd_crc5;
                    end if;
                end if;

            when st_cmd_crc5 =>
                if (cmd_tx_ready = '1') then
                    fsm_d <= st_wait_sync;
                    uart_tx_write <= '1';
                    uart_tx_data_wr <= "000" & crc5_tx;
                end if;
        end case;

        if (ctrl_enable = '0') then
            fsm_d <= st_idle;
        end if;

    end process;

    ------------------------------------------------------------------------------------------------
    -- Command Receive FIFO
    i_cmd_rx_fifo: entity work.fifo_block
    generic map (
        A => 8,     -- address width of FIFO - 256 words
        W => 32     -- number of data bits
    )
    port map (
        clk    => clk,
        rst    => rst,

        -- synchronous clear of FIFO
        clear  => rst_fifo_cmd_rx,

        -- write port - from FSM
        wr     => cmd_rx_fifo_wr,
        full   => cmd_rx_fifo_full,
        a_full => cmd_rx_fifo_a_full,
        data_w => cmd_rx_fifo_data_w,

        -- read port - from CPU
        rd     => cmd_rx_fifo_rd,
        empty  => cmd_rx_fifo_empty,
        data_r => cmd_rx_fifo_data
    );

    ------------------------------------------------------------------------------------------------
    -- Command Transmit FIFO
    i_cmd_tx_fifo: entity work.fifo_block
    generic map (
        A => 10,    -- address width of FIFO - 1k words
        W => 32     -- number of data bits
    )
    port map (
        clk    => clk,
        rst    => rst,

        -- synchronous clear of FIFO
        clear  => rst_fifo_cmd_tx,

        -- write port - from CPU
        wr     => cmd_tx_fifo_wr,
        full   => cmd_tx_fifo_full,
        a_full => open,
        data_w => cmd_tx_fifo_data,

        -- read port - from FSM
        rd     => cmd_tx_fifo_rd,
        empty  => cmd_tx_fifo_empty,
        data_r => cmd_tx_fifo_data_r
    );

    ------------------------------------------------------------------------------------------------
    -- Work Receive FIFO
    i_work_rx_fifo: entity work.fifo_block
    generic map (
        A => 10,    -- address width of FIFO - 1k words
        W => 32     -- number of data bits
    )
    port map (
        clk    => clk,
        rst    => rst,

        -- synchronous clear of FIFO
        clear  => rst_fifo_work_rx,

        -- write port - from FSM
        wr     => work_rx_fifo_wr,
        full   => work_rx_fifo_full,
        a_full => work_rx_fifo_a_full,
        data_w => work_rx_fifo_data_w,

        -- read port - from CPU
        rd     => work_rx_fifo_rd,
        empty  => work_rx_fifo_empty,
        data_r => work_rx_fifo_data
    );

    ------------------------------------------------------------------------------------------------
    -- Work Transmit FIFO
    i_work_tx_fifo: entity work.fifo_block_thr
    generic map (
        A => 11,    -- address width of FIFO - 2k words
        W => 32     -- number of data bits
    )
    port map (
        clk    => clk,
        rst    => rst,

        -- synchronous clear of FIFO
        clear  => rst_fifo_work_tx,

        -- threshold value and signalization for IRQ
        thr_value => reg_irq_fifo_thr,
        thr_irq   => irq_pending_work_tx,

        -- threshold value and signalization for work send
        thr_work_value => work_tx_fifo_thr_value,
        thr_work_ready => work_tx_fifo_thr_ready,

        -- write port - from CPU
        wr     => work_tx_fifo_wr,
        full   => work_tx_fifo_full,
        data_w => work_tx_fifo_data,

        -- read port - from FSM
        rd     => work_tx_fifo_rd,
        empty  => work_tx_fifo_empty,
        data_r => work_tx_fifo_data_r
    );

    work_tx_fifo_thr_value <=
        "00000001100" when (ctrl_midstate_cnt = "00") else  -- 1 midstate  -> required 12 words in FIFO
        "00000010100" when (ctrl_midstate_cnt = "01") else  -- 2 midstates -> required 20 words in FIFO
        "00000100100";                                      -- 4 midstates -> required 36 words in FIFO

    ------------------------------------------------------------------------------------------------
    i_uart: entity work.uart
    port map (
        clk        => clk,
        rst        => rst,

        -- UART interface
        rxd        => rxd,
        txd        => txd,

        -- synchronous clear FIFOs
        clear      => uart_clear,

        -- FIFO read port
        rx_read    => uart_rx_read,
        rx_empty   => uart_rx_empty,
        rx_data_rd => uart_rx_data_rd,

        -- FIFO write port
        tx_write   => uart_tx_write,
        tx_full    => uart_tx_full,
        tx_data_wr => uart_tx_data_wr,

        -- UART configuration
        division   => reg_uart_divisor,

        -- UART status
        sync_busy  => uart_sync_busy,
        frame_err  => uart_frame_err,
        over_err   => uart_over_err
    );


    ------------------------------------------------------------------------------------------------
    -- calculation of full work ID
    p_work_id_calc: process (fsm_rx_q, work_id_rx, work_id_rx_cmp, work_id_tx_q) begin
        -- default assignment
        work_id <= (others => '0');

        if (fsm_rx_q = st_write_work2) then
            work_id(6 downto 0) <= work_id_rx;                  -- copy received work ID
            work_id(15 downto 7) <= work_id_tx_q(15 downto 7);  -- preset of last send work ID

            if (work_id_rx_cmp > work_id_tx_q(6 downto 0)) then
                work_id(15 downto 7) <= std_logic_vector(unsigned(work_id_tx_q(15 downto 7)) - 1);
            end if;
        end if;
    end process;

    work_id_rx <= response_q(5)(6 downto 0);

    -- mask LSBs of response work ID according to number of midstates
    work_id_rx_cmp <=
        (response_q(5)(6 downto 0) and "1111111") when (ctrl_midstate_cnt = "00") else
        (response_q(5)(6 downto 0) and "1111110") when (ctrl_midstate_cnt = "01") else
        (response_q(5)(6 downto 0) and "1111100");

    ------------------------------------------------------------------------------------------------
    -- sequential part of receive FSM (state register)
    p_fsm_rx_seq: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                fsm_rx_q <= st_idle;
                byte_cnt_rx_q <= (others => '0');
                response_q <= (others => (others => '0'));
                irq_pending_work_rx_q <= '0';
                irq_pending_cmd_rx_q <= '0';
            else
                fsm_rx_q <= fsm_rx_d;
                byte_cnt_rx_q <= byte_cnt_rx_d;
                response_q <= response_d;
                irq_pending_work_rx_q <= irq_pending_work_rx_d;
                irq_pending_cmd_rx_q <= irq_pending_cmd_rx_d;
            end if;
        end if;
    end process;

    -- combinational part of receive FSM (next-state logic)
    p_fsm_rx_cmb: process (fsm_rx_q, ctrl_enable,
        work_rx_fifo_full, cmd_rx_fifo_full, work_rx_fifo_a_full, cmd_rx_fifo_a_full,
        uart_rx_empty, uart_rx_data_rd,
        byte_cnt_rx_q, response_q, crc5_rx_ready, crc5_rx_crc, work_id,
        irq_pending_work_rx_q, irq_pending_cmd_rx_q,
        work_rx_fifo_rd, cmd_rx_fifo_rd, rst_fifo_work_rx, rst_fifo_cmd_rx, ctrl_bm139x
    ) begin

        -- default assignment to registers and signals
        fsm_rx_d <= fsm_rx_q;

        byte_cnt_rx_d <= byte_cnt_rx_q;
        response_d <= response_q;

        irq_pending_work_rx_d <= irq_pending_work_rx_q;
        irq_pending_cmd_rx_d <= irq_pending_cmd_rx_q;

        crc5_rx_clear <= '0';
        crc5_rx_init <= (others => '0');
        crc5_rx_wr <= '0';
        crc5_rx_data <= (others => '0');

        work_rx_fifo_wr <= '0';
        work_rx_fifo_data_w <= (others => '0');
        cmd_rx_fifo_wr <= '0';
        cmd_rx_fifo_data_w <= (others => '0');

        uart_rx_read <= '0';

        receive_err <= '0';

        if ((work_rx_fifo_rd = '1') or (rst_fifo_work_rx = '1') or (ctrl_enable = '0')) then
            irq_pending_work_rx_d <= '0';
        end if;

        if ((cmd_rx_fifo_rd = '1') or (rst_fifo_cmd_rx = '1') or (ctrl_enable = '0')) then
            irq_pending_cmd_rx_d <= '0';
        end if;

        -- state machine
        case fsm_rx_q is
            when st_idle =>
                if (ctrl_enable = '1') then         -- wait for enable of IP core
                    fsm_rx_d <= st_wait;
                end if;

            when st_wait =>
                if (uart_rx_empty = '0') then
                    if (ctrl_bm139x = '1') then
                        fsm_rx_d <= st_read_AA;
                    else
                        fsm_rx_d <= st_read;
                    end if;
                    byte_cnt_rx_d <= "000";
                end if;

            when st_read_AA =>
                if (uart_rx_empty = '0') then
                    uart_rx_read <= '1';

                    -- check data
                    if (uart_rx_data_rd = X"AA") then
                        fsm_rx_d <= st_read_55;
                    else
                        fsm_rx_d <= st_wait;
                        receive_err <= '1';
                    end if;
                end if;

            when st_read_55 =>
                if (uart_rx_empty = '0') then
                    uart_rx_read <= '1';

                    -- check data
                    if (uart_rx_data_rd = X"55") then
                        fsm_rx_d <= st_read;
                    elsif (uart_rx_data_rd = X"AA") then
                        fsm_rx_d <= st_read_55;
                        receive_err <= '1';
                    else
                        fsm_rx_d <= st_wait;
                        receive_err <= '1';
                    end if;
                end if;

            when st_read =>
                if (uart_rx_empty = '0') then
                    uart_rx_read <= '1';

                    -- shift-in new data
                    response_d(0 to 5) <= response_q(1 to 6);
                    response_d(6) <= uart_rx_data_rd;

                    byte_cnt_rx_d <= byte_cnt_rx_q + 1;

                    if (byte_cnt_rx_q = "110") then
                        fsm_rx_d <= st_calc_crc;
                        crc5_rx_clear <= '1';
                        byte_cnt_rx_d <= "000";

                        if (uart_rx_data_rd(7) = '1') then
                            crc5_rx_init <= "11011";    -- CRC init value for work response
                        else
                            crc5_rx_init <= "00011";    -- CRC init value for command response
                        end if;
                    end if;
                end if;

            when st_calc_crc =>
                if (crc5_rx_ready = '1') then
                    crc5_rx_wr <= '1';
                    crc5_rx_data <= response_q(to_integer(byte_cnt_rx_q));
                    byte_cnt_rx_d <= byte_cnt_rx_q + 1;

                    if (byte_cnt_rx_q = "101") then
                        fsm_rx_d <= st_check_crc;
                    end if;
                end if;

            when st_check_crc =>
                if (crc5_rx_ready = '1') then
                    -- check CRC, drop data if mismatch
                    if (response_q(6)(4 downto 0) = crc5_rx_crc) then
                        if (response_q(6)(7) = '1') then
                            fsm_rx_d <= st_write_work1;    -- work response
                        else
                            fsm_rx_d <= st_write_cmd1;     -- command response
                        end if;
                    else
                        fsm_rx_d <= st_crc_err;
                    end if;
                end if;

            when st_write_work1 =>
                if (work_rx_fifo_a_full = '0') then
                    fsm_rx_d <= st_write_work2;
                    work_rx_fifo_wr <= '1';
                    work_rx_fifo_data_w <= response_q(3) & response_q(2) & response_q(1) & response_q(0);
                else
                    fsm_rx_d <= st_wait;    -- drop response if FIFO is full
                    receive_err <= '1';
                end if;

            when st_write_work2 =>
                if (work_rx_fifo_full = '0') then
                    fsm_rx_d <= st_wait;
                    irq_pending_work_rx_d <= '1';
                    work_rx_fifo_wr <= '1';
                    work_rx_fifo_data_w <= response_q(6) & work_id & response_q(4);
                end if;

            when st_write_cmd1 =>
                if (cmd_rx_fifo_a_full = '0') then
                    fsm_rx_d <= st_write_cmd2;
                    cmd_rx_fifo_wr <= '1';
                    cmd_rx_fifo_data_w <= response_q(3) & response_q(2) & response_q(1) & response_q(0);
                else
                    fsm_rx_d <= st_wait;    -- drop response if FIFO is full
                    receive_err <= '1';
                end if;

            when st_write_cmd2 =>
                if (cmd_rx_fifo_full = '0') then
                    fsm_rx_d <= st_wait;
                    irq_pending_cmd_rx_d <= '1';
                    cmd_rx_fifo_wr <= '1';
                    cmd_rx_fifo_data_w <= response_q(6) & X"00" & response_q(5) & response_q(4);
                end if;

            when st_crc_err =>
                -- update counter of received bytes to 6 and return back to read state
                fsm_rx_d <= st_read;
                byte_cnt_rx_d <= "110";
        end case;

        if (ctrl_enable = '0') then
            fsm_rx_d <= st_idle;
        end if;

    end process;

    ------------------------------------------------------------------------------------------------
    -- CRC5 engine for transmit
    i_crc5_tx: entity work.crc5_serial
    port map (
        clk     => clk,
        rst     => rst,
        clear   => crc5_tx_clear,
        data_wr => crc5_tx_wr,
        data_in => crc5_tx_data,
        ready   => crc5_tx_ready,
        crc     => crc5_tx
    );

    crc5_tx_data <= uart_tx_data_wr;


    ------------------------------------------------------------------------------------------------
    -- CRC5 engine for receive work and command frames
    i_crc5_rx: entity work.crc5_resp_serial
    port map (
        clk     => clk,
        rst     => rst,
        clear   => crc5_rx_clear,
        init    => crc5_rx_init,
        data_wr => crc5_rx_wr,
        data_in => crc5_rx_data,
        ready   => crc5_rx_ready,
        crc     => crc5_rx_crc
    );

    ------------------------------------------------------------------------------------------------
    -- CRC16 engine
    i_crc16: entity work.crc16_serial
    port map (
        clk     => clk,
        rst     => rst,
        clear   => crc16_clear,
        data_wr => crc16_wr,
        data_in => crc16_data,
        ready   => crc16_ready,
        crc     => crc16
    );

    crc16_data <= uart_tx_data_wr;

    ------------------------------------------------------------------------------------------------
    -- error counter
    p_err_cnt: process (clk) begin
        if rising_edge(clk) then
            if (rst = '0') then
                err_cnt_q <= (others => '0');
            elsif ((ctrl_err_cnt_clear = '1') or (err_cnt_clear = '1')) then
                err_cnt_q <= (others => '0');
            elsif ((fsm_rx_q = st_crc_err) or (receive_err = '1')) then
                err_cnt_q <= err_cnt_q + 1;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------------------------------------
    -- Status Registers
    reg_status_cmd <=
        irq_pending_cmd_rx_q &
        cmd_tx_fifo_full &
        cmd_tx_fifo_empty &
        cmd_rx_fifo_full &
        cmd_rx_fifo_empty;

    reg_status_work_rx <=
        irq_pending_work_rx_q &
        "00" &
        work_rx_fifo_full &
        work_rx_fifo_empty;

    reg_status_work_tx <=
        irq_pending_work_tx &
        work_tx_fifo_full &
        work_tx_fifo_empty &
        "00";

    ------------------------------------------------------------------------------------------------
    -- masked IRQ
    irq_work_tx <= irq_pending_work_tx and ctrl_irq_en_work_tx;
    irq_work_rx <= irq_pending_work_rx_q and ctrl_irq_en_work_rx;
    irq_cmd_rx <= irq_pending_cmd_rx_q and ctrl_irq_en_cmd_rx;

    -- error counter
    reg_err_counter <= std_logic_vector(err_cnt_q);

    -- last work ID
    reg_last_work_id <= work_id_tx_q;

    -- enable UART interface IO driver
    uart_en <= ctrl_enable;

end architecture;


