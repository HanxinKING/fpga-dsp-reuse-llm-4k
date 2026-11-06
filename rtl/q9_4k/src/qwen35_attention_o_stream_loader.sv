`timescale 1ns/1ps
// Lease and fill the existing O activation cache while gated Attention exits.
// No4096-word intermediate/replay. A failed payload completes an already
// opened activation load with poison zeros, then releases its lease without
// ever launching a matrix command. This preserves next-job recoverability.
module qwen35_attention_o_stream_loader #(parameter integer COUNT=4096,AW=$clog2(COUNT))(
 input wire clk,reset_n,sched_start_i,q_done_i,
 input wire gate_complete_i,gate_error_i,q_error_i,payload_done_i,payload_error_i,
 input wire gate_valid_i,input wire[AW-1:0]gate_index_i,input wire[23:0]gate_data_i,
 output wire gate_ready_o,
 input wire client_ready_i,begin_ready_i,x_ready_i,matrix_ready_i,
 output wire client_start_o,begin_o,x_valid_o,output wire[23:0]x_data_o,
 output wire[14:0]cols_o,output wire matrix_start_o,job_done_o,
 input wire matrix_last_fire_i,matrix_done_i,
 output reg fault_o=0,output reg[3:0]state_o=0,
 output reg[AW-1:0]index_o=0,output reg[1:0]drain_o=0,
 output reg q_error_o=0,payload_error_o=0
);
 localparam IDLE=0,CAPTURE=1,START=2,LOAD=3,MSTART=5,OUT=6,DONE=7,GATE_DRAIN=8,DISCARD=9,CANCEL_DRAIN=10,RETIRE=11;
 reg lease=0,matrix_done_seen=0;
 wire payload_failed=payload_done_i&&payload_error_i;
 wire bad_index=gate_valid_i&&gate_index_i!=index_o;
 wire capture_failed=payload_failed||bad_index;
 assign client_start_o=state_o==START&&client_ready_i&&!payload_failed;
 assign begin_o=state_o==LOAD&&begin_ready_i&&!payload_failed;
 assign cols_o=COUNT;
 assign x_valid_o=(state_o==CAPTURE&&gate_valid_i&&!capture_failed)||state_o==DISCARD;
 assign x_data_o=state_o==DISCARD?24'd0:gate_data_i;
 assign gate_ready_o=state_o==CAPTURE&&x_ready_i&&!capture_failed;
 assign matrix_start_o=state_o==MSTART&&matrix_ready_i&&!payload_failed;
 // The last accepted O value is not the matrix service's retirement point.
 // job_done also aborts its activation cache. Aborting on that last value
 // suppresses the inner matrix done and leaves the AXI command busy forever.
 // Hold ownership until both the final output and native done were observed.
 assign job_done_o=(state_o==RETIRE&&(matrix_done_i||matrix_done_seen))||(state_o==DONE&&fault_o&&lease);
 wire input_fire=x_valid_o&&x_ready_i;
 always @(posedge clk)begin
  if(!reset_n)begin state_o<=IDLE;index_o<=0;fault_o<=0;drain_o<=0;lease<=0;matrix_done_seen<=0;q_error_o<=0;payload_error_o<=0;end
  else begin
   if(sched_start_i)fault_o<=0;
   if(payload_failed&&state_o==GATE_DRAIN)payload_error_o<=1;
   if(matrix_start_o)matrix_done_seen<=0;
   else if((state_o==OUT||state_o==RETIRE)&&matrix_done_i)matrix_done_seen<=1;
   case(state_o)
    IDLE:if(q_done_i)begin drain_o<=3;q_error_o<=q_error_i;payload_error_o<=payload_failed;index_o<=0;state_o<=GATE_DRAIN;end
    GATE_DRAIN:if(drain_o!=0)drain_o<=drain_o-1'b1;
      else if(!gate_complete_i||gate_error_i||q_error_o||payload_error_o||payload_failed)begin fault_o<=1;state_o<=DONE;end
      else state_o<=START;
    START:if(payload_failed)begin fault_o<=1;state_o<=DONE;end
      else if(client_start_o)begin lease<=1;state_o<=LOAD;end
    LOAD:if(payload_failed)begin fault_o<=1;state_o<=DONE;end
      else if(begin_o)begin state_o<=CAPTURE;index_o<=0;end
    CAPTURE:if(capture_failed)begin fault_o<=1;state_o<=DISCARD;end
      else if(input_fire)begin if(index_o==COUNT-1)state_o<=MSTART;else index_o<=index_o+1'b1;end
    DISCARD:if(input_fire)begin
      if(index_o==COUNT-1)begin state_o<=CANCEL_DRAIN;drain_o<=2;end
      else index_o<=index_o+1'b1;
    end
    CANCEL_DRAIN:if(drain_o!=0)drain_o<=drain_o-1'b1;else state_o<=DONE;
    MSTART:if(payload_failed)begin fault_o<=1;drain_o<=2;state_o<=CANCEL_DRAIN;end
      else if(matrix_start_o)state_o<=OUT;
    OUT:if(matrix_last_fire_i)state_o<=RETIRE;
    RETIRE:if(matrix_done_i||matrix_done_seen)begin state_o<=DONE;lease<=0;end
    DONE:begin state_o<=IDLE;lease<=0;end
    default:state_o<=IDLE;
   endcase
  end
 end
 // synthesis translate_off
 always @(posedge clk)if(reset_n)begin
  if(matrix_start_o&&fault_o)$fatal(1,"O_STREAM_POISON_MATRIX_START");
  if(input_fire&&state_o!=DISCARD&&gate_index_i!=index_o)$fatal(1,"O_STREAM_INDEX");
 end
 // synthesis translate_on
endmodule
