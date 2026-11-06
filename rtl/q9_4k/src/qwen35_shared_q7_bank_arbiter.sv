`timescale 1ns/1ps
// One Q7-frozen 64-DSP bank shared by the Q9 FFN matrix client and GDN.
// Matrix uses the raw Q7 bank contract; GDN uses the calibrated PRIME/STREAM/
// CLOSE contract that qwen35_gdn_mac_share expects. The owner is held through
// the three-cycle bank pipeline and the GDN close drain.
module qwen35_shared_q7_bank_arbiter #(
    parameter integer LANES=64,NATIVE_S8=0,
    parameter integer BANK_UNITS=128,
    parameter integer PREADDER=0,
    parameter integer A_W=27,
    parameter integer B_W=18,
    parameter integer P_W=48,
    parameter integer STREAM_LATENCY=3,
    parameter integer MATRIX_DRAIN=3,
    parameter integer GDN_PRIME=3,
    parameter integer GDN_CLOSE=2
) (
    input wire scalar_request_i=1'b0,output wire scalar_ready_o,
    input wire[6:0]scalar_valid_i=7'd0,input wire[188:0]scalar_a_i=189'd0,input wire[125:0]scalar_b_i=126'd0,
    input wire rem_valid_i=1'b0,input wire[47:0]rem_n_i=48'd0,rem_product_i=48'd0,
    output wire[6:0]scalar_result_valid_o,output wire[335:0]scalar_result_o,
    output wire rem_result_valid_o,output wire[47:0]rem_result_o,
    input wire matrix_attention_qk_i=0,matrix_attention_av_i=0,
    input wire[767:0] matrix_attention_c_i=0,
    input wire matrix_pending_i=1'b0,
    input logic clk, input logic reset_n,
    input logic matrix_valid_i, input logic matrix_accumulate_i,
    input logic matrix_head_mode_i, input logic matrix_head_multiply_i,
    input logic matrix_head_mac_i, input logic matrix_head_accumulate_i,
    input logic [BANK_UNITS*A_W-1:0] matrix_a_i,
    input logic [BANK_UNITS*A_W-1:0] matrix_d_i,
    input logic matrix_use_d_i,
    input logic [BANK_UNITS*B_W-1:0] matrix_b_i,
    output logic [BANK_UNITS*P_W-1:0] matrix_product_o,
    input logic gdn_req_i, output logic gdn_grant_o,
    input logic gdn_issue_valid_i, output logic gdn_issue_ready_o,
    input logic gdn_issue_accumulate_i,
    input wire gdn_issue_shift17_i=1'b0,
    input logic [LANES*A_W-1:0] gdn_a_i,
    input logic [LANES*B_W-1:0] gdn_b_i,
    output logic gdn_stream_valid_o, output logic gdn_burst_done_o,
    output logic gdn_busy_o,
    output logic [LANES*P_W-1:0] gdn_product_o,
    output wire [1:0] owner_o
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    localparam logic [1:0] OWN_IDLE=2'd0, OWN_MATRIX=2'd1, OWN_GDN=2'd2,OWN_SCALAR=2'd3;
    localparam logic [1:0] G_IDLE=2'd0, G_PRIME=2'd1, G_STREAM=2'd2, G_CLOSE=2'd3;
    (* MAX_FANOUT=32 *) logic [1:0] owner=OWN_IDLE;
    logic [1:0] gstate=G_IDLE;
    logic [7:0] count='0;
    logic [3:0] matrix_drain='0;
    logic [STREAM_LATENCY-1:0] gdn_stream_pipe='0;
    logic [5:0] block_stream_pipe='0;logic block_burst=0;
    wire block_packet=gdn_issue_shift17_i;
    logic [BANK_UNITS*A_W-1:0] raw_a;
    logic [BANK_UNITS*A_W-1:0] raw_d;
    logic [BANK_UNITS*B_W-1:0] raw_b;
    logic raw_valid, raw_accumulate, raw_head_mode, raw_head_multiply, raw_shift17;
    logic raw_head_mac, raw_head_accumulate, raw_use_d;
    logic [BANK_UNITS*P_W-1:0] raw_product;
    logic [BANK_UNITS*A_W-1:0] gdn_a_ext='0;
    logic [BANK_UNITS*B_W-1:0] gdn_b_ext='0;
    wire attention_bank_busy,attention_pipeline_busy;
    wire matrix_active = attention_pipeline_busy || matrix_pending_i || matrix_valid_i || matrix_head_mode_i || matrix_head_multiply_i ||
                         matrix_head_mac_i || matrix_head_accumulate_i;
    wire gdn_accept = gdn_issue_valid_i && gdn_issue_ready_o;
    // Decode the NEXT phase on the preceding edge. This is the same STREAM
    // interval, without owner/gstate decode on the remote payload CEs.
    (* DONT_TOUCH="TRUE" *) logic gdn_ready_r=1'b0;
    always_ff @(posedge clk)begin
        if(q9_local_reset_active)gdn_ready_r<=1'b0;
        else gdn_ready_r<=owner==OWN_GDN &&
            ((gstate==G_PRIME && count<=1) ||
             (gstate==G_STREAM && gdn_issue_valid_i));
    end

    // Tag-addressed convolution reads still feed the delayed tap captures
    // after the final request. PRIME/CLOSE padding must not zero these B
    // operands; the bank's per-tap valid and existing lease drain qualify them.
    reg[2:0]conv_input_tail=0;
    always_ff @(posedge clk)begin
        if(q9_local_reset_active)conv_input_tail<=0;
        else conv_input_tail<={conv_input_tail[1:0],gdn_accept&&block_packet&&gdn_issue_accumulate_i};
    end

    // Payload select is relevant only on an enabled DSP input edge. IDLE
    // payload may follow the matrix directly. Same-edge owner/phase replicas
    // keep each wide selector local to eight DSP lanes, with no issue stage.
    // T73: four lanes per same-edge replica (was eight).
    localparam integer SEL_LANES=4,SELECT_GROUPS=(BANK_UNITS+SEL_LANES-1)/SEL_LANES;
    for(genvar sel=0;sel<SELECT_GROUPS;sel=sel+1)begin:g_local_select
        (* DONT_TOUCH="TRUE" *) logic gdn_select=1'b0,stream_select=1'b0;
        always_ff @(posedge clk)begin
            if(q9_local_reset_active)begin gdn_select<=0;stream_select<=0;end
            else begin
                gdn_select<=
                    (owner==OWN_IDLE && !matrix_active && !scalar_request_i && gdn_req_i) ||
                    (owner==OWN_GDN &&
                     ((gstate==G_IDLE && gdn_issue_valid_i) ||
                      (gstate==G_IDLE && gdn_req_i) ||
                      gstate==G_PRIME || gstate==G_STREAM || gstate==G_CLOSE));
                stream_select<=owner==OWN_GDN &&
                    ((gstate==G_PRIME && count<=1) ||
                     (gstate==G_STREAM && gdn_issue_valid_i));
            end
        end
        for(genvar lane=sel*SEL_LANES;lane<(sel+1)*SEL_LANES && lane<BANK_UNITS;lane=lane+1)begin:g_lane
            assign raw_a[lane*A_W+:A_W]=gdn_select ?
                gdn_a_ext[lane*A_W+:A_W] : matrix_a_i[lane*A_W+:A_W];
            assign raw_b[lane*B_W+:B_W]=gdn_select ?
                ((stream_select||(|conv_input_tail)) ? gdn_b_ext[lane*B_W+:B_W] : {B_W{1'b0}}) :
                matrix_b_i[lane*B_W+:B_W];
        end
    end
    assign raw_d=matrix_d_i;
    assign scalar_ready_o=reset_n&&owner==OWN_SCALAR;

    always_comb begin
        gdn_a_ext='0; gdn_b_ext='0;
        for(integer i=0;i<BANK_UNITS;i=i+1) begin
            if(i<LANES) begin
                gdn_a_ext[i*A_W +: A_W]=gdn_a_i[i*A_W +: A_W];
                gdn_b_ext[i*B_W +: B_W]=gdn_b_i[i*B_W +: B_W];
            end
        end
    end

    always_comb begin
        raw_valid=1'b0; raw_accumulate=1'b0; raw_head_mode=1'b0;
        raw_head_multiply=1'b0; raw_head_mac=1'b0; raw_head_accumulate=1'b0;
        raw_use_d=1'b0; raw_shift17=1'b0;
        if(owner==OWN_MATRIX || (owner==OWN_IDLE && matrix_active)) begin
            raw_valid=matrix_valid_i; raw_accumulate=matrix_accumulate_i;
            raw_head_mode=matrix_head_mode_i; raw_head_multiply=matrix_head_multiply_i;
            raw_head_mac=matrix_head_mac_i; raw_head_accumulate=matrix_head_accumulate_i;
            raw_use_d=matrix_use_d_i;
        end else if(owner==OWN_GDN) begin
            raw_valid=(gstate!=G_IDLE);
            raw_accumulate=(gstate==G_PRIME || gstate==G_CLOSE) ? 1'b1 : gdn_issue_accumulate_i;
            // Only B must be zero during PRIME/CLOSE. A remains a single
            // matrix/GDN mux; inactive A/D contents are unobservable.
            raw_shift17=(gstate==G_STREAM) && gdn_issue_shift17_i;
        end
    end

    qwen35_vpu_bank40 #(.GDN_B_LOW_DIRECT(1),.BLOCK32_IMPLIES_VALID(1),.REGISTERED_BUSY(1),.UNITS(BANK_UNITS),.SYSTOLIC_MATRIX(NATIVE_S8), .PREADDER(PREADDER), .HEAD_DIRECT(1), .ACTIVE_UNITS(LANES),.CONV_PRESKEWED(1),.GDN_PACKET_SEPARATE(1)) bank (
        .scalar_lease_i(owner==OWN_SCALAR),.scalar_valid_i(scalar_valid_i),.scalar_a_i(scalar_a_i),.scalar_b_i(scalar_b_i),
        .rem_valid_i(rem_valid_i),.rem_n_i(rem_n_i),.rem_product_i(rem_product_i),
        .scalar_result_valid_o(scalar_result_valid_o),.scalar_result_o(scalar_result_o),
        .rem_result_valid_o(rem_result_valid_o),.rem_result_o(rem_result_o),
        .clk(clk), .reset_n(reset_n), .valid_i(raw_valid), .accumulate_i(raw_accumulate), .shift17_i(raw_shift17),
        .block32_i(gdn_accept&&owner==OWN_GDN&&gstate==G_STREAM&&block_packet&&!gdn_issue_accumulate_i),
        .conv_chain_i(gdn_accept&&owner==OWN_GDN&&gstate==G_STREAM&&block_packet&&gdn_issue_accumulate_i),
        .gdn_lease_i(owner==OWN_GDN),
        .head_mode_i(raw_head_mode), .head_multiply_i(raw_head_multiply),
        .head_mac_i(raw_head_mac), .head_accumulate_i(raw_head_accumulate),
        .a_i(raw_a), .d_i(raw_d), .use_d_i(raw_use_d), .b_i(raw_b), .gdn_packet_a_i(gdn_a_ext),.gdn_packet_b_i(gdn_b_ext),.product_o(raw_product),.attention_qk_i(matrix_attention_qk_i&&owner!=OWN_GDN&&owner!=OWN_SCALAR),
        .attention_av_i(matrix_attention_av_i&&owner!=OWN_GDN&&owner!=OWN_SCALAR),.attention_c_i(matrix_attention_c_i),
        .attention_busy_o(attention_bank_busy),.attention_pipeline_busy_o(attention_pipeline_busy));

    assign matrix_product_o=raw_product;
    assign owner_o=owner;
    // synthesis translate_off
    always @(posedge clk)if(reset_n&&owner!=OWN_SCALAR)begin
        if(attention_pipeline_busy!==attention_bank_busy)$fatal(1,"BANK44_BUSY_OWNER_COFACTOR");
    end
    // synthesis translate_on
    assign gdn_product_o=raw_product[LANES*P_W-1:0];
    // The GDN client asks for exclusive ownership before it can issue data.
    // Grant may be asserted while idle so its own arbiter can capture the
    // request on the same edge that this arbiter acquires the bank.
    assign gdn_grant_o=reset_n && (owner==OWN_GDN ||
        (owner==OWN_IDLE && !matrix_active && !scalar_request_i && gdn_req_i));
    assign gdn_issue_ready_o=gdn_ready_r && reset_n;
    assign gdn_stream_valid_o=reset_n && (gdn_stream_pipe[STREAM_LATENCY-1]||block_stream_pipe[5]);
    assign gdn_burst_done_o=reset_n && owner==OWN_GDN && gstate==G_CLOSE && count<=1;
    // Match qwen35_gdn_mac_bank.busy_o: the inner client arbiter uses this
    // only to wait for the bank's PRIME/CLOSE pipeline, not for ownership.
    // Reporting ownership here makes its release wait on itself forever.
    assign gdn_busy_o=reset_n && owner==OWN_GDN &&
        (gstate==G_PRIME || gstate==G_CLOSE);

    always_ff @(posedge clk) begin
        if(q9_local_reset_active) begin
            owner<=OWN_IDLE; gstate<=G_IDLE; count<='0; matrix_drain<='0; gdn_stream_pipe<='0;
            block_stream_pipe<='0;block_burst<=0;
        end else begin
            gdn_stream_pipe <= {gdn_stream_pipe[STREAM_LATENCY-2:0],gdn_accept&&!(block_packet&&gdn_issue_accumulate_i)};
            block_stream_pipe<={block_stream_pipe[4:0],gdn_accept&&block_packet&&gdn_issue_accumulate_i};
            if(gdn_accept)block_burst<=block_packet&&gdn_issue_accumulate_i;
            case(owner)
                OWN_IDLE: begin
                    matrix_drain<='0;
                    if(matrix_active) owner<=OWN_MATRIX;
                    else if(scalar_request_i)owner<=OWN_SCALAR;
                    else if(gdn_req_i) begin owner<=OWN_GDN; gstate<=G_IDLE; count<='0; end
                end
                OWN_MATRIX: begin
                    if(matrix_active) matrix_drain<='0;
                    else if(matrix_drain < MATRIX_DRAIN[3:0]) matrix_drain<=matrix_drain+1'b1;
                    else begin owner<=OWN_IDLE; matrix_drain<='0; end
                end
                OWN_SCALAR:if(!scalar_request_i&&!attention_bank_busy)owner<=OWN_IDLE;
                OWN_GDN: begin
                    case(gstate)
                        G_IDLE: if(gdn_issue_valid_i) begin gstate<=G_PRIME; count<=GDN_PRIME[7:0]; end
                                else if(!gdn_req_i) owner<=OWN_IDLE;
                        G_PRIME: if(count<=1) begin gstate<=G_STREAM; count<='0; end else count<=count-1'b1;
                        G_STREAM: if(!gdn_issue_valid_i) begin gstate<=G_CLOSE; count<=block_burst?8'd5:GDN_CLOSE[7:0]; end
                        G_CLOSE: if(count<=1) begin gstate<=G_IDLE; count<='0; end else count<=count-1'b1;
                        default: begin gstate<=G_IDLE; owner<=OWN_IDLE; end
                    endcase
                end
                default: begin owner<=OWN_IDLE; gstate<=G_IDLE; end
            endcase
        end
    end
endmodule
