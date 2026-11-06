`timescale 1ns/1ps
module tb_q9_ip;
reg  core_clk=0;
reg  ui_clk=0;
reg  core_aresetn=0;
reg [31:0] board_errors_i=0;
wire  busy_o;
wire  done_o;
reg [15:0] s_axi_ctrl_awaddr=0;
reg  s_axi_ctrl_awvalid=0;
wire  s_axi_ctrl_awready;
reg [31:0] s_axi_ctrl_wdata=0;
reg [3:0] s_axi_ctrl_wstrb=0;
reg  s_axi_ctrl_wvalid=0;
wire  s_axi_ctrl_wready;
wire [1:0] s_axi_ctrl_bresp;
wire  s_axi_ctrl_bvalid;
reg  s_axi_ctrl_bready=0;
reg [15:0] s_axi_ctrl_araddr=0;
reg  s_axi_ctrl_arvalid=0;
wire  s_axi_ctrl_arready;
wire [31:0] s_axi_ctrl_rdata;
wire [1:0] s_axi_ctrl_rresp;
wire  s_axi_ctrl_rvalid;
reg  s_axi_ctrl_rready=0;
wire [3:0] m_axi_weight_pl_arid;
wire [33:0] m_axi_weight_pl_araddr;
wire [7:0] m_axi_weight_pl_arlen;
wire [2:0] m_axi_weight_pl_arsize;
wire [1:0] m_axi_weight_pl_arburst;
wire  m_axi_weight_pl_arlock;
wire [3:0] m_axi_weight_pl_arcache;
wire [2:0] m_axi_weight_pl_arprot;
wire [3:0] m_axi_weight_pl_arqos;
wire  m_axi_weight_pl_arvalid;
reg  m_axi_weight_pl_arready=0;
reg [3:0] m_axi_weight_pl_rid=0;
reg [511:0] m_axi_weight_pl_rdata=0;
reg [1:0] m_axi_weight_pl_rresp=0;
reg  m_axi_weight_pl_rlast=0;
reg  m_axi_weight_pl_rvalid=0;
wire  m_axi_weight_pl_rready;
wire [3:0] m_axi_weight_ps_arid;
wire [33:0] m_axi_weight_ps_araddr;
wire [7:0] m_axi_weight_ps_arlen;
wire [2:0] m_axi_weight_ps_arsize;
wire [1:0] m_axi_weight_ps_arburst;
wire  m_axi_weight_ps_arlock;
wire [3:0] m_axi_weight_ps_arcache;
wire [2:0] m_axi_weight_ps_arprot;
wire [3:0] m_axi_weight_ps_arqos;
wire  m_axi_weight_ps_arvalid;
reg  m_axi_weight_ps_arready=0;
reg [3:0] m_axi_weight_ps_rid=0;
reg [511:0] m_axi_weight_ps_rdata=0;
reg [1:0] m_axi_weight_ps_rresp=0;
reg  m_axi_weight_ps_rlast=0;
reg  m_axi_weight_ps_rvalid=0;
wire  m_axi_weight_ps_rready;
wire [3:0] m_axi_state_awid;
wire [33:0] m_axi_state_awaddr;
wire [7:0] m_axi_state_awlen;
wire [2:0] m_axi_state_awsize;
wire [1:0] m_axi_state_awburst;
wire  m_axi_state_awvalid;
reg  m_axi_state_awready=0;
wire [511:0] m_axi_state_wdata;
wire [63:0] m_axi_state_wstrb;
wire  m_axi_state_wlast;
wire  m_axi_state_wvalid;
reg  m_axi_state_wready=0;
reg [3:0] m_axi_state_bid=0;
reg [1:0] m_axi_state_bresp=0;
reg  m_axi_state_bvalid=0;
wire  m_axi_state_bready;
wire [3:0] m_axi_state_arid;
wire [33:0] m_axi_state_araddr;
wire [7:0] m_axi_state_arlen;
wire [2:0] m_axi_state_arsize;
wire [1:0] m_axi_state_arburst;
wire  m_axi_state_arvalid;
reg  m_axi_state_arready=0;
reg [3:0] m_axi_state_rid=0;
reg [511:0] m_axi_state_rdata=0;
reg [1:0] m_axi_state_rresp=0;
reg  m_axi_state_rlast=0;
reg  m_axi_state_rvalid=0;
wire  m_axi_state_rready;
q9_accelerator_4k_ip dut(.core_clk(core_clk),.ui_clk(ui_clk),.core_aresetn(core_aresetn),.board_errors_i(board_errors_i),.busy_o(busy_o),.done_o(done_o),.s_axi_ctrl_awaddr(s_axi_ctrl_awaddr),.s_axi_ctrl_awvalid(s_axi_ctrl_awvalid),.s_axi_ctrl_awready(s_axi_ctrl_awready),.s_axi_ctrl_wdata(s_axi_ctrl_wdata),.s_axi_ctrl_wstrb(s_axi_ctrl_wstrb),.s_axi_ctrl_wvalid(s_axi_ctrl_wvalid),.s_axi_ctrl_wready(s_axi_ctrl_wready),.s_axi_ctrl_bresp(s_axi_ctrl_bresp),.s_axi_ctrl_bvalid(s_axi_ctrl_bvalid),.s_axi_ctrl_bready(s_axi_ctrl_bready),.s_axi_ctrl_araddr(s_axi_ctrl_araddr),.s_axi_ctrl_arvalid(s_axi_ctrl_arvalid),.s_axi_ctrl_arready(s_axi_ctrl_arready),.s_axi_ctrl_rdata(s_axi_ctrl_rdata),.s_axi_ctrl_rresp(s_axi_ctrl_rresp),.s_axi_ctrl_rvalid(s_axi_ctrl_rvalid),.s_axi_ctrl_rready(s_axi_ctrl_rready),.m_axi_weight_pl_arid(m_axi_weight_pl_arid),.m_axi_weight_pl_araddr(m_axi_weight_pl_araddr),.m_axi_weight_pl_arlen(m_axi_weight_pl_arlen),.m_axi_weight_pl_arsize(m_axi_weight_pl_arsize),.m_axi_weight_pl_arburst(m_axi_weight_pl_arburst),.m_axi_weight_pl_arlock(m_axi_weight_pl_arlock),.m_axi_weight_pl_arcache(m_axi_weight_pl_arcache),.m_axi_weight_pl_arprot(m_axi_weight_pl_arprot),.m_axi_weight_pl_arqos(m_axi_weight_pl_arqos),.m_axi_weight_pl_arvalid(m_axi_weight_pl_arvalid),.m_axi_weight_pl_arready(m_axi_weight_pl_arready),.m_axi_weight_pl_rid(m_axi_weight_pl_rid),.m_axi_weight_pl_rdata(m_axi_weight_pl_rdata),.m_axi_weight_pl_rresp(m_axi_weight_pl_rresp),.m_axi_weight_pl_rlast(m_axi_weight_pl_rlast),.m_axi_weight_pl_rvalid(m_axi_weight_pl_rvalid),.m_axi_weight_pl_rready(m_axi_weight_pl_rready),.m_axi_weight_ps_arid(m_axi_weight_ps_arid),.m_axi_weight_ps_araddr(m_axi_weight_ps_araddr),.m_axi_weight_ps_arlen(m_axi_weight_ps_arlen),.m_axi_weight_ps_arsize(m_axi_weight_ps_arsize),.m_axi_weight_ps_arburst(m_axi_weight_ps_arburst),.m_axi_weight_ps_arlock(m_axi_weight_ps_arlock),.m_axi_weight_ps_arcache(m_axi_weight_ps_arcache),.m_axi_weight_ps_arprot(m_axi_weight_ps_arprot),.m_axi_weight_ps_arqos(m_axi_weight_ps_arqos),.m_axi_weight_ps_arvalid(m_axi_weight_ps_arvalid),.m_axi_weight_ps_arready(m_axi_weight_ps_arready),.m_axi_weight_ps_rid(m_axi_weight_ps_rid),.m_axi_weight_ps_rdata(m_axi_weight_ps_rdata),.m_axi_weight_ps_rresp(m_axi_weight_ps_rresp),.m_axi_weight_ps_rlast(m_axi_weight_ps_rlast),.m_axi_weight_ps_rvalid(m_axi_weight_ps_rvalid),.m_axi_weight_ps_rready(m_axi_weight_ps_rready),.m_axi_state_awid(m_axi_state_awid),.m_axi_state_awaddr(m_axi_state_awaddr),.m_axi_state_awlen(m_axi_state_awlen),.m_axi_state_awsize(m_axi_state_awsize),.m_axi_state_awburst(m_axi_state_awburst),.m_axi_state_awvalid(m_axi_state_awvalid),.m_axi_state_awready(m_axi_state_awready),.m_axi_state_wdata(m_axi_state_wdata),.m_axi_state_wstrb(m_axi_state_wstrb),.m_axi_state_wlast(m_axi_state_wlast),.m_axi_state_wvalid(m_axi_state_wvalid),.m_axi_state_wready(m_axi_state_wready),.m_axi_state_bid(m_axi_state_bid),.m_axi_state_bresp(m_axi_state_bresp),.m_axi_state_bvalid(m_axi_state_bvalid),.m_axi_state_bready(m_axi_state_bready),.m_axi_state_arid(m_axi_state_arid),.m_axi_state_araddr(m_axi_state_araddr),.m_axi_state_arlen(m_axi_state_arlen),.m_axi_state_arsize(m_axi_state_arsize),.m_axi_state_arburst(m_axi_state_arburst),.m_axi_state_arvalid(m_axi_state_arvalid),.m_axi_state_arready(m_axi_state_arready),.m_axi_state_rid(m_axi_state_rid),.m_axi_state_rdata(m_axi_state_rdata),.m_axi_state_rresp(m_axi_state_rresp),.m_axi_state_rlast(m_axi_state_rlast),.m_axi_state_rvalid(m_axi_state_rvalid),.m_axi_state_rready(m_axi_state_rready));

always #2 core_clk=~core_clk;
always #1.666 ui_clk=~ui_clk;
integer checks=0,fd;
task read_word(input[15:0]addr,input[31:0]expected,input[1:0]response);
integer t;begin
 @(negedge core_clk);s_axi_ctrl_araddr=addr;s_axi_ctrl_arvalid=1;
 do @(posedge core_clk);while(!s_axi_ctrl_arready);
 @(negedge core_clk);s_axi_ctrl_arvalid=0;t=0;
 while(!s_axi_ctrl_rvalid)begin @(negedge core_clk);t++;if(t>80)$fatal(1,"AXI_READ_TIMEOUT");end
 repeat(4)begin
  if(!s_axi_ctrl_rvalid||s_axi_ctrl_rdata!==expected||s_axi_ctrl_rresp!==response)$fatal(1,"AXI_READ_MISMATCH addr=%h got=%h",addr,s_axi_ctrl_rdata);
  @(negedge core_clk);
 end
 s_axi_ctrl_rready=1;@(negedge core_clk);s_axi_ctrl_rready=0;checks++;
end endtask
task rejected_write;
integer t;begin
 @(negedge core_clk);s_axi_ctrl_awaddr=16'h204;s_axi_ctrl_awvalid=1;
 do @(posedge core_clk);while(!s_axi_ctrl_awready);
 @(negedge core_clk);s_axi_ctrl_awvalid=0;
 repeat(3)@(negedge core_clk);
 s_axi_ctrl_wdata=4097;s_axi_ctrl_wstrb=15;s_axi_ctrl_wvalid=1;
 do @(posedge core_clk);while(!s_axi_ctrl_wready);
 @(negedge core_clk);s_axi_ctrl_wvalid=0;t=0;
 while(!s_axi_ctrl_bvalid)begin @(negedge core_clk);t++;if(t>80)$fatal(1,"AXI_WRITE_TIMEOUT");end
 repeat(4)begin if(s_axi_ctrl_bresp!==2||!s_axi_ctrl_bvalid)$fatal(1,"AXI_REJECT_OR_STALL");@(negedge core_clk);end
 s_axi_ctrl_bready=1;@(negedge core_clk);s_axi_ctrl_bready=0;checks++;
end endtask
initial begin
 repeat(32)@(negedge core_clk);core_aresetn=1;repeat(64)@(negedge core_clk);
 read_word(16'h1e0,32'h5139344b,0);
 read_word(16'h1e4,4096,0);
 read_word(16'h1e8,32'h00200404,0);
 read_word(16'h210,0,2);
 read_word(16'h1e1,0,2);
 rejected_write();read_word(16'h1e4,4096,0);
 fd=$fopen("Q9_4K_IP_AXI_SMOKE_PASS.txt","w");$fdisplay(fd,"Q9_4K_IP_AXI_SMOKE_PASS checks=%0d",checks);$fclose(fd);
 $display("Q9_4K_IP_AXI_SMOKE_PASS checks=%0d",checks);$finish;
end
initial begin #20000;$fatal(1,"IP_SMOKE_TIMEOUT");end

endmodule
