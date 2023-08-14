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
-- Description:    AXI Interface of AXI BM13xx IP core
--
-- Engineer:       Marian Pristach
-- Revision:       1.1.0 (22.07.2019)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bm13xx_S_AXI is
    generic (
        -- Users to add parameters here

        -- User parameters ends
        -- Do not modify the parameters beyond this line

        -- Width of S_AXI data bus
        C_S_AXI_DATA_WIDTH : integer := 32;
        -- Width of S_AXI address bus
        C_S_AXI_ADDR_WIDTH : integer := 6
    );
    port (
        -- Users to add ports here

        -- UART interface
        rxd : in  std_logic;
        txd : out std_logic;

        -- enable UART interface IO driver
        uart_en : out std_logic;

        -- Interrupt Request
        irq_work_tx : out std_logic;
        irq_work_rx : out std_logic;
        irq_cmd_rx  : out std_logic;

        -- User ports ends
        -- Do not modify the ports beyond this line

        -- Global Clock Signal
        S_AXI_ACLK      : in std_logic;
        -- Global Reset Signal. This Signal is Active LOW
        S_AXI_ARESETN   : in std_logic;
        -- Write address (issued by master, acceped by Slave)
        S_AXI_AWADDR    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        -- Write channel Protection type. This signal indicates the
        -- privilege and security level of the transaction, and whether
        -- the transaction is a data access or an instruction access.
        S_AXI_AWPROT    : in std_logic_vector(2 downto 0);
        -- Write address valid. This signal indicates that the master signaling
        -- valid write address and control information.
        S_AXI_AWVALID   : in std_logic;
        -- Write address ready. This signal indicates that the slave is ready
        -- to accept an address and associated control signals.
        S_AXI_AWREADY   : out std_logic;
        -- Write data (issued by master, acceped by Slave)
        S_AXI_WDATA     : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        -- Write strobes. This signal indicates which byte lanes hold
        -- valid data. There is one write strobe bit for each eight
        -- bits of the write data bus.
        S_AXI_WSTRB     : in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        -- Write valid. This signal indicates that valid write
        -- data and strobes are available.
        S_AXI_WVALID    : in std_logic;
        -- Write ready. This signal indicates that the slave
        -- can accept the write data.
        S_AXI_WREADY    : out std_logic;
        -- Write response. This signal indicates the status
        -- of the write transaction.
        S_AXI_BRESP     : out std_logic_vector(1 downto 0);
        -- Write response valid. This signal indicates that the channel
        -- is signaling a valid write response.
        S_AXI_BVALID    : out std_logic;
        -- Response ready. This signal indicates that the master
        -- can accept a write response.
        S_AXI_BREADY    : in std_logic;
        -- Read address (issued by master, acceped by Slave)
        S_AXI_ARADDR    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        -- Protection type. This signal indicates the privilege
        -- and security level of the transaction, and whether the
        -- transaction is a data access or an instruction access.
        S_AXI_ARPROT    : in std_logic_vector(2 downto 0);
        -- Read address valid. This signal indicates that the channel
        -- is signaling valid read address and control information.
        S_AXI_ARVALID   : in std_logic;
        -- Read address ready. This signal indicates that the slave is
        -- ready to accept an address and associated control signals.
        S_AXI_ARREADY   : out std_logic;
        -- Read data (issued by slave)
        S_AXI_RDATA     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        -- Read response. This signal indicates the status of the
        -- read transfer.
        S_AXI_RRESP     : out std_logic_vector(1 downto 0);
        -- Read valid. This signal indicates that the channel is
        -- signaling the required read data.
        S_AXI_RVALID    : out std_logic;
        -- Read ready. This signal indicates that the master can
        -- accept the read data and response information.
        S_AXI_RREADY    : in std_logic
    );
end bm13xx_S_AXI;

architecture rtl of bm13xx_S_AXI is

    -- AXI4LITE signals
    signal axi_awaddr    : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    signal axi_awready   : std_logic;
    signal axi_wready    : std_logic;
    signal axi_bresp     : std_logic_vector(1 downto 0);
    signal axi_bvalid    : std_logic;
    signal axi_araddr    : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    signal axi_arready   : std_logic;
    signal axi_rdata     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal axi_rdata_tmp : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal axi_rresp     : std_logic_vector(1 downto 0);
    signal axi_rvalid    : std_logic;

    -- Example-specific design signals
    -- local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
    -- ADDR_LSB is used for addressing 32/64 bit registers/memories
    -- ADDR_LSB = 2 for 32 bits (n downto 2)
    -- ADDR_LSB = 3 for 64 bits (n downto 3)
    constant ADDR_LSB  : integer := (C_S_AXI_DATA_WIDTH/32)+ 1;
    constant OPT_MEM_ADDR_BITS : integer := 11;
    ------------------------------------------------
    ---- Signals for user logic register space example
    --------------------------------------------------
    signal slv_cmd_rx_fifo      : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_cmd_tx_fifo      : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_work_rx_fifo     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_work_tx_fifo     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_ctrl_reg         : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_cmd_ctrl_reg     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_work_rx_ctrl_reg : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_work_tx_ctrl_reg : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_cmd_stat_reg     : std_logic_vector(4 downto 0);
    signal slv_work_rx_stat_reg : std_logic_vector(4 downto 0);
    signal slv_work_tx_stat_reg : std_logic_vector(4 downto 0);
    signal slv_baud_reg         : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_work_time        : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_work_tx_irq_thr  : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_err_counter      : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal slv_work_tx_last_id  : std_logic_vector(15 downto 0);
    signal slv_build_id         : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);

    signal slv_reg_rden         : std_logic;
    signal slv_reg_wren         : std_logic;
    signal reg_data_out         : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal byte_index           : integer;
    signal aw_en                : std_logic;

    -- user signals
    signal work_time_ack        : std_logic;
    signal cmd_rx_fifo_rd       : std_logic;
    signal cmd_tx_fifo_wr       : std_logic;
    signal work_rx_fifo_rd      : std_logic;
    signal work_tx_fifo_wr      : std_logic;

    -- Register mapping
    constant VERSION            : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"000";  -- IP Core Version Register
    constant BUILD_ID           : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"001";  -- Build ID Register
    constant CTRL_REG           : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"002";  -- Control Register
    constant STAT_REG           : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"003";  -- Status Register - reserved
    constant BAUD_REG           : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"004";  -- Baudrate Divisor Register
    constant WORK_TIME          : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"005";  -- Work Time Delay Register
    constant ERR_COUNTER        : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"006";  -- Error Counter Register
    constant CMD_RX_FIFO        : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"400";  -- Command Receive Interface FIFO
    constant CMD_TX_FIFO        : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"401";  -- Command Transmit Interface FIFO
    constant CMD_CTRL_REG       : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"402";  -- Command Control Register
    constant CMD_STAT_REG       : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"403";  -- Command Status Register
    constant WORK_RX_FIFO       : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"800";  -- Work Receive Interface FIFO
    constant WORK_RX_CTRL_REG   : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"802";  -- Work Receive Control Register
    constant WORK_RX_STAT_REG   : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"803";  -- Work Receive Status Register
    constant WORK_TX_FIFO       : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"C01";  -- Work Transmit Interface FIFO
    constant WORK_TX_CTRL_REG   : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"C02";  -- Work Transmit Control Register
    constant WORK_TX_STAT_REG   : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"C03";  -- Work Transmit Status Register
    constant WORK_TX_IRQ_THR    : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"C04";  -- Work Transmit IRQ Threshold
    constant WORK_TX_LAST_ID    : std_logic_vector(OPT_MEM_ADDR_BITS downto 0) := X"C05";  -- Work Transmit Last Work ID

begin
    -- I/O Connections assignments

    S_AXI_AWREADY  <= axi_awready;
    S_AXI_WREADY   <= axi_wready;
    S_AXI_BRESP    <= axi_bresp;
    S_AXI_BVALID   <= axi_bvalid;
    S_AXI_ARREADY  <= axi_arready;
    S_AXI_RDATA    <= axi_rdata;
    S_AXI_RRESP    <= axi_rresp;
    S_AXI_RVALID   <= axi_rvalid;
    -- Implement axi_awready generation
    -- axi_awready is asserted for one S_AXI_ACLK clock cycle when both
    -- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
    -- de-asserted when reset is low.

    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_awready <= '0';
          aw_en <= '1';
        else
          if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
            -- slave is ready to accept write address when
            -- there is a valid write address and write data
            -- on the write address and data bus. This design
            -- expects no outstanding transactions.
            axi_awready <= '1';
            elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then
                aw_en <= '1';
                axi_awready <= '0';
          else
            axi_awready <= '0';
          end if;
        end if;
      end if;
    end process;

    -- Implement axi_awaddr latching
    -- This process is used to latch the address when both
    -- S_AXI_AWVALID and S_AXI_WVALID are valid.

    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_awaddr <= (others => '0');
        else
          if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
            -- Write Address latching
            axi_awaddr <= S_AXI_AWADDR;
          end if;
        end if;
      end if;
    end process;

    -- Implement axi_wready generation
    -- axi_wready is asserted for one S_AXI_ACLK clock cycle when both
    -- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is
    -- de-asserted when reset is low.

    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_wready <= '0';
        else
          if (axi_wready = '0' and S_AXI_WVALID = '1' and S_AXI_AWVALID = '1' and aw_en = '1') then
              -- slave is ready to accept write data when
              -- there is a valid write address and write data
              -- on the write address and data bus. This design
              -- expects no outstanding transactions.
              axi_wready <= '1';
          else
            axi_wready <= '0';
          end if;
        end if;
      end if;
    end process;

    -- Implement memory mapped register select and write logic generation
    -- The write data is accepted and written to memory mapped registers when
    -- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
    -- select byte enables of slave registers while writing.
    -- These registers are cleared when reset (active low) is applied.
    -- Slave register write enable is asserted when valid address and data are available
    -- and the slave is ready to accept the write address and write data.
    slv_reg_wren <= axi_wready and S_AXI_WVALID and axi_awready and S_AXI_AWVALID ;


    -- Signals - write
    process (axi_awaddr, slv_reg_wren, S_AXI_WSTRB, S_AXI_WDATA)
    variable loc_addr :std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
    begin
      cmd_tx_fifo_wr <= '0';
      work_tx_fifo_wr <= '0';
      slv_cmd_tx_fifo <= (others => '0');
      slv_work_tx_fifo <= (others => '0');

      loc_addr := axi_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
      if (slv_reg_wren = '1') then
        case loc_addr is
          -- Command Transmit Interface FIFO
          when CMD_TX_FIFO =>
            cmd_tx_fifo_wr <= '1';
            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
              if ( S_AXI_WSTRB(byte_index) = '1' ) then
                -- Respective byte enables are asserted as per write strobes
                slv_cmd_tx_fifo(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
              end if;
            end loop;
          -- Work Transmit Interface FIFO
          when WORK_TX_FIFO =>
            work_tx_fifo_wr <= '1';
            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
              if ( S_AXI_WSTRB(byte_index) = '1' ) then
                -- Respective byte enables are asserted as per write strobes
                slv_work_tx_fifo(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
              end if;
            end loop;
          when others =>
        end case;
      end if;
    end process;

    -- Registers
    process (S_AXI_ACLK)
    variable loc_addr :std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          slv_ctrl_reg <= (others => '0');
          slv_cmd_ctrl_reg <= (others => '0');
          slv_work_rx_ctrl_reg <= (others => '0');
          slv_work_tx_ctrl_reg <= (others => '0');
          slv_baud_reg <= (others => '0');
          slv_work_time <= X"00000001";
          slv_work_tx_irq_thr <= (others => '0');
        else

          -- clear error counter reset request
          slv_ctrl_reg(0) <= '0';

          -- clear reset requests
          if (work_time_ack = '1') then
            slv_cmd_ctrl_reg(1 downto 0) <= (others => '0');
            slv_work_rx_ctrl_reg(1 downto 0) <= (others => '0');
            slv_work_tx_ctrl_reg(1 downto 0) <= (others => '0');
          end if;

          loc_addr := axi_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
          if (slv_reg_wren = '1') then
            case loc_addr is
              -- Control Register
              when CTRL_REG =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    slv_ctrl_reg(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              -- Command Control Register
              when CMD_CTRL_REG =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    slv_cmd_ctrl_reg(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              -- Work Receive Control Register
              when WORK_RX_CTRL_REG =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    slv_work_rx_ctrl_reg(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              -- Work Transmit Control Register
              when WORK_TX_CTRL_REG =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    slv_work_tx_ctrl_reg(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              -- Baudrate Divisor Register
              when BAUD_REG =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    slv_baud_reg(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              -- Work Time Delay Register
              when WORK_TIME =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    slv_work_time(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              -- Work Transmit IRQ Threshold
              when WORK_TX_IRQ_THR =>
                for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
                  if ( S_AXI_WSTRB(byte_index) = '1' ) then
                    -- Respective byte enables are asserted as per write strobes
                    slv_work_tx_irq_thr(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
                  end if;
                end loop;
              when others =>
            end case;
          end if;
        end if;
      end if;
    end process;

    -- Implement write response logic generation
    -- The write response and response valid signals are asserted by the slave
    -- when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.
    -- This marks the acceptance of address and indicates the status of
    -- write transaction.

    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_bvalid  <= '0';
          axi_bresp   <= "00"; --need to work more on the responses
        else
          if (axi_awready = '1' and S_AXI_AWVALID = '1' and axi_wready = '1' and S_AXI_WVALID = '1' and axi_bvalid = '0'  ) then
            axi_bvalid <= '1';
            axi_bresp  <= "00";
          elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then   --check if bready is asserted while bvalid is high)
            axi_bvalid <= '0';                                 -- (there is a possibility that bready is always asserted high)
          end if;
        end if;
      end if;
    end process;

    -- Implement axi_arready generation
    -- axi_arready is asserted for one S_AXI_ACLK clock cycle when
    -- S_AXI_ARVALID is asserted. axi_awready is
    -- de-asserted when reset (active low) is asserted.
    -- The read address is also latched when S_AXI_ARVALID is
    -- asserted. axi_araddr is reset to zero on reset assertion.

    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_arready <= '0';
          axi_araddr  <= (others => '1');
        else
          if (axi_arready = '0' and S_AXI_ARVALID = '1') then
            -- indicates that the slave has acceped the valid read address
            axi_arready <= '1';
            -- Read Address latching
            axi_araddr  <= S_AXI_ARADDR;
          else
            axi_arready <= '0';
          end if;
        end if;
      end if;
    end process;

    -- Implement axi_arvalid generation
    -- axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both
    -- S_AXI_ARVALID and axi_arready are asserted. The slave registers
    -- data are available on the axi_rdata bus at this instance. The
    -- assertion of axi_rvalid marks the validity of read data on the
    -- bus and axi_rresp indicates the status of read transaction.axi_rvalid
    -- is deasserted on reset (active low). axi_rresp and axi_rdata are
    -- cleared to zero on reset (active low).
    process (S_AXI_ACLK)
    begin
      if rising_edge(S_AXI_ACLK) then
        if S_AXI_ARESETN = '0' then
          axi_rvalid <= '0';
          axi_rresp  <= "00";
        else
          if (axi_arready = '1' and S_AXI_ARVALID = '1' and axi_rvalid = '0') then
            -- Valid read data is available at the read data bus
            axi_rvalid <= '1';
            axi_rresp  <= "00"; -- 'OKAY' response
          elsif (axi_rvalid = '1' and S_AXI_RREADY = '1') then
            -- Read data is accepted by the master
            axi_rvalid <= '0';
          end if;
        end if;
      end if;
    end process;

    -- Implement memory mapped register select and read logic generation
    -- Slave register read enable is asserted when valid address is available
    -- and the slave is ready to accept the read address.
    slv_reg_rden <= axi_arready and S_AXI_ARVALID and (not axi_rvalid) ;

    process (slv_ctrl_reg, slv_cmd_ctrl_reg, slv_work_rx_ctrl_reg, slv_work_tx_ctrl_reg,
        slv_cmd_stat_reg, slv_work_rx_stat_reg, slv_work_tx_stat_reg, slv_baud_reg,
        slv_work_time, slv_work_tx_irq_thr, slv_err_counter, slv_work_tx_last_id,
        slv_build_id, axi_araddr, slv_reg_rden
    )
        variable loc_addr :std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
    begin
        cmd_rx_fifo_rd <= '0';
        work_rx_fifo_rd <= '0';

        -- Address decoding for reading registers
        loc_addr := axi_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
        case loc_addr is
            -- IP Core Version Register
            when VERSION =>
                reg_data_out <= X"00901000";
            -- Build ID Register
            when BUILD_ID =>
                reg_data_out <= slv_build_id;
            -- Control Register
            when CTRL_REG =>
                reg_data_out <= slv_ctrl_reg;
            -- Status Register - reserved
            when STAT_REG =>
                reg_data_out <= (others => '0');
            -- Baudrate Divisor Register
            when BAUD_REG =>
                reg_data_out <= slv_baud_reg;
            -- Work Time Delay Register
            when WORK_TIME =>
                reg_data_out <= slv_work_time;
            -- Error Counter Register
            when ERR_COUNTER =>
                reg_data_out <= slv_err_counter;

            -- Command Receive Interface FIFO
            when CMD_RX_FIFO =>
                cmd_rx_fifo_rd <= slv_reg_rden;
                reg_data_out <= (others => '0');
            -- Command Transmit Interface FIFO
            when CMD_TX_FIFO =>
                reg_data_out <= (others => '0');
            -- Command Control Register
            when CMD_CTRL_REG =>
                reg_data_out <= slv_cmd_ctrl_reg;
            -- Command Status Register
            when CMD_STAT_REG =>
                reg_data_out <= std_logic_vector(resize(unsigned(slv_cmd_stat_reg), 32));

            -- Work Receive Interface FIFO
            when WORK_RX_FIFO =>
                work_rx_fifo_rd <= slv_reg_rden;
                reg_data_out <= (others => '0');
            -- Work Receive Control Register
            when WORK_RX_CTRL_REG =>
                reg_data_out <= slv_work_rx_ctrl_reg;
            -- Work Receive Status Register
            when WORK_RX_STAT_REG =>
                reg_data_out <= std_logic_vector(resize(unsigned(slv_work_rx_stat_reg), 32));

            -- Work Transmit Interface FIFO
            when WORK_TX_FIFO =>
                reg_data_out <= (others => '0');
            -- Work Transmit Control Register
            when WORK_TX_CTRL_REG =>
                reg_data_out <= slv_work_tx_ctrl_reg;
            -- Work Transmit Status Register
            when WORK_TX_STAT_REG =>
                reg_data_out <= std_logic_vector(resize(unsigned(slv_work_tx_stat_reg), 32));
            -- Work Transmit IRQ Threshold
            when WORK_TX_IRQ_THR =>
                reg_data_out <= slv_work_tx_irq_thr;
            -- Work Transmit Last Work ID
            when WORK_TX_LAST_ID =>
                reg_data_out <= std_logic_vector(resize(unsigned(slv_work_tx_last_id), 32));

            when others =>
                reg_data_out <= (others => '0');
        end case;
    end process;


    -- Output register or memory read data
    process( S_AXI_ACLK ) is
    begin
      if (rising_edge (S_AXI_ACLK)) then
        if ( S_AXI_ARESETN = '0' ) then
          axi_rdata_tmp  <= (others => '0');
        else
          if (slv_reg_rden = '1') then
            -- When there is a valid read address (S_AXI_ARVALID) with
            -- acceptance of read address by the slave (axi_arready),
            -- output the read dada
            -- Read address mux
              axi_rdata_tmp <= reg_data_out;     -- register read data
          end if;
        end if;
      end if;
    end process;


    -- mux for register data and data from synchronous FIFO
    axi_rdata <=
      slv_cmd_rx_fifo when (axi_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB) = CMD_RX_FIFO) else
      slv_work_rx_fifo when (axi_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB) = WORK_RX_FIFO) else
      axi_rdata_tmp;

    ------------------------------------------------------------------------------------------------
    -- Add user logic here
    ------------------------------------------------------------------------------------------------

    -- instance of bm13xx core
    i_bm13xx: entity work.bm13xx_core
    port map (
        clk               => S_AXI_ACLK,
        rst               => S_AXI_ARESETN,

        -- UART interface
        rxd               => rxd,
        txd               => txd,

        -- enable UART interface IO driver
        uart_en           => uart_en,

        -- Interrupt Request
        irq_work_tx       => irq_work_tx,
        irq_work_rx       => irq_work_rx,
        irq_cmd_rx        => irq_cmd_rx,

        -- Signalization of work time delay
        work_time_ack     => work_time_ack,

        -- Command FIFO read port
        cmd_rx_fifo_rd    => cmd_rx_fifo_rd,
        cmd_rx_fifo_data  => slv_cmd_rx_fifo,

        -- Command FIFO write port
        cmd_tx_fifo_wr    => cmd_tx_fifo_wr,
        cmd_tx_fifo_data  => slv_cmd_tx_fifo,

        -- Work FIFO read port
        work_rx_fifo_rd   => work_rx_fifo_rd,
        work_rx_fifo_data => slv_work_rx_fifo,

        -- Work FIFO write port
        work_tx_fifo_wr   => work_tx_fifo_wr,
        work_tx_fifo_data => slv_work_tx_fifo,

        -- Control Register
        reg_ctrl           => slv_ctrl_reg(4 downto 0),
        reg_ctrl_cmd       => slv_cmd_ctrl_reg(2 downto 0),
        reg_ctrl_work_rx   => slv_work_rx_ctrl_reg(2 downto 0),
        reg_ctrl_work_tx   => slv_work_tx_ctrl_reg(2 downto 0),

        -- Status Registers
        reg_status_cmd     => slv_cmd_stat_reg,
        reg_status_work_rx => slv_work_rx_stat_reg,
        reg_status_work_tx => slv_work_tx_stat_reg,

        -- UART baudrate divisor Register
        reg_uart_divisor  => slv_baud_reg(11 downto 0),

        -- Work time delay Register
        reg_work_time     => slv_work_time(23 downto 0),

        -- Threshold for Work Transmit FIFO IRQ
        reg_irq_fifo_thr  => slv_work_tx_irq_thr(10 downto 0),

        -- Error counter (output)
        reg_err_counter   => slv_err_counter,

        -- Last Work ID sent to ASICs (output)
        reg_last_work_id  => slv_work_tx_last_id

    );

    ------------------------------------------------------------------------------------------------
    -- instance of bm13xx core version
    i_bm13xx_version: entity work.bm13xx_version
    port map (
        timestamp => slv_build_id
    );

    ------------------------------------------------------------------------------------------------
    -- User logic ends
    ------------------------------------------------------------------------------------------------

end rtl;
