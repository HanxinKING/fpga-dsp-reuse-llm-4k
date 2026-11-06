# Called on an isolated copy of the already accepted PS bridge BD.
# Four narrow HP ports share the existing PS DDR_LOW. No DDR geometry,
# voltage, MIO, physical pins, or PS clock/DDR timing is changed here.
proc configure_q3_dual_ddr_ps {ui_hz} {
    if {$ui_hz != 300120000} {error "Dual DDR UI contract changed; revalidate timing and BFM"}
    set ps [get_bd_cells ps]
    set saved_ddr_low [get_property CONFIG.PSU_DDR_RAM_HIGHADDR $ps]
    # Physical PS DDR is vendor-configured as 8 GiB. Q7's weights and DMA
    # pool use only the fixed LOW segment; the HIGH segment remains unused.
    if {[expr {$saved_ddr_low}] ni {2147483647 8589934591}} {error "Unexpected RK PS DDR extent: $saved_ddr_low"}
    set properties {}
    for {set port 0} {$port<4} {incr port} {
        set gp [expr {$port+2}]
        lappend properties CONFIG.PSU__USE__S_AXI_GP${gp} 1
        lappend properties CONFIG.PSU__SAXIGP${gp}__DATA_WIDTH 128
    }
    set_property -dict $properties $ps
    set_property CONFIG.FREQ_HZ $ui_hz [get_bd_ports ui_clk]
    # The routed UI critical path was PS MAXIGP0 -> SmartConnect upsizer CE.
    # Full slices register every AXI channel, including READY, with no bubbles
    # at steady state. Preserve the existing UI clock, reset and AXI widths.
    set old_ddr_net [get_bd_intf_nets -of_objects [get_bd_intf_pins ps/M_AXI_HPM0_FPD]]
    if {[llength $old_ddr_net]!=1} {error "PS DDR master interface net missing"}
    set old_ddr_ends [get_bd_intf_pins -of_objects $old_ddr_net]
    if {[llength $old_ddr_ends]!=2 || [lsearch -exact $old_ddr_ends /ddr_smc/S00_AXI]<0} {error "Unexpected PS DDR master topology: $old_ddr_ends"}
    disconnect_bd_intf_net $old_ddr_net [get_bd_intf_pins ddr_smc/S00_AXI]
    set slice [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_register_slice:2.1 ddr_hpm_slice]
    set_property -dict [list CONFIG.REG_AW 1 CONFIG.REG_W 1 CONFIG.REG_B 1 CONFIG.REG_AR 1 CONFIG.REG_R 1] $slice
    connect_bd_intf_net [get_bd_intf_pins ps/M_AXI_HPM0_FPD] [get_bd_intf_pins ddr_hpm_slice/S_AXI]
    connect_bd_intf_net [get_bd_intf_pins ddr_hpm_slice/M_AXI] [get_bd_intf_pins ddr_smc/S00_AXI]
    connect_bd_net [get_bd_ports ui_clk] [get_bd_pins ddr_hpm_slice/aclk]
    connect_bd_net [get_bd_ports aresetn] [get_bd_pins ddr_hpm_slice/aresetn]
    puts "Q7_DDR_HPM_FULL_SLICE channels=AW,W,B,AR,R ui_hz=$ui_hz"
    for {set port 0} {$port<4} {incr port} {
        set bus [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 S_AXI_PS${port}]
        set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.ADDR_WIDTH 40 CONFIG.DATA_WIDTH 128 \
            CONFIG.ID_WIDTH 6 CONFIG.ARUSER_WIDTH 1 CONFIG.AWUSER_WIDTH 1 \
            CONFIG.HAS_BURST 1 CONFIG.HAS_LOCK 1 CONFIG.HAS_CACHE 1 CONFIG.HAS_PROT 1 \
            CONFIG.HAS_QOS 1 CONFIG.HAS_REGION 0 CONFIG.SUPPORTS_NARROW_BURST 0 \
            CONFIG.NUM_READ_OUTSTANDING 8 CONFIG.NUM_WRITE_OUTSTANDING 1 \
            CONFIG.FREQ_HZ $ui_hz] $bus
        connect_bd_intf_net $bus [get_bd_intf_pins ps/S_AXI_HP${port}_FPD]
        connect_bd_net [get_bd_ports ui_clk] [get_bd_pins ps/saxihp${port}_fpd_aclk]
    }
    # Derive reachable PS segments from the live BD; validate rejects mappings
    # not exposed by this PS configuration. Only low DDR is used by the RTL.
    assign_bd_address
    set old_bus [get_property CONFIG.ASSOCIATED_BUSIF [get_bd_ports ui_clk]]
    set_property CONFIG.ASSOCIATED_BUSIF "${old_bus}:S_AXI_PS0:S_AXI_PS1:S_AXI_PS2:S_AXI_PS3" [get_bd_ports ui_clk]
    puts "Q3_DUAL_PS_PORTS_CONFIGURED hp_ports=4 narrow_bits=128 ps_controllers=1 ui_hz=$ui_hz"
}

# Export only the generated AFI register block, never DDR/PLL/MIO init. The
# vendor FSBL remains authoritative for the DIMM and board electrical setup.
proc export_q3_dual_afi {root} {
    # import_files preserves the source BD's directory ("board" here), not
    # necessarily its design name. Still require the exact generated PS IP.
    set paths [glob -nocomplain [file join $root project *.gen sources_1 bd * ip sidewinder_ps_dual_hpm_bridge_ps_0 psu_init.tcl]]
    if {[llength $paths] != 1} {error "Expected exactly one generated PS init"}
    set f [open [lindex $paths 0] r];set text [read $f];close $f
    if {![regexp {(?s)set psu_afi_config \{(.*?)\n\}} $text -> block]} {error "Generated AFI block missing"}
    set out [open [file join $root dual_afi_config.tcl] w]
    puts $out "# AFI-only commands extracted from this candidate's generated psu_init.tcl"
    set hp_widths 0
    foreach line [split $block "\n"] {
        if {![regexp {^\s*mask_write\s+(0[Xx][0-9A-Fa-f]+)\s+(0[Xx][0-9A-Fa-f]+)\s+(0[Xx][0-9A-Fa-f]+)} $line -> address mask value]} {continue}
        set a [expr {$address}];set m [expr {$mask}];set v [expr {$value}]
        set hp [expr {$a>=0xFD380000 && $a<=0xFD3B0014 && (($a&0xffff)==0 || ($a&0xffff)==0x14)}]
        if {$hp} {
            if {($m&3)!=3 || ($v&3)!=0} {error "HP interface is not generated as 128 bit"}
            incr hp_widths
        } elseif {$a!=0xFD1A0100 && $a!=0xFF5E023C && $a!=0xFD615000 && $a!=0xFF419000} {
            # Explicit reset/HPM-width register allowlist (not DDRC/PHY).
            close $out;error "Unreviewed generated AFI register: $address"
        }
        puts $out "q3_mask_write $address $mask $value"
    }
    close $out
    if {$hp_widths!=8} {error "Expected 4 HP read + write width settings, got $hp_widths"}
    puts "Q3_DUAL_AFI_EXPORTED hp_widths=$hp_widths"
}
