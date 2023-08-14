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
# Load auxiliary procedures
source src/tcl/utils.tcl

####################################################################################################
timestamp "Executing system_build.tcl ..."

####################################################################################################
# Defaults
####################################################################################################
# Set number of parallel jobs
set jobs [cpu_num]

# Limit number of jobs to 8
if {$jobs > 8} {
    set jobs 8
}

puts "INFO: Setting number of jobs to $jobs"

####################################################################################################
# Save any gui changes
####################################################################################################
validate_bd_design
make_wrapper -files [get_files $projdir/${design}.srcs/sources_1/bd/${design}/${design}.bd] -top

####################################################################################################
# Add generated wrapper file
####################################################################################################
remove_files -fileset sources_1 $projdir/${design}.srcs/sources_1/bd/${design}/hdl/${design}_wrapper.v
add_files -fileset sources_1 -norecurse $projdir/${design}.srcs/sources_1/bd/${design}/hdl/${design}_wrapper.v
# replace generated wrapper by custom modified file
# add_files -fileset sources_1 -norecurse src/hdl/${design}_wrapper.v

####################################################################################################
# Prepare for synthesis
####################################################################################################
if {[info exists synthesis_options]} {
    puts "INFO: Synthesis with following options: $synthesis_options"
    set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value $synthesis_options -objects [get_runs synth_1]
}
# Newer Vivado doesn't seem to support the above
if {[info exists verilog_define]} {
    puts "INFO: Adding following verilog defines to fileset: ${verilog_define}"
    set_property verilog_define ${verilog_define} [current_fileset]
}

# # Write system definition
# generate_target all [get_files $bd_design]
# write_hwdef -force -file "$projdir/results/${design}.hwdef"
# puts "Extracting content of hardware definition file ..."
# exec unzip "$projdir/results/${design}.hwdef" -d "$projdir/results/system"
# exit

####################################################################################################
# Synthesis
####################################################################################################
timestamp "Starting synthesis ..."
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1

set synth_status [get_property status [get_runs synth_1]]
set synth_progress [get_property progress [get_runs synth_1]]

if { $synth_status != "synth_design Complete!" || $synth_progress != "100%" } {
    puts "ERROR: \[SDSoC 0-0\]: Synthesis failed: status $synth_status, progress $synth_progress"
    exit 1
}

####################################################################################################
# Create reports
####################################################################################################
open_run synth_1
report_timing_summary -file $projdir/reports/timing_synth.rpt
report_utilization -file $projdir/reports/utilization_synth.rpt
report_utilization -hierarchical -file $projdir/reports/utilization_synth_hier.rpt
report_drc -file $projdir/reports/drc_synth.rpt

####################################################################################################
# Create hardware definition file
####################################################################################################
write_hwdef -force -file $projdir/results/${design}.hwdef

####################################################################################################
# Place and route
####################################################################################################
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]
set_property STRATEGY "Performance_Explore" [get_runs impl_1]

timestamp "Starting implementation ..."
launch_runs impl_1 -jobs $jobs
wait_on_run impl_1

set impl_status [get_property status [get_runs impl_1]]
set impl_progress [get_property progress [get_runs impl_1]]

if { $impl_status != "route_design Complete!" || $impl_progress != "100%" } {
    puts "ERROR: \[SDSoC 0-0\]: Implementation failed: status $impl_status, progress $impl_progress"
    exit 1
}

####################################################################################################
# Create netlist + reports
####################################################################################################
# write_verilog ./${design}.v

open_run impl_1
report_timing_summary -file $projdir/reports/timing_routed.rpt
report_utilization -file $projdir/reports/utilization_routed.rpt
report_utilization -hierarchical -file $projdir/reports/utilization_routed_hier.rpt
report_io -file $projdir/reports/io_placed.rpt
report_drc -file $projdir/reports/drc_routed.rpt

####################################################################################################
# Write bitstream
####################################################################################################
timestamp "Starting bitstream generation ..."
write_bitstream -force -bin_file -file $projdir/results/${design}.bit

####################################################################################################
# Write system definition
####################################################################################################
write_sysdef -force \
    -hwdef $projdir/results/${design}.hwdef \
    -bitfile $projdir/results/${design}.bit \
    -file $projdir/results/${design}.hdf

# extract content of archive
puts "Extracting content of hardware definition file ..."
exec unzip $projdir/results/${design}.hdf -d $projdir/results/system
