`timescale 1ns/1ps
// Bundled-data command mailbox, not a payload-per-bit synchronizer.
// Source holds the payload until destination capture is acknowledged. The
// destination can hold its output while one further command waits at source.
// Integration requires a bounded physical delay/skew on payload_hold ->
// payload_out; do not blanket-false-path those data nets in the board XDC.
module qwen35_command_cdc #(parameter integer WIDTH=98)(
    input wire source_clk,dest_clk,reset_n,
    input wire source_valid,output wire source_ready,input wire [WIDTH-1:0] source_data,
    output wire dest_valid,input wire dest_ready,output wire [WIDTH-1:0] dest_data
);
    wire srst,drst;
    xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) rs(
        .src_arst(reset_n),.dest_clk(source_clk),.dest_arst(srst));
    xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) rd(
        .src_arst(reset_n),.dest_clk(dest_clk),.dest_arst(drst));
    reg request=0,acknowledge=0,output_valid=0;
    (* ASYNC_REG="TRUE" *) reg ack1=0,ack2=0,req1=0,req2=0;
    reg [WIDTH-1:0] payload_hold,payload_out;
    assign source_ready=srst&&ack2==request;
    assign dest_valid=drst&&output_valid;assign dest_data=payload_out;
    always @(posedge source_clk or negedge srst)begin
        if(!srst)begin request<=0;ack1<=0;ack2<=0;end
        else begin
            ack1<=acknowledge;ack2<=ack1;
            if(source_valid&&source_ready)request<=~request;
        end
    end
    always @(posedge source_clk)if(source_valid&&source_ready)payload_hold<=source_data;
    always @(posedge dest_clk or negedge drst)begin
        if(!drst)begin acknowledge<=0;req1<=0;req2<=0;output_valid<=0;end
        else begin
            req1<=request;req2<=req1;
            if(output_valid&&dest_ready)output_valid<=0;
            if(!output_valid&&req2!=acknowledge)begin output_valid<=1;acknowledge<=req2;end
        end
    end
    always @(posedge dest_clk)if(drst&&!output_valid&&req2!=acknowledge)payload_out<=payload_hold;
endmodule
