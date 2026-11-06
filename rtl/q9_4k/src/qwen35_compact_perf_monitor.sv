`timescale 1ns/1ps
// Passive, per-token native128 observation. No outputs feed the datapath.
// Events and token-window controls are sampled together, then counted one
// clock later. DONE freezes the live bank after that last sampled cycle.
// Reset invalidates the bank; payload registers clear only on token admission.
module qwen35_compact_perf_monitor #(
    parameter integer COUNTER_W=32,
    parameter integer CORE_HZ=250000000,
    // T76: 1 = every event input passes one extra register stage. The owner
    // then drives start/done/txn with registered copies of the same events,
    // so the whole observation window shifts by one clock and every count is
    // unchanged.
    parameter integer INPUT_STAGE=0
)(
    input wire clk,reset_n,start_i,done_i,txn_active_i,
    input wire matrix_active_i,matrix_issue_i,
    input wire [7:0] matrix_stall_i,
    input wire [2:0] ffn_phase_i,
    input wire gdn_context_i,fa_context_i,head_w8_i,ffn_context_i,
    input wire [5:0] auxiliary_events_i,
    input wire [5:0] addr_i,
    output reg [31:0] data_o
);
    reg [COUNTER_W-1:0] counters[0:23];
    reg [23:0] overflow=0;
    reg [31:0] generation=0;
    reg running=0,valid=0;
    reg sample_valid=0,done_q=0;
    reg matrix_active_q,matrix_issue_q;
    reg[7:0]matrix_stall_q;reg[2:0]ffn_phase_q;
    reg gdn_context_q,fa_context_q,head_w8_q,ffn_context_q;
    reg[5:0]auxiliary_events_q;
    wire matrix_active_s,matrix_issue_s;wire[7:0]matrix_stall_s;wire[2:0]ffn_phase_s;
    wire gdn_context_s,fa_context_s,head_w8_s,ffn_context_s;wire[5:0]auxiliary_events_s;
    generate if(INPUT_STAGE)begin:g_input_stage
        reg matrix_active_r=0,matrix_issue_r=0;reg[7:0]matrix_stall_r=0;reg[2:0]ffn_phase_r=0;
        reg gdn_context_r=0,fa_context_r=0,head_w8_r=0,ffn_context_r=0;reg[5:0]auxiliary_events_r=0;
        always @(posedge clk)begin
            matrix_active_r<=matrix_active_i;matrix_issue_r<=matrix_issue_i;matrix_stall_r<=matrix_stall_i;
            ffn_phase_r<=ffn_phase_i;gdn_context_r<=gdn_context_i;fa_context_r<=fa_context_i;
            head_w8_r<=head_w8_i;ffn_context_r<=ffn_context_i;auxiliary_events_r<=auxiliary_events_i;
        end
        assign matrix_active_s=matrix_active_r;assign matrix_issue_s=matrix_issue_r;assign matrix_stall_s=matrix_stall_r;
        assign ffn_phase_s=ffn_phase_r;assign gdn_context_s=gdn_context_r;assign fa_context_s=fa_context_r;
        assign head_w8_s=head_w8_r;assign ffn_context_s=ffn_context_r;assign auxiliary_events_s=auxiliary_events_r;
    end else begin:g_input_direct
        assign matrix_active_s=matrix_active_i;assign matrix_issue_s=matrix_issue_i;assign matrix_stall_s=matrix_stall_i;
        assign ffn_phase_s=ffn_phase_i;assign gdn_context_s=gdn_context_i;assign fa_context_s=fa_context_i;
        assign head_w8_s=head_w8_i;assign ffn_context_s=ffn_context_i;assign auxiliary_events_s=auxiliary_events_i;
    end endgenerate
    always @(posedge clk)begin
        matrix_active_q<=matrix_active_s;matrix_issue_q<=matrix_issue_s;matrix_stall_q<=matrix_stall_s;
        ffn_phase_q<=ffn_phase_s;gdn_context_q<=gdn_context_s;fa_context_q<=fa_context_s;
        head_w8_q<=head_w8_s;ffn_context_q<=ffn_context_s;auxiliary_events_q<=auxiliary_events_s;
    end
    wire[23:0]clear_pending66;
    reg [23:0] events;
    for(genvar n66=0;n66<24;n66++)begin:g_counter66
        (* DONT_TOUCH="TRUE" *) reg clear_q=0;
        always @(posedge clk)clear_q<=reset_n&&start_i;
        assign clear_pending66[n66]=clear_q;
        // START already clears sample_valid. This spare sample edge clears
        // payload locally; MMIO masks that pending-clear interval to zero.
        always @(posedge clk)begin
            if(clear_q)counters[n66]<=0;
            // T74: no reset_n/start_i term. A count taken on a START edge is
            // replaced by the clear on the next edge (clear_pending masks MMIO
            // meanwhile); one taken on a reset edge is unreadable because
            // reset leaves running=valid=0 until the next START clears it.
            else if(running&&sample_valid&&events[n66]&&!overflow[n66]&&!(&counters[n66]))
                counters[n66]<=counters[n66]+1'b1;
        end
    end
    always @* begin
        events=24'd0;
        events[0]=1'b1;
        events[1]=matrix_active_q;
        events[2]=matrix_issue_q;
        if(matrix_active_q&&!matrix_issue_q) begin
            if(matrix_stall_q[4]) events[3]=1'b1;
            else if(matrix_stall_q[0]) events[4]=1'b1;
            else if(matrix_stall_q[2]) events[5]=1'b1;
            else if(matrix_stall_q[1]) events[6]=1'b1;
            else if(matrix_stall_q[3]) events[7]=1'b1;
            else events[8]=1'b1;
        end
        if(!matrix_active_q) begin
            if(matrix_stall_q[5]||matrix_stall_q[6]) events[9]=1'b1;
            else if(ffn_phase_q==2||ffn_phase_q==3) events[10]=1'b1;
            else if(gdn_context_q) events[11]=1'b1;
            else if(fa_context_q) events[12]=1'b1;
            else events[13]=1'b1;
        end
        events[14]=matrix_active_q&&head_w8_q;
        events[15]=matrix_issue_q&&head_w8_q;
        events[16]=matrix_active_q&&ffn_context_q;
        events[17]=matrix_issue_q&&ffn_context_q;
        // Auxiliary events overlap the partition. Bit22 is an integrity alarm.
        events[23:18]=auxiliary_events_q;
        events[22]=matrix_issue_q&&!matrix_active_q;
    end
    always @(posedge clk) begin
        if(!reset_n) begin
            // Do not distribute reset through the counter payload.
            overflow<=0;generation<=0;running<=0;valid<=0;
            sample_valid<=0;done_q<=0;
        end else if(start_i) begin
            overflow<=0;generation<=generation+1'b1;running<=1;valid<=0;
            sample_valid<=0;done_q<=0;
        end else begin
            sample_valid<=running&&txn_active_i;
            done_q<=running&&txn_active_i&&done_i;
            if(running&&sample_valid) begin
                for(integer n=0;n<24;n++) if(events[n]&&!overflow[n]) begin
                    if(&counters[n]) overflow[n]<=1'b1;
                end
                if(done_q) begin running<=0;valid<=1;end
            end
        end
    end
    always @* begin
        data_o=0;
        if(addr_i<24) begin
            // Invalid payloads are deliberately unreadable after reset.
            if((running||valid)&&!clear_pending66[0]) data_o={{(32-COUNTER_W){1'b0}},counters[addr_i]};
        end else case(addr_i)
            24:data_o=32'h51394331; // Q9C1
            25:data_o=32'h00010000; // ABI major1/minor0
            26:data_o=generation;
            27:data_o={29'd0,(|overflow),running,valid};
            28:data_o={8'd0,overflow};
            29:data_o=32'd24;
            30:data_o=CORE_HZ;
            31:data_o=32'd128;
            32:data_o=32'h00000007; // true reference issue / full token / exclusive primary partition
            default:data_o=0;
        endcase
    end
endmodule
