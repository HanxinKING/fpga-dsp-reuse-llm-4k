// 3B GENERATED CANDIDATE: not admitted for board use.
`timescale 1ns/1ps
// Contiguous lossless matrix stream reader, entirely in the DDR UI domain.
// Constant AXI ID gives ordered returns. Eight queued descriptors hide request
// latency; tile boundaries, not AXI burst boundaries, drive stream LAST.
module qwen_shared_axi_weight_reader #(
    parameter integer MAX_BEATS=64,OUTSTANDING=8
)(
    input logic clk,reset_n,input logic start_i,output wire start_ready_o,
    input logic [33:0] base_i,input logic [31:0] words_i,tile_words_i,
    output wire valid_o,input logic ready_i,output wire [511:0] data_o,output wire last_o,
    output wire busy_o,output logic done_o,output logic [3:0] status_o,
    output logic [31:0] cycles_o,requests_o,received_o,peak_outstanding_o,
    output wire [3:0] m_axi_arid,output logic [33:0] m_axi_araddr,
    output logic [7:0] m_axi_arlen,output wire [2:0] m_axi_arsize,
    output wire [1:0] m_axi_arburst,output wire m_axi_arlock,
    output wire [3:0] m_axi_arcache,output wire [2:0] m_axi_arprot,
    output wire [3:0] m_axi_arqos,output logic m_axi_arvalid,input logic m_axi_arready,
    input logic [3:0] m_axi_rid,input logic [511:0] m_axi_rdata,
    input logic [1:0] m_axi_rresp,input logic m_axi_rlast,m_axi_rvalid,output wire m_axi_rready
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    localparam integer PW=$clog2(OUTSTANDING);
    (* MAX_FANOUT=32 *) logic active=0;logic [33:0] address=0;
    logic [31:0] remaining=0,total=0,tile_words=0,tile_received=0;
    logic [31:0] tile_penultimate=0;logic tile_last=0;
    logic [PW:0] outstanding=0;
    logic [PW-1:0] wp=0,rp=0;
    // 8 x OUTSTANDING bits, read combinationally for the rlast check.  Without
    // an attribute Vivado inferred RAMD32; its WADR2 arc was 32 of the 100
    // worst hold paths in run q9_uram_timing_20260922_r3.  Registers are
    // cheaper than a primitive here and remove the arc.
    (* ram_style="registers" *) logic [7:0] lengths[0:OUTSTANDING-1];logic [7:0] burst_received=0;
    logic [6:0] chosen;
    logic prepared_valid=0;
    logic [6:0] prepared_beats;
    wire ar_accept=m_axi_arvalid&&m_axi_arready;
    wire r_accept=m_axi_rvalid&&m_axi_rready;
    wire retire=r_accept&&m_axi_rlast;
    // A separate length preparation stage splits page/min selection from
    // address/remaining arithmetic. Cursor advancement reserves the command
    // at publication; a stalled AR stays immutable and is never recounted.
    wire [PW+1:0] exposed_requests={1'b0,outstanding}+m_axi_arvalid;
    wire prepare_command=active&&!prepared_valid&&remaining!=0&&exposed_requests<OUTSTANDING;
    wire publish_command=active&&prepared_valid&&(!m_axi_arvalid||ar_accept);
    wire [40:0] requested_end={7'd0,base_i}+({9'd0,words_i}<<6);
    always_comb begin
        chosen=7'd64-{1'b0,address[11:6]};
        if(chosen>MAX_BEATS)chosen=MAX_BEATS;
        if(remaining<chosen)chosen=remaining[6:0];
    end
    assign start_ready_o=reset_n&&!active;
    assign busy_o=active;
    assign valid_o=reset_n&&active&&outstanding!=0&&m_axi_rvalid;
    assign m_axi_rready=reset_n&&active&&outstanding!=0&&ready_i;
    assign data_o=m_axi_rdata;
    assign last_o=tile_last;
    assign m_axi_arid=4'd5;assign m_axi_arsize=3'd6;assign m_axi_arburst=2'b01;
    assign m_axi_arlock=0;assign m_axi_arcache=4'b0011;assign m_axi_arprot=0;assign m_axi_arqos=0;
    always_ff @(posedge clk)begin
        if(q9_local_reset_active)begin
            active<=0;address<=0;remaining<=0;total<=0;tile_words<=0;tile_received<=0;
            tile_penultimate<=0;tile_last<=0;
            outstanding<=0;wp<=0;rp<=0;burst_received<=0;m_axi_arvalid<=0;m_axi_araddr<=0;m_axi_arlen<=0;
            done_o<=0;status_o<=0;cycles_o<=0;requests_o<=0;received_o<=0;peak_outstanding_o<=0;prepared_valid<=0;
        end else begin
            done_o<=0;if(active)cycles_o<=cycles_o+1;
            if(outstanding>peak_outstanding_o)peak_outstanding_o<=outstanding;
            if(start_i&&start_ready_o)begin
                status_o<=0;cycles_o<=0;requests_o<=0;received_o<=0;peak_outstanding_o<=0;
                address<=base_i;remaining<=words_i;total<=words_i;tile_words<=tile_words_i;tile_received<=0;
                tile_penultimate<=tile_words_i-32'd2;tile_last<=tile_words_i==1;
                outstanding<=0;wp<=0;rp<=0;burst_received<=0;m_axi_arvalid<=0;prepared_valid<=0;
                // No runtime modulo/divider in the descriptor admission path.
                // An incomplete final tile is flagged at stream completion.
                if(base_i[5:0]!=0||words_i==0||tile_words_i==0||tile_words_i>words_i||requested_end>41'h400000000)begin status_o[0]<=1;done_o<=1;end
                else active<=1;
            end
            if(prepare_command)begin prepared_valid<=1;prepared_beats<=chosen;end
            if(ar_accept)m_axi_arvalid<=0;
            if(publish_command)begin
                prepared_valid<=0;m_axi_arvalid<=1;
                m_axi_araddr<=address;m_axi_arlen<=8'(prepared_beats)-8'd1;
                address<=address+(34'(prepared_beats)<<6);
                remaining<=remaining-32'(prepared_beats);
            end
            if(ar_accept)begin
                requests_o<=requests_o+1;
                lengths[wp]<=m_axi_arlen;wp<=wp+1'b1;
            end
            if(active)case({ar_accept,retire})
                2'b10:outstanding<=outstanding+1'b1;
                2'b01:outstanding<=outstanding-1'b1;
                default:begin end
            endcase
            if(r_accept)begin
                received_o<=received_o+1;
                tile_received<=last_o?0:tile_received+1;
                tile_last<=last_o?(tile_words==1):(tile_received==tile_penultimate);
                if(m_axi_rresp!=0)status_o[1]<=1;
                if(m_axi_rid!=5)status_o[2]<=1;
                if(m_axi_rlast!=(burst_received==lengths[rp]))status_o[3]<=1;
                if(m_axi_rlast)begin burst_received<=0;rp<=rp+1'b1;end
                else burst_received<=burst_received+1;
                if(received_o==total-1)begin
                    if(!last_o)status_o[0]<=1;
                    active<=0;done_o<=1;
                end else if(retire && outstanding==1 && remaining==0 &&
                            !prepared_valid && !m_axi_arvalid)begin
                    // All published AXI descriptors have retired, but a slave
                    // returned fewer beats than requested. Preserve the RLAST
                    // error receipt and release the drained failed command.
                    // The legal full-length path above is unchanged.
                    status_o[0]<=1;active<=0;done_o<=1;
                end
            end
        end
    end
    initial if(MAX_BEATS<1||MAX_BEATS>64||OUTSTANDING<2||(OUTSTANDING&(OUTSTANDING-1))!=0)$fatal(1,"AXI_READER_CONFIG_FAIL");
endmodule
