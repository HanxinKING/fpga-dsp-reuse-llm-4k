`timescale 1ns/1ps
// Single-clock response buffer. Payload RAM is never reset; valid/count are
// reset instead. A registered synchronous read maps the wide payload to BRAM.
module qwen_sync_block_fifo #(
    parameter integer WIDTH=515, ADDR_W=8
)(
    input wire clk, reset_n,
    input wire in_valid, output wire in_ready,
    input wire [WIDTH-1:0] in_data,
    output reg out_valid=0, input wire out_ready,
    output reg [WIDTH-1:0] out_data,
    output wire [ADDR_W:0] occupancy
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    localparam integer DEPTH=1<<ADDR_W;
    (* ram_style="block" *) reg [WIDTH-1:0] mem[0:DEPTH-1];
    reg [ADDR_W-1:0] wp=0,rp=0;
    reg [ADDR_W:0] count=0;
    wire take_mem=(count!=0)&&(!out_valid||out_ready);
    wire push=in_valid&&in_ready;
    // Protocol state still resets normally. Writes made while reset is
    // asserted are never published; removing reset here localizes BRAM EN.
    wire payload_write=in_valid&&(count<DEPTH);
    assign in_ready=reset_n&&(count<DEPTH);
    assign occupancy=count+out_valid;
    always @(posedge clk) begin
        if(payload_write) mem[wp]<=in_data;
        if(take_mem) out_data<=mem[rp];
        if(q9_local_reset_active) begin wp<=0;rp<=0;count<=0;out_valid<=0;end
        else begin
            if(push) wp<=wp+1'b1;
            if(take_mem) begin rp<=rp+1'b1;out_valid<=1;end
            else if(out_ready) out_valid<=0;
            case({push,take_mem})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
        end
    end
endmodule
