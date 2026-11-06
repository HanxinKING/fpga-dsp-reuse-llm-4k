if {[llength [get_ports -quiet m2*]]} {error PS_M2_PL_STORAGE_PORTS_SURVIVED}
set forbidden [get_cells -quiet -hier -filter {REF_NAME =~ GTHE* || REF_NAME =~ GTYE* || REF_NAME =~ PCIE* || NAME =~ *ssd_rp* || NAME =~ *ssd_dma_smc*}]
if {[llength $forbidden]} {error "PS_M2_PL_SSD_CELLS_SURVIVED $forbidden"}
set f [open [file join $out ${stage}_ps_m2_structure.txt] w]
puts $f "PS_M2_STRUCTURE_PASS stage=$stage PL_PCIE_cells=0 PL_GT_cells=0 FMC_M2_ports=0"
close $f
