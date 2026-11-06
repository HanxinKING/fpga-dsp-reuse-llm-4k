`timescale 1ns/1ps
// Q7 shared raw reader with local command arbitration. Three clients retain
// publication ledgers; ownership remains fixed through reader/FIFO drain.
module qwen35_raw_reader_service(
 input wire clk,reset_n,input wire[302:0]cmd_i,output wire[2078:0]rsp_o,output wire[1:0]owner_o,
 output wire[3:0]m_arid,output wire[33:0]m_araddr,output wire[7:0]m_arlen,
 output wire[2:0]m_arsize,output wire[1:0]m_arburst,output wire m_arvalid,input wire m_arready,
 input wire[3:0]m_rid,input wire[511:0]m_rdata,input wire[1:0]m_rresp,input wire m_rlast,m_rvalid,output wire m_rready
);
 reg[1:0]owner=0;wire rr,rv,rl,rb,done;wire[3:0]status;wire[31:0]cycles,requests,received,peak;wire[511:0]data;
 wire[1:0]choice=cmd_i[99]?2'd0:cmd_i[2*101+99]?2'd2:2'd1;
 wire[100:0]command=cmd_i[choice*101+:101],running=cmd_i[owner*101+:101];
 wire launch=reset_n&&rr&&command[99];assign owner_o=owner;
 always @(posedge clk)if(!reset_n)owner<=0;else if(launch)owner<=choice;
 qwen_shared_axi_weight_reader #(.MAX_BEATS(16),.OUTSTANDING(4)) reader(
  .clk,.reset_n,.start_i(launch),.start_ready_o(rr),.base_i(command[97:64]),.words_i(command[63:32]),.tile_words_i(command[31:0]),
  .valid_o(rv),.ready_i(running[98]),.data_o(data),.last_o(rl),.busy_o(rb),.done_o(done),.status_o(status),
  .cycles_o(cycles),.requests_o(requests),.received_o(received),.peak_outstanding_o(peak),
  .m_axi_arid(m_arid),.m_axi_araddr(m_araddr),.m_axi_arlen(m_arlen),.m_axi_arsize(m_arsize),.m_axi_arburst(m_arburst),
  .m_axi_arlock(),.m_axi_arcache(),.m_axi_arprot(),.m_axi_arqos(),.m_axi_arvalid(m_arvalid),.m_axi_arready(m_arready),
  .m_axi_rid(m_rid),.m_axi_rdata(m_rdata),.m_axi_rresp(m_rresp),.m_axi_rlast(running[100]),.m_axi_rvalid(m_rvalid),.m_axi_rready(m_rready));
 for(genvar i=0;i<3;i++)begin:response
  wire mine=owner==i;
  assign rsp_o[i*693+:693]={m_arvalid&&mine,m_araddr,m_arlen,m_rready&&mine,rr&&choice==i,rv&&mine,rl,rb&&mine,done&&mine,
    status,cycles,requests,received,peak,data};
 end
endmodule