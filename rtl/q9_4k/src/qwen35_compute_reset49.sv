`timescale 1ns/1ps
// Parallel reset copies capture the SAME CDC output on the SAME edge as the
// original accelerator_reset_n. No stage is inserted in assertion or release.
// Separate registered roots keep unrelated datapath READY/CE cones local.
module qwen35_compute_reset49 #(parameter integer PARTS=12)(
 input wire clk,core_reset_n,output wire[PARTS-1:0]reset_parts_n
);
 for(genvar p=0;p<PARTS;p++)begin:g_part
  (* DONT_TOUCH="TRUE",MAX_FANOUT=64 *)reg reset_q=1'b0;
  always @(posedge clk)reset_q<=core_reset_n;
  assign reset_parts_n[p]=reset_q;
 end
endmodule
