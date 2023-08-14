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
-- Description:    Top module of Fan Controller IP core
--
-- Engineer:       Marian Pristach
-- Revision:       1.0.0 (15.10.2019)
-- Comments:
----------------------------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_fan_ctrl_v1_0 is
    generic (
        -- Users to add parameters here

        -- User parameters ends
        -- Do not modify the parameters beyond this line


        -- Parameters of Axi Slave Bus Interface S_AXI
        C_S_AXI_DATA_WIDTH : integer    := 32;
        C_S_AXI_ADDR_WIDTH : integer    := 5
    );
    port (
        -- Users to add ports here

        -- Fan sense inputs
        fan_sense         : in std_logic_vector(3 downto 0);

        -- PWM output
        pwm               : out std_logic;

        -- User ports ends
        -- Do not modify the ports beyond this line


        -- Ports of Axi Slave Bus Interface S_AXI
        s_axi_aclk      : in std_logic;
        s_axi_aresetn   : in std_logic;
        s_axi_awaddr    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_awprot    : in std_logic_vector(2 downto 0);
        s_axi_awvalid   : in std_logic;
        s_axi_awready   : out std_logic;
        s_axi_wdata     : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_wstrb     : in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        s_axi_wvalid    : in std_logic;
        s_axi_wready    : out std_logic;
        s_axi_bresp     : out std_logic_vector(1 downto 0);
        s_axi_bvalid    : out std_logic;
        s_axi_bready    : in std_logic;
        s_axi_araddr    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        s_axi_arprot    : in std_logic_vector(2 downto 0);
        s_axi_arvalid   : in std_logic;
        s_axi_arready   : out std_logic;
        s_axi_rdata     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        s_axi_rresp     : out std_logic_vector(1 downto 0);
        s_axi_rvalid    : out std_logic;
        s_axi_rready    : in std_logic
    );
end axi_fan_ctrl_v1_0;

architecture rtl of axi_fan_ctrl_v1_0 is

    -- component declaration
    component fan_ctrl_S_AXI is
        generic (
            C_S_AXI_DATA_WIDTH    : integer    := 32;
            C_S_AXI_ADDR_WIDTH    : integer    := 5
        );
        port (
            -- Fan sense inputs
            fan_sense       : in std_logic_vector(3 downto 0);

            -- PWM output
            pwm             : out std_logic;

            S_AXI_ACLK      : in std_logic;
            S_AXI_ARESETN   : in std_logic;
            S_AXI_AWADDR    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
            S_AXI_AWPROT    : in std_logic_vector(2 downto 0);
            S_AXI_AWVALID   : in std_logic;
            S_AXI_AWREADY   : out std_logic;
            S_AXI_WDATA     : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
            S_AXI_WSTRB     : in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
            S_AXI_WVALID    : in std_logic;
            S_AXI_WREADY    : out std_logic;
            S_AXI_BRESP     : out std_logic_vector(1 downto 0);
            S_AXI_BVALID    : out std_logic;
            S_AXI_BREADY    : in std_logic;
            S_AXI_ARADDR    : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
            S_AXI_ARPROT    : in std_logic_vector(2 downto 0);
            S_AXI_ARVALID   : in std_logic;
            S_AXI_ARREADY   : out std_logic;
            S_AXI_RDATA     : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
            S_AXI_RRESP     : out std_logic_vector(1 downto 0);
            S_AXI_RVALID    : out std_logic;
            S_AXI_RREADY    : in std_logic
        );
    end component fan_ctrl_S_AXI;

begin

    -- Instantiation of Axi Bus Interface S_AXI
    i_fan_ctrl_S_AXI : fan_ctrl_S_AXI
        generic map (
            C_S_AXI_DATA_WIDTH => C_S_AXI_DATA_WIDTH,
            C_S_AXI_ADDR_WIDTH => C_S_AXI_ADDR_WIDTH
        )
        port map (
            -- Fan sense inputs
            fan_sense       => fan_sense,

            -- PWM output
            pwm             => pwm,

            S_AXI_ACLK      => s_axi_aclk,
            S_AXI_ARESETN   => s_axi_aresetn,
            S_AXI_AWADDR    => s_axi_awaddr,
            S_AXI_AWPROT    => s_axi_awprot,
            S_AXI_AWVALID   => s_axi_awvalid,
            S_AXI_AWREADY   => s_axi_awready,
            S_AXI_WDATA     => s_axi_wdata,
            S_AXI_WSTRB     => s_axi_wstrb,
            S_AXI_WVALID    => s_axi_wvalid,
            S_AXI_WREADY    => s_axi_wready,
            S_AXI_BRESP     => s_axi_bresp,
            S_AXI_BVALID    => s_axi_bvalid,
            S_AXI_BREADY    => s_axi_bready,
            S_AXI_ARADDR    => s_axi_araddr,
            S_AXI_ARPROT    => s_axi_arprot,
            S_AXI_ARVALID   => s_axi_arvalid,
            S_AXI_ARREADY   => s_axi_arready,
            S_AXI_RDATA     => s_axi_rdata,
            S_AXI_RRESP     => s_axi_rresp,
            S_AXI_RVALID    => s_axi_rvalid,
            S_AXI_RREADY    => s_axi_rready
        );

    -- Add user logic here

    -- User logic ends

end rtl;
