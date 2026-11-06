# Onboard M.2 J5: schematic 505_TX0/RX0, PERST through PS MIO37.
# The manual's prose says lane1; the schematic and vendor PS preset use lane0.
# No PL PCIe, GT, GPIO, reference-clock or SSD arbitration IP is instantiated.
proc configure_ps_m2 {out} {
    set ps [get_bd_cells ps]
    foreach {key value} {
        PSU__PCIE__PERIPHERAL__ENABLE 1
        PSU__PCIE__PERIPHERAL__ROOTPORT_ENABLE 1
        PSU__PCIE__PERIPHERAL__ENDPOINT_ENABLE 0
        PSU__PCIE__PERIPHERAL__ROOTPORT_IO {MIO 37}
        PSU__PCIE__LANE0__ENABLE 1
        PSU__PCIE__LANE0__IO {GT Lane0}
        PSU__PCIE__LANE1__ENABLE 0
        PSU__PCIE__LANE2__ENABLE 0
        PSU__PCIE__LANE3__ENABLE 0
        PSU__PCIE__LINK_SPEED {5.0 Gb/s}
        PSU__PCIE__MAXIMUM_LINK_WIDTH x1
        PSU__PCIE__DEVICE_PORT_TYPE {Root Port}
        PSU__PCIE__REF_CLK_SEL {Ref Clk0}
        PSU__PCIE__REF_CLK_FREQ 100
    } {
        set actual [get_property CONFIG.$key $ps]
        if {$actual ne $value} {error "PS_M2_VENDOR_PRESET_MISMATCH $key actual=$actual expected=$value"}
    }
    foreach port {0 1 2 3} {
        set bus [get_bd_intf_ports S_AXI_PS${port}]
        set net [get_bd_intf_nets -of_objects $bus]
        if {[llength $net]!=1} {error "PS_M2_HP_NET_MISSING $port"}
        set pins [get_bd_intf_pins -of_objects $net]
        if {[llength $pins]!=1 || $pins ne "/ps/S_AXI_HP${port}_FPD"} {error "PS_M2_HP_NOT_DIRECT $port $pins"}
    }
    if {[llength [get_bd_cells -quiet ssd*]] || [llength [get_bd_intf_ports -quiet m2*]] || [llength [get_bd_ports -quiet m2*]]} {
        error PS_M2_UNEXPECTED_PL_SSD_BRANCH
    }
    set f [open [file join $out ps_m2_configuration.txt] w]
    puts $f "PS_M2_CONFIGURATION_PASS storage=onboard_J5 ps_gtr=lane0 perst=MIO37 mode=root_port speed=Gen2 width=x1 HP0..3=direct PL_SSD_IP=none hardware_actions=0"
    close $f
}
