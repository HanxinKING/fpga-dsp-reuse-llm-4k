`timescale 1ns/1ps
// Narrow dual-clock ring replaces the 64x512 word ring and 1024-bit gather.
// UI serializer admits one 512-bit beat, writes PAYLOAD_BITS per UI clock.
// Core consumes 64-bit slices directly from the registered BRAM word.
// Last belongs only to the final slice. Both pointers cross as Gray codes;
// only committed narrow words are visible, including partial serialized beats.
// At META_FIFO_ADDR_W=5/PAYLOAD_BITS=256 this is 128x257 in four native BRAM36.
// The 32768 data-bit capacity is preserved. 256-bit storage avoids the measured
// narrower UI serialization throughput loss while retaining a 64-bit client.
module qwen7b_metadata_fifo64 #(parameter integer META_FIFO_ADDR_W=5,PAYLOAD_BITS=256)(
 input wire write_clk,read_clk,reset_n,
 input wire valid_i,output wire ready_o,input wire[511:0] data_i,input wire last_i,
 output wire valid_o,input wire ready_i,output wire[63:0] data_o,output wire last_o
);
 localparam integer PARTS=512/PAYLOAD_BITS,WORDS=PAYLOAD_BITS/64;
 localparam integer SW=PARTS>1?$clog2(PARTS):1,RW=WORDS>1?$clog2(WORDS):1;
 localparam integer AW=META_FIFO_ADDR_W+1+$clog2(PARTS);
 wire wrst,rrst;
 xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) wr(
  .src_arst(reset_n),.dest_clk(write_clk),.dest_arst(wrst));
 xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) rd(
  .src_arst(reset_n),.dest_clk(read_clk),.dest_arst(rrst));
 reg holding=0,held_last=0;reg[SW-1:0] slice=0;reg[RW-1:0] read_slice=0;reg[511:0] held;
 reg[AW:0] wb=0,wg=0,rb=0,rg=0;
 (* ASYNC_REG="TRUE" *) reg[AW:0] rs1=0,rs2=0,ws1=0,ws2=0;
 reg full=0,prefetch_valid=0,output_valid=0;
 wire write_narrow=wrst&&holding&&!full;
 assign ready_o=wrst&&(!holding||(write_narrow&&slice==PARTS-1));
 wire take=valid_i&&ready_o;
 wire[AW:0] wn=wb+write_narrow,wgn=(wn>>1)^wn;
 wire empty=rg==ws2;
 wire last_slice=read_slice==WORDS-1;
 wire advance=!output_valid||(ready_i&&last_slice);
 wire fetch=rrst&&(!prefetch_valid||advance)&&!empty;
 wire[AW:0] rn=rb+fetch,rgn=(rn>>1)^rn;
 wire[PAYLOAD_BITS:0] word;
 assign valid_o=rrst&&output_valid;assign data_o=word[read_slice*64+:64];assign last_o=word[PAYLOAD_BITS]&&last_slice;
 qwen7b_ingress_sdp_mem #(.WIDTH(PAYLOAD_BITS+1),.ADDR_W(AW),.COMPACT_RAM(0),.PIPELINED_READ(1)) payload(
  .write_clk(write_clk),.read_clk(read_clk),.write_enable(write_narrow),.read_enable(fetch),
  .output_enable(rrst&&advance),.write_address(wb[AW-1:0]),.read_address(rb[AW-1:0]),
  .write_data({held_last&&slice==PARTS-1,held[PAYLOAD_BITS-1:0]}),.read_data(word));
 always @(posedge write_clk or negedge wrst)begin
  if(!wrst)begin wb<=0;wg<=0;rs1<=0;rs2<=0;full<=0;holding<=0;slice<=0;held_last<=0;end
  else begin
   rs1<=rg;rs2<=rs1;wb<=wn;wg<=wgn;full<=wgn=={~rs2[AW:AW-1],rs2[AW-2:0]};
   if(write_narrow)begin
    if(slice==PARTS-1)begin holding<=0;slice<=0;end else slice<=slice+1'b1;
   end
   if(take)begin holding<=1;slice<=0;held_last<=last_i;end
  end
 end
 // Payload is unreset. Validity, pointers and LAST own stale data after reset.
 // The serializer can capture an uncommitted input whenever the current
 // payload is empty or consumes its final slice. Holding/full protect every
 // live slice; only TAKE publishes new data and LAST. Stale upper slices
 // need no zero-fill because no valid read reaches them after PARTS writes.
 wire capture_payload66=!holding||(!full&&slice==PARTS-1);
 generate if(PAYLOAD_BITS<512)begin:g_shift_payload66
  always @(posedge write_clk)begin
   if(holding&&!full)held[511-PAYLOAD_BITS:0]<=held[511:PAYLOAD_BITS];
   if(capture_payload66)held<=data_i;
  end
 end else begin:g_whole_payload66
  always @(posedge write_clk)if(capture_payload66)held<=data_i;
 end endgenerate
 always @(posedge read_clk or negedge rrst)begin
  if(!rrst)begin rb<=0;rg<=0;ws1<=0;ws2<=0;prefetch_valid<=0;output_valid<=0;read_slice<=0;end
  else begin
   ws1<=wg;ws2<=ws1;rb<=rn;rg<=rgn;
   if(!prefetch_valid||advance)prefetch_valid<=!empty;
   if(advance)output_valid<=prefetch_valid;
   if(output_valid&&ready_i)read_slice<=last_slice?0:read_slice+1'b1;
  end
 end
 initial if(META_FIFO_ADDR_W<2||(PAYLOAD_BITS!=64&&PAYLOAD_BITS!=128&&PAYLOAD_BITS!=256&&PAYLOAD_BITS!=512))$fatal(1,"Q7_META64_FIFO_SHAPE");
endmodule
