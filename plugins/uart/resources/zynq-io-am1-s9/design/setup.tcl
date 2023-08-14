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
# Procedure for printing state of script run with timestamp
proc timestamp {arg} {
    puts ""
    puts [string repeat "-" 80]
    puts "[clock format [clock seconds] -format %H:%M:%S:] $arg"
    puts [string repeat "-" 80]
}

####################################################################################################
# CHECK INPUT ARGUMENTS
####################################################################################################
# check number of arguments
if {$argc == 1} {
    set board [lindex $argv 0]
} else {
    puts "ERROR: Wrong number of TCL arguments! Expected 1 argument, get $argc"
    puts "List of arguments: $argv"
    exit 1
}

# list of supported boards
set supported_boards [list \
    "S9" \
    "S9k" \
    "S11" \
    "S15" \
    "T15" \
    "S17" \
    "T17" \
]

# check name of the board
if {$board ni $supported_boards} {
    puts "ERROR: Unknown board: $board"
    puts "List of supported boards: [join $supported_boards {, }]"
    exit 1
}

####################################################################################################
# Preset global variables and attributes
####################################################################################################
# Project name
set project "Zynq IO"

# Design name
set design "system"

# Device name
if {$board == "S9"} {
    set fpga "xc7z010"
    set partname "xc7z010clg400-1"
} else {
    set fpga "xc7z007s"
    set partname "xc7z007sclg225-1"
}

# Project directory
set projdir "./build_$board"

# Paths to all IP blocks to use in Vivado "system.bd"
set ip_repos [ list \
    "$projdir" \
]

# Set synthesis and implementation constraints files
set constraints_files [list \
    "src/constrs/pin_assignment_${fpga}.tcl" \
]

####################################################################################################
# Set name of top module
set top_module "system_wrapper"

####################################################################################################
# Generate build ID information
####################################################################################################
# get timestamp
set build_id [clock seconds]
set date_time [clock format $build_id -format "%d.%m.%Y %H:%M:%S"]

puts [string repeat "-" 80]
puts "Project:  $project"
puts "Board:    $board"
puts "Build ID: ${build_id} (${date_time})"

####################################################################################################
# Run synthesis, P&R and bitstream generation
####################################################################################################
# Create new project and generate block design of system
source "system_init.tcl"

# Run synthesis, implementation and bitstream generation
source "system_build.tcl"

# Run simulation & verification
source "src/ip_cores/axi_bm13xx/fve/sim.tcl"

####################################################################################################
# Exit Vivado
####################################################################################################
# Generate build history file, backup of build directory, print statistics
source "system_final.tcl"
