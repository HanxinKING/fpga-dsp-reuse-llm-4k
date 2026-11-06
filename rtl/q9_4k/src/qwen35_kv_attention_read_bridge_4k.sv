`timescale 1ns/1ps
// Ascending KV-head/P32-page traversal. Page-sized reader storage remains
// identical to T80. Score save/load and pipeline-drain fences are explicit.
module qwen35_kv_attention_read_bridge_4k #(
 parameter integer EXTERNAL_READER=0,QUERY_HEADS=16,KV_HEADS=4,HEAD_DIM=256,MAX_TOKENS=4096
)(
 input wire clk,reset_n,start_i,output wire start_ready_o,
 input wire [33:0] code_base_i,param_base_i,
 input wire lookup_valid_i,input wire [5:0] valid_tokens_i,
 input wire [13:0] token_base_i,output wire [8:0] lookup_page_o,
 output wire page_cmd_valid_o,output wire [1:0] page_cmd_kind_o,page_cmd_head_o,
 output wire [8:0] page_cmd_page_o,input wire page_cmd_ready_i,
 output wire [100:0] raw_ext_cmd_o,input wire [692:0] raw_ext_rsp_i=693'd0,
 output wire k_valid_o,input wire k_ready_i,output wire [$clog2(KV_HEADS)-1:0] k_kv_head_o,
 output wire [$clog2(MAX_TOKENS)-1:0] k_token_o,output wire [$clog2(HEAD_DIM)-1:0] k_dim_o,
 output wire [63:0] k_code_o,output wire [255:0] k_scale_o,k_min_o,
 output wire [QUERY_HEADS-1:0] k_head_enable_o,output wire k_pass_done_o,
 output wire v_valid_o,input wire v_ready_i,output wire [$clog2(KV_HEADS)-1:0] v_kv_head_o,
 output wire [$clog2(MAX_TOKENS)-1:0] v_token_o,output wire [$clog2(HEAD_DIM)-1:0] v_dim_o,
 output wire [63:0] v_code_o,output wire [255:0] v_scale_o,v_min_o,
 output wire [QUERY_HEADS-1:0] v_head_enable_o,output wire v_pass_done_o,
 output wire busy_o,output reg done_o,output reg [7:0] status_o,
 output reg [31:0] read_cycles_o,read_vectors_o,
 output wire [3:0] m_arid,output wire [33:0] m_araddr,output wire [7:0] m_arlen,
 output wire [2:0] m_arsize,output wire [1:0] m_arburst,output wire m_arvalid,input wire m_arready,
 input wire [3:0] m_rid,input wire [511:0] m_rdata,input wire [1:0] m_rresp,
 input wire m_rlast,m_rvalid,output wire m_rready
);
 localparam IDLE=0,KLOOK=1,KLAUNCH=2,KSTREAM=3,KSAVE=4,
            VLOOK=5,VLOAD=6,VLAUNCH=7,VSTREAM=8,VDRAIN=9,DONE=10;
 reg [3:0] state=IDLE;reg [1:0] head;reg [8:0] page,last_page;
 wire rr,rv,rl,rb,rd;wire [1:0] rh;wire [13:0] rt;wire [7:0] dim,rs;
 wire [63:0] code;wire [255:0] scale,minimum;
 wire [31:0] reader_cycles,reader_vectors;
 wire stream_k=state==KSTREAM,stream_v=state==VSTREAM;
 wire take=rv&&(stream_k?k_ready_i:v_ready_i);
 wire final_page=page==last_page,final_head=head==KV_HEADS-1;
 assign start_ready_o=state==IDLE;assign busy_o=state!=IDLE;
 assign lookup_page_o=page;
 assign page_cmd_valid_o=state==KSAVE||state==VLOAD||state==VDRAIN;
 assign page_cmd_kind_o=state==KSAVE?2'd0:state==VLOAD?2'd1:2'd2;
 assign page_cmd_head_o=head;assign page_cmd_page_o=page;
 assign k_valid_o=rv&&stream_k;assign v_valid_o=rv&&stream_v;
 assign k_kv_head_o=rh;assign v_kv_head_o=rh;
 assign k_token_o=rt[$clog2(MAX_TOKENS)-1:0];assign v_token_o=rt[$clog2(MAX_TOKENS)-1:0];
 assign k_dim_o=dim;assign v_dim_o=dim;
 assign k_code_o=code;assign v_code_o=code;
 assign k_scale_o=scale;assign v_scale_o=scale;assign k_min_o=minimum;assign v_min_o=minimum;
 assign k_head_enable_o={QUERY_HEADS{1'b1}};assign v_head_enable_o={QUERY_HEADS{1'b1}};
 assign k_pass_done_o=stream_k&&take&&rl&&final_head&&final_page;
 assign v_pass_done_o=stream_v&&take&&rl&&final_head&&final_page;
 qwen35_kv_page_axi_reader #(.EXTERNAL_READER(EXTERNAL_READER),.HEAD_DIM(HEAD_DIM),.MAX_TOKENS(32)) reader(
  .clk,.reset_n,.start_i((state==KLAUNCH||state==VLAUNCH)&&rr),.start_ready_o(rr),
  .raw_ext_cmd_o(raw_ext_cmd_o),.raw_ext_rsp_i(raw_ext_rsp_i),
  .code_base_i(code_base_i),.param_base_i(param_base_i),.head_i(head),
  .value_i(state==VLAUNCH||state==VSTREAM),.valid_tokens_i(valid_tokens_i),.token_base_i({page,5'd0}),
  .out_valid_o(rv),.out_ready_i(stream_k?k_ready_i:stream_v?v_ready_i:1'b0),
  .out_head_o(rh),.out_value_o(),.out_token_o(rt),.out_dimension_o(dim),
  .out_code_o(code),.out_scale_o(scale),.out_minimum_o(minimum),.out_last_o(rl),
  .busy_o(rb),.done_o(rd),.status_o(rs),.cycles_o(reader_cycles),.read_bytes_o(),
  .read_bursts_o(),.vector_count_o(reader_vectors),
  .m_arid,.m_araddr,.m_arlen,.m_arsize,.m_arburst,.m_arvalid,.m_arready,
  .m_rid,.m_rdata,.m_rresp,.m_rlast,.m_rvalid,.m_rready);
 always @(posedge clk)begin
  if(!reset_n)begin state<=IDLE;head<=0;page<=0;last_page<=0;done_o<=0;status_o<=0;read_cycles_o<=0;read_vectors_o<=0;end
  else begin
   done_o<=0;
   if((stream_k||stream_v)&&take)read_vectors_o<=read_vectors_o+1'b1;
   if((stream_k||stream_v)&&rd)begin status_o<=status_o|rs;read_cycles_o<=read_cycles_o+reader_cycles;end
   case(state)
    IDLE:if(start_i)begin
     head<=0;page<=0;last_page<=token_base_i[13:5];status_o<=0;read_cycles_o<=0;read_vectors_o<=0;
     if(token_base_i>=MAX_TOKENS)begin status_o<=8'h80;state<=DONE;end else state<=KLOOK;
    end
    KLOOK:if(!lookup_valid_i||valid_tokens_i==0||valid_tokens_i>32)begin status_o<=8'h40;state<=DONE;end else state<=KLAUNCH;
    KLAUNCH:if(rr)state<=KSTREAM;
    KSTREAM:if(rd)state<=rs!=0?DONE:KSAVE;
    KSAVE:if(page_cmd_ready_i)begin
     if(!final_page)begin page<=page+1'b1;state<=KLOOK;end
     else if(!final_head)begin head<=head+1'b1;page<=0;state<=KLOOK;end
     else begin head<=0;page<=0;state<=VLOOK;end
    end
    VLOOK:if(!lookup_valid_i||valid_tokens_i==0||valid_tokens_i>32)begin status_o<=8'h40;state<=DONE;end else state<=VLOAD;
    VLOAD:if(page_cmd_ready_i)state<=VLAUNCH;
    VLAUNCH:if(rr)state<=VSTREAM;
    VSTREAM:if(rd)begin
     if(rs!=0||final_head&&final_page)state<=DONE;else state<=VDRAIN;
    end
    VDRAIN:if(page_cmd_ready_i)begin
     if(!final_page)page<=page+1'b1;else begin head<=head+1'b1;page<=0;end
     state<=VLOOK;
    end
    DONE:begin done_o<=1;state<=IDLE;end
    default:begin status_o<=8'h80;state<=DONE;end
   endcase
  end
 end
 initial if(QUERY_HEADS!=16||KV_HEADS!=4||HEAD_DIM!=256||MAX_TOKENS<32||MAX_TOKENS>4096||MAX_TOKENS%32!=0)
  $fatal(1,"Q9_PAGED_READER_GEOMETRY");
endmodule
