# Pure helpers: no Vivado command, design mutation, or implicit frequency scan.
# A profile is one explicit future candidate. Missing file preserves baseline.
proc qwen_ddr_period_ps {root} {
    set file [file join $root ddr_period_ps.txt]
    set period 1071
    if {[file exists $file]} {
        set f [open $file r]
        set period [string trim [read $f]]
        close $f
    }
    # DS925: FFV -2 at 0.85V, two-rank DIMM is limited to 2133 Mb/s.
    # The fitted 16GB SODIMM is two-rank. Its own 2400 rating does not
    # override this FPGA PHY topology limit; do not admit the 833ps profile.
    # 938ps cannot keep this board's 2999ps reference in the vendor clock list.
    # 1000ps has passed native IP generation at 2999ps, M=9/D=2/O=6.
    if {$period ni {1071 1000}} {error "Unsupported fixed-reference DDR profile: $period"}
    return $period
}

proc qwen_ddr_ui_hz {input_ps multiply divide output_divide} {
    foreach value [list $input_ps $multiply $divide $output_divide] {
        if {![string is double -strict $value] || $value <= 0} {
            error "Invalid generated MIG clock divisor"
        }
    }
    # Derive from the generated MIG PLL parameters, not the requested DDR
    # period. Match the existing monitor's nearest-kHz convention.
    set hz [expr {1.0e12 / $input_ps * $multiply / $divide / $output_divide}]
    if {$hz < 200.0e6 || $hz > 305.0e6} {error "Unexpected generated UI clock: $hz"}
    return [expr {wide(round($hz / 1000.0)) * 1000}]
}

proc qwen_ddr_ui_payload_bound {ui_period_ns} {
    if {![string is double -strict $ui_period_ns] || $ui_period_ns <= 0.25} {
        error "Invalid UI timing period"
    }
    # Never relax the accepted 4 ns bound. For a faster receiver, tighten it
    # below one receiving cycle; actual implementation reports remain required.
    return [expr {min(4.0, $ui_period_ns - 0.25)}]
}
