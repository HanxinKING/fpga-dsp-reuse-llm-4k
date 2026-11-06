`timescale 1ns/1ps

// P1 cycle-level token profiler.
//
// The counter bank is passive: it observes one-cycle event pulses/levels and
// never participates in ready/valid or owner arbitration.  A token starts the
// live bank, token_done freezes a coherent snapshot, and software can read the
// snapshot without polling the live counters.  All counters saturate so a
// token diagnostics cannot wrap into a plausible result. Internal40bit counters
// cover >5497 seconds at200MHz; the host token timeout is30 seconds.
// The64bit readout ABI is retained with zero-filled upper24bits.
module qwen35_perf_counters #(
    parameter integer SLOT_COUNT = 36
) (
    input  logic clk,
    input  logic reset_n,
    input  logic token_start_i,
    input  logic token_done_i,

    input  logic matrix_busy_i,
    input  logic matrix_wait_data_i,
    input  logic matrix_wait_owner_i,
    input  logic matrix_bubble_i,
    input  logic matrix_issue_beat_i,
    input  logic matrix_response_beat_i,
    input  logic matrix_fence_wait_i,

    input  logic gdn_busy_i,
    input  logic gdn_wait_data_i,
    input  logic gdn_wait_owner_i,
    input  logic gdn_bubble_i,
    input  logic gdn_transfer_beat_i,
    input  logic gdn_state_read_beat_i,
    input  logic gdn_state_write_beat_i,
    input  logic gdn_fence_wait_i,

    input  logic attn_busy_i,
    input  logic attn_wait_data_i,
    input  logic attn_wait_owner_i,
    input  logic attn_bubble_i,
    input  logic attn_transfer_beat_i,
    input  logic attn_kv_request_beat_i,
    input  logic attn_kv_response_beat_i,
    input  logic attn_fence_wait_i,

    input  logic raw_request_beat_i,
    input  logic raw_response_beat_i,
    input  logic raw_actual_beat_i,
    input  logic raw_short_burst_i,
    input  logic raw_unaligned_request_i,
    input  logic raw_owner_wait_i,

    input  logic head_busy_i,
    input  logic head_wait_data_i,
    input  logic head_bubble_i,
    input  logic head_transfer_beat_i,
    input  logic head_fence_wait_i,
    input  logic controller_fence_or_done_wait_i,

    output logic snapshot_valid_o,
    output logic running_o,
    output logic overflow_o,
    output logic [31:0] snapshot_generation_o,
    output logic [SLOT_COUNT*64-1:0] snapshot_bus_o
);

    // Stable snapshot slot map.  Keep this map in sync with the software/debug
    // register map; changing it is an ABI change for performance receipts.
    localparam integer S_TOKEN_TOTAL       = 0;
    localparam integer S_MATRIX_BUSY      = 1;
    localparam integer S_MATRIX_WAIT_DATA = 2;
    localparam integer S_MATRIX_WAIT_OWNER= 3;
    localparam integer S_MATRIX_BUBBLE    = 4;
    localparam integer S_MATRIX_ISSUE     = 5;
    localparam integer S_MATRIX_RESPONSE  = 6;
    localparam integer S_MATRIX_FENCE     = 7;
    localparam integer S_GDN_BUSY         = 8;
    localparam integer S_GDN_WAIT_DATA    = 9;
    localparam integer S_GDN_WAIT_OWNER   = 10;
    localparam integer S_GDN_BUBBLE       = 11;
    localparam integer S_GDN_TRANSFER     = 12;
    localparam integer S_GDN_STATE_READ   = 13;
    localparam integer S_GDN_STATE_WRITE  = 14;
    localparam integer S_GDN_FENCE        = 15;
    localparam integer S_ATTN_BUSY        = 16;
    localparam integer S_ATTN_WAIT_DATA   = 17;
    localparam integer S_ATTN_WAIT_OWNER  = 18;
    localparam integer S_ATTN_BUBBLE      = 19;
    localparam integer S_ATTN_TRANSFER    = 20;
    localparam integer S_ATTN_KV_REQUEST  = 21;
    localparam integer S_ATTN_KV_RESPONSE = 22;
    localparam integer S_ATTN_FENCE       = 23;
    localparam integer S_RAW_REQUEST      = 24;
    localparam integer S_RAW_RESPONSE     = 25;
    localparam integer S_RAW_ACTUAL       = 26;
    localparam integer S_RAW_SHORT        = 27;
    localparam integer S_RAW_UNALIGNED    = 28;
    localparam integer S_RAW_OWNER_WAIT   = 29;
    localparam integer S_HEAD_BUSY        = 30;
    localparam integer S_HEAD_WAIT_DATA   = 31;
    localparam integer S_HEAD_BUBBLE      = 32;
    localparam integer S_HEAD_TRANSFER    = 33;
    localparam integer S_HEAD_FENCE       = 34;
    localparam integer S_CONTROLLER_WAIT  = 35;

    logic [SLOT_COUNT-1:0] event_bus;
    logic [39:0] live_ctr [0:SLOT_COUNT-1];
    logic [39:0] snapshot_ctr [0:SLOT_COUNT-1];
    integer j;
    // Align every observation with the same single register boundary. This
    // moves event decode off the 64-bit counter/snapshot paths. Counts and
    // token boundaries are unchanged; snapshot_valid is one clock later.
    logic [SLOT_COUNT-1:0] event_q;
    logic token_start_q, token_done_q;
    always_ff @(posedge clk) begin
        if (!reset_n) begin
            event_q <= '0;
            token_start_q <= 1'b0;
            token_done_q <= 1'b0;
        end else begin
            event_q <= event_bus;
            token_start_q <= token_start_i;
            token_done_q <= token_done_i;
        end
    end

    function automatic [39:0] sat_inc(input logic [39:0] value);
        begin
            if (&value)
                sat_inc = {40{1'b1}};
            else
                sat_inc = value + 40'd1;
        end
    endfunction

    always_comb begin
        event_bus = '0;
        event_bus[S_MATRIX_BUSY]       = matrix_busy_i;
        event_bus[S_MATRIX_WAIT_DATA]  = matrix_wait_data_i;
        event_bus[S_MATRIX_WAIT_OWNER] = matrix_wait_owner_i;
        event_bus[S_MATRIX_BUBBLE]     = matrix_bubble_i;
        event_bus[S_MATRIX_ISSUE]      = matrix_issue_beat_i;
        event_bus[S_MATRIX_RESPONSE]   = matrix_response_beat_i;
        event_bus[S_MATRIX_FENCE]      = matrix_fence_wait_i;
        event_bus[S_GDN_BUSY]          = gdn_busy_i;
        event_bus[S_GDN_WAIT_DATA]     = gdn_wait_data_i;
        event_bus[S_GDN_WAIT_OWNER]    = gdn_wait_owner_i;
        event_bus[S_GDN_BUBBLE]        = gdn_bubble_i;
        event_bus[S_GDN_TRANSFER]      = gdn_transfer_beat_i;
        event_bus[S_GDN_STATE_READ]    = gdn_state_read_beat_i;
        event_bus[S_GDN_STATE_WRITE]   = gdn_state_write_beat_i;
        event_bus[S_GDN_FENCE]         = gdn_fence_wait_i;
        event_bus[S_ATTN_BUSY]         = attn_busy_i;
        event_bus[S_ATTN_WAIT_DATA]    = attn_wait_data_i;
        event_bus[S_ATTN_WAIT_OWNER]   = attn_wait_owner_i;
        event_bus[S_ATTN_BUBBLE]       = attn_bubble_i;
        event_bus[S_ATTN_TRANSFER]     = attn_transfer_beat_i;
        event_bus[S_ATTN_KV_REQUEST]   = attn_kv_request_beat_i;
        event_bus[S_ATTN_KV_RESPONSE]  = attn_kv_response_beat_i;
        event_bus[S_ATTN_FENCE]        = attn_fence_wait_i;
        event_bus[S_RAW_REQUEST]       = raw_request_beat_i;
        event_bus[S_RAW_RESPONSE]      = raw_response_beat_i;
        event_bus[S_RAW_ACTUAL]        = raw_actual_beat_i;
        event_bus[S_RAW_SHORT]         = raw_short_burst_i;
        event_bus[S_RAW_UNALIGNED]     = raw_unaligned_request_i;
        event_bus[S_RAW_OWNER_WAIT]    = raw_owner_wait_i;
        event_bus[S_HEAD_BUSY]         = head_busy_i;
        event_bus[S_HEAD_WAIT_DATA]    = head_wait_data_i;
        event_bus[S_HEAD_BUBBLE]       = head_bubble_i;
        event_bus[S_HEAD_TRANSFER]     = head_transfer_beat_i;
        event_bus[S_HEAD_FENCE]        = head_fence_wait_i;
        event_bus[S_CONTROLLER_WAIT]   = controller_fence_or_done_wait_i;
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            running_o <= 1'b0;
            snapshot_valid_o <= 1'b0;
            overflow_o <= 1'b0;
            snapshot_generation_o <= 32'd0;
        end else if (token_start_q) begin
            // The start cycle belongs to the token.  It is included in the
            // total and in every event asserted with token_start_i.
            snapshot_valid_o <= 1'b0;
            overflow_o <= 1'b0;
            if (running_o && (live_ctr[S_TOKEN_TOTAL] == {40{1'b1}}))
                overflow_o <= 1'b1;
            if (token_done_q) begin
                snapshot_valid_o <= 1'b1;
                snapshot_generation_o <= snapshot_generation_o + 32'd1;
                running_o <= 1'b0;
            end else begin
                running_o <= 1'b1;
            end
        end else if (running_o) begin
            if (live_ctr[S_TOKEN_TOTAL] == {40{1'b1}})
                overflow_o <= 1'b1;
            if (token_done_q) begin
                snapshot_valid_o <= 1'b1;
                snapshot_generation_o <= snapshot_generation_o + 32'd1;
                running_o <= 1'b0;
            end
        end
    end

    // Explicit preserved reset leaves cap each reset output at32 payload FFs.
    // A MAX_FANOUT hint alone previously left hundreds of distant reset sinks.
    // These are combinational inversions: no reset-release cycle is added.
    for (genvar slot = 0; slot < SLOT_COUNT; slot = slot + 1) begin:g_counter
        wire count_event = (slot == S_TOKEN_TOTAL) || event_q[slot];
        wire [39:0] initial_value = (slot == S_TOKEN_TOTAL || event_q[slot]) ? 40'd1 : 40'd0;
        // One common saturated next value serves live and done snapshots.
        // Preserve the live event CE and all registered boundary priorities.
        wire step=count_event&&!(&live_ctr[slot]);
        wire [39:0] incremented=live_ctr[slot]+{39'd0,step};
        for (genvar half = 0; half < 2; half = half + 1) begin:g_half
            wire live_reset, snapshot_reset;
            (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b01)) live_reset_leaf(
                .I0(reset_n), .O(live_reset));
            (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b01)) snapshot_reset_leaf(
                .I0(reset_n), .O(snapshot_reset));
            always_ff @(posedge clk) begin
                if (live_reset) live_ctr[slot][half*32+:((half==0)?32:8)] <= 32'd0;
                else if (token_start_q) live_ctr[slot][half*32+:((half==0)?32:8)] <= initial_value[half*32+:((half==0)?32:8)];
                else if (running_o && count_event)
                    live_ctr[slot][half*32+:((half==0)?32:8)] <= incremented[half*32+:((half==0)?32:8)];
            end
            always_ff @(posedge clk) begin
                if (snapshot_reset) snapshot_ctr[slot][half*32+:((half==0)?32:8)] <= 32'd0;
                else if (token_start_q && token_done_q)
                    snapshot_ctr[slot][half*32+:((half==0)?32:8)] <= initial_value[half*32+:((half==0)?32:8)];
                else if (!token_start_q && running_o && token_done_q)
                    snapshot_ctr[slot][half*32+:((half==0)?32:8)] <=
                        incremented[half*32+:((half==0)?32:8)];
            end
        end
    end

    always_comb begin
        snapshot_bus_o = '0;
        for (j = 0; j < SLOT_COUNT; j = j + 1)
            snapshot_bus_o[j*64 +: 64] = snapshot_ctr[j];
    end

endmodule

// 82 passive event counters,40bit live+snapshot,64bit software readout.
module qwen35_detail_counters #(parameter integer N=82)(
 input wire clk,reset_n,token_start_i,token_done_i,input wire [N-1:0] events_i,
 input wire [319:0] ui_addends_i,
 output wire [N*64-1:0] snapshot_bus_o,
 output reg snapshot_valid_o=0,running_o=0,overflow_o=0,output reg [31:0] generation_o=0
);
 reg start_q=0,done_q=0;reg [N-1:0] events_q;reg [319:0] addends_q;
 localparam GROUPS=(N+3)/4;
 (* DONT_TOUCH="TRUE" *) reg [GROUPS-1:0] start_local=0,done_local=0,running_local=0;
 always @(posedge clk)begin
   if(!reset_n)begin start_q<=0;done_q<=0;events_q<=0;addends_q<=0;start_local<=0;done_local<=0;running_local<=0;end
   else begin
     start_q<=token_start_i;done_q<=token_done_i;events_q<=events_i;addends_q<=ui_addends_i;
     for(integer g=0;g<GROUPS;g++)begin
       start_local[g]<=token_start_i;done_local[g]<=token_done_i;
       if(start_local[g])running_local[g]<=!done_local[g];
       else if(running_local[g]&&done_local[g])running_local[g]<=0;
     end
   end
 end
 wire [N-1:0] overflow;
 always @(posedge clk)begin
   if(!reset_n)begin snapshot_valid_o<=0;running_o<=0;overflow_o<=0;generation_o<=0;end
   else if(start_q)begin
     running_o<=!done_q;snapshot_valid_o<=done_q;overflow_o<=0;
     if(done_q)generation_o<=generation_o+1;
   end else if(running_o)begin
     if(|overflow)overflow_o<=1;
     if(done_q)begin running_o<=0;snapshot_valid_o<=1;generation_o<=generation_o+1;end
   end
 end
 for(genvar s=0;s<N;s++)begin:g_counter
   reg [39:0] live_value,snapshot_value;
   wire [39:0] delta;
    if(s>=74&&s<82)assign delta=addends_q[(s-74)*40+:40];
   else assign delta=40'd1;
    wire [39:0] next_value;
    // UI byte/count deltas keep the original41bit addition and carry rule.
    if(s>=74&&s<82)begin:g_dynamic_delta
      wire [40:0] sum={1'b0,live_value}+{1'b0,delta};
      wire [39:0] updated=sum[40]?{40{1'b1}}:sum[39:0];
      assign next_value=events_q[s]?updated:live_value;
      assign overflow[s]=events_q[s]&&sum[40];
    end else begin:g_unit_delta
      wire step=events_q[s]&&!(&live_value);
      assign next_value=live_value+{39'd0,step};
      assign overflow[s]=events_q[s]&&(&live_value);
    end
    wire [39:0] initial_value=events_q[s]?delta:40'd0;
   assign snapshot_bus_o[s*64+:64]={24'd0,snapshot_value};
   for(genvar half=0;half<2;half++)begin:g_half
     localparam W=half==0?32:8;
     wire live_reset,snapshot_reset;
     (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b01)) live_leaf(.I0(reset_n),.O(live_reset));
     (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b01)) snapshot_leaf(.I0(reset_n),.O(snapshot_reset));
     always @(posedge clk)begin
       if(live_reset)live_value[half*32+:W]<=0;
       else if(start_local[s/4])live_value[half*32+:W]<=initial_value[half*32+:W];
       else if(running_local[s/4]&&events_q[s])live_value[half*32+:W]<=next_value[half*32+:W];
     end
     always @(posedge clk)begin
       if(snapshot_reset)snapshot_value[half*32+:W]<=0;
       else if(start_local[s/4]&&done_local[s/4])snapshot_value[half*32+:W]<=initial_value[half*32+:W];
       else if(!start_local[s/4]&&running_local[s/4]&&done_local[s/4])snapshot_value[half*32+:W]<=
         next_value[half*32+:W];
     end
   end
 end
endmodule
