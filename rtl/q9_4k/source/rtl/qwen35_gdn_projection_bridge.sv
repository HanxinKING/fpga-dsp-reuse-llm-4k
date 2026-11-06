`timescale 1ns/1ps
// Bridges the GDN projection schedule to one shared, DDR-fed INT4 matrix
// service.  It owns only command/output ordering: weight movement, activation
// storage and MAC lanes remain in the parent service.  A request completes
// only after both the matrix service reports done and the final output beat is
// accepted, so a downstream stall cannot advance the next projection early.
module qwen35_gdn_projection_bridge #(
    parameter integer EARLY_GATES = 0,
    parameter integer HIDDEN = 4096,
    parameter integer KEY_HEADS = 16,
    parameter integer VALUE_HEADS = 32,
    parameter integer HEAD_DIM = 128,
    parameter integer MODEL_LAYERS = 24,
    parameter BASE_ROM_FILE_PL = "gdn_pl_bases.mem",
    parameter BASE_ROM_FILE_PS = "gdn_ps_bases.mem",
    parameter logic [33:0] QKV_WEIGHT_BASE = 34'd0,
    parameter logic [33:0] Z_WEIGHT_BASE = 34'd0,
    parameter logic [33:0] B_WEIGHT_BASE = 34'd0,
    parameter logic [33:0] A_WEIGHT_BASE = 34'd0,
    parameter logic [33:0] O_WEIGHT_BASE = 34'd0
) (
    input  logic clk,
    input  logic reset_n,
    input  logic start_i,
    input  logic [((MODEL_LAYERS <= 1) ? 1 : $clog2(MODEL_LAYERS))-1:0] layer_i,
    output logic start_ready_o,
    output logic busy_o,
    output logic done_o,
    output logic [31:0] cycles_o,

    // One command at a time to the existing shared matrix/DDR service.
    output logic matrix_cmd_valid_o,
    input  logic matrix_cmd_ready_i,
    output logic [2:0] matrix_cmd_kind_o,
    output logic [14:0] matrix_cmd_rows_o,
    output logic [14:0] matrix_cmd_cols_o,
    output logic [33:0] matrix_cmd_weight_base_o,
    output logic [33:0] matrix_cmd_ps_base_o,
    output logic matrix_cmd_pl_only_o,
    output logic matrix_cmd_bf16_o,
    input  logic matrix_done_i,

    // Result stream from that service, forwarded with its projection tag.
    input  logic matrix_out_valid_i,
    output logic matrix_out_ready_o,
    input  logic [14:0] matrix_out_index_i,
    input  logic signed [23:0] matrix_out_data_i,
    input  logic matrix_out_last_i,
    output logic proj_out_valid_o,
    input  logic proj_out_ready_i,
    output logic [2:0] proj_out_kind_o,
    output logic [14:0] proj_out_index_o,
    output logic signed [23:0] proj_out_data_o,
    output logic proj_out_last_o,
    output logic [7:0] status_o
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    logic sched_req_valid, sched_req_ready, sched_req_done;
    logic [2:0] sched_req_kind;
    logic [14:0] sched_req_rows, sched_req_cols;
    logic [33:0] sched_req_weight_base, sched_req_ps_base, sched_req_hidden_base;
    logic sched_req_bf16;
    logic sched_req_pl_only;
    logic active_r, done_seen_r, last_seen_r;
    logic [2:0] active_kind_r;
    logic finish_now;
    logic out_fire;
    // Two output slots cut the shared matrix result/fault/owner cone before
    // the GDN scalar RAM write decoder. Steady-state throughput remains1/cycle.
    logic [1:0] response_count;
    logic source_last_seen_r;
    // The front slot is the actual output register. No read-pointer mux or
    // asynchronous LUTRAM may drive the wide banked QKV RAM data bus.
    // Keep replication legal: MAX_FANOUT can place equivalent front FFs
    // near the bank groups; DONT_TOUCH would prohibit that optimization.
    (* KEEP="TRUE", SHREG_EXTRACT="NO", MAX_FANOUT=32 *) logic [39:0] response_front_r;
    (* SHREG_EXTRACT="NO" *) logic [39:0] response_skid_r;
    (* KEEP="TRUE", MAX_FANOUT=32 *) logic response_front_valid_r;
    wire [39:0] response_source_payload={matrix_out_last_i,matrix_out_index_i,matrix_out_data_i};
    wire source_fire=matrix_out_valid_i&&matrix_out_ready_o;

    qwen35_gdn_projection_schedule #(
        .EARLY_GATES(EARLY_GATES), .HIDDEN(HIDDEN), .KEY_HEADS(KEY_HEADS), .VALUE_HEADS(VALUE_HEADS), .HEAD_DIM(HEAD_DIM),
        .MODEL_LAYERS(MODEL_LAYERS), .BASE_ROM_FILE_PL(BASE_ROM_FILE_PL), .BASE_ROM_FILE_PS(BASE_ROM_FILE_PS),
        .QKV_WEIGHT_BASE(QKV_WEIGHT_BASE), .Z_WEIGHT_BASE(Z_WEIGHT_BASE),
        .B_WEIGHT_BASE(B_WEIGHT_BASE), .A_WEIGHT_BASE(A_WEIGHT_BASE), .O_WEIGHT_BASE(O_WEIGHT_BASE)
    ) scheduler (
        .clk(clk), .reset_n(reset_n), .start_i(start_i), .layer_i(layer_i), .start_ready_o(start_ready_o),
        .busy_o(busy_o), .done_o(done_o), .phase_o(),
        .req_valid_o(sched_req_valid), .req_ready_i(sched_req_ready), .req_kind_o(sched_req_kind),
        .req_rows_o(sched_req_rows), .req_cols_o(sched_req_cols), .req_weight_base_o(sched_req_weight_base),
        .req_ps_base_o(sched_req_ps_base),
        .req_pl_only_o(sched_req_pl_only),
        .req_hidden_base_o(sched_req_hidden_base), .req_bf16_o(sched_req_bf16),
        .req_done_i(sched_req_done), .cycles_o(cycles_o)
    );

    assign matrix_cmd_valid_o = sched_req_valid && !active_r;
    assign matrix_cmd_kind_o = sched_req_kind;
    assign matrix_cmd_rows_o = sched_req_rows;
    assign matrix_cmd_cols_o = sched_req_cols;
    assign matrix_cmd_weight_base_o = sched_req_weight_base;
    assign matrix_cmd_ps_base_o = sched_req_ps_base;
    assign matrix_cmd_pl_only_o = sched_req_pl_only;
    assign matrix_cmd_bf16_o = sched_req_bf16;
    assign sched_req_ready = matrix_cmd_ready_i && !active_r;

    assign proj_out_valid_o = response_front_valid_r;
    assign matrix_out_ready_o = active_r && response_count<2;
    assign proj_out_kind_o = active_kind_r;
    assign proj_out_index_o = response_front_r[38:24];
    assign proj_out_data_o = response_front_r[23:0];
    assign proj_out_last_o = response_front_r[39];
    assign out_fire = proj_out_valid_o && proj_out_ready_i;
    assign finish_now = active_r && (done_seen_r || matrix_done_i) &&
                        (last_seen_r || (out_fire && proj_out_last_o));
    assign sched_req_done = finish_now;

    // The legacy descriptor bit is retained for ABI compatibility, but the
    // Intel AutoRound candidate is never allowed to re-enter the old BF16
    // owner path.
    // synthesis translate_off
    always @(posedge clk) if (reset_n && sched_req_valid && sched_req_bf16)
        $fatal(1, "QWEN35_GDN_SCHEDULER_REQUESTED_BF16");
    // synthesis translate_on

    // synthesis translate_off
    always @(posedge clk) if(reset_n) begin
        if(response_front_valid_r !== (active_r && response_count!=0))
            $fatal(1,"Q9_GDN_REGISTER_FIFO_VALID_INVARIANT");
        if(response_count>2 || (out_fire && response_count==0))
            $fatal(1,"Q9_GDN_REGISTER_FIFO_OCCUPANCY_INVARIANT");
    end
    // synthesis translate_on

    // status[0]: matrix done arrived before a genuine upstream final beat.
    // status[1]: a result beat arrived without an active command.
    always_ff @(posedge clk) begin
        if (q9_local_reset_active) begin
            active_r <= 1'b0;
            active_kind_r <= '0;
            done_seen_r <= 1'b0;
            last_seen_r <= 1'b0;
            status_o <= '0;
            response_count<=0;response_front_valid_r<=0;source_last_seen_r<=0;
        end else begin
            case({source_fire,out_fire})
                2'b10:response_count<=response_count+1'b1;
                2'b01:response_count<=response_count-1'b1;
                default:;
            endcase
            // Identical two-slot push/pop contract. A full queue still
            // refuses an upstream push even when it pops on this edge.
            if(out_fire && response_count==2)
                response_front_r<=response_skid_r;
            else if(source_fire && (response_count==0 || out_fire))
                response_front_r<=response_source_payload;
            if(source_fire && response_count==1 && !out_fire)
                response_skid_r<=response_source_payload;
            if(source_fire && response_count==0)
                response_front_valid_r<=1'b1;
            else if(out_fire && response_count==1 && !source_fire)
                response_front_valid_r<=1'b0;
            if(source_fire)begin
                if(matrix_out_last_i)source_last_seen_r<=1;
                if(source_last_seen_r)status_o[1]<=1;
            end
            if (matrix_out_valid_i && !active_r) status_o[1] <= 1'b1;
            if (matrix_cmd_valid_o && matrix_cmd_ready_i) begin
                active_r <= 1'b1;
                active_kind_r <= sched_req_kind;
                response_count<=0;response_front_valid_r<=0;source_last_seen_r<=0;
                done_seen_r <= 1'b0;
                last_seen_r <= 1'b0;
            end
            if (active_r && matrix_done_i) begin
                done_seen_r <= 1'b1;
                if (!(source_last_seen_r || (source_fire && matrix_out_last_i))) status_o[0] <= 1'b1;
            end
            if (out_fire && proj_out_last_o) last_seen_r <= 1'b1;
            if (finish_now) begin
                if(response_count>1)status_o[1]<=1;
                response_count<=0;response_front_valid_r<=0;source_last_seen_r<=0;
                active_r <= 1'b0;
                done_seen_r <= 1'b0;
                last_seen_r <= 1'b0;
            end
        end
    end
endmodule
