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
# Generate IP core
####################################################################################################
set ip_name "uart_mux"
set ip_library "ip"
set ip_version "1.0"
set ip_vendor "braiins.com"
set src_path [file join src ip_cores $ip_name hdl]
set ip_repo [file join $projdir ip_repo]

# Set list of VHDL files in compilation order
set ip_hdl_files [ list \
    "uart_mux.vhd" \
]

timestamp "Generating IP core ${ip_name} ..."

####################################################################################################
# set VHDL as target language for files generation
set_property target_language VHDL [current_project]

set ip_id "${ip_vendor}:${ip_library}:${ip_name}:${ip_version}"
set ip_repo_path "${ip_repo}/${ip_name}_${ip_version}"

# remove directory if exists
if [file exists $ip_repo_path] {
    file delete -force $ip_repo_path
}

####################################################################################################
# Create new IP peripheral core
####################################################################################################
ipx::infer_core -vendor $ip_vendor -library $ip_library -root_dir $ip_repo_path -files [file join $src_path $ip_hdl_files]

####################################################################################################
# Open IP core for edit
####################################################################################################
set ipx_xml ${ip_repo_path}/component.xml
set ipx_project ${ip_name}_${ip_version}
set project_dir ${ip_name}_${ip_version}

# ipx::open_core ${ip_repo_path}/component.xml
ipx::edit_ip_in_project -upgrade true -name $ipx_project -directory ${projdir}/system.tmp/${ipx_project} $ipx_xml

# set additional information about IP core
set_property display_name "UART Multiplexer" [ipx::current_core]
set_property description "UART-Fan Multiplexer IP core" [ipx::current_core]
set_property company_url "http://www.braiins.com" [ipx::current_core]

# remove original file groups;
ipx::remove_file_group xilinx_anylanguagesynthesis [ipx::current_core]
ipx::remove_file_group xilinx_anylanguagebehavioralsimulation [ipx::current_core]

# create new file groups
ipx::add_file_group -type vhdl:synthesis {} [ipx::current_core]
ipx::add_file_group -type vhdl:simulation {} [ipx::current_core]

set vhdl_synth_group [ipx::get_file_groups xilinx_vhdlsynthesis -of_objects [ipx::current_core]]
set vhdl_sim_group [ipx::get_file_groups xilinx_vhdlbehavioralsimulation -of_objects [ipx::current_core]]

set ip_hdl_list {}

# create directory if not exists
if { ![file exists "${ip_repo_path}/hdl"] } {
    file mkdir "${ip_repo_path}/hdl"
}

# copy source files into IP core directory
foreach FILE $ip_hdl_files {
    file copy -force [file join $src_path $FILE] [file join $ip_repo_path hdl]
    lappend ip_hdl_list [file join hdl $FILE]
}


####################################################################################################
# Add source files into IP core, update and save IP core
####################################################################################################
foreach FILE $ip_hdl_list {
    ipx::remove_file $FILE $vhdl_synth_group
    ipx::add_file $FILE $vhdl_synth_group
    set_property type vhdlSource [ipx::get_files $FILE -of_objects $vhdl_synth_group]
    set_property library_name xil_defaultlib [ipx::get_files $FILE -of_objects $vhdl_synth_group]
}

# Copy list of synthesis group into simulation group
ipx::copy_contents_from $vhdl_synth_group $vhdl_sim_group

set_property model_name $ip_name $vhdl_synth_group
set_property model_name $ip_name $vhdl_sim_group

# Update parameters and ports according to RTL sources
ipx::merge_project_changes hdl_parameters [ipx::current_core]
ipx::merge_project_changes ports [ipx::current_core]

ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]
close_project
