`timescale 1ns/1ps
    // AXI-Lite, one buffered AW and W, one read in flight. No soft reset of an
    // active DMA. 0x4000 exposes committed token/time/position records. 0x800: prompt IDs.
    // A start write is a transaction boundary: the completion bit is cleared for
    // every start attempt, including a rejected attempt.  Software must use BRESP
    // to distinguish an accepted start from a busy/not-ready rejection; clearing
    // here prevents a previous token's sticky DONE from being mistaken for the
    // rejected token even if an old runtime ignores BRESP.
module qwen35_model_mmio #(parameter integer DETAIL_COUNTERS=82)(
    input wire clk,reset_n,
    input wire[15:0] awaddr,input wire awvalid,output wire awready,
    input wire[31:0] wdata,input wire[3:0] wstrb,input wire wvalid,output wire wready,
    output logic[1:0] bresp,output logic bvalid,input wire bready,
    input wire[15:0] araddr,input wire arvalid,output wire arready,
    output logic[31:0] rdata,output logic[1:0] rresp,output logic rvalid,input wire rready,
    output logic start_o,input wire start_ready_i,busy_i,done_i,input wire[5:0] phase_i,
    input wire[31:0] status_i,cycles_i,run_id_i,qkv_cycles_i,write_cycles_i,read_cycles_i,
    input wire[31:0] output_count_i,raw_count_i,pl_words_i,ps_words_i,write_bytes_i,read_bytes_i,
    input wire[31:0] qkv_checksum_i,raw_checksum_i,board_errors_i,
    input wire[31:0] prefix_cycles_i,attention_cycles_i,o_cycles_i,ffn_cycles_i,attention_count_i,o_count_i,ffn_count_i,
    output logic cfg_write_o,input wire cfg_ready_i,output logic[9:0] cfg_address_o,output logic[31:0] cfg_data_o,
    input wire[63:0] full_cycles_i,first_token_cycles_i,input wire[17:0] last_token_i,input wire[13:0] position_i,input wire[4:0] layer_i,
    input wire[7:0] quant_warning_flags_i,input wire[31:0] quant_warning_events_i,
    input wire[511:0] fault_snapshot_i,
    input wire[255:0] pl_read_fault_snapshot_i,
    output logic[13:0] debug_addr_o,input wire[31:0] debug_data_i
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    reg[31:0]read_scalar49;reg[1:0]read_resp49;
    logic awheld,wheld,done_sticky;logic[15:0] address,read_address;logic[31:0] data;logic[3:0] strobe;
    // Transaction-boundary telemetry.  These counters live in the same
    // MMIO clock domain as the AXI-Lite shell, so PS can read them without
    // introducing another CDC path into the model core.
    logic done_i_q;
    logic [31:0] start_attempt_count;
    logic [31:0] start_accept_count;
    logic [31:0] start_reject_count;
    logic [31:0] done_rise_count;
    logic [31:0] orphan_done_count;
    // Detailed token-boundary telemetry.  These counters intentionally stay
    // in the core-clock/MMIO domain so every value is directly readable by
    // the PS without a second CDC bank.  The legacy 0x88..0x98 counters above
    // retain their original meaning.
    logic [31:0] token_start_count,token_done_count,token_success_count,token_fault_count;
    logic [63:0] total_busy_cycle_count,active_token_cycles;
    logic [63:0] last_token_cycles,max_token_cycles;
    logic [31:0] phase_enter_count0,phase_enter_count1,phase_enter_count2,phase_enter_count3;
    logic [31:0] busy_enter_count,busy_exit_count,lm_done_count,output_commit_count,status_event_count;
    logic [5:0] phase_q;
    logic busy_q;
    logic[1:0] read_state;
    wire start_write_event = awheld && wheld && !bvalid &&
                             address==16'h0000 && strobe==4'hf && data==32'h00000001;
    wire start_accept_event = start_write_event && start_ready_i && !busy_i;
    wire start_reject_event = start_write_event && !(start_ready_i && !busy_i);
    wire done_rise_event = done_i && !done_i_q;
    wire token_success_event = done_rise_event && phase_i==6'd2 && status_i==32'd0;
    wire token_fault_event = done_rise_event && (phase_i==6'd3 || status_i!=32'd0);
    wire lm_done_event = done_rise_event && phase_i==6'd2;
    wire phase_enter_event = phase_i!=phase_q;
    wire status_event_pulse;
    qwen35_status_edge44 status_event_cut(.clk(clk),.reset_n(reset_n),.status_i(status_i),.pulse_o(status_event_pulse),.level_o());
    wire orphan_event48;
    qwen35_orphan_event48 orphan_compare(.clk(clk),.reset_n(reset_n),
        .done_count_i(done_rise_count),.accept_count_i(start_accept_count),
        .accept_i(start_accept_event),.done_i(done_rise_event),.event_o(orphan_event48));
    reg[31:0]status_readback48;
    always @(posedge clk)status_readback48<=status_i;
    assign awready=reset_n&&!awheld&&!bvalid;assign wready=reset_n&&!wheld&&!bvalid;
    assign arready=reset_n&&read_state==0&&!rvalid;
    // Configuration address/data are payload, authorized only by cfg_write_o.
    // Sample from the already buffered AXI-Lite write unconditionally, keeping
    // busy/start-ready qualification on the single valid bit instead of42
    // payload clock enables. Valid addresses have exactly the original map.
    always_ff @(posedge clk)begin
        cfg_data_o<=data;
        cfg_address_o<=address[11]?10'd256+{1'b0,address[10:2]}:{8'd0,address[3:2]};
    end
    always_ff @(posedge clk)begin
        if(q9_local_reset_active)begin
            awheld<=0;wheld<=0;bresp<=0;bvalid<=0;read_state<=0;rdata<=0;rresp<=0;rvalid<=0;
            start_o<=0;cfg_write_o<=0;done_sticky<=0;debug_addr_o<=0;address<=0;data<=0;strobe<=0;read_address<=0;
            done_i_q<=1'b0;
            phase_q<=6'd0;busy_q<=1'b0;
            start_attempt_count<=32'd0;
            start_accept_count<=32'd0;
            start_reject_count<=32'd0;
            done_rise_count<=32'd0;
            orphan_done_count<=32'd0;
            token_start_count<=32'd0;token_done_count<=32'd0;
            token_success_count<=32'd0;token_fault_count<=32'd0;
            total_busy_cycle_count<=64'd0;active_token_cycles<=64'd0;
            last_token_cycles<=64'd0;max_token_cycles<=64'd0;
            phase_enter_count0<=32'd0;phase_enter_count1<=32'd0;
            phase_enter_count2<=32'd0;phase_enter_count3<=32'd0;
            busy_enter_count<=32'd0;busy_exit_count<=32'd0;
            lm_done_count<=32'd0;output_commit_count<=32'd0;status_event_count<=32'd0;
        end else begin
            start_o<=0;cfg_write_o<=0;
            done_i_q<=done_i;
            phase_q<=phase_i;busy_q<=busy_i;
            if (busy_i) begin
                total_busy_cycle_count<=total_busy_cycle_count+64'd1;
                active_token_cycles<=active_token_cycles+64'd1;
            end
            if (busy_i&&!busy_q) busy_enter_count<=busy_enter_count+32'd1;
            if (!busy_i&&busy_q) begin
                last_token_cycles<=active_token_cycles;
                if (active_token_cycles>max_token_cycles) max_token_cycles<=active_token_cycles;
                active_token_cycles<=64'd0;
                busy_exit_count<=busy_exit_count+32'd1;
            end
            if (phase_enter_event) begin
                case (phase_i)
                    6'd0: phase_enter_count0<=phase_enter_count0+32'd1;
                    6'd1: phase_enter_count1<=phase_enter_count1+32'd1;
                    6'd2: phase_enter_count2<=phase_enter_count2+32'd1;
                    6'd3: phase_enter_count3<=phase_enter_count3+32'd1;
                    default: ;
                endcase
            end
            if (status_event_pulse) status_event_count<=status_event_count+32'd1;
            if (start_write_event) start_attempt_count<=start_attempt_count+32'd1;
            if (start_accept_event) begin
                start_accept_count<=start_accept_count+32'd1;
                token_start_count<=token_start_count+32'd1;
                active_token_cycles<=64'd0;
            end
            if (start_reject_event) start_reject_count<=start_reject_count+32'd1;
            if (done_rise_event) begin
                done_rise_count<=done_rise_count+32'd1;
                token_done_count<=token_done_count+32'd1;
                if (token_success_event) begin
                    token_success_count<=token_success_count+32'd1;
                    output_commit_count<=output_commit_count+32'd1;
                end
                if (token_fault_event) token_fault_count<=token_fault_count+32'd1;
                if (lm_done_event) lm_done_count<=lm_done_count+32'd1;
                // Include an accepted start in this same cycle.  A done
                // event is orphaned only when no accepted transaction is
                // outstanding before or at the event boundary.

            end
            if(orphan_event48)orphan_done_count<=orphan_done_count+32'd1;
            if(done_i)done_sticky<=1;
            if(bvalid&&bready)bvalid<=0;
            if(rvalid&&rready)rvalid<=0;
            if(awvalid&&awready)begin awheld<=1;address<=awaddr;end
            if(wvalid&&wready)begin wheld<=1;data<=wdata;strobe<=wstrb;end
            if(awheld&&wheld&&!bvalid)begin
                awheld<=0;wheld<=0;bvalid<=1;bresp<=2'b10;
                if(address==0&&strobe==4'hf&&data==1)begin
                    done_sticky<=0;
                    if(start_ready_i&&!busy_i)begin
                        start_o<=1;bresp<=0;
                    end
                end else if(cfg_ready_i&&!busy_i&&strobe==4'hf&&address[1:0]==0&&
                    (address==16'h100||address==16'h104||address==16'h108||(address>=16'h800&&address<16'h1000)))begin
                    cfg_write_o<=1;bresp<=0;
                end
            end
            if(arvalid&&arready)begin
                read_address<=araddr;debug_addr_o<=14'((araddr-16'h4000)>>2);read_state<=1;
            end
            // Use the existing wait cycle to select scalar/fault words. The
            // debug RAM path keeps its original two-clock address latency.
            // Scalar telemetry is sampled one clock earlier; AXI response
            // latency and stalled RDATA/RRESP remain unchanged.
            if(read_state==1)begin
                read_state<=2;read_resp49<=0;
                if(read_address[1:0]!=0)begin read_resp49<=2'b10;read_scalar49<=0;end
                else if(read_address>=16'h4000)read_scalar49<=0;
                else if(read_address>=16'h0180 && read_address<16'h01c0)
                    read_scalar49<=fault_snapshot_i[read_address[5:2]*32+:32];
                else if(read_address>=16'h01c0 && read_address<16'h01e0)
                    read_scalar49<=pl_read_fault_snapshot_i[read_address[4:2]*32+:32];
                else case(read_address)
                    16'h00:read_scalar49<=0;
                    16'h04:read_scalar49<=32'h51374d31;
                    // Existing phase_q/busy_q capture the AR acceptance edge.
                    // Reuse them instead of putting the live fence/phase
                    // network before the wide scalar read-address mux.
                    16'h08:read_scalar49<={10'd0,phase_q,14'd0,done_sticky,busy_q};
                    16'h0c:read_scalar49<=status_readback48;
                    16'h10:read_scalar49<=cycles_i;
                    16'h14:read_scalar49<=run_id_i;
                    16'h18:read_scalar49<=qkv_cycles_i;
                    16'h1c:read_scalar49<=write_cycles_i;
                    16'h20:read_scalar49<=read_cycles_i;
                    16'h24:read_scalar49<=output_count_i;
                    16'h28:read_scalar49<=raw_count_i;
                    16'h2c:read_scalar49<=pl_words_i;
                    16'h30:read_scalar49<=ps_words_i;
                    16'h34:read_scalar49<=write_bytes_i;
                    16'h38:read_scalar49<=read_bytes_i;
                    16'h3c:read_scalar49<=qkv_checksum_i;
                    16'h40:read_scalar49<=raw_checksum_i;
                    16'h44:read_scalar49<=board_errors_i;
                    16'h48:read_scalar49<=32'h001c0200;
                    16'h1e0:read_scalar49<=32'h5139344b;
                    16'h1e4:read_scalar49<=32'd4096;
                    16'h1e8:read_scalar49<=32'h00200404;
                    16'h4c:read_scalar49<=prefix_cycles_i;
                    16'h50:read_scalar49<=attention_cycles_i;
                    16'h54:read_scalar49<=o_cycles_i;
                    16'h58:read_scalar49<=ffn_cycles_i;
                    16'h5c:read_scalar49<=attention_count_i;
                    16'h60:read_scalar49<=o_count_i;
                    16'h64:read_scalar49<=ffn_count_i;
                    16'h68:read_scalar49<=full_cycles_i[31:0];
                    16'h6c:read_scalar49<=full_cycles_i[63:32];
                    16'h70:read_scalar49<=first_token_cycles_i[31:0];
                    16'h74:read_scalar49<=first_token_cycles_i[63:32];
                    16'h78:read_scalar49<={14'd0,last_token_i};
                    16'h7c:read_scalar49<={11'd0,layer_i,2'd0,position_i};
                    16'h80:read_scalar49<={24'd0,quant_warning_flags_i};
                    16'h84:read_scalar49<=quant_warning_events_i;
                    16'h88:read_scalar49<=start_attempt_count;
                    16'h8c:read_scalar49<=start_accept_count;
                    16'h90:read_scalar49<=start_reject_count;
                    16'h94:read_scalar49<=done_rise_count;
                    16'h98:read_scalar49<=orphan_done_count;
                     // Detailed token/model telemetry.  Addresses are kept
                     // below 0x100 so existing configuration writes at 0x100+
                     // remain untouched.
                     16'ha0:read_scalar49<=token_start_count;
                     16'ha4:read_scalar49<=token_done_count;
                     16'ha8:read_scalar49<=token_success_count;
                     16'hac:read_scalar49<=token_fault_count;
                     16'hb0:read_scalar49<=total_busy_cycle_count[31:0];
                     16'hb4:read_scalar49<=total_busy_cycle_count[63:32];
                     16'hb8:read_scalar49<=last_token_cycles[31:0];
                     16'hbc:read_scalar49<=last_token_cycles[63:32];
                     16'hc0:read_scalar49<=max_token_cycles[31:0];
                     16'hc4:read_scalar49<=max_token_cycles[63:32];
                     16'hc8:read_scalar49<=phase_enter_count0;
                     16'hcc:read_scalar49<=phase_enter_count1;
                     16'hd0:read_scalar49<=phase_enter_count2;
                     16'hd4:read_scalar49<=phase_enter_count3;
                     16'hd8:read_scalar49<=busy_enter_count;
                     16'hdc:read_scalar49<=busy_exit_count;
                     16'he0:read_scalar49<=lm_done_count;
                     16'he4:read_scalar49<=output_commit_count;
                     16'he8:read_scalar49<=status_event_count;
                     16'hec:read_scalar49<=status_readback48;
                     16'hf0:read_scalar49<={25'd0,phase_q,busy_q};
                     16'hf4:read_scalar49<=active_token_cycles[31:0];
                     16'hf8:read_scalar49<=active_token_cycles[63:32];
                    default:begin read_scalar49<=0;read_resp49<=2'b10;end
                endcase
            end
            if(read_state==2)read_state<=3;
            if(read_state==3)begin
                read_state<=0;rvalid<=1;rdata<=read_scalar49;rresp<=read_resp49;
                if(read_address[1:0]==0&&read_address>=16'h4000)begin
                    rdata<=debug_data_i;
                    // 0x4000..0x494c is the live diagnostic/counter window.
                    // It remains readable while a token is busy, which is
                    // required to distinguish token0's long path from the
                    // later fast-path.  The old output-record gate is kept for
                    // addresses outside this explicitly admitted window.
                    // Compact Q9C1 words are live diagnostics, independent of
                    // the legacy committed-output record count. Alignment is
                    // still enforced by the enclosing read-address condition.
                    if(read_address[15:8]!=8'h4a &&
                       read_address>=16'(16'h4000+4*(512+2*(DETAIL_COUNTERS-40))) &&
                       ((read_address-16'h4000)>>4)>=output_count_i)rresp<=2'b10;
                end
            end
        end
    end
endmodule

// Preserve the original unsigned32-bit wrapping comparison. A current
// accept selects a predicate AFTER the counter comparison, instead of
// propagating start-ready through an incrementer and a second carry chain.
(* use_dsp="no" *) module qwen35_orphan_done44(
 input wire[31:0]done_count_i,accept_count_i,input wire accept_i,output wire orphan_o
);
 // A current accept is only the fourth input of one final LUT. Counter-only
 // predicates stay outside it, preventing accept from entering a carry chain.
 (* KEEP="TRUE" *) wire greater=done_count_i>accept_count_i;
 (* KEEP="TRUE" *) wire equal_counts=done_count_i==accept_count_i;
 (* KEEP="TRUE" *) wire accept_wrap=&accept_count_i;
 (* DONT_TOUCH="TRUE" *) LUT4 #(.INIT(16'hFAEE)) orphan_control45(
   .I0(greater),.I1(equal_counts),.I2(accept_wrap),.I3(accept_i),.O(orphan_o));
endmodule

// Diagnostic edge capture only: the event count is identical, updated one
// clock later. Busy-cycle counters, done/fault classification and all control
// handshakes keep their original timing. Post-token reads see the same totals.
module qwen35_status_edge44(
 input wire clk,reset_n,input wire[31:0]status_i,output wire pulse_o,output wire level_o
);
 reg[31:0]sampled=0;reg previous=0;
 wire level=|sampled;
 always @(posedge clk)begin
  if(!reset_n)begin sampled<=0;previous<=0;end
  else begin sampled<=status_i;previous<=level;end
 end
 assign level_o=level;
 assign pulse_o=level&&!previous;
endmodule
// Reuse the already-captured status level; qualify it with eligibility from
// that same observation edge. Only the diagnostic fault counter is delayed.
module qwen35_fault_observer45(
 input wire clk,reset_n,eligible_i,level_delayed_i,output wire pulse_o
);
 reg eligible_q=0;
 always @(posedge clk)begin
  if(!reset_n)eligible_q<=0;else eligible_q<=eligible_i;
 end
 assign pulse_o=eligible_q&&level_delayed_i;
endmodule

// Passive debug payload only. Functional live status/fault capture continues
// to use the original vector, and MMIO already waits for address settlement.
module qwen35_debug_vector45 #(parameter integer W=256)(
 input wire clk,input wire[W-1:0]data_i,output reg[W-1:0]data_o
);
 always @(posedge clk)data_o<=data_i;
endmodule

// Preserve the original unsigned32 wrapping predicate at its observation edge.
// Five local bits cross the pipeline boundary; no duplicated 32-bit counters.
(* use_dsp="no" *) module qwen35_orphan_event48(
 input wire clk,reset_n,input wire[31:0]done_count_i,accept_count_i,
 input wire accept_i,done_i,output wire event_o
);
 reg greater_q=0,equal_q=0,wrap_q=0,accept_q=0,done_q=0;
 always @(posedge clk)begin
  if(!reset_n)begin greater_q<=0;equal_q<=0;wrap_q<=0;accept_q<=0;done_q<=0;end
  else begin
   greater_q<=done_count_i>accept_count_i;equal_q<=done_count_i==accept_count_i;
   wrap_q<=&accept_count_i;accept_q<=accept_i;done_q<=done_i;
  end
 end
 wire orphan;
 LUT4 #(.INIT(16'hFAEE)) predicate(.I0(greater_q),.I1(equal_q),.I2(wrap_q),.I3(accept_q),.O(orphan));
 assign event_o=done_q&&orphan;
endmodule
