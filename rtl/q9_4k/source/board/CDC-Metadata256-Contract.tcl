# Batched CDC identity and binding checks. No per-cell clock/property discovery.
namespace eval q35cdc {
 variable metadata stage/hybrid/attention/schedule/matrix/svc/metadata/metadata_fifo
 variable codes {stage/hybrid/attention/schedule/matrix/svc/matrix/feed/g_segment32.fifo0 stage/hybrid/attention/schedule/matrix/svc/matrix/feed/g_segment32.fifo1}
 if {![info exists cached_stage]} {variable cached_stage {};variable cache {};variable net_cache [dict create]}
 proc names {objects} {if {![llength $objects]} {return {}};return [get_property NAME $objects]}
 proc same {a b} {return [expr {[lsort -unique $a] eq [lsort -unique $b]}]}
 proc clocks {} {
  set core [get_clocks -quiet clk_out1_sidewinder_core_clk_wiz];set ui [get_clocks -quiet mmcm_clkout0]
  if {[llength $core]!=1 || [llength $ui]!=1} {error CDC_REAL_CORE_UI_CLOCK_REQUIRED}
  return [list $core $ui [expr {min(3.5,[get_property PERIOD $core]-0.25,[get_property PERIOD $ui]-0.25)}]]
 }
 proc cell_map {cells} {
  set result [dict create]
  foreach c $cells n [names $cells] {dict set result $n $c}
  return $result
 }
 proc ff_candidates {cells root stage} {
  # Prefix globs also match synthesis helpers such as wb_reg[0]_i_1.
  # Keep every true FD register, report every excluded helper, and reject a
  # non-FD object that occupies any exact architectural register identity.
  set ns [names $cells];set refs [get_property REF_NAME $cells]
  if {[llength $ns]!=[llength $cells] || [llength $refs]!=[llength $cells]} {error CDC_CANDIDATE_PROPERTY_COVERAGE}
  set f [open [file join $root ${stage}_cdc_candidate_filter.tsv] w]
  puts $f "cell\tref\tselected_as_FF"
  set regs {}
  foreach c $cells n $ns ref $refs {
   if {[string match FD* $ref]} {lappend regs $c;puts $f "$n\t$ref\t1"} else {
    puts $f "$n\t$ref\t0"
    if {[regexp {/(rs1|ws1|rs2|ws2|rg|wg|rb|wb)_reg\[[0-9]+\]$|/last_prefetch_reg$} $n]} {
     close $f;error "CDC_ARCHITECTURAL_REGISTER_NOT_FD $n ref=$ref"
    }
   }
  }
  close $f
  if {![llength $regs]} {error CDC_NO_FD_CANDIDATES}
  puts "Q35_CDC_FF_CANDIDATES raw=[llength $cells] registers=[llength $regs] excluded_helpers=[expr {[llength $cells]-[llength $regs]}]"
  return $regs
 }
 proc pin_map {cells refpin} {
  set ps [get_pins -quiet -of_objects $cells -filter "REF_PIN_NAME == $refpin"]
  set result [dict create]
  foreach p $ps n [names $ps] {dict set result [file dirname $n] $p}
  if {[dict size $result]!=[llength $cells]} {error "CDC_PIN_VECTOR_COVERAGE $refpin expected=[llength $cells] actual=[dict size $result]"}
  return $result
 }
 # Prove every supplied CK pin is connected, every unique net has exactly
 # the expected clock and one known leaf clock driver. Cache per net/stage.
 proc clock_pins {ps expected label} {
  variable net_cache
  if {![llength $ps]} {error "CDC_EMPTY_CK_VECTOR $label"}
  set nets [get_nets -quiet -of_objects $ps]
  if {![llength $nets]} {error "CDC_UNCONNECTED_CK_VECTOR $label"}
  set covered [dict create]
  foreach net $nets nn [names $nets] {
   if {![dict exists $net_cache $nn]} {
    set nc [lsort -unique [get_clocks -quiet -of_objects $net]]
    set connected [get_pins -quiet -of_objects $net -filter {IS_CLOCK == 1}]
    if {![llength $connected]} {error "CDC_CLOCK_NET_WITHOUT_CLOCK_PINS $nn"}
    # -of_objects resolves pins/cells, not a second net query. Start from
    # a real clock pin, as in the accepted physical-buffer proof.
    set segments [get_nets -quiet -segments -of_objects [lindex $connected 0]]
    set drivers [get_pins -quiet -leaf -of_objects $segments -filter {DIRECTION == OUT}]
    if {[llength $nc]!=1 || [llength $drivers]!=1} {error "CDC_UNKNOWN_CLOCK_NET $nn clocks=$nc drivers=$drivers"}
    set dc [get_cells -quiet -of_objects $drivers]
    set ref [get_property REF_NAME $dc]
    if {$ref ni {BUFG BUFGCE BUFGCTRL BUFGCE_DIV MMCME4_ADV PLLE4_ADV}} {error "CDC_UNKNOWN_CLOCK_DRIVER $nn ref=$ref"}
    set connected_names [names $connected]
    dict set net_cache $nn [list $nc $connected_names [names $drivers] $ref]
   }
   lassign [dict get $net_cache $nn] nc connected driver ref
   if {$nc ne $expected} {error "CDC_VECTOR_WRONG_CLOCK $label net=$nn expected=$expected actual=$nc"}
   foreach cp $connected {dict set covered $cp 1}
  }
  foreach cp [names $ps] {if {![dict exists $covered $cp]} {error "CDC_UNCLOCKED_OR_UNCONNECTED_PIN $label $cp"}}
  return [list [llength $ps] [llength $nets] $expected]
 }
 proc ff_clock {cells expected label} {
  set refs [get_property REF_NAME $cells]
  foreach ref $refs {if {![string match FD* $ref]} {error "CDC_NON_FF_SOURCE $label $ref"}}
  set ps [get_pins -quiet -of_objects $cells -filter {IS_CLOCK == 1}]
  if {[llength $ps]!=[llength $cells]} {error "CDC_ONE_CK_PER_FF_REQUIRED $label"}
  set seen [dict create]
  foreach p [names $ps] {dict set seen [file dirname $p] 1}
  foreach n [names $cells] {if {![dict exists $seen $n]} {error "CDC_MISSING_FF_CK $label $n"}}
  return [clock_pins $ps $expected $label]
 }
 proc direct_pairs {sources destinations label} {
  # Only small first/second vectors use direct net queries (56 bit pairs);
  # never all_fanin or clocks_of per bit. All NAME/REF/ASYNC values are bulk.
  if {[llength $sources]!=[llength $destinations]} {error "CDC_DIRECT_PAIR_WIDTH $label"}
  foreach s $sources d $destinations {
   set sn [get_nets -quiet -of_objects $s];set dn [get_nets -quiet -of_objects $d]
   if {[llength $sn]!=1 || [llength $dn]!=1 || ![same [names $sn] [names $dn]]} {error "CDC_NOT_DIRECT_REGISTER_PAIR $label source=$s destination=$d"}
  }
 }
 proc inventory {root stage} {
  variable cached_stage;variable cache;variable net_cache;variable metadata;variable codes
  set tag [expr {$stage eq "pre_binding"?"synth":$stage}]
  if {$tag eq $cached_stage && [llength $cache]} {return $cache}
  set net_cache [dict create]
  lassign [clocks] core ui bound
  set regs [get_cells -quiet -hier -filter {NAME =~ */rs1_reg* || NAME =~ */ws1_reg* || NAME =~ */rs2_reg* || NAME =~ */ws2_reg* || NAME =~ */rg_reg* || NAME =~ */wg_reg* || NAME =~ */rb_reg* || NAME =~ */wb_reg* || NAME =~ */last_prefetch_reg}]
  set regs [ff_candidates $regs $root $stage]
  set map [cell_map $regs]
  set dmap [pin_map $regs D];set qmap [pin_map $regs Q]
  set async_values [dict create];foreach n [names $regs] a [get_property -quiet ASYNC_REG $regs] {dict set async_values $n [string tolower $a]}
  set first_names {};set actual_groups [dict create]
  foreach n [dict keys $map] {if {[regexp {^(.*)/(rs1|ws1)_reg\[([0-9]+)\]$} $n -> parent dir bit]} {lappend first_names $n;dict lappend actual_groups $parent/$dir $bit}}
  if {[llength $first_names]!=56 || [dict size $actual_groups]!=6} {error CDC_EXACT_56_FIRST_AND_SIX_GROUPS_REQUIRED}
  set groups {};set pairs [open [file join $root ${stage}_cdc_direct_pairs.tsv] w]
  puts $pairs "group\tbit\tsource\tfirst\tsecond\tsource_clock\tdestination_clock"
  foreach parent [concat $codes [list $metadata]] {
   set w [expr {$parent eq $metadata?8:10}]
   foreach dir {rs1 ws1} {
    set key $parent/$dir
    if {![dict exists $actual_groups $key] || [llength [lsort -unique [dict get $actual_groups $key]]]!=$w} {error "CDC_GROUP_IDENTITY_WIDTH $key expected=$w"}
    set dc [expr {$dir eq "rs1"?$ui:$core}];set sc [expr {$dir eq "rs1"?$core:$ui}]
    set src {};set first {};set second {};set sq {};set fd {};set fq {};set sd {}
    for {set b 0} {$b<$w} {incr b} {
     set fn [format {%s/%s_reg[%d]} $parent $dir $b]
     set sn [format {%s/%s2_reg[%d]} $parent [string range $dir 0 1] $b]
     set gn [format {%s/%s_reg[%d]} $parent [expr {$dir eq "rs1"?"rg":"wg"}] $b]
     set bn [format {%s/%s_reg[%d]} $parent [expr {$dir eq "rs1"?"rb":"wb"}] $b]
     if {![dict exists $map $gn]} {if {$b!=$w-1 || ![dict exists $map $bn]} {error "CDC_GRAY_OR_MSB_ALIAS_MISSING $gn"};set gn $bn}
     if {$b==$w-1 && [dict exists $map $bn]} {
      set gn_net [get_nets -quiet -of_objects [dict get $qmap $gn]];set fd_net [get_nets -quiet -of_objects [dict get $dmap $fn]]
      if {![same [names $gn_net] [names $fd_net]]} {set gn $bn}
     }
     foreach n [list $fn $sn] {if {![dict exists $map $n] || [dict get $async_values $n] ni {1 true}} {error "CDC_SYNC_ASYNC_REG_REQUIRED $n"}}
     lappend src [dict get $map $gn];lappend first [dict get $map $fn];lappend second [dict get $map $sn]
     lappend sq [dict get $qmap $gn];lappend fd [dict get $dmap $fn];lappend fq [dict get $qmap $fn];lappend sd [dict get $dmap $sn]
     puts $pairs "$key\t$b\t$gn\t$fn\t$sn\t$sc\t$dc"
    }
    ff_clock $src $sc $key/source;ff_clock $first $dc $key/first;ff_clock $second $dc $key/second
    direct_pairs $sq $fd $key/gray;direct_pairs $fq $sd $key/second
    lappend groups [dict create key $key width $w sources $src first $first second $second first_d $fd second_d $sd]
   }
  }
  close $pairs
  set actual_last [get_cells -quiet -hier -filter {NAME =~ */last_prefetch_reg}]
  set expected_last {};foreach parent $codes {lappend expected_last $parent/last_prefetch_reg}
  if {![same [names $actual_last] $expected_last]} {error CDC_EXACT_TWO_CODE_LAST_CAPTURES_REQUIRED}
  set lasts {};set f [open [file join $root ${stage}_cdc_last_vectors.tsv] w]
  puts $f "capture\tUI_source_count\tcore_control_count\tUI_clock_pins\tUI_clock_nets\tUI_clock"
  foreach cap $actual_last cn [names $actual_last] {
   set parent [file dirname $cn];set dp [get_pins -quiet -of_objects $cap -filter {REF_PIN_NAME == D}]
   set starts [all_fanin -flat -startpoints_only -only_cells -to $dp]
   # Two all_fanin queries total. Classify from bulk NAME/REF, then prove
   # complete CK vectors for all512 UI sources and every core control.
   set ui_sources {};set core_sources {};set indexes {}
   foreach obj $starts n [names $starts] ref [get_property REF_NAME $starts] {
    if {![string match FD* $ref]} {error "CDC_LAST_NON_FF_OR_UNKNOWN_START $cn source=$n ref=$ref"}
    if {[regexp {^(.*)/last_memory_reg\[([0-9]+)\]$} $n -> mp idx]} {
     if {$mp ne $parent || $idx>511} {error "CDC_LAST_UNKNOWN_MEMORY_SOURCE $n"}
     lappend ui_sources $obj;lappend indexes $idx
    } else {lappend core_sources $obj}
   }
   if {[llength $ui_sources]!=512 || [llength [lsort -unique $indexes]]!=512} {error "CDC_LAST_EXACT_512_UI_SOURCES $cn actual=[llength $ui_sources]"}
   set cp [ff_clock $ui_sources $ui $cn/UI512]
   if {[llength $core_sources]} {ff_clock $core_sources $core $cn/core_controls}
   ff_clock $cap $core $cn/capture
   puts $f "$cn\t512\t[llength $core_sources]\t[join $cp \t]"
   lappend lasts [dict create name $cn sources $ui_sources destination $dp controls $core_sources]
  }
  close $f
  set meta [get_cells -quiet -hier -filter {REF_NAME =~ qwen7b_metadata_fifo64*}]
  if {[llength $meta]!=1 || [get_property NAME $meta] ne $metadata} {error CDC_METADATA256_EXACT_SCOPE_REQUIRED}
  set ram [get_cells -quiet -hier -filter "IS_PRIMITIVE == 1 && NAME =~ $metadata/* && REF_NAME == RAMB36E2"]
  if {[llength $ram]!=4} {error CDC_METADATA257_FOUR_NATIVE_BRAM_REQUIRED}
  set rp [get_pins -quiet -of_objects $ram -filter {IS_CLOCK == 1}]
  set ac {};set bc {}
  foreach pin $rp ref [get_property REF_PIN_NAME $rp] {if {$ref eq "CLKARDCLK"} {lappend ac $pin} elseif {$ref eq "CLKBWRCLK"} {lappend bc $pin} else {error "CDC_UNKNOWN_RAM_CLOCK_PIN $ref"}}
  if {[llength $ac]!=4 || [llength $bc]!=4} {error CDC_METADATA_RAM_CLOCK_PIN_COVERAGE}
  set acl [lsort -unique [get_clocks -quiet -of_objects [get_nets -quiet -of_objects $ac]]];set bcl [lsort -unique [get_clocks -quiet -of_objects [get_nets -quiet -of_objects $bc]]]
  if {[llength $acl]!=1 || [llength $bcl]!=1 || ![same [concat $acl $bcl] [list $core $ui]]} {error CDC_METADATA_RAM_TWO_DOMAIN_IDENTITY}
  clock_pins $ac $acl metadata/CLK_A;clock_pins $bc $bcl metadata/CLK_B
  set cache [dict create groups $groups lasts $lasts metadata $meta brams $ram ram_clock_A $acl ram_clock_B $bcl bound $bound]
  set cached_stage $tag
  return $cache
 }
 proc apply {root} {
  set data [inventory $root pre_binding];set bound [dict get $data bound]
  foreach group [dict get $data groups] {set_max_delay -datapath_only $bound -from [dict get $group sources] -to [dict get $group first_d];set_bus_skew $bound -from [dict get $group sources] -to [dict get $group first_d]}
  foreach last [dict get $data lasts] {set_max_delay -datapath_only $bound -from [dict get $last sources] -to [dict get $last destination]}
  puts "Q35_CDC_BATCH_APPLIED gray_groups=6 first_bits=56 last_groups=2 UI_LAST_sources=1024 bound_ns=$bound"
 }
 proc covered_paths {paths endpoints label expected_req} {
  if {[llength $paths]!=[llength $endpoints] || ![same [get_property ENDPOINT_PIN $paths] [names $endpoints]]} {error "CDC_TIMING_ENDPOINT_COVERAGE $label expected=[llength $endpoints] actual=[llength $paths]"}
  if {$expected_req ne {}} {foreach r [get_property REQUIREMENT $paths] {if {abs($r-$expected_req)>0.0001} {error "CDC_TIMING_REQUIREMENT $label actual=$r expected=$expected_req"}}}
 }
 proc binding_guard {root stage} {
  set data [inventory $root $stage];set bound [dict get $data bound]
  set f [open [file join $root ${stage}_cdc_bound.tsv] w]
  puts $f "kind\tgroup\tendpoints_covered\trequirements"
  foreach group [dict get $data groups] {
   set key [dict get $group key];set w [dict get $group width]
   set p [get_timing_paths -quiet -from [dict get $group sources] -to [dict get $group first_d] -delay_type max -max_paths $w -nworst 1]
   covered_paths $p [dict get $group first_d] $key/first $bound
   puts $f "gray_max\t$key\t[llength $p]\t[get_property REQUIREMENT $p]"
   foreach delay {max min} {
    set p [get_timing_paths -quiet -from [dict get $group first] -to [dict get $group second_d] -delay_type $delay -max_paths $w -nworst 1]
    covered_paths $p [dict get $group second_d] $key/second/$delay {}
    puts $f "second_$delay\t$key\t[llength $p]\t[get_property REQUIREMENT $p]"
   }
  }
  foreach last [dict get $data lasts] {
   set p [get_timing_paths -quiet -from [dict get $last sources] -to [dict get $last destination] -delay_type max -max_paths 1 -nworst 1]
   covered_paths $p [dict get $last destination] [dict get $last name]/LAST $bound
   puts $f "last_max\t[dict get $last name]\t1\t[get_property REQUIREMENT $p]"
  }
  close $f
  report_bus_skew -file [file join $root ${stage}_cdc_bus_skew.rpt]
 }
}
