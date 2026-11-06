# Candidate-local timing report hook for the verified nominal core clock.
set q9_nominal_clks [get_clocks -quiet clk_out1_sidewinder_core_clk_wiz]
if {[llength $q9_nominal_clks] != 1} {
    error "counter_diag_nominal: nominal core clock is missing"
}
set q9_nominal_period [get_property PERIOD [lindex $q9_nominal_clks 0]]
if {[expr {abs($q9_nominal_period-(1000.0/250.0)) > 0.017}]} {
    error "counter_diag_nominal: unexpected core period $q9_nominal_period"
}
puts "COUNTER_DIAG_CORE_CLOCK name=clk_out1_sidewinder_core_clk_wiz period=$q9_nominal_period target_MHz=250"
report_clocks -file counter_diag_nominal_clocks.rpt
report_clock_networks -file counter_diag_nominal_clock_networks.rpt
report_timing_summary -delay_type min_max -file counter_diag_nominal_timing_summary.rpt
