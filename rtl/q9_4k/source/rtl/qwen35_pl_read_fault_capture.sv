`timescale 1ns/1ps
// Passive ordered PL read observer. No signal returns to the AXI datapath.
// The arbiter admits only one source epoch at a time; model reads use one ID.
// Overflow, missing descriptors, or inconsistent ID/source/LAST invalidate
// association until reset. The first non-OKAY response is immutable until reset.
module qwen35_pl_read_fault_capture #(
    parameter integer DEPTH=8
)(
    input wire clk,reset_n,
    input wire arvalid,arready,
    input wire [33:0] araddr,
    input wire [7:0] arlen,
    input wire [2:0] arsize,
    input wire [3:0] arid,
    input wire [1:0] arsource,
    input wire arsource_valid,
    input wire rvalid,rready,
    input wire [1:0] rresp,
    input wire [3:0] rid,
    input wire rlast,
    input wire [1:0] rsource,
    output logic [255:0] snapshot_o
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    localparam integer PW=$clog2(DEPTH);
    // {source_valid, source, ID, size, len, address}: 52 bits.
    (* ram_style="registers" *) logic [51:0] descriptors [0:DEPTH-1];
    logic [PW-1:0] wp,rp;
    logic [PW:0] count;
    logic [7:0] beat;
    logic frozen,overflow_seen,underflow_seen,tracking_lost;
    logic [31:0] ar_count,r_count;
    wire ar_fire=arvalid&&arready;
    wire r_fire=rvalid&&rready;
    wire [51:0] incoming={arsource_valid,arsource,arid,arsize,arlen,araddr};
    // Also support a legal zero-latency response on an empty queue.
    wire have_desc=(count!=0)||ar_fire;
    wire [51:0] head=(count!=0)?descriptors[rp]:incoming;
    wire [7:0] head_beat=(count!=0)?beat:8'd0;
    wire pop=r_fire&&rlast&&have_desc;
    wire overflow_now=ar_fire&&(count==DEPTH)&&!pop;
    wire push=ar_fire&&!overflow_now;
    wire underflow_now=r_fire&&!have_desc;
    wire id_bad=have_desc&&(rid!=head[48:45]);
    wire source_bad=have_desc&&(!head[51]||rsource!=head[50:49]);
    wire last_bad=have_desc&&(rlast!=(head_beat==head[41:34]));
    wire association_valid=have_desc&&!tracking_lost&&!overflow_now&&
                           !id_bad&&!source_bad&&!last_bad;
    always_ff @(posedge clk) begin
        if(q9_local_reset_active) begin
            wp<=0;rp<=0;count<=0;beat<=0;frozen<=0;
            overflow_seen<=0;underflow_seen<=0;tracking_lost<=0;
            ar_count<=0;r_count<=0;
            snapshot_o<={224'd0,32'h51394131};
        end else if(!frozen) begin
            if(ar_fire)ar_count<=ar_count+1'b1;
            if(r_fire)r_count<=r_count+1'b1;
            if(push)begin descriptors[wp]<=incoming;wp<=wp+1'b1;end
            if(pop)rp<=rp+1'b1;
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
            if(r_fire&&have_desc)beat<=rlast?8'd0:head_beat+1'b1;
            if(overflow_now)overflow_seen<=1;
            if(underflow_now)underflow_seen<=1;
            if(overflow_now||underflow_now||
               (r_fire&&(id_bad||source_bad||last_bad)))tracking_lost<=1;
            if(r_fire&&rresp!=2'b00)begin
                frozen<=1;
                // Word 1: valid, descriptor present, trustworthy association,
                // overflow, underflow, ID/source/LAST mismatch, prior tracking
                // loss, descriptor source-valid; outstanding count at [19:16].
                snapshot_o[63:32]<=32'd1|({31'd0,have_desc}<<1)|
                    ({31'd0,association_valid}<<2)|
                    ({31'd0,(overflow_seen||overflow_now)}<<3)|
                    ({31'd0,(underflow_seen||underflow_now)}<<4)|
                    ({31'd0,id_bad}<<5)|({31'd0,source_bad}<<6)|
                    ({31'd0,last_bad}<<7)|({31'd0,tracking_lost}<<8)|
                    ({31'd0,(have_desc&&head[51])}<<9)|(32'(count)<<16);
                snapshot_o[95:64]<=have_desc?head[31:0]:32'd0;
                // Word 3: address[33:32], ARLEN[15:8], ARSIZE[18:16],
                // ARID[23:20], source[25:24], source valid[26].
                snapshot_o[127:96]<=have_desc?
                    {5'd0,head[51],head[50:49],head[48:45],1'b0,
                     head[44:42],head[41:34],6'd0,head[33:32]}:32'd0;
                // Word 4 preserves raw RRESP, RID, RLAST, beat and source.
                snapshot_o[159:128]<={6'd0,rsource,head_beat,7'd0,rlast,rid,2'd0,rresp};
                snapshot_o[191:160]<=ar_count+32'(ar_fire);
                snapshot_o[223:192]<=r_count+32'd1;
                snapshot_o[255:224]<=0;
            end
        end
    end
    initial if(DEPTH<2||(DEPTH&(DEPTH-1))!=0||DEPTH>8)
        $fatal(1,"PL_FAULT_CAPTURE_DEPTH");
endmodule
