`timescale 1ns/1ps
// Serial page-reader owner for one full-attention job.
//
// qwen35_attention_compact consumes all four KV heads in one K pass followed by
// all four heads in one V pass.  The page reader is intentionally single-head
// and single-kind so its code/metadata RAM is reused.  This bridge launches
// eight reads in order and exposes the reader stream directly; only the page
// reader's small storage is present, with no per-head replication.
module qwen35_kv_attention_read_bridge #(
    parameter integer EXTERNAL_READER=0,
    parameter integer QUERY_HEADS = 16,
    parameter integer KV_HEADS = 4,
    parameter integer HEAD_DIM = 256,
    parameter integer MAX_TOKENS = 32
)(
    output wire[100:0]raw_ext_cmd_o,input wire[692:0]raw_ext_rsp_i=693'd0,
    input logic clk, reset_n,
    input logic start_i, output logic start_ready_o,
    input logic [33:0] code_base_i, param_base_i,
    input logic [5:0] valid_tokens_i, input logic [13:0] token_base_i,
    output logic busy_o, done_o, output logic [7:0] status_o,

    output logic k_valid_o, input logic k_ready_i,
    output logic [$clog2(KV_HEADS)-1:0] k_kv_head_o,
    output logic [$clog2(MAX_TOKENS)-1:0] k_token_o,
    output logic [$clog2(HEAD_DIM)-1:0] k_dim_o,
    output logic [15*4+4-1:0] k_code_o,
    output logic [15*16+16-1:0] k_scale_o, k_min_o,
    output logic [QUERY_HEADS-1:0] k_head_enable_o,
    output logic k_pass_done_o,

    output logic v_valid_o, input logic v_ready_i,
    output logic [$clog2(KV_HEADS)-1:0] v_kv_head_o,
    output logic [$clog2(MAX_TOKENS)-1:0] v_token_o,
    output logic [$clog2(HEAD_DIM)-1:0] v_dim_o,
    output logic [15*4+4-1:0] v_code_o,
    output logic [15*16+16-1:0] v_scale_o, v_min_o,
    output logic [QUERY_HEADS-1:0] v_head_enable_o,
    output logic v_pass_done_o,

    output logic [31:0] read_cycles_o, read_vectors_o,
    output logic [3:0] m_arid, output logic [33:0] m_araddr,
    output logic [7:0] m_arlen, output logic [2:0] m_arsize,
    output logic [1:0] m_arburst, output logic m_arvalid, input logic m_arready,
    input logic [3:0] m_rid, input logic [511:0] m_rdata,
    input logic [1:0] m_rresp, input logic m_rlast, m_rvalid,
    output logic m_rready
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    localparam integer KVW = (KV_HEADS<=1)?1:$clog2(KV_HEADS);
    localparam integer TW = (MAX_TOKENS<=1)?1:$clog2(MAX_TOKENS);
    localparam integer DW = (HEAD_DIM<=1)?1:$clog2(HEAD_DIM);
    localparam integer S_IDLE=0,S_LAUNCH_K=1,S_STREAM_K=2,
                       S_LAUNCH_V=3,S_STREAM_V=4,S_DONE=5;
    (* MAX_FANOUT=32 *) logic [2:0] state;
    logic [KVW-1:0] job_head;
    logic reader_start, reader_ready, reader_valid, reader_ready_i;
    logic reader_out_value, reader_last, reader_busy, reader_done;
    logic [1:0] reader_head;
    logic [13:0] reader_token;
    logic [7:0] reader_dim;
    logic [63:0] reader_code;
    logic [255:0] reader_scale, reader_min;
    logic [7:0] reader_status;
    logic [31:0] reader_cycles, reader_bytes, reader_bursts, reader_vectors;
    wire stream_k = state==S_STREAM_K;
    wire stream_v = state==S_STREAM_V;
    wire stream_ready = stream_k ? k_ready_i : v_ready_i;
    wire stream_take = reader_valid && stream_ready;

    assign start_ready_o = state==S_IDLE;
    assign busy_o = state!=S_IDLE;
    assign k_valid_o = reader_valid && stream_k;
    assign v_valid_o = reader_valid && stream_v;
    assign k_kv_head_o = reader_head[KVW-1:0];
    assign v_kv_head_o = reader_head[KVW-1:0];
    assign k_token_o = reader_token[TW-1:0];
    assign v_token_o = reader_token[TW-1:0];
    assign k_dim_o = reader_dim[DW-1:0];
    assign v_dim_o = reader_dim[DW-1:0];
    assign k_code_o = reader_code;
    assign v_code_o = reader_code;
    assign k_scale_o = reader_scale;
    assign v_scale_o = reader_scale;
    assign k_min_o = reader_min;
    assign v_min_o = reader_min;
    assign k_head_enable_o = {QUERY_HEADS{1'b1}};
    assign v_head_enable_o = {QUERY_HEADS{1'b1}};
    assign k_pass_done_o = stream_k && stream_take && reader_last && job_head==KV_HEADS-1;
    assign v_pass_done_o = stream_v && stream_take && reader_last && job_head==KV_HEADS-1;
    assign reader_ready_i = stream_ready;
    assign reader_start = (state==S_LAUNCH_K || state==S_LAUNCH_V) && reader_ready;

    qwen35_kv_page_axi_reader #(.EXTERNAL_READER(EXTERNAL_READER),.HEAD_DIM(HEAD_DIM),.MAX_TOKENS(MAX_TOKENS)) reader (
        .clk(clk),.reset_n(reset_n),.start_i(reader_start),.start_ready_o(reader_ready),
.raw_ext_cmd_o(raw_ext_cmd_o),.raw_ext_rsp_i(raw_ext_rsp_i),
        .code_base_i(code_base_i),.param_base_i(param_base_i),.head_i(job_head),
        .value_i(state==S_LAUNCH_V || state==S_STREAM_V),
        .valid_tokens_i(valid_tokens_i),.token_base_i(token_base_i),
        .out_valid_o(reader_valid),.out_ready_i(reader_ready_i),
        .out_head_o(reader_head),.out_value_o(reader_out_value),.out_token_o(reader_token),
        .out_dimension_o(reader_dim),.out_code_o(reader_code),.out_scale_o(reader_scale),
        .out_minimum_o(reader_min),.out_last_o(reader_last),.busy_o(reader_busy),
        .done_o(reader_done),.status_o(reader_status),.cycles_o(reader_cycles),
        .read_bytes_o(reader_bytes),.read_bursts_o(reader_bursts),.vector_count_o(reader_vectors),
        .m_arid(m_arid),.m_araddr(m_araddr),.m_arlen(m_arlen),.m_arsize(m_arsize),
        .m_arburst(m_arburst),.m_arvalid(m_arvalid),.m_arready(m_arready),
        .m_rid(m_rid),.m_rdata(m_rdata),.m_rresp(m_rresp),.m_rlast(m_rlast),
        .m_rvalid(m_rvalid),.m_rready(m_rready));

    assign read_cycles_o = reader_cycles;
    assign read_vectors_o = reader_vectors;

    always_ff @(posedge clk) begin
        if (q9_local_reset_active) begin
            state <= S_IDLE; job_head <= '0; done_o <= 0; status_o <= 0;
        end else begin
            done_o <= 0;
            if (reader_done) status_o <= status_o | reader_status;
            case (state)
                S_IDLE: if (start_i) begin
                    job_head <= '0; status_o <= 0; state <= S_LAUNCH_K;
                end
                S_LAUNCH_K: if (reader_ready) state <= S_STREAM_K;
                S_STREAM_K: if (reader_done) begin
                    if (job_head==KV_HEADS-1) begin job_head <= '0; state <= S_LAUNCH_V; end
                    else begin job_head <= job_head + 1'b1; state <= S_LAUNCH_K; end
                end
                S_LAUNCH_V: if (reader_ready) state <= S_STREAM_V;
                S_STREAM_V: if (reader_done) begin
                    if (job_head==KV_HEADS-1) state <= S_DONE;
                    else begin job_head <= job_head + 1'b1; state <= S_LAUNCH_V; end
                end
                S_DONE: begin done_o <= 1; state <= S_IDLE; end
                default: begin status_o[7] <= 1; state <= S_DONE; end
            endcase
        end
    end

    initial begin
        if (QUERY_HEADS % KV_HEADS != 0 || HEAD_DIM % 16 != 0 || MAX_TOKENS != 32)
            $fatal(1,"QWEN35_KV_ATTENTION_READ_BRIDGE_GEOMETRY");
    end
endmodule
