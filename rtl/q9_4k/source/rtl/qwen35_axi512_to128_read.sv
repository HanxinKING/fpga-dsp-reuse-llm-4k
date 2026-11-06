`timescale 1ns/1ps
// Read-only AXI adapter for one native PS HP port. A 64-byte source beat is
// four ordered 16-byte HP beats. Commands remain within their original 4KiB
// page, so length expansion never creates an illegal AXI boundary crossing.
// The two response slots permit filling the next beat while retiring one.
module qwen35_axi512_to128_read #(
    parameter integer INPUT_R_SLICE=0
)(
    input wire clk,reset_n,
    input wire [39:0] s_araddr,input wire [7:0] s_arlen,
    input wire s_arvalid,output wire s_arready,
    output wire [511:0] s_rdata,output wire [1:0] s_rresp,
    output wire s_rlast,s_rvalid,input wire s_rready,
    output wire [39:0] m_araddr,output wire [7:0] m_arlen,
    output wire m_arvalid,input wire m_arready,
    input wire [127:0] m_rdata,input wire [1:0] m_rresp,
    input wire m_rlast,m_rvalid,output wire m_rready,
    output reg protocol_error=0
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    reg [511:0] partial;
    reg [1:0] quarter=0, response=0;
    reg [514:0] slots[0:1];
    reg wp=0,rp=0;
    reg [1:0] count=0;
    // Optional native-width capture boundary. Its READY depends only on the
    // registered two-slot occupancy; it has no downstream READY look-through.
    // The existing assembly/publication state consumes this ordered stream.
    wire [127:0] capture_rdata;
    wire [1:0] capture_rresp;
    wire capture_rlast,capture_rvalid;
    wire capture_rready=reset_n&&(count<2);
    generate if(INPUT_R_SLICE)begin:g_input_rslice
        qwen7b_read_response_buffer #(.WIDTH(131)) r_capture(
            .clk(clk),.reset_n(reset_n),.valid_i(m_rvalid),.ready_o(m_rready),
            .data_i({m_rlast,m_rresp,m_rdata}),.valid_o(capture_rvalid),
            .ready_i(capture_rready),.data_o({capture_rlast,capture_rresp,capture_rdata}));
    end else begin:g_input_bypass
        assign {capture_rlast,capture_rresp,capture_rdata}={m_rlast,m_rresp,m_rdata};
        assign capture_rvalid=m_rvalid;
        assign m_rready=capture_rready;
    end endgenerate
    wire pop=s_rvalid&&s_rready;
    wire accept=capture_rvalid&&capture_rready;
    wire push=accept&&quarter==3;
    assign m_araddr=s_araddr;
    assign m_arlen={s_arlen[5:0],2'b11};
    assign m_arvalid=reset_n&&s_arvalid;
    assign s_arready=reset_n&&m_arready;
    assign s_rvalid=reset_n&&(count!=0);
    assign {s_rlast,s_rresp,s_rdata}=slots[rp];
    always @(posedge clk) begin
        // Only quarter/count/pointers publish a completed source beat. While
        // a slot is free, its payload and the unaccepted current quarter may
        // capture speculatively; reset and RVALID do not drive wide RAM WEs.
        if(count<2)begin
            partial[quarter*128+:128]<=capture_rdata;
            slots[wp]<={capture_rlast,response|capture_rresp,capture_rdata,partial[383:0]};
        end
        if(q9_local_reset_active) begin quarter<=0;response<=0;wp<=0;rp<=0;count<=0;protocol_error<=0;end
        else begin
            if(s_arvalid&&s_arready&&(s_arlen>63||s_araddr[5:0]!=0||
                ({1'b0,s_araddr[11:0]}+(({5'd0,s_arlen}+13'd1)<<6))>4096)) protocol_error<=1;
            if(accept) begin
                response<=response|capture_rresp;
                quarter<=quarter+1'b1;
                if(capture_rlast&&quarter!=3) protocol_error<=1;
                if(quarter==3) begin
                    response<=0;wp<=~wp;
                end
            end
            if(pop) rp<=~rp;
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
        end
    end
endmodule
