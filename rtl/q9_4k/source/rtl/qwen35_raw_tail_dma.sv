`timescale 1ns/1ps
// Q9 geometry of the accepted Q7 raw-tail DMA, core-clock AXI only. This pool
// is on PL DDR; physical CDC/global arbitration is external. Absolute model
// layers use 32 slots of 256 KiB each: K[32][256] then V[32][256], 128-bit
// slots containing {zero32, four signed24 heads}. Preserve all 24-bit data.
// APPEND writes just one token (4 KiB K + 4 KiB V); REPLAY streams its published
// prefix. No local abort after an AXI command: producer/consumer must drain.
// REPLAY is a speculative stream: late R errors invalidate the ENTIRE result.
// The consumer must combine done/status with codec/writer before publication.
module qwen35_raw_tail_dma #(parameter integer OVERLAP_STREAM=1,EXTERNAL_LAYER_META=0,EXTERNAL_READER=0)(
    output wire[100:0]ext_cmd_o,input wire[692:0]ext_rsp_i=693'd0,
    input logic clk,reset_n,start_i,output wire start_ready_o,
    input wire incremental_v_i=1'b0,input logic replay_i,input logic[33:0] pool_base_i,
    input logic[4:0] layer_i,input logic[13:0] token_i,input logic[31:0] context_i,
    input logic in_valid_i,output wire in_ready_o,input logic in_value_i,
    input logic[7:0] in_dimension_i,input logic[95:0] in_samples_i,input logic in_last_i,
    input logic[4:0] in_layer_i,input logic[13:0] in_token_i,
    output wire out_valid_o,input logic out_ready_i,output wire out_value_o,
    output wire[12:0] out_index_o,output wire[95:0] out_samples_o,output wire out_last_o,
    output logic[5:0] valid_tokens_o,output logic[4:0] layer_o,
    output logic[13:0] page_token_base_o,output logic[31:0] context_o,
    output logic busy_o,done_o,committed_o,output logic[15:0] status_o,
    output logic[31:0] cycles_o,input_vectors_o,output_vectors_o,
    output logic[31:0] write_bytes_o,write_bursts_o,write_responses_o,read_bytes_o,read_bursts_o,
    output wire[3:0] m_awid,output wire[33:0] m_awaddr,output wire[7:0] m_awlen,
    output wire[2:0] m_awsize,output wire[1:0] m_awburst,output wire m_awvalid,input logic m_awready,
    output wire[511:0] m_wdata,output wire[63:0] m_wstrb,output wire m_wlast,m_wvalid,input logic m_wready,
    input logic[3:0] m_bid,input logic[1:0] m_bresp,input logic m_bvalid,output wire m_bready,
    output wire[3:0] m_arid,output wire[33:0] m_araddr,output wire[7:0] m_arlen,
    output wire[2:0] m_arsize,output wire[1:0] m_arburst,output wire m_arvalid,input logic m_arready,
    input logic[3:0] m_rid,input logic[511:0] m_rdata,input logic[1:0] m_rresp,
    input logic m_rlast,m_rvalid,output wire m_rready,
    output wire meta_we_o,meta_re_o,output wire[4:0]meta_waddr_o,meta_raddr_o,
    output wire[46:0]meta_wdata_o,input wire[46:0]meta_rdata_i=47'd0
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    typedef enum logic[3:0]{IDLE,WPREP,AW,WDATA,B,RREQ,RDATA,DONE,CMD_LOOKUP,CMD_CHECK,CMD_APPLY} state_t;
    state_t state=IDLE;
    logic[31:0] known;
    logic configured;logic[33:0] configured_base,layer_base,write_address;
    logic[13:0] token;logic[4:0] offset;
    logic[6:0] write_word;logic[1:0] pack_piece;logic[511:0] pack_word;logic packed_valid;
    logic read_plane,reader_seen;logic reader_count_good48;logic[511:0] read_word;logic read_holding;logic[1:0] read_piece;
    logic[13:0] emitted,vector_limit;
    logic cmd_replay,selected_known,command_bad,incremental_v;
    logic[33:0] cmd_pool;logic[34:0] pool_end;
    logic[5:0] selected_count;logic[8:0] selected_page;logic[31:0] selected_context;
    wire address_bad=cmd_pool[17:0]!=0||cmd_pool<34'h1_0000_0000
        ||pool_end>35'h4_0000_0000||(configured&&cmd_pool!=configured_base);
    wire same_context=selected_known&&selected_context==context_o;
    wire same_page=same_context&&selected_page==token[13:5];
    wire new_context_start=token==0&&(!selected_known||selected_context!=context_o||selected_count==0);
    wire next_page_start=same_context&&token[4:0]==0&&
        ((selected_count==32&&{1'b0,selected_page}+10'd1=={1'b0,token[13:5]})
         ||(selected_count==0&&selected_page==token[13:5]));
    // Re-running the slot that was just committed is an idempotent overwrite:
    // the same page/slot is rewritten and the committed count is unchanged.
    // Without it, any retry or re-evaluation of the latest position is
    // rejected as command_bad (status 0x80) because none of the three
    // original admission cases match a repeat.
    wire append_ok=(token[4:0]==0?(new_context_start||next_page_start):
        same_page&&selected_count=={1'b0,token[4:0]})
        ||(same_page&&selected_count=={1'b0,token[4:0]}+6'd1);
    wire replay_ok=same_page&&selected_count==({1'b0,token[4:0]}+6'd1);
    wire bad_command=layer_o[1:0]!=2'b11||address_bad||(cmd_replay?!replay_ok:!append_ok);
    // A layer's count, page and context are one atomic record. Command
    // admission already has a LOOKUP stage: read RAM on command capture and
    // latch its result there, preserving all existing command cycles.
    // Only known[] resets; an unknown layer never exposes stale RAM data.
    wire [46:0] layer_record;
    wire begin_page=state==CMD_APPLY&&!command_bad&&!cmd_replay&&token[4:0]==0;
    wire commit_page=state==B&&m_bvalid&&write_word==127&&status_o==0&&m_bresp==0&&m_bid==3;
    assign meta_we_o=reset_n&&(begin_page||commit_page);assign meta_waddr_o=layer_o;
    assign meta_wdata_o={context_o,token[13:5],commit_page?valid_tokens_o:6'd0};
    assign meta_re_o=reset_n&&state==IDLE&&start_i&&layer_i[1:0]==2'b11;assign meta_raddr_o=layer_i;
    generate if(EXTERNAL_LAYER_META)begin:g_external_meta assign layer_record=meta_rdata_i;end
    else begin:g_local_meta
      qwen7b_sdp_ram #(.WIDTH(47),.DEPTH(32),.STYLE("distributed")) layer_metadata(
       .clk,.write_enable(meta_we_o),.write_address(meta_waddr_o),.write_data(meta_wdata_o),
       .read_enable(meta_re_o),.read_address(meta_raddr_o),.read_data(layer_record));
    end endgenerate
    assign start_ready_o=state==IDLE;
    // Consume a completed word and capture the next word's first vector on
    // the same edge. Do not cross the burst's B-response barrier.
    wire replace_write=OVERLAP_STREAM&&packed_valid&&m_wready&&!m_wlast;
    wire[6:0] input_word=write_word+{6'd0,replace_write};
    assign in_ready_o=state==WDATA&&(!packed_valid||replace_write);
    assign m_awid=4'd3;assign m_awaddr=write_address;assign m_awlen=8'd15;
    assign m_awsize=3'd6;assign m_awburst=2'b01;assign m_awvalid=state==AW;
    assign m_wdata=pack_word;assign m_wstrb=64'hffffffffffffffff;
    assign m_wlast=write_word[3:0]==15;assign m_wvalid=state==WDATA&&packed_valid;
    assign m_bready=state==B;
    assign out_valid_o=state==RDATA&&read_holding;
    assign out_value_o=read_plane;assign out_index_o=emitted[12:0];
    assign out_samples_o=read_word[95:0];
    assign out_last_o=read_plane&&emitted+14'd1==vector_limit;
    wire reader_ready,reader_valid,reader_last,reader_busy,reader_done;
    wire[511:0] reader_data;wire[3:0] reader_status;
    wire[31:0] reader_cycles,requests,received,peak;
    wire reader_start=state==RREQ;
    wire sink_ready=state==RDATA&&(!read_holding||(OVERLAP_STREAM&&read_piece==3&&out_ready_i));
    wire[31:0] words=read_plane&&incremental_v?32'd64:({26'd0,valid_tokens_o}<<6);
    qwen35_raw_reader_endpoint #(.MAX_BEATS(16),.OUTSTANDING(4),.EXTERNAL_READER(EXTERNAL_READER)) reader(
        .ext_cmd_o(ext_cmd_o),.ext_rsp_i(ext_rsp_i),
        .clk(clk),.reset_n(reset_n),.start_i(reader_start),.start_ready_o(reader_ready),
        .base_i(layer_base+({33'd0,read_plane}<<17)+((read_plane&&incremental_v)?({29'd0,offset}<<12):34'd0)),.words_i(words),.tile_words_i(words),
        .valid_o(reader_valid),.ready_i(sink_ready),.data_o(reader_data),.last_o(reader_last),
        .busy_o(reader_busy),.done_o(reader_done),.status_o(reader_status),.cycles_o(reader_cycles),
        .requests_o(requests),.received_o(received),.peak_outstanding_o(peak),
        .m_axi_arid(m_arid),.m_axi_araddr(m_araddr),.m_axi_arlen(m_arlen),.m_axi_arsize(m_arsize),.m_axi_arburst(m_arburst),
        .m_axi_arlock(),.m_axi_arcache(),.m_axi_arprot(),.m_axi_arqos(),.m_axi_arvalid(m_arvalid),.m_axi_arready(m_arready),
        .m_axi_rid(m_rid),.m_axi_rdata(m_rdata),.m_axi_rresp(m_rresp),.m_axi_rlast(m_rlast),.m_axi_rvalid(m_rvalid),.m_axi_rready(m_rready));
    always_ff @(posedge clk)begin
        if(q9_local_reset_active)begin
            state<=IDLE;known<=0;configured<=0;configured_base<=0;command_bad<=0;incremental_v<=0;
            layer_base<=0;write_address<=0;layer_o<=0;token<=0;offset<=0;context_o<=0;page_token_base_o<=0;valid_tokens_o<=0;
            write_word<=0;pack_piece<=0;packed_valid<=0;
            read_plane<=0;reader_seen<=0;reader_count_good48<=0;read_holding<=0;read_piece<=0;emitted<=0;vector_limit<=0;
            busy_o<=0;done_o<=0;committed_o<=0;status_o<=0;cycles_o<=0;
            input_vectors_o<=0;output_vectors_o<=0;write_bytes_o<=0;write_bursts_o<=0;write_responses_o<=0;read_bytes_o<=0;read_bursts_o<=0;
        end else begin
            done_o<=0;committed_o<=0;if(busy_o)cycles_o<=cycles_o+1'b1;
            if(reader_done)begin
                // The receipt is stable on DONE; compare while capturing it,
                // before another shared owner can change the live response.
                reader_count_good48<=received==words;
                reader_seen<=1;status_o[11:8]<=status_o[11:8]|reader_status;
                read_bytes_o<=read_bytes_o+(received<<6);read_bursts_o<=read_bursts_o+requests;
            end
            if(out_valid_o&&out_ready_i)begin
                emitted<=emitted+1'b1;output_vectors_o<=output_vectors_o+1'b1;
                read_word<=read_word>>128;
                if(read_piece==3)read_holding<=0;else read_piece<=read_piece+1'b1;
            end
            // Incoming data wins when the previous final vector retires.
            // Held output still reserves read_word until its handshake.
            if(reader_valid&&sink_ready)begin
                read_word<=reader_data;read_holding<=1;read_piece<=0;
                for(integer p=0;p<4;p=p+1)if(reader_data[p*128+96+:32]!=0)status_o[14]<=1;
            end
            case(state)
            IDLE:if(start_i)begin
                busy_o<=1;status_o<=0;cycles_o<=0;committed_o<=0;
                input_vectors_o<=0;output_vectors_o<=0;write_bytes_o<=0;write_bursts_o<=0;write_responses_o<=0;read_bytes_o<=0;read_bursts_o<=0;
                layer_o<=layer_i;token<=token_i;offset<=token_i[4:0];context_o<=context_i;page_token_base_o<={token_i[13:5],5'd0};
                valid_tokens_o<={1'b0,token_i[4:0]}+6'd1;vector_limit<=({9'd0,token_i[4:0]}+14'd1)<<8;
                cmd_pool<=pool_base_i;cmd_replay<=replay_i;incremental_v<=incremental_v_i;state<=CMD_LOOKUP;
                write_word<=0;pack_piece<=0;packed_valid<=0;read_plane<=0;reader_seen<=0;read_holding<=0;emitted<=0;
            end
            CMD_LOOKUP:begin
                pool_end<={1'b0,cmd_pool}+35'd8388608;
                layer_base<=cmd_pool+({29'd0,layer_o}<<18);
                selected_known<=0;selected_count<=0;selected_page<=0;selected_context<=0;
                if(layer_o[1:0]==2'b11)begin
                    selected_known<=known[layer_o];
                    if(known[layer_o])begin
                        selected_count<=layer_record[5:0];selected_page<=layer_record[14:6];
                        selected_context<=layer_record[46:15];
                    end
                end
                state<=CMD_CHECK;
            end
            CMD_CHECK:begin command_bad<=bad_command;state<=CMD_APPLY;end
            CMD_APPLY:begin
                if(command_bad)begin status_o<=16'h0080;state<=DONE;end
                else begin
                    configured<=1;configured_base<=cmd_pool;
                    if(cmd_replay)state<=RREQ;
                    else begin
                        // Commit only the captured command; failure leaves count zero for retry.
                        if(token[4:0]==0)begin
                            known[layer_o]<=1;
                        end
                        state<=WPREP;
                    end
                end
            end
            WPREP:begin
                write_address<=layer_base+({33'd0,write_word[6]}<<17)+({29'd0,offset}<<12)+({28'd0,write_word[5:0]}<<6);
                state<=AW;
            end
            AW:if(m_awready)begin write_bursts_o<=write_bursts_o+1'b1;state<=WDATA;end
            WDATA:begin
                // T74: the current piece slot is unpublished while in_ready_o,
                // so it is written speculatively; the taking edge leaves the
                // accepted vector there and advances pack_piece.
                if(in_ready_o)pack_word[pack_piece*128+:128]<={32'd0,in_samples_i};
                if(in_valid_i&&in_ready_o)begin
                    input_vectors_o<=input_vectors_o+1'b1;
                    if(in_value_i!=input_word[6]||in_dimension_i!={input_word[5:0],pack_piece}
                       ||in_layer_i!=layer_o||in_token_i!=token||in_last_i!==(input_word==127&&pack_piece==3))status_o[1]<=1;
                    if(pack_piece==3)begin packed_valid<=1;pack_piece<=0;end else pack_piece<=pack_piece+1'b1;
                end
                if(m_wvalid&&m_wready)begin
                    packed_valid<=0;write_bytes_o<=write_bytes_o+64;
                    if(m_wlast)state<=B;else write_word<=write_word+1'b1;
                end
            end
            B:if(m_bvalid)begin
                write_responses_o<=write_responses_o+1'b1;
                if(m_bresp!=0)status_o[2]<=1;if(m_bid!=3)status_o[3]<=1;
                if(write_word==127)begin
                    if(status_o==0&&m_bresp==0&&m_bid==3)committed_o<=1;
                    state<=DONE;
                end else begin write_word<=write_word+1'b1;state<=WPREP;end
            end
            RREQ:if(reader_ready)begin reader_seen<=0;reader_count_good48<=0;emitted<=read_plane&&incremental_v?{1'b0,offset,8'd0}:14'd0;state<=RDATA;end
            RDATA:if(reader_seen&&!read_holding)begin
                if(!reader_count_good48||emitted!=vector_limit)status_o[15]<=1;
                if(read_plane)state<=DONE;else begin read_plane<=1;state<=RREQ;end
            end
            DONE:begin busy_o<=0;done_o<=1;state<=IDLE;end
            default:begin status_o[15]<=1;state<=DONE;end
            endcase
        end
    end
endmodule
