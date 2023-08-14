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

# Add path to Vivado executables if necessary
# export PATH=$PATH:
# Set license file
# export XILINXD_LICENSE_FILE=

print_help() {
    echo ""
    echo "Usage: ./run.sh BOARD"
    echo "  BOARD - name of the board, available values: S9, S9k, S11, S15, T15, S17, T17"
}

if [ "$1" == "--help" ]; then
    echo "Synthesis script for Xilinx FPGAs used in Antminer control boards"
    print_help
    exit 0
fi

if [ "$#" -ne 1 ]; then
    echo "Wrong number of arguments!"
    print_help
    exit 1
fi

WORK="build_$1"

rm -rf $WORK
mkdir $WORK
vivado -mode batch -notrace -source setup.tcl -journal $WORK/vivado.jou -log $WORK/vivado.log -tclargs $1
