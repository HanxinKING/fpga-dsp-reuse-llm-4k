`timescale 1ns/1ps
// Four Q heads x P32 x signed24, losslessly padded to 32 bits in DDR.
// One 512-byte page, eight AXI beats. The existing score RAM remains the
// single page window. No arithmetic or extra score URAM is introduced.
module qwen35_score_page_dma #(parameter integer EXTERNAL_READER=0)(
 input wire clk,reset_n,start_i,load_i,
 input wire [33:0] address_i,input wire [1:0] head_i,input wire [5:0] count_i,
 output wire ready_o,busy_o,output reg done_o,output reg [7:0] status_o,
 output wire sc_re_o,sc_we_o,output wire [8:0] sc_addr_o,
 output wire [23:0] sc_wdata_o,input wire [23:0] sc_rdata_i,
 output wire [100:0] raw_ext_cmd_o,input wire [692:0] raw_ext_rsp_i=693'd0,
 output wire [3:0] awid,output wire [33:0] awaddr,output wire [7:0] awlen,
 output wire [2:0] awsize,output wire [1:0] awburst,output wire awvalid,input wire awready,
 output wire [511:0] wdata,output wire [63:0] wstrb,output wire wlast,wvalid,input wire wready,
 input wire [3:0] bid,input wire [1:0] bresp,input wire bvalid,output wire bready,
 output wire [3:0] arid,output wire [33:0] araddr,output wire [7:0] arlen,
 output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
 input wire [3:0] rid,input wire [511:0] rdata,input wire [1:0] rresp,
 input wire rlast,rvalid,output wire rready
);
 localparam IDLE=0,AW=1,FETCH=2,CAPTURE=3,WRITE=4,B=5,
            RSTART=6,RUN=7,RFINISH=8,DONE=9;
 reg [3:0] state=IDLE;reg [33:0] address;
 reg [1:0] head;reg [5:0] count;reg [2:0] beat;
 reg [3:0] piece;reg [7:0] emitted;
 reg [511:0] holding;reg have_word,read_seen;
 wire reader_ready,reader_valid,reader_last,reader_busy,reader_done;
 wire [511:0] reader_data;wire [3:0] reader_status;wire [31:0] received;
 wire read_take=reader_valid&&state==RUN&&!have_word;
 assign ready_o=state==IDLE;assign busy_o=state!=IDLE;
 assign sc_re_o=state==FETCH;
 assign sc_we_o=state==RUN&&have_word;
 assign sc_addr_o={head,beat,piece};
 assign sc_wdata_o=holding[piece*32+:24];
 assign awid=4'd7;assign awaddr=address;assign awlen=7;
 assign awsize=6;assign awburst=1;assign awvalid=state==AW;
 assign wdata=holding;assign wstrb=64'hffffffffffffffff;
 assign wlast=beat==7;assign wvalid=state==WRITE;assign bready=state==B;
 qwen35_raw_reader_endpoint #(.MAX_BEATS(4),.OUTSTANDING(4),.EXTERNAL_READER(EXTERNAL_READER)) reader(
  .clk,.reset_n,.ext_cmd_o(raw_ext_cmd_o),.ext_rsp_i(raw_ext_rsp_i),
  .start_i(state==RSTART),.start_ready_o(reader_ready),.base_i(address),
  .words_i(32'd8),.tile_words_i(32'd8),.valid_o(reader_valid),
  .ready_i(state==RUN&&!have_word),.data_o(reader_data),.last_o(reader_last),
  .busy_o(reader_busy),.done_o(reader_done),.status_o(reader_status),
  .cycles_o(),.requests_o(),.received_o(received),.peak_outstanding_o(),
  .m_axi_arid(arid),.m_axi_araddr(araddr),.m_axi_arlen(arlen),.m_axi_arsize(arsize),
  .m_axi_arburst(arburst),.m_axi_arlock(),.m_axi_arcache(),.m_axi_arprot(),.m_axi_arqos(),
  .m_axi_arvalid(arvalid),.m_axi_arready(arready),.m_axi_rid(rid),.m_axi_rdata(rdata),
  .m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_rvalid(rvalid),.m_axi_rready(rready));
 always @(posedge clk)begin
  if(!reset_n)begin
   state<=IDLE;done_o<=0;status_o<=0;beat<=0;piece<=0;address<=0;head<=0;count<=0;
   have_word<=0;read_seen<=0;emitted<=0;
  end else begin
   done_o<=0;
   if(reader_done&&(state==RUN||state==RFINISH))begin
    read_seen<=1;status_o[3:0]<=status_o[3:0]|reader_status;
    if(received!=8)status_o[4]<=1;
   end
   case(state)
    IDLE:if(start_i)begin
     address<=address_i;head<=head_i;count<=count_i;beat<=0;piece<=0;
     status_o<=0;have_word<=0;read_seen<=0;emitted<=0;
     if(address_i[8:0]!=0||count_i==0||count_i>32)begin status_o<=8'h80;state<=DONE;end
     else state<=load_i?RSTART:AW;
    end
    AW:if(awready)state<=FETCH;
    FETCH:state<=CAPTURE;
    CAPTURE:begin
     // Undefined tail entries never become observable, and deterministic zero
     // padding prevents uninitialised SRAM contents entering a DDR trace.
     holding[piece*32+:32]<=({beat[0],piece}<count)?{8'd0,sc_rdata_i}:32'd0;
     if(piece==15)state<=WRITE;else begin piece<=piece+1'b1;state<=FETCH;end
    end
    WRITE:if(wready)begin
     piece<=0;if(beat==7)state<=B;else begin beat<=beat+1'b1;state<=FETCH;end
    end
    B:if(bvalid)begin
     if(bresp!=0)status_o[1]<=1;if(bid!=7)status_o[2]<=1;state<=DONE;
    end
    RSTART:if(reader_ready)state<=RUN;
    RUN:begin
     if(read_take)begin
      holding<=reader_data;have_word<=1;piece<=0;
      if(reader_last!=(beat==7))status_o[5]<=1;
     end
     if(have_word)begin
      emitted<=emitted+1'b1;
      if(piece==15)begin
       have_word<=0;piece<=0;
       if(beat==7)state<=RFINISH;else beat<=beat+1'b1;
      end else piece<=piece+1'b1;
     end
     // An early failed/short descriptor cannot be mistaken for a complete hit.
     if((read_seen||reader_done)&&!reader_busy&&!have_word&&!reader_valid&&received!=8)begin
      status_o[4]<=1;state<=DONE;
     end
    end
    RFINISH:if((read_seen||reader_done)&&!reader_busy)begin
     if(emitted!=128||received!=8)status_o[4]<=1;state<=DONE;
    end
    DONE:begin done_o<=1;state<=IDLE;end
    default:begin status_o<=8'h80;state<=DONE;end
   endcase
  end
 end
endmodule
