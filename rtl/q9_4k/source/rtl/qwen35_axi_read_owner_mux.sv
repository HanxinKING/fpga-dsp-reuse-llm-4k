`timescale 1ns/1ps
// Two read masters in ONE UI domain. No core sequencer bit selects AXI.
// Reserve an owner before exposing ARVALID, then keep it through every
// accepted AR's RLAST, including AR stalls and gaps between response beats.
// A common reset aborts the complete fabric; independent client resets are
// not supported. No data pipeline and no change to within-owner burst II.
module qwen35_axi_read_owner_mux #(
    parameter integer MAX_OUTSTANDING=16
)(
    input wire ui_clk,reset_n,
    input wire [62:0] a_ar,b_ar,
    input wire a_arvalid,b_arvalid,
    output wire a_arready,b_arready,
    output wire [62:0] m_ar,
    output wire m_arvalid,input wire m_arready,
    input wire m_rvalid,m_rlast,
    output wire a_rvalid,b_rvalid,
    input wire a_rready,b_rready,output wire m_rready
);
    localparam integer CW=$clog2(MAX_OUTSTANDING+1);
    wire rst;
    xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) reset_ui(
        .src_arst(reset_n),.dest_clk(ui_clk),.dest_arst(rst));
    (* MAX_FANOUT=32 *) reg active=0,owner=0,last_owner=1;
    reg [CW-1:0] outstanding=0;
    wire selected_valid=owner?b_arvalid:a_arvalid;
    wire room=outstanding<MAX_OUTSTANDING;
    assign m_ar=owner?b_ar:a_ar;
    assign m_arvalid=rst&&active&&room&&selected_valid;
    assign a_arready=rst&&active&&!owner&&room&&m_arready;
    assign b_arready=rst&&active&&owner&&room&&m_arready;
    wire ar_take=m_arvalid&&m_arready;
    // A zero-latency slave holds its response until the accepted AR is counted.
    // Do not make RVALID/RREADY combinationally depend on ARREADY.
    // T78: the per-client response grant is a register loaded with the same
    // next-state value, so RVALID/RREADY see one AND instead of the reset
    // synchronizer, active and the outstanding compare. Async reset clears it
    // with the state, where the old term was also 0.
    (* MAX_FANOUT=32 *) reg a_owned=0,b_owned=0;
    wire response_owned=a_owned||b_owned;
    assign a_rvalid=a_owned&&m_rvalid;
    assign b_rvalid=b_owned&&m_rvalid;
    assign m_rready=(a_owned&&a_rready)||(b_owned&&b_rready);
    wire retire=m_rvalid&&m_rready&&m_rlast;
    reg active_n,owner_n,last_owner_n;reg [CW-1:0] outstanding_n;
    always @* begin
        active_n=active;owner_n=owner;last_owner_n=last_owner;outstanding_n=outstanding;
        if(!active)begin
            if(a_arvalid||b_arvalid)begin
                owner_n=(a_arvalid&&b_arvalid)?!last_owner:b_arvalid;
                active_n=1;
            end
        end else if(outstanding==0&&!selected_valid)begin
            active_n=0;last_owner_n=owner;
        end
        case({ar_take,retire})
            2'b10:outstanding_n=outstanding+1'b1;
            2'b01:outstanding_n=outstanding-1'b1;
            default:begin end
        endcase
    end
    always @(posedge ui_clk or negedge rst)begin
        if(!rst)begin active<=0;owner<=0;last_owner<=1;outstanding<=0;a_owned<=0;b_owned<=0;end
        else begin
            active<=active_n;owner<=owner_n;last_owner<=last_owner_n;outstanding<=outstanding_n;
            a_owned<=active_n&&!owner_n&&(outstanding_n!=0);
            b_owned<=active_n&&owner_n&&(outstanding_n!=0);
        end
    end
    // synthesis translate_off
    always @(posedge ui_clk)if(rst)begin
        if(retire&&outstanding==0&&!ar_take)$fatal(1,"Q9_AXI_OWNER_UNDERFLOW");
        if(outstanding>MAX_OUTSTANDING)$fatal(1,"Q9_AXI_OWNER_OVERFLOW");
        if(a_rvalid&&b_rvalid)$fatal(1,"Q9_AXI_OWNER_RESPONSE_FANOUT");
    end
    always @(negedge ui_clk)if(a_owned!==(rst&&active&&!owner&&outstanding!=0)||
        b_owned!==(rst&&active&&owner&&outstanding!=0))$fatal(1,"T78_OWNER_GRANT_MISMATCH");
    initial if(MAX_OUTSTANDING<1)$fatal(1,"Q9_AXI_OWNER_CONFIG");
    // synthesis translate_on
endmodule

// Full AXI read-channel elastic boundary used between a client owner mux and
// the external UI read arbiter.  The owner mux reserves a response owner when
// the request enters this boundary; therefore the queue must accept AR before
// the external arbiter is ready and hold every AR field until that handshake.
// The response queue applies the same rule to RID/RDATA/RRESP/RLAST.  Both
// queues have registered occupancy, so neither READY path reaches across the
// 512-bit data route or back into the owner decision logic.
module qwen35_axi_read_channel_slice (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [62:0] s_ar,
    input  wire        s_arvalid,
    output wire        s_arready,
    output wire [62:0] m_ar,
    output wire        m_arvalid,
    input  wire        m_arready,
    input  wire [518:0] m_r,
    input  wire        m_rvalid,
    output wire        m_rready,
    output wire [518:0] s_r,
    output wire        s_rvalid,
    input  wire        s_rready
);
    wire ui_reset_n;
    xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0))
        slice_reset(.src_arst(reset_n),.dest_clk(clk),.dest_arst(ui_reset_n));

    qwen7b_read_response_buffer #(.WIDTH(63)) ar_slice (
        .clk(clk),.reset_n(ui_reset_n),.valid_i(s_arvalid),.ready_o(s_arready),
        .data_i(s_ar),.valid_o(m_arvalid),.ready_i(m_arready),.data_o(m_ar));
    qwen7b_read_response_buffer #(.WIDTH(519)) r_slice (
        .clk(clk),.reset_n(ui_reset_n),.valid_i(m_rvalid),.ready_o(m_rready),
        .data_i(m_r),.valid_o(s_rvalid),.ready_i(s_rready),.data_o(s_r));
endmodule
