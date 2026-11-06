// 3B GENERATED CANDIDATE: not admitted for board use.
`timescale 1ns / 1ps

// Clock-domain bridge for a 512-bit AXI read channel.  The 16-entry request
// FIFO supports the model path's eight outstanding bursts; request and
// response payloads cross through independent XPM asynchronous FIFOs, so no
// multi-bit bus is sampled directly.
module axi512_single_read_cdc (
    input  logic         core_clk,
    input  logic         core_reset_n,
    input  logic [3:0]   core_arid,
    input  logic [33:0]  core_araddr,
    input  logic [7:0]   core_arlen,
    input  logic [2:0]   core_arsize,
    input  logic [1:0]   core_arburst,
    input  logic         core_arlock,
    input  logic [3:0]   core_arcache,
    input  logic [2:0]   core_arprot,
    input  logic [3:0]   core_arqos,
    input  logic         core_arvalid,
    output logic         core_arready,
    output logic [3:0]   core_rid,
    output logic [511:0] core_rdata,
    output logic [1:0]   core_rresp,
    output logic         core_rlast,
    output logic         core_rvalid,
    input  logic         core_rready,

    input  logic         ui_clk,
    input  logic         ui_reset_n,
    output logic [3:0]   ui_arid,
    output logic [33:0]  ui_araddr,
    output logic [7:0]   ui_arlen,
    output logic [2:0]   ui_arsize,
    output logic [1:0]   ui_arburst,
    output logic         ui_arlock,
    output logic [3:0]   ui_arcache,
    output logic [2:0]   ui_arprot,
    output logic [3:0]   ui_arqos,
    output logic         ui_arvalid,
    input  logic         ui_arready,
    input  logic [3:0]   ui_rid,
    input  logic [511:0] ui_rdata,
    input  logic [1:0]   ui_rresp,
    input  logic         ui_rlast,
    input  logic         ui_rvalid,
    output logic         ui_rready
);
    localparam integer REQ_WIDTH=63;
    localparam integer RESP_WIDTH=519;
    logic [REQ_WIDTH-1:0] req_din,req_dout; logic req_full,req_empty;
    logic [RESP_WIDTH-1:0] resp_din,resp_dout; logic resp_full,resp_empty;
    logic req_wr_rst_busy,req_rd_rst_busy;
    logic resp_wr_rst_busy,resp_rd_rst_busy;

    assign req_din={core_arid,core_araddr,core_arlen,core_arsize,
        core_arburst,core_arlock,core_arcache,core_arprot,core_arqos};
    assign {ui_arid,ui_araddr,ui_arlen,ui_arsize,ui_arburst,ui_arlock,
        ui_arcache,ui_arprot,ui_arqos}=req_dout;
    // XPM FIFO reset is synchronous to its write clock.  The request FIFO is
    // written by core_clk, whereas the response FIFO is written by ui_clk.
    // Giving both FIFOs the OR of two unrelated resets creates an unsafe
    // combinational reset CDC and makes the internal XPM reset FSM a timed
    // core_clk-to-ui_clk path.  Each FIFO therefore receives only the reset
    // that is synchronous to its own write clock.  The XPM reset handshake
    // propagates that state safely to the corresponding read clock domain.
    assign core_arready=core_reset_n&&!req_wr_rst_busy&&!req_full;
    assign ui_arvalid=ui_reset_n&&!req_rd_rst_busy&&!req_empty;

    assign resp_din={ui_rid,ui_rdata,ui_rresp,ui_rlast};
    wire [RESP_WIDTH-1:0] buffered_response;
    wire response_input_ready;
    wire response_input_valid=core_reset_n&&!resp_rd_rst_busy&&!resp_empty;
    assign {core_rid,core_rdata,core_rresp,core_rlast}=buffered_response;
    // Only registered occupancy reaches the XPM FIFO output enable. The
    // existing asynchronous FIFO, ownership and reset handshake are retained.
    qwen7b_read_response_buffer #(.WIDTH(RESP_WIDTH)) core_response(
        .clk(core_clk),.reset_n(core_reset_n&&!resp_rd_rst_busy),
        .valid_i(response_input_valid),.ready_o(response_input_ready),.data_i(resp_dout),
        .valid_o(core_rvalid),.ready_i(core_rready),.data_o(buffered_response));
    assign ui_rready=ui_reset_n&&!resp_wr_rst_busy&&!resp_full;

    xpm_fifo_async #(
        // Keep the shallow request queue local to the CDC control logic.
        .FIFO_MEMORY_TYPE("distributed"),.ECC_MODE("no_ecc"),
        .RELATED_CLOCKS(0),.FIFO_WRITE_DEPTH(16),
        .WRITE_DATA_WIDTH(REQ_WIDTH),.READ_DATA_WIDTH(REQ_WIDTH),
        .WR_DATA_COUNT_WIDTH(5),.RD_DATA_COUNT_WIDTH(5),
        .PROG_FULL_THRESH(10),.PROG_EMPTY_THRESH(5),
        .CDC_SYNC_STAGES(2),.READ_MODE("fwft"),.FIFO_READ_LATENCY(0),
        .FULL_RESET_VALUE(0),.DOUT_RESET_VALUE("0"),
        .USE_ADV_FEATURES("0000"),.WAKEUP_TIME(0),.SIM_ASSERT_CHK(0)
    ) request_fifo(
        .rst(!core_reset_n),.wr_clk(core_clk),.wr_en(core_arvalid&&core_arready),
        .din(req_din),.full(req_full),.rd_clk(ui_clk),
        .rd_en(ui_arvalid&&ui_arready),.dout(req_dout),.empty(req_empty),
        .wr_rst_busy(req_wr_rst_busy),.rd_rst_busy(req_rd_rst_busy),
        .sleep(1'b0),.injectsbiterr(1'b0),.injectdbiterr(1'b0));

    xpm_fifo_async #(
        // A 16x519 response queue is shallow and very wide.  Distributed
        // storage keeps its registered output beside the core consumers;
        // the former auto-selected BRAM created a 512-bit cross-device route.
        .FIFO_MEMORY_TYPE("distributed"),.ECC_MODE("no_ecc"),
        .RELATED_CLOCKS(0),.FIFO_WRITE_DEPTH(16),
        .WRITE_DATA_WIDTH(RESP_WIDTH),.READ_DATA_WIDTH(RESP_WIDTH),
        .WR_DATA_COUNT_WIDTH(5),.RD_DATA_COUNT_WIDTH(5),
        .PROG_FULL_THRESH(10),.PROG_EMPTY_THRESH(5),
        .CDC_SYNC_STAGES(2),.READ_MODE("fwft"),.FIFO_READ_LATENCY(0),
        .FULL_RESET_VALUE(0),.DOUT_RESET_VALUE("0"),
        .USE_ADV_FEATURES("0000"),.WAKEUP_TIME(0),.SIM_ASSERT_CHK(0)
    ) response_fifo(
        .rst(!ui_reset_n),.wr_clk(ui_clk),.wr_en(ui_rvalid&&ui_rready),
        .din(resp_din),.full(resp_full),.rd_clk(core_clk),
        .rd_en(response_input_valid&&response_input_ready),.dout(resp_dout),.empty(resp_empty),
        .wr_rst_busy(resp_wr_rst_busy),.rd_rst_busy(resp_rd_rst_busy),
        .sleep(1'b0),.injectsbiterr(1'b0),.injectdbiterr(1'b0));
endmodule

// Two core-domain entries decouple consumer RREADY from the 519-bit CDC
// output register. Capacity depends only on registered occupancy, never on
// RREADY lookahead. One initial clock is added; sustained transfer II is one.
// Shared qwen7b_read_response_buffer is defined once in the explicitly bound
// rtl/q9_int4_dep/qwen7b_read_response_buffer.sv (identical admitted body).

