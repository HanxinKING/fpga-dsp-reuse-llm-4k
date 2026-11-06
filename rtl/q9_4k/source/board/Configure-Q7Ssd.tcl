# Called only after configure_q3_dual_ddr_ps in a new project.
proc configure_q7_ssd {root} {
# Canonicalize the existing Q7 bridge before taking the preservation snapshot.
# The imported PS still carries 10 MHz metadata until BD validation propagates
# its already-connected 300.120 MHz UI and 300 MHz control clocks.
validate_bd_design
set ps [get_bd_cells ps]
set before_ps [dict create]
foreach key [list_property $ps] {if {[string match CONFIG.* $key]} {dict set before_ps $key [get_property $key $ps]}}
set before_maps [dict create]
foreach space [get_bd_addr_spaces] {
    foreach seg [get_bd_addr_segs -of_objects $space] {
        dict set before_maps $seg [list [get_property OFFSET $seg] [get_property RANGE $seg]]
    }
}


set rp [create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:4.2 ssd_rp]
set_property -dict [list \
    CONFIG.functional_mode {AXI_Bridge} \
    CONFIG.mode_selection {Advanced} \
    CONFIG.device_port_type {Root_Port_of_PCI_Express_Root_Complex} \
    CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
    CONFIG.pl_link_cap_max_link_width {X4} \
    CONFIG.axi_data_width {256_bit} \
    CONFIG.axi_addr_width {64} \
    CONFIG.axisten_freq {125} \
    CONFIG.en_gt_selection {true} \
    CONFIG.pcie_blk_locn {X1Y0} \
    CONFIG.select_quad {GTH_Quad_226} \
    CONFIG.pf0_msi_enabled {false} \
    CONFIG.pf0_bar0_enabled {false} \
    CONFIG.pf0_bar1_enabled {false} \
    CONFIG.BASEADDR {0xA0000000} \
    CONFIG.HIGHADDR {0xA3FFFFFF} \
    CONFIG.axibar_num {1} \
    CONFIG.axibar_0 {0x0000000088000000} \
    CONFIG.axibar_highaddr_0 {0x000000008BFFFFFF} \
    CONFIG.axibar2pciebar_0 {0x0000000088000000}] $rp
foreach {key expected} {select_quad GTH_Quad_226 pcie_blk_locn X1Y0 pl_link_cap_max_link_width X4 pl_link_cap_max_link_speed 8.0_GT/s axi_data_width 256_bit axisten_freq 125} {
    set actual [get_property CONFIG.$key $rp]
    if {$actual ne $expected} {error "RK_SSD_CONFIG_REJECTED $key expected=$expected actual=$actual"}
}

set ref [create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:2.2 ssd_refclk]
set_property -dict [list CONFIG.C_BUF_TYPE {IBUFDSGTE} CONFIG.C_SIZE {1}] $ref
set refport [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 m2_refclk]
set_property CONFIG.FREQ_HZ 100000000 $refport
connect_bd_intf_net $refport [get_bd_intf_pins ssd_refclk/CLK_IN_D]
connect_bd_net [get_bd_pins ssd_refclk/IBUF_OUT] [get_bd_pins ssd_rp/sys_clk_gt]
connect_bd_net [get_bd_pins ssd_refclk/IBUF_DS_ODIV2] [get_bd_pins ssd_rp/sys_clk]
connect_bd_net [get_bd_ports ctrl_aresetn] [get_bd_pins ssd_rp/sys_rst_n]
set mgt [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:pcie_7x_mgt_rtl:1.0 m2_pcie]
connect_bd_intf_net $mgt [get_bd_intf_pins ssd_rp/pcie_mgt]

set gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 ssd_gpio]
set_property -dict [list CONFIG.C_GPIO_WIDTH {1} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_DOUT_DEFAULT {0x00000001}] $gpio
set perst [create_bd_port -dir O m2_perst_n]
connect_bd_net $perst [get_bd_pins ssd_gpio/gpio_io_o]
connect_bd_net [get_bd_ports ctrl_clk] [get_bd_pins ssd_gpio/s_axi_aclk]
connect_bd_net [get_bd_ports ctrl_aresetn] [get_bd_pins ssd_gpio/s_axi_aresetn]

set_property -dict [list CONFIG.NUM_MI {3} CONFIG.NUM_CLKS {2}] [get_bd_cells ctrl_smc]
connect_bd_net [get_bd_pins ssd_rp/axi_aclk] [get_bd_pins ctrl_smc/aclk1]
set_property -dict [list CONFIG.NUM_MI {2} CONFIG.NUM_CLKS {2}] [get_bd_cells ddr_smc]
connect_bd_net [get_bd_pins ssd_rp/axi_aclk] [get_bd_pins ddr_smc/aclk1]
connect_bd_intf_net [get_bd_intf_pins ddr_smc/M01_AXI] [get_bd_intf_pins ssd_rp/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ctrl_smc/M01_AXI] [get_bd_intf_pins ssd_rp/S_AXI_B]
connect_bd_intf_net [get_bd_intf_pins ctrl_smc/M02_AXI] [get_bd_intf_pins ssd_gpio/S_AXI]

set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 ssd_dma_smc]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {2}] $dma
set oldnet [get_bd_intf_nets -of_objects [get_bd_intf_pins ps/S_AXI_HP0_FPD]]
if {[llength $oldnet] != 1} {error "HP0_ORIGINAL_NET_MISSING"}
delete_bd_objs $oldnet
connect_bd_intf_net [get_bd_intf_ports S_AXI_PS0] [get_bd_intf_pins ssd_dma_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ssd_rp/M_AXI_B] [get_bd_intf_pins ssd_dma_smc/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins ssd_dma_smc/M00_AXI] [get_bd_intf_pins ps/S_AXI_HP0_FPD]
connect_bd_net [get_bd_ports ui_clk] [get_bd_pins ssd_dma_smc/aclk]
connect_bd_net [get_bd_pins ssd_rp/axi_aclk] [get_bd_pins ssd_dma_smc/aclk1]
connect_bd_net [get_bd_ports aresetn] [get_bd_pins ssd_dma_smc/aresetn]

assign_bd_address -offset 0xA0000000 -range 0x04000000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs -of_objects [get_bd_intf_pins ssd_rp/S_AXI_LITE]]
assign_bd_address -offset 0x88000000 -range 0x04000000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs -of_objects [get_bd_intf_pins ssd_rp/S_AXI_B]]
assign_bd_address -offset 0x83000000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs -of_objects [get_bd_intf_pins ssd_gpio/S_AXI]]
assign_bd_address -offset 0x00000000 -range 0x80000000 -target_address_space [get_bd_addr_spaces -of_objects [get_bd_intf_pins ssd_rp/M_AXI_B]] [get_bd_addr_segs ps/SAXIGP2/HP0_DDR_LOW]
# The new arbiter preserves the pre-existing HP0 low/high address spaces.
foreach suffix {LOW HIGH} {
    set oldseg /S_AXI_PS0/SEG_ps_HP0_DDR_${suffix}
    if {![dict exists $before_maps $oldseg]} {
        if {$suffix eq "LOW"} {error "MISSING_ORIGINAL_HP0_MAP $oldseg"}
        continue
    }
    lassign [dict get $before_maps $oldseg] old_offset old_range
    assign_bd_address -offset $old_offset -range $old_range -target_address_space [get_bd_addr_spaces S_AXI_PS0] [get_bd_addr_segs ps/SAXIGP2/HP0_DDR_${suffix}]
}
validate_bd_design
# PG194: XDMA AXI-Lite control addresses are 512 MiB aligned. Bits
# [27:20] encode the ECAM bus, so 0x84000000 incorrectly selects bus 64.
set mapped [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps/Data] -filter {NAME =~ *ssd_rp*CTL0*}]
if {[llength $mapped]!=1} {error SSD_CONTROL_SEGMENT_NOT_UNIQUE}
set control_base [get_property OFFSET $mapped]
set control_range [get_property RANGE $mapped]
if {[expr {$control_base}]!=0xA0000000 || [expr {$control_range}]!=0x04000000 ||
    [expr {$control_base & 0x1fffffff}]!=0 || [expr {($control_base>>20)&255}]!=0} {error SSD_CONTROL_ALIGNMENT_FAILURE}
puts "SSD_CONTROL_512M_ALIGNMENT_PASS base=$control_base range=$control_range root_bus=0"
dict for {key old} $before_ps {
    set now [get_property $key $ps]
    if {$now eq $old} {continue}
    if {[string match *__FRACDATA $key] && [string is double -strict $old] && [string is double -strict $now] && double($old)==0 && double($now)==0} {continue}
    error "UNRELATED_PS_CONFIG_CHANGED $key: $old -> $now"
}
dict for {seg value} $before_maps {
    lassign $value old_offset old_range
    if {[llength [get_bd_addr_segs -quiet $seg]]!=1} {error "ORIGINAL_MASTER_MAP_LOST $seg"}
    set now_offset [get_property OFFSET $seg]
    set now_range [get_property RANGE $seg]
    puts "SSD_ORIGINAL_MAP_CHECK $seg old_offset=$old_offset now_offset=$now_offset old_range=$old_range now_range=$now_range"
    if {[expr {$old_offset}] != [expr {$now_offset}] || [expr {$old_range}] != [expr {$now_range}]} {error "ORIGINAL_CPU_ADDRESS_MAP_CHANGED $seg old=$value now=[list $now_offset $now_range]"}
}

set audit [open [file join $root ssd_bd_address_audit.txt] w]
puts $audit "part=[get_property PART [current_project]] core_hz=300000000 ui_hz=300120000 SSD_AXI_hz=125000000"
foreach space [get_bd_addr_spaces] {
    foreach seg [get_bd_addr_segs -of_objects $space] {puts $audit "$seg [get_property OFFSET $seg] [get_property RANGE $seg]"}
}
close $audit
puts "Q7_SSD_INTEGRATION_CONFIGURED original_maps_preserved=1 compute_contract_unchanged=1"
}

