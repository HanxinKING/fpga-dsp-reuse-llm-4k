# Called once on the current isolated BD by the native prepare stage.
# Keep the original SmartConnect address decoder and DECERR protection.
# Move the 128 -> 512 accumulation into the vendor packet FIFO upsizer.
proc configure_q9_ui65 {} {
    set sc [get_bd_cells ddr_smc]
    set ps [get_bd_cells ps]
    if {[get_property CONFIG.PSU__MAXIGP0__DATA_WIDTH $ps] != 128} {error UI65_PS_WIDTH}
    if {[llength [get_bd_cells -quiet ddr_width65]]} {error UI65_PRESERVE_EXISTING_CONFIGURATION}
    set before [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps/Data]]
    set addresses {}
    foreach a $before {lappend addresses [list $a [get_property OFFSET $a] [get_property RANGE $a]]}
    set net [get_bd_intf_nets -of_objects [get_bd_intf_pins ddr_smc/S00_AXI]]
    set ends [get_bd_intf_pins -of_objects $net]
    if {[llength $ends]!=2 || [lsearch -exact $ends /ddr_hpm_slice/M_AXI]<0} {error "UI65_TOPOLOGY $ends"}
    set master [get_bd_intf_pins ddr_hpm_slice/M_AXI]
    set address_bits [get_property CONFIG.ADDR_WIDTH $master]
    set id_bits [get_property CONFIG.ID_WIDTH $master]
    if {![string is integer -strict $address_bits] || $address_bits<37 || ![string is integer -strict $id_bits] || $id_bits<1} {error "UI65_MASTER_GEOMETRY addr=$address_bits id=$id_bits"}
    disconnect_bd_intf_net $net [get_bd_intf_pins ddr_smc/S00_AXI]
    set up [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dwidth_converter:2.1 ddr_width65]
    set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.READ_WRITE_MODE READ_WRITE \
      CONFIG.SI_DATA_WIDTH 128 CONFIG.MI_DATA_WIDTH 512 CONFIG.ADDR_WIDTH $address_bits \
      CONFIG.SI_ID_WIDTH $id_bits CONFIG.FIFO_MODE 1 CONFIG.ACLK_ASYNC 0] $up
    connect_bd_intf_net [get_bd_intf_pins ddr_hpm_slice/M_AXI] [get_bd_intf_pins ddr_width65/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins ddr_width65/M_AXI] [get_bd_intf_pins ddr_smc/S00_AXI]
    connect_bd_net [get_bd_ports ui_clk] [get_bd_pins ddr_width65/s_axi_aclk]
    connect_bd_net [get_bd_ports aresetn] [get_bd_pins ddr_width65/s_axi_aresetn]
    validate_bd_design
    foreach row $addresses {
      lassign $row path offset range
      set a [get_bd_addr_segs $path]
      if {[get_property OFFSET $a] ne $offset || [get_property RANGE $a] ne $range} {error "UI65_ADDRESS_MAP_CHANGED $path"}
    }
    if {[get_property CONFIG.FREQ_HZ [get_bd_ports ui_clk]]!=300120000} {error UI65_UI_CLOCK_CHANGED}
    save_bd_design
    puts {UI65_VENDOR_PACKET_UPSIZER_CONFIGURED estimated_added_bram36=16 decoder_preserved=1 measured_resources_pending=1}
}
