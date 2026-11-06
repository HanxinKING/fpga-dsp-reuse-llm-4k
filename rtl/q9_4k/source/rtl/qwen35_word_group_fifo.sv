`timescale 1ns/1ps
// One 512-bit dual-clock BRAM ring with a separately staged last bit instead of 2/4 wide parallel read banks.
// The ring retains GROUP_WORDS * 2**ADDR_W words. A core-clock assembler
// delivers one group per GROUP_WORDS clocks at steady state. Gray ownership
// protects the RAM payload; reset discards the ring, partial group and output.
module qwen35_word_group_fifo #(
    parameter integer ADDR_W=4,GROUP_WORDS=2,FULL_GROUPS_ONLY=0,
    parameter integer COUNT_W=$clog2(GROUP_WORDS+1)
)(
    input wire write_clk,read_clk,reset_n,
    input wire valid_i,output wire ready_o,input wire [511:0] data_i,input wire last_i,
    output wire valid_o,input wire ready_i,output reg [GROUP_WORDS*512-1:0] data_o,
    output reg [COUNT_W-1:0] count_o,output reg last_o
);
    localparam integer G=$clog2(GROUP_WORDS),AW=ADDR_W+G;
    wire wrst,read_reset_sync;
    (* MAX_FANOUT=64 *) reg rrst=0;
    always @(posedge read_clk or negedge read_reset_sync)
        if(!read_reset_sync)rrst<=0;else rrst<=1;
    xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) rw(
        .src_arst(reset_n),.dest_clk(write_clk),.dest_arst(wrst));
    xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) rr(
        .src_arst(reset_n),.dest_clk(read_clk),.dest_arst(read_reset_sync));
    reg [AW:0] wb=0,wg=0,rb=0,rg=0;
    (* ASYNC_REG="TRUE" *) reg [AW:0] rs1=0,rs2=0,ws1=0,ws2=0;
    reg full=0,prefetch_valid=0,word_valid=0,output_valid=0;
    reg [G-1:0] word_index=0;
    reg [511:0] staging[GROUP_WORDS-1];
    wire [512:0] word;
    // Ownership is shared with the payload ring. Capturing this single bit
    // in local FFs avoids BRAM placement driving the wide gather enable.
    // See q9_int4_dep/qwen7b_word_group_fifo.sv: `distributed` produced RAMD32
    // primitives whose WADR arc appears in the run q9_uram_timing_20260922_r3
    // hold census.  Registers match the "local FFs" intent stated above.
    (* ram_style="registers" *) reg last_memory[0:(1<<AW)-1];
    (* MAX_FANOUT=32 *) reg last_prefetch,last_word;
    assign word[512]=last_word;
    wire final_word=word_index==GROUP_WORDS-1||word[512];
    // Complete groups are at least two words apart. Excluding ready_i from
    // the final gather enable preserves full-rate groups with a ready sink;
    // a release from backpressure can cost one clock, not a slower steady II.
    wire word_ready=!final_word||!output_valid||(!FULL_GROUPS_ONLY&&ready_i);
    // word_valid is asynchronously cleared by rrst and cannot be set until
    // the local read pipeline restarts. Its registered validity already
    // excludes reset; repeating rrst here drives a wide gather CE network.
    // Keep rrst on external valid/ready, BRAM fetch and pointer ownership.
    wire consume=word_valid&&word_ready;
    wire take=valid_i&&ready_o;
    wire [AW:0] wn=wb+take,wgn=(wn>>1)^wn;
    wire empty=rg==ws2;
    // Two elastic read stages allow the BRAM output register to hold a
    // stalled word while its internal read latch holds the next word.
    wire word_load=!word_valid||word_ready;
    wire fetch=rrst&&(!prefetch_valid||word_load)&&!empty;
    wire [AW:0] rn=rb+fetch,rgn=(rn>>1)^rn;
    assign ready_o=wrst&&!full;
    assign valid_o=rrst&&output_valid;
    always @(posedge write_clk)if(take)last_memory[wb[AW-1:0]]<=last_i;
    always @(posedge read_clk)begin
        if(fetch)last_prefetch<=last_memory[rb[AW-1:0]];
        if(rrst&&word_load)last_word<=last_prefetch;
    end
    qwen35_ingress_sdp_mem #(.WIDTH(512),.ADDR_W(AW),.COMPACT_RAM(0),.PIPELINED_READ(1)) payload(
        .write_clk(write_clk),.read_clk(read_clk),.write_enable(take),.read_enable(fetch),
        .output_enable(rrst&&word_load),
        .write_address(wb[AW-1:0]),.read_address(rb[AW-1:0]),
        .write_data(data_i),.read_data(word[511:0]));
    always @(posedge write_clk or negedge wrst)begin
        if(!wrst)begin wb<=0;wg<=0;rs1<=0;rs2<=0;full<=0;end
        else begin
            rs1<=rg;rs2<=rs1;wb<=wn;wg<=wgn;
            full<=wgn=={~rs2[AW:AW-1],rs2[AW-2:0]};
        end
    end
    always @(posedge read_clk or negedge rrst)begin
        if(!rrst)begin rb<=0;rg<=0;ws1<=0;ws2<=0;prefetch_valid<=0;word_valid<=0;output_valid<=0;word_index<=0;end
        else begin
            ws1<=wg;ws2<=ws1;rb<=rn;rg<=rgn;
            if(!prefetch_valid||word_load)prefetch_valid<=!empty;
            if(word_load)word_valid<=prefetch_valid;
            if(output_valid&&ready_i)output_valid<=0;
            if(consume)begin
                if(final_word)begin
                    output_valid<=1;word_index<=0;
                end else word_index<=word_index+1'b1;
            end
        end
    end
    // Unreset payload. Only valid/count expose initialized words. Fixed word
    // enables and zero padding avoid a variable 2048-bit insert/shift network.
    generate if(FULL_GROUPS_ONLY)begin:fixed_gather
        // Matrix/Head require complete groups and already reject count != G.
        // For malformed short groups only count/last are meaningful; the
        // parent reports format_error. Complete groups use fixed wiring.
        reg [(GROUP_WORDS-1)*512-1:0] gathered;
        wire [(GROUP_WORDS-1)*512-1:0] shifted={word[511:0],gathered}>>512;
        wire [GROUP_WORDS*512-1:0] assembled={word[511:0],gathered};
        // One preserved enable leaf per32 data bits. No extra FIFO cycle.
        for(genvar part=0;part<(GROUP_WORDS-1)*16;part=part+1)begin:g_gather_leaf
            wire local_write;
            (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b10)) enable_leaf(.I0(consume),.O(local_write));
            always @(posedge read_clk)if(local_write)gathered[part*32+:32]<=shifted[part*32+:32];
        end
        for(genvar part=0;part<GROUP_WORDS*16;part=part+1)begin:g_output_leaf
            wire local_write;
            (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b10)) enable_leaf(.I0(consume&&final_word),.O(local_write));
            always @(posedge read_clk)if(local_write)data_o[part*32+:32]<=assembled[part*32+:32];
        end
    end else begin:padded_gather
    for(genvar g=0;g<GROUP_WORDS;g=g+1)begin:assembly
        for(genvar part=0;part<16;part=part+1)begin:g_payload_leaf
            if(g<GROUP_WORDS-1)begin:partial
                wire local_stage;
                (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b10)) enable_leaf(
                    .I0(consume&&!final_word&&word_index==g),.O(local_stage));
                always @(posedge read_clk)if(local_stage)
                    staging[g][part*32+:32]<=word[part*32+:32];
            end
            wire local_output;
            (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b10)) output_leaf(.I0(consume&&final_word),.O(local_output));
            always @(posedge read_clk)if(local_output)begin
                if(word_index==g)data_o[g*512+part*32+:32]<=word[part*32+:32];
                else if(word_index<g)data_o[g*512+part*32+:32]<=0;
                else if(g<GROUP_WORDS-1)data_o[g*512+part*32+:32]<=staging[g][part*32+:32];
            end
        end
    end
    end endgenerate
    always @(posedge read_clk)if(consume&&final_word)begin
        count_o<={1'b0,word_index}+1'b1;last_o<=word[512];
    end
    initial if(ADDR_W<2||(GROUP_WORDS!=2&&GROUP_WORDS!=4))$fatal(1,"Q7_WORD_GROUP_FIFO_CONFIG");
endmodule
