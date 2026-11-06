`timescale 1ns/1ps
// Passive UI-domain AXI observer. Nothing here drives READY, VALID or owner.
// One accepted token defines a window. Start/done toggles cross together with
// three-stage synchronizers; events are counted on the observed UI edges.
// Only the completed immutable bank crosses to the core via XPM handshake.
module qwen35_bandwidth65 #(parameter integer UI_HZ=300120048,COUNTER_W=32)(
 input wire ui_clk,ui_reset_n,core_clk,core_reset_n,start_i,done_i,
 input wire[3:0]ps_valid_i,ps_ready_i,input wire[7:0]ps_resp_i,
 input wire pl_weight_valid_i,pl_weight_ready_i,
 input wire pl_rvalid_i,pl_rready_i,input wire[1:0]pl_rresp_i,
 input wire pl_wvalid_i,pl_wready_i,input wire[63:0]pl_wstrb_i,
 input wire pl_arvalid_i,pl_arready_i,input wire[2:0]pl_arsize_i,
 input wire[4:0]word_i,output reg[31:0]data_o
);
 reg start_toggle=0,done_toggle=0;
 reg[31:0]core_generation=0;
 reg core_running=0;
 always @(posedge core_clk)begin
  if(!core_reset_n)begin start_toggle<=0;done_toggle<=0;core_generation<=0;core_running<=0;end
  else begin
   if(start_i)begin start_toggle<=!start_toggle;core_generation<=core_generation+1'b1;core_running<=1;end
   if(done_i)begin done_toggle<=!done_toggle;core_running<=0;end
  end
 end
 wire start_ui,done_ui,core_ready_ui;
 xpm_cdc_single #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.SRC_INPUT_REG(0)) start_cdc(
  .src_clk(core_clk),.src_in(start_toggle),.dest_clk(ui_clk),.dest_out(start_ui));
 xpm_cdc_single #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.SRC_INPUT_REG(0)) done_cdc(
  .src_clk(core_clk),.src_in(done_toggle),.dest_clk(ui_clk),.dest_out(done_ui));
 xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) reset_cdc(
  .src_arst(core_reset_n),.dest_clk(ui_clk),.dest_arst(core_ready_ui));
 reg start_seen=0,done_seen=0,running=0,pending=0,send=0;
 reg[31:0]generation=0,seen_generation=0;
 reg[15:0]overflow=0;
 reg dropped=0;
 reg[COUNTER_W-1:0]count[16];
 wire[3:0]pf=ps_valid_i&ps_ready_i;
 wire rf=pl_rvalid_i&&pl_rready_i,wf=pl_wvalid_i&&pl_wready_i;
 wire ps_error=(pf[0]&&ps_resp_i[1:0]!=0)||(pf[1]&&ps_resp_i[3:2]!=0)||
               (pf[2]&&ps_resp_i[5:4]!=0)||(pf[3]&&ps_resp_i[7:6]!=0);
 wire[15:0]events={pl_arvalid_i&&pl_arready_i&&pl_arsize_i!=6,1'b0,
  ps_error||(rf&&pl_rresp_i!=0),rf||wf,|pf,
  pl_wvalid_i&&!pl_wready_i,pl_rvalid_i&&!pl_rready_i,|(ps_valid_i&~ps_ready_i),
  wf,rf,pl_weight_valid_i&&pl_weight_ready_i,pf,1'b1};
 // Small balanced byte-popcount; only the diagnostic increment sees WSTRB.
 wire[6:0]write_bytes;
 wire[3:0]bytes8[8];wire[4:0]bytes16[4];wire[5:0]bytes32[2];
 for(genvar g=0;g<8;g++)begin:g_bytes8
  assign bytes8[g]={3'd0,pl_wstrb_i[g*8]}+{3'd0,pl_wstrb_i[g*8+1]}+
   {3'd0,pl_wstrb_i[g*8+2]}+{3'd0,pl_wstrb_i[g*8+3]}+
   {3'd0,pl_wstrb_i[g*8+4]}+{3'd0,pl_wstrb_i[g*8+5]}+
   {3'd0,pl_wstrb_i[g*8+6]}+{3'd0,pl_wstrb_i[g*8+7]};
 end
 for(genvar g=0;g<4;g++)assign bytes16[g]={1'b0,bytes8[g*2]}+{1'b0,bytes8[g*2+1]};
 for(genvar g=0;g<2;g++)assign bytes32[g]={1'b0,bytes16[g*2]}+{1'b0,bytes16[g*2+1]};
 assign write_bytes={1'b0,bytes32[0]}+{1'b0,bytes32[1]};
 // Register the event boundary before counter adders. The last UI window
 // cycle drains into the counters before send is asserted.
 reg[15:0]event_q=0;reg[6:0]bytes_q=0;reg sample_q=0,stop_q=0;
 wire ack,request;wire[575:0]frame;
 wire[511:0]payload;
 for(genvar n=0;n<16;n++)begin:g_count
  assign payload[n*32+:32]={{(32-COUNTER_W){1'b0}},count[n]};
  wire[6:0]increment=n==14?bytes_q:{6'd0,event_q[n]};
  wire[COUNTER_W:0]sum={1'b0,count[n]}+increment;
  always @(posedge ui_clk)begin
   if(ui_reset_n&&core_ready_ui&&start_ui!=start_seen&&!pending&&!send&&!ack&&!running&&!sample_q)
    count[n]<=0;
   else if(sample_q)count[n]<=sum[COUNTER_W-1:0];
  end
  always @(posedge ui_clk)begin
   if(!ui_reset_n||!core_ready_ui)overflow[n]<=0;
   else if(start_ui!=start_seen&&!pending&&!send&&!ack&&!running&&!sample_q)overflow[n]<=0;
   else if(sample_q&&sum[COUNTER_W])overflow[n]<=1;
  end
 end
 always @(posedge ui_clk)begin
  if(!ui_reset_n||!core_ready_ui)begin
   start_seen<=0;done_seen<=0;running<=0;sample_q<=0;stop_q<=0;
   pending<=0;send<=0;generation<=0;seen_generation<=0;dropped<=0;event_q<=0;bytes_q<=0;
  end else begin
   event_q<=events;bytes_q<=wf?write_bytes:7'd0;
   sample_q<=running;stop_q<=running&&(done_ui!=done_seen);
   start_seen<=start_ui;done_seen<=done_ui;
   if(send&&ack)begin send<=0;pending<=0;end
   if(stop_q)begin pending<=1;end
   if(pending&&!send&&!ack)send<=1;
   if(done_ui!=done_seen)running<=0;
   if(start_ui!=start_seen)begin
    seen_generation<=seen_generation+1'b1;
    // No datapath stall: an impossibly short uncollected next window is
    // rejected explicitly. Never change a payload while XPM owns it.
    if(pending||send||ack||running||sample_q)begin dropped<=1;running<=0;sample_q<=0;end
    else begin generation<=seen_generation+1'b1;running<=1;sample_q<=0;dropped<=0;end
   end
  end
 end
 // dropped is excluded from the immutable XPM bank. A rejected generation
 // cannot equal core_generation and therefore cannot be published as valid.
 xpm_cdc_handshake #(.DEST_EXT_HSK(0),.DEST_SYNC_FF(3),.SRC_SYNC_FF(3),
  .INIT_SYNC_FF(1),.SIM_ASSERT_CHK(1),.WIDTH(576)) snapshot(
  .src_clk(ui_clk),.src_in({16'd0,overflow,generation,payload}),.src_send(send),.src_rcv(ack),
  .dest_clk(core_clk),.dest_out(frame),.dest_req(request),.dest_ack(1'b0));
 reg published=0;
 always @(posedge core_clk)begin
  if(!core_reset_n||start_i)published<=0;
  else if(request)published<=1;
 end
 wire valid=published&&!core_running&&frame[543:512]==core_generation;
 // Words 33..63 in the existing 64-word compact frame, offset word_i=0.
 always @*begin
  data_o=0;
  case(word_i)
   0:data_o=32'h51394231; // Q9B1, AXI bandwidth ABI
   1:data_o=32'h00010000;
   2:data_o=frame[543:512];
   3:data_o={29'd0,(|frame[559:544]),core_running,valid};
   4:data_o=UI_HZ;
   21:data_o={16'd0,frame[559:544]};
   22:data_o=32'd16; // four PS read ports: bytes per handshake
   23:data_o=32'd64; // PL read interface: bytes per full-width handshake
   24:data_o=32'h0000000f; // native UI edges / token window / frozen CDC / WSTRB bytes
   default:if(word_i>=5&&word_i<21&&valid)data_o=frame[(word_i-5)*32+:32];
  endcase
 end
 initial if(COUNTER_W<7||COUNTER_W>32)$fatal(1,"BW65_COUNTER_WIDTH");
endmodule
