// # Generate IP Cores
// ####################################################################################################
// // TODO: Translate the following TCL line to Rust
// // source generate_ip_axi_bm13xx.tcl
// // TODO: Translate the following TCL line to Rust
// // source generate_ip_axi_fan_ctrl.tcl
// // TODO: Translate the following TCL line to Rust
// // source generate_ip_uart_mux.tcl
// 
// ####################################################################################################
// # Add IP Repositories to search path
// ####################################################################################################
// 
// // TODO: Translate the following TCL line to Rust
// // set other_repos [get_property ip_repo_paths [current_project]]
// // TODO: Translate the following TCL line to Rust
// // set_property  ip_repo_paths  "$ip_repos $other_repos" [current_project]
// 
// // TODO: Translate the following TCL line to Rust
// // update_ip_catalog -rebuild
// 
// ####################################################################################################
// # CREATE BLOCK DESIGN (GUI/TCL COMBO)
// ####################################################################################################
// // TODO: Translate the following TCL line to Rust
// // timestamp "Generating system block design ..."
// 
// // TODO: Translate the following TCL line to Rust
// // set_property target_language Verilog [current_project]
// // TODO: Translate the following TCL line to Rust
// // create_bd_design "system"
// 
// // TODO: Translate the following TCL line to Rust
// // puts "Source system_${fpga}.tcl ..."
// // TODO: Translate the following TCL line to Rust
// // source "system_${fpga}.tcl"
// 
// // TODO: Translate the following TCL line to Rust
// // validate_bd_design
// // TODO: Translate the following TCL line to Rust
// // write_bd_tcl -force ./${design}.backup.tcl
// // TODO: Translate the following TCL line to Rust
// // make_wrapper -files [get_files $projdir/${design}.srcs/sources_1/bd/system/system.bd] -top
// 
// ####################################################################################################
// # Add files
// ####################################################################################################
// 
// # HDL
// // TODO: Translate the following TCL line to Rust
// // if {[string equal [get_filesets -quiet sources_1] ""]} {
// // TODO: Translate the following TCL line to Rust
// //     create_fileset -srcset sources_1
// // TODO: Translate the following TCL line to Rust
// // }
// // TODO: Translate the following TCL line to Rust
// // set top_wrapper $projdir/${design}.srcs/sources_1/bd/system/hdl/system_wrapper.v
// // TODO: Translate the following TCL line to Rust
// // add_files -norecurse -fileset [get_filesets sources_1] $top_wrapper
// 
// # Constraints
// // TODO: Translate the following TCL line to Rust
// // if {[string equal [get_filesets -quiet constrs_1] ""]} {
// // TODO: Translate the following TCL line to Rust
// //   create_fileset -constrset constrs_1
// // TODO: Translate the following TCL line to Rust
// // }
// // TODO: Translate the following TCL line to Rust
// // if {[llength $constraints_files] != 0} {
// // TODO: Translate the following TCL line to Rust
// //     add_files -norecurse -fileset [get_filesets constrs_1] $constraints_files
// // TODO: Translate the following TCL line to Rust
// // }
// 