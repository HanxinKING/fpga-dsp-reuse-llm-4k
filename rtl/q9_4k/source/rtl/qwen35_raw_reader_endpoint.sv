`timescale 1ns/1ps
module qwen35_raw_reader_endpoint #(
    parameter integer MAX_BEATS=16,OUTSTANDING=4,EXTERNAL_READER=0
)(
    output wire [100:0] ext_cmd_o,input wire [692:0] ext_rsp_i=693'd0,
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
    // Command: corrected RLAST, START, sink READY, base34, words32, tile32.
    // Response: ARVALID/address34/len8/RREADY, ready/valid/last/busy/done,
    // status4, cycles/requests/received/peak (32 each), data512.
    assign ext_cmd_o={m_axi_rlast,start_i,ready_i,base_i,words_i,tile_words_i};
    generate if(EXTERNAL_READER)begin:g_external
        wire xd;wire[3:0]xs;wire[31:0]xc,xq,xn,xp;
        reg saved=0;reg[3:0]ss;reg[31:0]sc,sq,sn,sp;
        assign {m_axi_arvalid,m_axi_araddr,m_axi_arlen,m_axi_rready,
            start_ready_o,valid_o,last_o,busy_o,xd,xs,xc,xq,xn,xp,data_o}=ext_rsp_i;
        // The shared reader can serve another owner while this wrapper is
        // still retiring its own final unpack/commit. Hold descriptor receipts
        // until the next accepted command; never expose another owner's count.
        always @(posedge clk)begin
          if(!reset_n)saved<=0;
          else if(start_i&&start_ready_o)saved<=0;
          else if(xd)begin saved<=1;ss<=xs;sc<=xc;sq<=xq;sn<=xn;sp<=xp;end
        end
        assign done_o=xd;
        assign status_o=saved&&!xd?ss:xs;assign cycles_o=saved&&!xd?sc:xc;
        assign requests_o=saved&&!xd?sq:xq;assign received_o=saved&&!xd?sn:xn;
        assign peak_outstanding_o=saved&&!xd?sp:xp;
        assign m_axi_arid=5;assign m_axi_arsize=6;assign m_axi_arburst=1;
        assign m_axi_arlock=0;assign m_axi_arcache=3;assign m_axi_arprot=0;assign m_axi_arqos=0;
    end else begin:g_local
        qwen_shared_axi_weight_reader #(.MAX_BEATS(MAX_BEATS),.OUTSTANDING(OUTSTANDING)) reader(
            .clk(clk),
            .reset_n(reset_n),
            .start_i(start_i),
            .start_ready_o(start_ready_o),
            .base_i(base_i),
            .words_i(words_i),
            .tile_words_i(tile_words_i),
            .valid_o(valid_o),
            .ready_i(ready_i),
            .data_o(data_o),
            .last_o(last_o),
            .busy_o(busy_o),
            .done_o(done_o),
            .status_o(status_o),
            .cycles_o(cycles_o),
            .requests_o(requests_o),
            .received_o(received_o),
            .peak_outstanding_o(peak_outstanding_o),
            .m_axi_arid(m_axi_arid),
            .m_axi_araddr(m_axi_araddr),
            .m_axi_arlen(m_axi_arlen),
            .m_axi_arsize(m_axi_arsize),
            .m_axi_arburst(m_axi_arburst),
            .m_axi_arlock(m_axi_arlock),
            .m_axi_arcache(m_axi_arcache),
            .m_axi_arprot(m_axi_arprot),
            .m_axi_arqos(m_axi_arqos),
            .m_axi_arvalid(m_axi_arvalid),
            .m_axi_arready(m_axi_arready),
            .m_axi_rid(m_axi_rid),
            .m_axi_rdata(m_axi_rdata),
            .m_axi_rresp(m_axi_rresp),
            .m_axi_rlast(m_axi_rlast),
            .m_axi_rvalid(m_axi_rvalid),
            .m_axi_rready(m_axi_rready));
    end endgenerate
endmodule
