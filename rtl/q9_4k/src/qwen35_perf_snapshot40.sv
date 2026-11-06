`timescale 1ns/1ps
// Coherent counter snapshots feed one small distributed 40-bit read store.
// Keep the existing simultaneous counter capture: serialising live counters
// would corrupt a snapshot if the next token starts early. A new generation
// aborts/restarts an unfinished transfer; partial contents are never valid.
module qwen35_perf_snapshot40 #(parameter integer N=128,AW=$clog2(N))(
 input wire clk,reset_n,valid_i,invalidate_i,input wire[31:0]generation_i,
 input wire[N*64-1:0]snapshot_i,input wire[AW-1:0]read_index_i,input wire read_high_i,
 output wire[31:0]read_word_o,output reg valid_o=0,busy_o=0,output reg[31:0]generation_o=0
);
 (* ram_style="distributed" *) reg[39:0]snapshot[0:(1<<AW)-1];
 reg[AW-1:0]write_index=0;reg seen=0;reg[31:0]seen_generation;
 reg write_pending=0,write_last=0,draining=0;
 reg[AW-1:0]write_address_q;
 reg[39:0]write_data_q;
 // Copy and MMIO read phases are exclusive. Sharing the physical address
 // permits single-port LUTRAM instead of paying for a second async port.
 wire[AW-1:0]memory_address=busy_o?write_address_q:read_index_i;
 wire[39:0]read_value=snapshot[memory_address];
 // Invalidation takes effect on its accepting clock edge, exactly like
 // valid_o itself. A concurrent pre-edge read can return only the previous
 // complete generation; partial/new contents are never advertised valid.
 assign read_word_o=(!valid_o||generation_o!=generation_i)?32'd0:
     read_high_i?{24'd0,read_value[39:32]}:read_value[31:0];
 // Unconditional payload/address capture and a registered write promise cut
 // token-admission/invalidation away from the forty LUTRAM write enables.
 // A canceled old write is harmless while valid_o is cleared; a new copy
 // overwrites every address before publishing its generation.
 always @(posedge clk)begin
  write_address_q<=write_index;write_data_q<=snapshot_i[write_index*64+:40];
  if(write_pending)snapshot[memory_address]<=write_data_q;
  write_pending<=0;write_last<=0;
  if(!reset_n)begin valid_o<=0;busy_o<=0;write_index<=0;seen<=0;draining<=0;end
  else if(invalidate_i||!valid_i)begin valid_o<=0;busy_o<=0;write_index<=0;seen<=0;draining<=0;end
  else if(!seen||seen_generation!=generation_i)begin
   seen<=1;seen_generation<=generation_i;write_index<=0;busy_o<=1;valid_o<=0;draining<=0;
  end else if(busy_o)begin
   if(draining)begin
    if(write_pending&&write_last)begin busy_o<=0;valid_o<=1;draining<=0;end
   end else begin
    write_pending<=1;write_last<=write_index==N-1;
    if(write_index==N-1)draining<=1;
    else write_index<=write_index+1'b1;
   end
  end
 end
 // Generation is frame payload. A canceled final store may update this
 // invalid payload; publication and generation matching still prevent a
 // partial/canceled frame from being exposed. Current invalidate/valid no
 // longer drive32 metadata data enables or the asynchronous MMIO read path.
 always @(posedge clk)begin
  if(!reset_n)generation_o<=0;
  else if(write_pending&&write_last)generation_o<=seen_generation;
 end
 initial if(N<2||N>(1<<AW))$fatal(1,"PERF40_RAM_SHAPE");
endmodule
