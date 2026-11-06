set rk_cdc_board {E:/KV_Cache/q9_context4k_T80_20261102_01/candidate/source/board}
set rk_cdc_output [pwd]
# No whole-clock false path: retain all synchronous setup/hold paths.
# Handshake payloads are held until acknowledgement; bound their real route.
#
# This script is added as a LATE-processing constraint file with
# USED_IN_SYNTHESIS false (build.tcl:159-164), so it runs during implementation,
# after the IP checkpoints are linked.  That is the only context in which the IP
# clocks exist -- opening synth_1/qwen35_model_top.dcp alone leaves them as black
# boxes and get_clocks returns nothing, which is NOT evidence about the names.
# List the clocks here so the next real run reports them from the valid context.
puts "Q9_CDC_CLOCKS_BEGIN"
foreach q9c [get_clocks -quiet] {
    puts "Q9_CDC_CLK name=[get_property NAME $q9c] period=[get_property PERIOD $q9c]"
}
puts "Q9_CDC_CLOCKS_END count=[llength [get_clocks -quiet]]"

set q9_cdc_failures 0
set q7_core [get_clocks -quiet clk_out1_sidewinder_core_clk_wiz]
set q7_ui [get_clocks mmcm_clkout0]
if {[llength $q7_core]!=1 || [llength $q7_ui]!=1} {
    # Record and abort THIS SCRIPT ONLY (return, not error).  An `error` here
    # aborted the whole Vivado session in the first A5 run; the run then never
    # reached implementation.  q9_cdc_failures does not exist yet at this point,
    # so the marker below is the receipt.
    puts "Q9_CDC_CLOCK_LOOKUP_FAILED core=[llength $q7_core] ui=[llength $q7_ui] -- CDC NOT APPLIED"
    incr q9_cdc_failures
    puts "Q9_CDC_FAILURES total=$q9_cdc_failures"
    puts "Q9_CDC_INCOMPLETE failures=$q9_cdc_failures -- clocks unavailable"
    puts "Q9_CDC_RECEIPT_END sections=clock_lookup_only"
    return
}
set q7_bound [expr {min(3.5,[get_property PERIOD $q7_ui]-0.25,[get_property PERIOD $q7_core]-0.25)}]
proc q7_cells {pattern} {return [get_cells -quiet -hier -filter "NAME =~ $pattern"]}

# --- Q9 failure accounting (defined FIRST: the sections below use it) --------
# q9_expect: a count mismatch is recorded loudly but does NOT abort the session.
# Removing the abort is not the same as accepting the run -- q9_cdc_failures is
# printed at the end and must be zero for the constraints to count as applied.
# Never report an unconstrained run as passing.
set q9_cdc_failures 0
proc q9_expect {label got want} {
    if {$got != $want} {
        puts "Q9_CDC_MISMATCH $label expected=$want got=$got"
        return 1
    }
    return 0
}
proc q9_false_path {label cells} {
    if {![llength $cells]} {
        puts "Q9_CDC_EMPTY $label -- set_false_path skipped (would be fatal)"
        return 1
    }
    set pins [get_pins -quiet -of_objects $cells -filter {REF_PIN_NAME == D}]
    if {[llength $pins] != [llength $cells]} {
        puts "Q9_CDC_MISSING_D $label cells=[llength $cells] pins=[llength $pins]"
        return 1
    }
    set_false_path -to $pins
    return 0
}
source [file join $rk_cdc_board CDC-Metadata256-Contract.tcl]
q35cdc::inventory $rk_cdc_output pre_binding
set q7_outputs [q7_cells */payload_out_reg*]
# This whole mailbox section still uses Q7-era patterns (*/payload_out_reg*,
# payload_hold_reg*, req1_reg/ack1_reg) that have NOT been measured against the
# Q9 netlist.  Every hard `error` here was therefore a run-killer of unknown
# probability, so they are recorded instead of raised.  q9_cdc_failures is
# printed at the end; a non-zero value means the CDC coverage is NOT applied.
if {![llength $q7_outputs]} {
    puts "Q9_CDC_EMPTY mailbox endpoints (*/payload_out_reg*) -- section skipped, patterns unmeasured for Q9"
    incr q9_cdc_failures
}
set q7_parents {}
foreach c $q7_outputs {lappend q7_parents [file dirname [get_property NAME $c]]}
foreach parent [lsort -unique $q7_parents] {
    set s [q7_cells $parent/payload_hold_reg*]
    set d [q7_cells $parent/payload_out_reg*]
    if {![llength $s] || ![llength $d]} {puts "Q9_CDC_MAILBOX_PARTIAL $parent"; incr q9_cdc_failures; continue}
    set_max_delay -datapath_only $q7_bound -from $s -to $d
    set_bus_skew $q7_bound -from $s -to $d
    foreach first {req1_reg ack1_reg} {
        set sync [q7_cells $parent/$first]
        if {![llength $sync]} {puts "Q9_CDC_NO_SYNC $parent/$first"; incr q9_cdc_failures; continue}
        set_false_path -to [get_pins -of_objects $sync -filter {REF_PIN_NAME == D}]
    }
    puts "Q7_MAILBOX_BOUND parent=$parent source=[llength $s] dest=[llength $d] ns=$q7_bound"
}
set q7_error [q7_cells */metadata/error_s1_reg]
# r15 source-derived: P2 retains one physical matrix service.
incr q9_cdc_failures [q9_expect "metadata_error_sync" [llength $q7_error] 1]
incr q9_cdc_failures [q9_false_path "metadata_error_sync" $q7_error]
# XPM FIFO/reset/single-bit primitives supply their own scoped constraints.
# Do not waive recovery/removal or synchronous raw-tail/control logic.
puts Q9_STAGE_CDC_BINDING_ATTEMPTED

# Shared INT8 Head uses the existing matrix service; no independent Head CDC.
# Matrix code FIFO0/1: 2 * 2 * (8+1+1) =40 first-stage Gray bits.
# Metadata FIFO256: PARTS2/AW7 => 2 *8 =16, total56 bits /6 directed buses.
# Exactly2 code last-sideband capture registers; metadata LAST is in257bit BRAM and2 reader request mailboxes.
# Counts come from instantiated source parameters; the linked design must match.
# Reader request mailboxes include constant command fields. Bind first-stage
# handshakes explicitly; retain timing on their second stages.
set q7_head_sync [get_cells -quiet -hier -filter {NAME =~ */requests_cdc/req1_reg || NAME =~ */requests_cdc/ack1_reg}]
incr q9_cdc_failures [q9_expect "head_command_sync" [llength $q7_head_sync] 4]
incr q9_cdc_failures [q9_false_path "head_command_sync" $q7_head_sync]
# The new storage/sideband identities are checked as complete vectors.
# No whole-clock waiver, no per-LAST-source clock discovery or bit timing loop.
q35cdc::apply $rk_cdc_output
puts "Q9_CDC_FAILURES total=$q9_cdc_failures"
puts "Q9_CDC_RECEIPT_END sections=mailboxes_and_batched_native_FIFO"
if {$q9_cdc_failures!=0} {error "SUPPLY_CDC_COVERAGE_INCOMPLETE failures=$q9_cdc_failures"}