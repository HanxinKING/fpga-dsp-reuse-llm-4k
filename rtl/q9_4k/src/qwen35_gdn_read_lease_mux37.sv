`timescale 1ns/1ps
// Two tagged GDN commands may be outstanding. Each response is authorized by
// the oldest complete command identity, not by the latest selected producer.
module qwen35_gdn_read_lease_mux37(
    input wire clk,reset_n,flush_i,
    input wire s_req_valid_i,output wire s_req_ready_o,
    input wire [63:0] s_req_addr_i,input wire [4:0] s_req_beats_i,
    output wire s_valid_o,input wire s_ready_i,output wire [511:0] s_data_o,output wire s_last_o,s_error_o,
    input wire c_req_valid_i,output wire c_req_ready_o,
    input wire [63:0] c_req_addr_i,input wire [4:0] c_req_beats_i,
    output wire c_valid_o,input wire c_ready_i,output wire [511:0] c_data_o,output wire c_last_o,c_error_o,
    output wire m_req_valid_o,input wire m_req_ready_i,
    output wire [63:0] m_req_addr_o,output wire [4:0] m_req_beats_o,output wire [31:0] m_req_tag_o,
    input wire m_valid_i,output wire m_ready_o,input wire [511:0] m_data_i,
    input wire [31:0] m_tag_i,input wire m_last_i,m_error_i,m_idle_i,
    output wire [1:0] active_owner_o,output reg [3:0] status_o=0
);
    reg command_hold=0,held_cache=0,cancel_wait=0,flush_seen=0;
    reg [31:0] held_tag;
    reg [63:0] held_address;
    reg [4:0] held_beats;
    reg [15:0] epoch=0;reg [14:0] ticket=0;
    reg [31:0] tags[0:1];reg [4:0] remaining[0:1];
    reg write_pointer=0,read_pointer=0;reg [1:0] count=0;
    // A bad response is blocked combinationally at this authority boundary.
    // Consumers receive a registered error event; they never need to traverse
    // AXI VALID -> tag/LAST comparison -> history READY -> restore checking.
    reg sequence_error48=0;
    wire choose_cache=command_hold?held_cache:c_req_valid_i;
    wire selected_valid=choose_cache?c_req_valid_i:s_req_valid_i;
    wire oldest_cache=tags[read_pointer][0];
    wire sequence_bad=m_valid_i&&count!=0&&
        (m_tag_i!=tags[read_pointer]||(m_last_i!=(remaining[read_pointer]==1)));
    wire effective_flush=flush_i||m_error_i||sequence_bad;
    wire response_allowed=reset_n&&!effective_flush&&!cancel_wait&&count!=0&&!sequence_bad;
    assign s_valid_o=response_allowed&&!oldest_cache&&m_valid_i;
    assign c_valid_o=response_allowed&&oldest_cache&&m_valid_i;
    assign s_data_o=m_data_i;assign c_data_o=m_data_i;
    // The valid handshake authorizes each consumer. LAST, like DATA/TAG,
    // remains payload and is immaterial on an invalid response cycle.
    assign s_last_o=m_last_i;assign c_last_o=m_last_i;
    assign s_error_o=m_error_i||sequence_error48;assign c_error_o=s_error_o;
    assign m_ready_o=reset_n&&(effective_flush||cancel_wait||sequence_bad||
        (count!=0&&(oldest_cache?c_ready_i:s_ready_i)));
    wire response_take=m_valid_i&&m_ready_o&&response_allowed;
    wire response_last=response_take&&m_last_i;
    // Use registered credit only. Borrowing response_last propagated a
    // consumer's ready/error cone back through both request arbiters.
    wire command_room=count<2;
    // Register the selected descriptor before exposing it to the AXI queue.
    // This is a request boundary, not early acceptance: each producer retains
    // VALID until the real downstream handshake and cancellation still drains
    // all previously accepted commands. One launch cycle is added per burst.
    assign m_req_valid_o=reset_n&&!effective_flush&&!cancel_wait&&command_room&&command_hold&&selected_valid;
    assign m_req_addr_o=held_address;
    assign m_req_beats_o=held_beats;
    assign m_req_tag_o=held_tag;
    assign s_req_ready_o=reset_n&&!effective_flush&&!cancel_wait&&command_room&&command_hold&&!held_cache&&m_req_ready_i;
    assign c_req_ready_o=reset_n&&!effective_flush&&!cancel_wait&&command_room&&command_hold&&held_cache&&m_req_ready_i;
    assign active_owner_o=count==0?2'd0:oldest_cache?2'd2:2'd1;
    wire command_take=m_req_valid_o&&m_req_ready_i;
    always @(posedge clk)begin
        if(!reset_n)begin
            command_hold<=0;held_cache<=0;cancel_wait<=0;flush_seen<=0;epoch<=0;ticket<=0;sequence_error48<=0;
            write_pointer<=0;read_pointer<=0;count<=0;status_o<=0;
        end else begin
            flush_seen<=effective_flush;
            sequence_error48<=!flush_i&&!m_error_i&&!cancel_wait&&sequence_bad;
            if(!effective_flush&&!cancel_wait&&command_room&&selected_valid&&!command_hold)begin
                command_hold<=1;held_cache<=choose_cache;held_tag<={epoch,ticket,choose_cache};
                held_address<=choose_cache?c_req_addr_i:s_req_addr_i;
                held_beats<=choose_cache?c_req_beats_i:s_req_beats_i;
            end
            if(command_hold&&!selected_valid&&!effective_flush)status_o[2]<=1;
            case({command_take,response_last})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:;
            endcase
            if(command_take)begin
                command_hold<=0;tags[write_pointer]<=m_req_tag_o;remaining[write_pointer]<=m_req_beats_o;
                write_pointer<=!write_pointer;ticket<=ticket+1'b1;
                if(m_req_beats_o==0||m_req_beats_o>16)status_o[0]<=1;
            end
            if(response_take)begin
                if(response_last)read_pointer<=!read_pointer;
                else remaining[read_pointer]<=remaining[read_pointer]-1'b1;
            end
            if(sequence_bad&&!cancel_wait)status_o[3]<=1;
            if(m_valid_i&&count==0&&!cancel_wait&&!effective_flush)status_o[1]<=1;
            if(effective_flush)begin
                command_hold<=0;cancel_wait<=1;count<=0;write_pointer<=0;read_pointer<=0;
                if(!flush_seen)epoch<=epoch+1'b1;
                if(flush_i)status_o<=0;
            end else if(cancel_wait&&m_idle_i)cancel_wait<=0;
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk)if(reset_n&&!effective_flush&&!cancel_wait)begin
        if(count>2)$fatal(1,"GDN37_READ_LEASE_CREDIT");
        if(sequence_bad&&(s_valid_o||c_valid_o))$fatal(1,"GDN48_BAD_RESPONSE_PUBLISHED");
    end
`endif
endmodule
