####################################################################################################
# Copyright (C) 2019  Braiins Systems s.r.o.
#
# This file is part of Braiins Open-Source Initiative (BOSI).
#
# BOSI is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Please, keep in mind that we may also license BOSI or any part thereof
# under a proprietary license. For more information on the terms and conditions
# of such proprietary license or if you have any other questions, please
# contact us at opensource@braiins.com.
####################################################################################################

####################################################################################################
# Procedure to generate verification design
proc create_ipi_design {design_name} {
    create_bd_design $design_name
    open_bd_design $design_name

    # Create Clock and Reset Ports
    set ACLK [create_bd_port -dir I -type clk ACLK]
    set_property -dict [list CONFIG.FREQ_HZ {50000000} CONFIG.PHASE {0.000} CONFIG.CLK_DOMAIN "${design_name}_ACLK"] $ACLK
    set ARESETN [create_bd_port -dir I -type rst ARESETN]
    set_property -dict [list CONFIG.POLARITY {ACTIVE_LOW}] $ARESETN
    set_property CONFIG.ASSOCIATED_RESET ARESETN $ACLK

    # Create instance: axi_bm13xx_0, and set properties
    set axi_bm13xx_0 [create_bd_cell -type ip -vlnv braiins.com:ip:axi_bm13xx:1.0 axi_bm13xx_0]

    # Create instance: master_0, and set properties
    set master_0 [create_bd_cell -type ip -vlnv  xilinx.com:ip:axi_vip master_0]
    set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.INTERFACE_MODE {MASTER}] $master_0

    # Create interface connections
    connect_bd_intf_net [get_bd_intf_pins master_0/M_AXI] [get_bd_intf_pins axi_bm13xx_0/S_AXI]

    # Create port connections
    connect_bd_net -net aclk_net [get_bd_ports ACLK] [get_bd_pins master_0/ACLK] [get_bd_pins axi_bm13xx_0/S_AXI_ACLK]
    connect_bd_net -net aresetn_net [get_bd_ports ARESETN] [get_bd_pins master_0/ARESETN] [get_bd_pins axi_bm13xx_0/S_AXI_ARESETN]

    # Create external ports for rest of DUT pins
    make_bd_pins_external [get_bd_cells axi_bm13xx_0]

    # Auto assign address
    assign_bd_address
}

####################################################################################################
timestamp "Generating verification environment for IP core axi_bm13xx ..."

# name of verification design
set design_name "axi_bm13xx_bfm"

# set name of fileset
set fileset "sim_axi_bm13xx"

# suppress warning from AXI protocol checker:
#  The "System Verilog Assertion" is not supported yet for simulation. The statement will be ignored.
set_msg_config -id {XSIM 43-4127} -suppress

####################################################################################################
# create new fileset
create_fileset -simset $fileset

# generate verification design
create_ipi_design $design_name
validate_bd_design

set wrapper_file [make_wrapper -files [get_files ${design_name}.bd] -top -force]
import_files -force -norecurse $wrapper_file

# make current fileset active and delete original fileset
current_fileset -simset [get_filesets $fileset]
delete_fileset sim_1

set_property target_simulator XSim [current_project]
set_property -name {xsim.simulate.runtime} -value {100ms} -objects [get_filesets $fileset]
set_property SOURCE_SET sources_1 [get_filesets $fileset]

# set global verilog defines
if {$board != "S9"} {
    set_property verilog_define "BM139X=1" [get_filesets $fileset]
}

# import verification files
add_files -fileset $fileset -norecurse "src/ip_cores/axi_bm13xx/fve/axi_bm13xx_tb.sv"
add_files -fileset $fileset -norecurse "src/ip_cores/axi_bm13xx/fve/axi_bm13xx_pkg.sv"
add_files -fileset $fileset -norecurse "src/ip_cores/axi_bm13xx/fve/bfm_uart.sv"

set_property top axi_bm13xx_tb [get_filesets $fileset]
set_property top_lib {} [get_filesets $fileset]
set_property top_file {} [get_filesets $fileset]

####################################################################################################
timestamp "Launching simulation ..."
launch_simulation -simset $fileset -mode behavioral
close_sim

####################################################################################################
# check result of simulation
set ok 0
set fd [open "${projdir}/system.sim/${fileset}/behav/xsim/simulate.log" "r"]

# find simulation result
while { [gets $fd line] != -1 } {
    if { $line == "Simulation finished: PASSED" } {
        set ok 1
    }
}

# close file
close $fd

# check result of simulation
if { $ok != 1 } {
    puts "ERROR: \[axi_bm13xx\]: Verification failed, check simulation report"
#     exit 1
}
