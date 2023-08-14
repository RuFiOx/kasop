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
timestamp "Finishing build ..."

####################################################################################################
# Get information about GIT repository
####################################################################################################
if { [catch {exec git status} msg] } {
    set git_log "Warning: GIT repository not found!"
    set git_diff ""
    puts $git_log
} else {
    # get last commit
    set git_log [exec git log -1]
    # check if git worktree is clean
    set git_diff [exec git diff HEAD]
}

####################################################################################################
# Generate build history file
####################################################################################################
# name of the build history file
set filename "build_history.txt"

# open the file for read/write
set fd [open $filename "a+"]

# read content ofthe file
seek $fd 0 start
set file_data [read $fd]

# put new record at beginning
seek $fd 0 start
puts $fd [string repeat "-" 80]
puts $fd "Build ${date_time} (${build_id})"
puts $fd [string repeat "-" 80]
puts $fd "Project:       $project"
puts $fd "Board:         $board"
puts $fd [string repeat "-" 80]
puts $fd $git_log
puts $fd ""

if { [string length $git_diff] > 0 } {
    puts $fd "Warning: git worktree is dirty! Check git diff log in build directory."
    puts $fd ""
}

puts $fd ""

# put original file content
puts -nonewline $fd $file_data

# close the file
close $fd

####################################################################################################
# Save git diff into file in build directory
####################################################################################################
if { [string length $git_diff] > 0 } {
    set filename [file join $projdir git.diff]
    set fd [open $filename "w"]
    puts $fd $git_diff
    close $fd
}

####################################################################################################
# Report utilization
####################################################################################################
# name of the report file
set filename [file join $projdir reports utilization_routed.rpt]

# open the file for read
set fd [open $filename "r"]

# extract line with Slice LUTs
while {[gets $fd line] >= 0} {
    if [regexp "Slice LUTs" $line] {
        set lineLUT $line
    }
    if [regexp "LUT as Memory" $line] {
        set lineLUTRAM $line
    }
    if [regexp "Slice Registers" $line] {
        set lineRegs $line
    }
    if [regexp "\\| Block RAM Tile" $line] {
        set lineBram $line
    }
    if [regexp "DSPs" $line] {
        set lineDSP $line
    }
}

# close the file
close $fd

# extract info about utilization from report
set numLUT [string trim [lindex [split $lineLUT "|"] 2]]
set percentLUT [string trim [lindex [split $lineLUT "|"] 5]]
set numLUTRAM [string trim [lindex [split $lineLUTRAM "|"] 2]]
set percentLUTRAM [string trim [lindex [split $lineLUTRAM "|"] 5]]
set numRegs [string trim [lindex [split $lineRegs "|"] 2]]
set percentRegs [string trim [lindex [split $lineRegs "|"] 5]]
set numBRAM [string trim [lindex [split $lineBram "|"] 2]]
set percentBRAM [string trim [lindex [split $lineBram "|"] 5]]
set numDSP [string trim [lindex [split $lineDSP "|"] 2]]
set percentDSP [string trim [lindex [split $lineDSP "|"] 5]]

# get timing parameters
set wns [format {%.3f} [get_property STATS.WNS [current_run]]]

# print report into console
puts "Device utilization:"
puts "LUT:     $numLUT\t ${percentLUT}%"
puts "LUT RAM: $numLUTRAM\t ${percentLUTRAM}%"
puts "FF:      $numRegs\t ${percentRegs}%"
puts "BRAM:    $numBRAM\t ${percentBRAM}%"
puts "DSP:     $numDSP\t ${percentDSP}%"
puts ""
puts "Timing:"
puts "WNS:     $wns ns"
puts [string repeat "-" 80]

# name of CSV file
set filename "report.csv"

# check if file exists
if { [file exists $filename] } {
    # open the file for append
    set fd [open $filename "a"]
} else {
    # open the file for write and create header
    set fd [open $filename "w"]
    puts -nonewline $fd {"Project Name","Top module","Build ID","Build Time","Device",}
    puts -nonewline $fd {"LUT [-]","LUT [%]",}
    puts -nonewline $fd {"LUT RAM [-]","LUT RAM [%]",}
    puts -nonewline $fd {"FF [-]","FF [%]",}
    puts -nonewline $fd {"BRAM [-]","BRAM [%]",}
    puts -nonewline $fd {"DSP [-]","DSP [%]",}
    puts $fd {"WNS [ns]"}
}

# print report to CSV file
puts -nonewline $fd "\"$project $board\",\"$top_module\",\"${build_id}\",\"${date_time}\",\"$partname\","
puts -nonewline $fd "$numLUT,$percentLUT,"
puts -nonewline $fd "$numLUTRAM,$percentLUTRAM,"
puts -nonewline $fd "$numRegs,$percentRegs,"
puts -nonewline $fd "$numBRAM,$percentBRAM,"
puts -nonewline $fd "$numDSP,$percentDSP,"
puts $fd "$wns"

# close the file
close $fd

####################################################################################################
# Final report
####################################################################################################
set elapsed_time [clock format [expr [clock seconds] - $build_id] -gmt 1 -format "%H:%M:%S"]
puts "Elapsed time: $elapsed_time"

####################################################################################################
# Create backup of build directory
####################################################################################################
puts "Creating backup of build directory ..."
set backup_dir [file join backup "${projdir}_${build_id}"]
set bitstream_src [file join $projdir results system.bit]
set bitstream_dst [file join backup "${design}_${board}.bit"]

if { ![file exists "backup"] } {
    file mkdir "backup"
}

if { [file exists $bitstream_dst] } {
    file delete -force $bitstream_dst
}

file copy $projdir $backup_dir
file copy $bitstream_src $bitstream_dst
