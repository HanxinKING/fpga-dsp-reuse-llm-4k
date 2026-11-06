set f [open [file join $root "${stage}_ssd_lane_mapping.txt"] w]
foreach {kind pads} {rxp {AJ2 AK4 AL2 AM4} rxn {AJ1 AK3 AL1 AM3} txp {AH8 AJ6 AK8 AL6} txn {AH7 AJ5 AK7 AL5}} {
    for {set lane 0} {$lane<4} {incr lane} {
        set name [format {m2_pcie_%s[%d]} $kind $lane]
        set port [get_ports $name]
        set expected [lindex $pads $lane]
        set actual [get_property PACKAGE_PIN $port]
        set cells [get_cells -of_objects [get_pins -leaf -of_objects [get_nets -segments -of_objects $port]] -filter {REF_NAME == GTHE4_CHANNEL}]
        set cells [lsort -unique $cells]
        if {[llength $cells]!=1} {error "M2_UNIQUE_GT_REQUIRED:$name"}
        set site [get_sites -of_objects [get_package_pins $expected]]
        set loc [get_property LOC $cells]
        puts $f "port=$name expected_pad=$expected actual_pad=$actual site=$site cell_loc=$loc cell=$cells"
        if {$loc ne $site} {error "M2_GT_LOCATION_MISMATCH:$name:$loc:$site"}
        if {$actual ne "" && $actual ne $expected} {error "M2_PAD_MISMATCH:$name:$actual:$expected"}
    }
}
set pcie [get_cells -hier -filter {REF_NAME == PCIE40E4}]
if {[llength $pcie]!=1 || [get_property PL_DISABLE_LANE_REVERSAL $pcie] ne "FALSE"} {error SSD_ROOT_LANE_REVERSAL_DISABLED}
puts $f "ROOT_PORT_LANE_REVERSAL_ENABLED=1";close $f
puts "SSD_LANE_MAPPING_16_PINS_PASS"

