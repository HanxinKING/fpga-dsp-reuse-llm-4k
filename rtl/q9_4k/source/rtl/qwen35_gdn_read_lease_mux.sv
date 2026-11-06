`timescale 1ns/1ps
// Two clients of the existing serialized GDN state-AXI read service.
// Hold a stalled command's selected producer; hold accepted ownership through
// the final consumed response beat. There is no extra data buffer or AXI master.
module qwen35_gdn_read_lease_mux (
    input wire clk,reset_n,
    input wire s_req_valid_i,output wire s_req_ready_o,
    input wire [63:0] s_req_addr_i,input wire [4:0] s_req_beats_i,
    output wire s_valid_o,input wire s_ready_i,output wire [511:0] s_data_o,
    input wire c_req_valid_i,output wire c_req_ready_o,
    input wire [63:0] c_req_addr_i,input wire [4:0] c_req_beats_i,
    output wire c_valid_o,input wire c_ready_i,output wire [511:0] c_data_o,
    output wire m_req_valid_o,input wire m_req_ready_i,
    output wire [63:0] m_req_addr_o,output wire [4:0] m_req_beats_o,
    input wire m_valid_i,output wire m_ready_o,input wire [511:0] m_data_i,
    output wire [1:0] active_owner_o,
    output logic [3:0] status_o
);
    logic leased,owner_cache,command_hold,held_cache;
    logic [4:0] remaining;
    wire select_cache=command_hold?held_cache:c_req_valid_i;
    wire selected_valid=select_cache?c_req_valid_i:s_req_valid_i;
    assign m_req_valid_o=!leased&&selected_valid;
    assign m_req_addr_o=select_cache?c_req_addr_i:s_req_addr_i;
    assign m_req_beats_o=select_cache?c_req_beats_i:s_req_beats_i;
    assign s_req_ready_o=!leased&&!select_cache&&m_req_ready_i;
    assign c_req_ready_o=!leased&&select_cache&&m_req_ready_i;
    assign s_valid_o=leased&&!owner_cache&&m_valid_i;
    assign c_valid_o=leased&&owner_cache&&m_valid_i;
    assign s_data_o=m_data_i;
    assign c_data_o=m_data_i;
    assign m_ready_o=leased&&(owner_cache?c_ready_i:s_ready_i);
    assign active_owner_o=leased?(owner_cache?2'd2:2'd1):2'd0;
    wire command_fire=m_req_valid_o&&m_req_ready_i;
    wire response_fire=m_valid_i&&m_ready_o;
    always_ff @(posedge clk)begin
        if(!reset_n)begin
            leased<=0;owner_cache<=0;command_hold<=0;held_cache<=0;remaining<=0;status_o<=0;
        end else begin
            if(!leased&&m_req_valid_o&&!m_req_ready_i)begin
                command_hold<=1;held_cache<=select_cache;
            end
            if(command_hold&&!selected_valid)status_o[2]<=1;
            if(command_fire)begin
                command_hold<=0;leased<=1;owner_cache<=select_cache;
                remaining<=m_req_beats_o;
                if(m_req_beats_o==0||m_req_beats_o>16)status_o[0]<=1;
            end
            // The existing state-AXI service has a request/AR stage, so it
            // cannot return a response on the command-accept edge itself.
            if(m_valid_i&&!leased)status_o[1]<=1;
            if(response_fire)begin
                if(remaining==1)begin leased<=0;remaining<=0;end
                else remaining<=remaining-1'b1;
            end
        end
    end
endmodule
