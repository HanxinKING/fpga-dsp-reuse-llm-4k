`timescale 1ns/1ps
// Two-entry elastic buffer. Only occupancy and pointers publish payload.
module qwen7b_read_response_buffer #(parameter integer WIDTH=519)(
    input wire clk,reset_n,valid_i,output wire ready_o,input wire [WIDTH-1:0] data_i,
    output wire valid_o,input wire ready_i,output wire [WIDTH-1:0] data_o
);
    // Local, same-polarity reset inversion: duplicate the short LUT leaf near
    // its sinks rather than route one inverted reset across distant regions.
    (* KEEP="TRUE",MAX_FANOUT=32 *) wire q9_local_reset_active=!reset_n;

    reg [1:0] count=0;
    (* MAX_FANOUT=64 *) reg read_bank=0;
    reg write_bank=0;
    reg [WIDTH-1:0] bank0,bank1;
    wire push=valid_i&&ready_o,pop=valid_o&&ready_i;
    assign ready_o=reset_n&&count<2;
    assign valid_o=reset_n&&count!=0;
    assign data_o=read_bank?bank1:bank0;
    always @(posedge clk)begin
        // A free slot is private until the original push commits it. Capture
        // speculatively to remove reset/valid from the wide payload CE; no
        // accepted beat or backpressure timing changes.
        // Payload writes use the equivalent local leaves below.
        if(q9_local_reset_active)begin count<=0;read_bank<=0;write_bank<=0;end
        else begin
            if(push)write_bank<=!write_bank;
            if(pop)read_bank<=!read_bank;
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
        end
    end
    for(genvar l66=0;l66<(WIDTH+31)/32;l66++)begin:g_capture66
        localparam integer W=(WIDTH-l66*32>=32)?32:WIDTH-l66*32;
        wire cap0,cap1;
        (* DONT_TOUCH="TRUE" *) LUT2 #(.INIT(4'h1)) leaf0(.I0(count[1]),.I1(write_bank),.O(cap0));
        (* DONT_TOUCH="TRUE" *) LUT2 #(.INIT(4'h4)) leaf1(.I0(count[1]),.I1(write_bank),.O(cap1));
        always @(posedge clk)begin
            if(cap0)bank0[l66*32+:W]<=data_i[l66*32+:W];
            if(cap1)bank1[l66*32+:W]<=data_i[l66*32+:W];
        end
    end
    // synthesis translate_off
    always @(posedge clk)if(reset_n&&count>2)$fatal(1,"Q7_READ_RESPONSE_OVERFLOW");
    // synthesis translate_on
endmodule
