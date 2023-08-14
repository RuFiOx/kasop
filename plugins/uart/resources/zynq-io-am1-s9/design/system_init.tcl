####################################################################################################
# Copyright (c) 2016  Andreas Olofsson
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
timestamp "Executing system_init.tcl ..."

####################################################################################################
# Create project
####################################################################################################
create_project -force $design $projdir -part $partname
set_property target_language Verilog [current_project]

if {[info exists board_part]} {
    set_property board_part $board_part [current_project]
}

####################################################################################################
# Create Report/Results Directory
####################################################################################################
set report_dir [file join $projdir reports]
set results_dir [file join $projdir results]
if ![file exists $report_dir]  {file mkdir $report_dir}
if ![file exists $results_dir] {file mkdir $results_dir}

####################################################################################################
# Generate IP Cores
####################################################################################################
source generate_ip_axi_bm13xx.tcl
source generate_ip_axi_fan_ctrl.tcl
source generate_ip_uart_mux.tcl

####################################################################################################
# Add IP Repositories to search path
####################################################################################################

set other_repos [get_property ip_repo_paths [current_project]]
set_property  ip_repo_paths  "$ip_repos $other_repos" [current_project]

update_ip_catalog -rebuild

####################################################################################################
# CREATE BLOCK DESIGN (GUI/TCL COMBO)
####################################################################################################
timestamp "Generating system block design ..."

set_property target_language Verilog [current_project]
create_bd_design "system"

puts "Source system_${fpga}.tcl ..."
source "system_${fpga}.tcl"

validate_bd_design
write_bd_tcl -force ./${design}.backup.tcl
make_wrapper -files [get_files $projdir/${design}.srcs/sources_1/bd/system/system.bd] -top

####################################################################################################
# Add files
####################################################################################################

# HDL
if {[string equal [get_filesets -quiet sources_1] ""]} {
    create_fileset -srcset sources_1
}
set top_wrapper $projdir/${design}.srcs/sources_1/bd/system/hdl/system_wrapper.v
add_files -norecurse -fileset [get_filesets sources_1] $top_wrapper

# Constraints
if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}
if {[llength $constraints_files] != 0} {
    add_files -norecurse -fileset [get_filesets constrs_1] $constraints_files
}
