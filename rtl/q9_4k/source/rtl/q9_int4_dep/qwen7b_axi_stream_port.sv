`timescale 1ns/1ps
// One physical DDR stream port: core-domain descriptor -> UI-domain AXI reader
// -> UI-domain payload (to an async data FIFO), with coherent completion counters
// returning to core. Instantiate independently for PL and PS; no shared output.
module qwen7b_axi_stream_port #(parameter integer OUTSTANDING=8,MAX_BEATS=64)(
    output wire [159:0] perf_counts_o,
    input wire core_clk,ui_clk,reset_n,
    input wire cmd_valid,output wire cmd_ready,input wire [33:0] cmd_base,
    input wire [31:0] cmd_words,cmd_tile_words,
    output wire stream_valid,input wire stream_ready,output wire [511:0] stream_data,output wire stream_last,
    output wire result_valid,input wire result_ready,output wire [3:0] result_status,
    output wire [31:0] result_cycles,result_requests,result_received,result_peak,
    output wire [3:0] m_axi_arid,output wire [33:0] m_axi_araddr,output wire [7:0] m_axi_arlen,
    output wire [2:0] m_axi_arsize,output wire [1:0] m_axi_arburst,output wire m_axi_arlock,
    output wire [3:0] m_axi_arcache,output wire [2:0] m_axi_arprot,output wire [3:0] m_axi_arqos,
    output wire m_axi_arvalid,input wire m_axi_arready,
    input wire [3:0] m_axi_rid,input wire [511:0] m_axi_rdata,input wire [1:0] m_axi_rresp,
    input wire m_axi_rlast,m_axi_rvalid,output wire m_axi_rready
);
    wire uirst,cv,cr,reader_ready,reader_done,result_source_ready;wire [97:0] command;
    wire [3:0] status;wire [31:0] cycles,requests,received,peak;
    wire [291:0] completion;
    wire reader_busy;
    reg [39:0] perf_ui[0:3];
    reg [5:0] pending_reads=0;
    reg inside_burst=0;
    wire ar_take=m_axi_arvalid&&m_axi_arready;
    wire r_take=m_axi_rvalid&&m_axi_rready;
    wire [3:0] perf_ui_events={pending_reads!=0&&inside_burst&&!m_axi_rvalid,
        pending_reads!=0&&!inside_burst&&!m_axi_rvalid,
        m_axi_rvalid&&!m_axi_rready,m_axi_arvalid&&!m_axi_arready};
    always @(posedge ui_clk)begin
        if(!uirst||cv&&cr)begin
            pending_reads<=0;inside_burst<=0;
            for(integer n=0;n<4;n++)perf_ui[n]<=0;
        end else begin
            case({ar_take,r_take&&m_axi_rlast})
                2'b10:pending_reads<=pending_reads+1'b1;
                2'b01:pending_reads<=pending_reads-1'b1;
                default:begin end
            endcase
            if(r_take)inside_burst<=!m_axi_rlast;
            if(reader_busy)for(integer n=0;n<4;n++)
                if(perf_ui_events[n]&&!(&perf_ui[n]))perf_ui[n]<=perf_ui[n]+40'd1;
        end
    end
    xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0)) ru(
        .src_arst(reset_n),.dest_clk(ui_clk),.dest_arst(uirst));
    qwen7b_command_cdc #(.WIDTH(98)) requests_cdc(
        .source_clk(core_clk),.dest_clk(ui_clk),.reset_n(reset_n),
        .source_valid(cmd_valid),.source_ready(cmd_ready),.source_data({cmd_base,cmd_words,cmd_tile_words}),
        .dest_valid(cv),.dest_ready(cr),.dest_data(command));
    // Reserve the completion mailbox before starting a new transfer. The
    // reader_done cycle is excluded so it cannot overwrite an undelivered result.
    assign cr=reader_ready&&result_source_ready&&!reader_done;
    qwen_shared_axi_weight_reader #(.OUTSTANDING(OUTSTANDING),.MAX_BEATS(MAX_BEATS)) reader(
        .clk(ui_clk),.reset_n(uirst),.start_i(cv&&cr),.start_ready_o(reader_ready),
        .base_i(command[97:64]),.words_i(command[63:32]),.tile_words_i(command[31:0]),
        .valid_o(stream_valid),.ready_i(stream_ready),.data_o(stream_data),.last_o(stream_last),
        .busy_o(reader_busy),.done_o(reader_done),.status_o(status),.cycles_o(cycles),.requests_o(requests),
        .received_o(received),.peak_outstanding_o(peak),
        .m_axi_arid(m_axi_arid),.m_axi_araddr(m_axi_araddr),.m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),.m_axi_arburst(m_axi_arburst),.m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),.m_axi_arprot(m_axi_arprot),.m_axi_arqos(m_axi_arqos),
        .m_axi_arvalid(m_axi_arvalid),.m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),.m_axi_rdata(m_axi_rdata),.m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),.m_axi_rvalid(m_axi_rvalid),.m_axi_rready(m_axi_rready));
    qwen7b_command_cdc #(.WIDTH(292)) completion_cdc(
        .source_clk(ui_clk),.dest_clk(core_clk),.reset_n(reset_n),
        .source_valid(reader_done),.source_ready(result_source_ready),.source_data({perf_ui[3],perf_ui[2],perf_ui[1],perf_ui[0],status,cycles,requests,received,peak}),
        .dest_valid(result_valid),.dest_ready(result_ready),.dest_data(completion));
    assign {perf_counts_o,result_status,result_cycles,result_requests,result_received,result_peak}=completion;
`ifndef SYNTHESIS
    always @(posedge ui_clk)if(uirst&&reader_done&&!result_source_ready)$fatal(1,"Q7_AXI_COMPLETION_OVERFLOW");
`endif
endmodule
