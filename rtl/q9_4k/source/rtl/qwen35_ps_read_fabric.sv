`timescale 1ns/1ps
// Dedicated PS DDR read fabric. Four 128-bit HP ports expose ONE memory
// controller. Requests are striped by 4KiB page; responses are restored to
// their request order at an independent 512-bit PS output (not merged with PL).
// Constant source ID=5 is the shared-reader contract. No single-DDR mode.
module qwen35_ps_read_fabric #(
    parameter integer ORDER_AW=4,RESPONSE_AW=6,STRIPE_SHIFT=12,PIPELINED_REQUESTS=0,
    parameter integer ENABLE_HIGH_DDR=1,
    parameter [34:0] PS_LOGICAL_BYTES=35'h100000000
)(
    input wire clk,reset_n,
    input wire [3:0] s_arid,input wire [33:0] s_araddr,input wire [7:0] s_arlen,
    input wire s_arvalid,output wire s_arready,
    output wire [3:0] s_rid,output wire [511:0] s_rdata,output wire [1:0] s_rresp,
    output wire s_rlast,s_rvalid,input wire s_rready,
    output wire [159:0] m_araddr,output wire [31:0] m_arlen,
    output wire [3:0] m_arvalid,input wire [3:0] m_arready,
    input wire [511:0] m_rdata,input wire [7:0] m_rresp,
    input wire [3:0] m_rlast,m_rvalid,output wire [3:0] m_rready,
    output reg [7:0] errors=0,output reg [31:0] accepted_requests=0,retired_requests=0,
    output reg [31:0] concurrent_response_cycles=0,output wire [127:0] port_responses
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    localparam DEPTH=1<<ORDER_AW;
    reg req_valid=0;reg [1:0] req_port=0;reg [39:0] req_address=0;reg [7:0] req_length=0;
    reg [1:0] order_port[0:DEPTH-1];reg [7:0] order_length[0:DEPTH-1];
    reg [ORDER_AW-1:0] wp=0,rp=0;reg [ORDER_AW:0] count=0;reg [7:0] beat=0;
    wire [3:0] ar_ready,bv,br,protocol_error;wire [2059:0] buffered;
    wire [1:0] head=count!=0?order_port[rp]:2'b00;
    wire [514:0] selected=buffered[head*515+:515];
    wire issued=req_valid&&ar_ready[req_port];
    wire take=s_rvalid&&s_rready;wire retire=take&&beat==order_length[rp];
    // Keep existing low logical offsets unchanged. DDR above the first2GiB
    // is physically mapped at32GiB by the MPSoC, not at CPU0x80000000.
    // The native HP side is40bit; all translations occur before AR capture.
    wire [39:0] physical_address=(ENABLE_HIGH_DDR&&s_araddr>=34'h080000000)?
        (40'h0800000000+({6'd0,s_araddr}-40'h0080000000)):{6'd0,s_araddr};
    wire [34:0] admitted_bytes=ENABLE_HIGH_DDR?PS_LOGICAL_BYTES:35'h080000000;
    wire legal=s_arid==5&&s_araddr[5:0]==0&&s_arlen<=63&&
        ({1'b0,s_araddr[11:0]}+(({5'b0,s_arlen}+13'd1)<<6))<=4096&&
        ({1'b0,s_araddr}+(({27'd0,s_arlen}+35'd1)<<6))<=admitted_bytes;
    // Reserve one order entry for an already buffered request. A departing
    // request may be replaced in the SAME cycle, without overrunning the order
    // FIFO when its old request fills the last free entry. No data format or
    // address mapping changes: all four HP ports access the same PS DDR.
    wire order_credit=(count<(req_valid?DEPTH-1:DEPTH))||retire;
    assign s_arready=reset_n&&legal&&(PIPELINED_REQUESTS?
        ((!req_valid||issued)&&order_credit):(!req_valid&&count<DEPTH));
    assign s_rvalid=reset_n&&count!=0&&bv[head];assign s_rid=5;
    assign {s_rlast,s_rresp,s_rdata}=selected;
    for(genvar port=0;port<4;port=port+1)begin:g_port
        (* DONT_TOUCH="TRUE" *) reg[39:0]request_address66=0;
        always @(posedge clk)begin
            if(q9_local_reset_active)request_address66<=0;
            // T76: unpipelined, the copy is read only while req_valid and
            // req_valid rises only on the s_arvalid&&s_arready edge, so it may
            // load on every !req_valid edge: the legal range carry chain and
            // the order credit leave its CE. The admission-edge value is the
            // same physical_address as req_address.
            else if(PIPELINED_REQUESTS?(s_arvalid&&s_arready):!req_valid)request_address66<=physical_address;
        end
        // Same admission edge and address, one physical source per PS port.
`ifndef SYNTHESIS
        always @(posedge clk)if(reset_n&&req_valid&&request_address66!==req_address)
            $fatal(1,"PS66_SAME_EDGE_REQUEST_ADDRESS");
`endif
        wire [511:0] wide_data;wire [1:0] wide_resp;wire wide_last,wide_valid,wide_ready;
        reg [31:0] responses=0;assign port_responses[port*32+:32]=responses;
        assign br[port]=reset_n&&count!=0&&head==port&&s_rready;
        qwen35_axi512_to128_read #(.INPUT_R_SLICE(1)) narrow(
            .clk(clk),.reset_n(reset_n),.s_araddr(request_address66),.s_arlen(req_length),
            .s_arvalid(reset_n&&req_valid&&req_port==port),.s_arready(ar_ready[port]),
            .s_rdata(wide_data),.s_rresp(wide_resp),.s_rlast(wide_last),.s_rvalid(wide_valid),.s_rready(wide_ready),
            .m_araddr(m_araddr[port*40+:40]),.m_arlen(m_arlen[port*8+:8]),
            .m_arvalid(m_arvalid[port]),.m_arready(m_arready[port]),
            .m_rdata(m_rdata[port*128+:128]),.m_rresp(m_rresp[port*2+:2]),
            .m_rlast(m_rlast[port]),.m_rvalid(m_rvalid[port]),.m_rready(m_rready[port]),
            .protocol_error(protocol_error[port]));
        qwen_sync_block_fifo #(.WIDTH(515),.ADDR_W(RESPONSE_AW)) response(
            .clk(clk),.reset_n(reset_n),.in_valid(wide_valid),.in_ready(wide_ready),
            .in_data({wide_last,wide_resp,wide_data}),.out_valid(bv[port]),.out_ready(br[port]),
            .out_data(buffered[port*515+:515]),.occupancy());
        always @(posedge clk)begin
            if(q9_local_reset_active)responses<=0;
            else if(m_rvalid[port]&&m_rready[port])responses<=responses+1;
        end
    end
    wire [3:0] response_accept=m_rvalid&m_rready;
    always @(posedge clk)begin
        if(q9_local_reset_active)begin
            req_valid<=0;req_port<=0;req_address<=0;req_length<=0;wp<=0;rp<=0;count<=0;beat<=0;
            errors<=0;accepted_requests<=0;retired_requests<=0;concurrent_response_cycles<=0;
        end else begin
            if(s_arvalid&&!legal)errors[0]<=1;
            if(issued)begin
                req_valid<=0;order_port[wp]<=req_port;order_length[wp]<=req_length;wp<=wp+1'b1;
            end
            if(s_arvalid&&s_arready)begin
                req_valid<=1;req_port<=s_araddr[STRIPE_SHIFT+:2];req_address<=physical_address;req_length<=s_arlen;
                accepted_requests<=accepted_requests+1;
            end
            if(take)begin
                if(selected[514]!=(beat==order_length[rp]))errors[1]<=1;
                if(selected[513:512]!=0)errors[2]<=1;
                if(retire)begin rp<=rp+1'b1;beat<=0;retired_requests<=retired_requests+1;end
                else beat<=beat+1'b1;
            end
            case({issued,retire})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
            if(|protocol_error)errors[3]<=1;
            if((response_accept&(response_accept-4'd1))!=0)concurrent_response_cycles<=concurrent_response_cycles+1;
        end
    end
    initial if(ORDER_AW<2||RESPONSE_AW<2||STRIPE_SHIFT<6||STRIPE_SHIFT>12)$fatal(1,"Q7_PS_FABRIC_CONFIG");
    initial if(PS_LOGICAL_BYTES<35'h080000000||PS_LOGICAL_BYTES>35'h400000000)
        $fatal(1,"Q9_PS_LOGICAL_CAPACITY_CONFIG");
endmodule
