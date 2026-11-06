// 3B GENERATED CANDIDATE: not admitted for board use.
`timescale 1ns / 1ps

// Single-outstanding AXI4 write CDC for a 512-bit MIG port.  AW, W and B use
// independent XPM asynchronous FIFOs.  The UI side does not expose WVALID
// until the corresponding AW has been accepted and keeps transaction
// ownership until its B response has crossed back to the core clock.
module axi512_single_write_cdc (
    input  logic core_clk,
    input  logic core_reset_n,
    input  logic [3:0] core_awid,
    input  logic [33:0] core_awaddr,
    input  logic [7:0] core_awlen,
    input  logic [2:0] core_awsize,
    input  logic [1:0] core_awburst,
    input  logic core_awlock,
    input  logic [3:0] core_awcache,
    input  logic [2:0] core_awprot,
    input  logic [3:0] core_awqos,
    input  logic core_awvalid,
    output logic core_awready,
    input  logic [511:0] core_wdata,
    input  logic [63:0] core_wstrb,
    input  logic core_wlast,
    input  logic core_wvalid,
    output logic core_wready,
    output logic [3:0] core_bid,
    output logic [1:0] core_bresp,
    output logic core_bvalid,
    input  logic core_bready,

    input  logic ui_clk,
    input  logic ui_reset_n,
    output logic [3:0] ui_awid,
    output logic [33:0] ui_awaddr,
    output logic [7:0] ui_awlen,
    output logic [2:0] ui_awsize,
    output logic [1:0] ui_awburst,
    output logic ui_awlock,
    output logic [3:0] ui_awcache,
    output logic [2:0] ui_awprot,
    output logic [3:0] ui_awqos,
    output logic ui_awvalid,
    input  logic ui_awready,
    output logic [511:0] ui_wdata,
    output logic [63:0] ui_wstrb,
    output logic ui_wlast,
    output logic ui_wvalid,
    input  logic ui_wready,
    input  logic [3:0] ui_bid,
    input  logic [1:0] ui_bresp,
    input  logic ui_bvalid,
    output logic ui_bready
);
    localparam integer AW_WIDTH = 63;
    localparam integer W_WIDTH = 577;
    localparam integer B_WIDTH = 6;
    logic [AW_WIDTH-1:0] aw_din, aw_dout;
    logic [W_WIDTH-1:0] w_din, w_dout;
    logic [B_WIDTH-1:0] b_din, b_dout;
    logic aw_full, aw_empty, w_full, w_empty, b_full, b_empty;
    logic aw_wr_rst_busy, aw_rd_rst_busy;
    logic w_wr_rst_busy, w_rd_rst_busy;
    logic b_wr_rst_busy, b_rd_rst_busy;
    logic ui_transaction_active = 1'b0;
    logic w_pipe_valid = 1'b0;
    logic [W_WIDTH-1:0] w_pipe_payload;
    logic w_pipe_push, w_pipe_pop;

    assign aw_din = {core_awid, core_awaddr, core_awlen, core_awsize,
        core_awburst, core_awlock, core_awcache, core_awprot, core_awqos};
    assign {ui_awid, ui_awaddr, ui_awlen, ui_awsize, ui_awburst,
        ui_awlock, ui_awcache, ui_awprot, ui_awqos} = aw_dout;
    // A one-entry elastic register terminates the arbiter grant/data mux
    // before the wide distributed FIFO.  It sustains one beat per core clock
    // through simultaneous pop/push.  The 577-bit payload is intentionally
    // not reset; w_pipe_valid is the only state that controls consumption.
    assign w_din = w_pipe_payload;
    assign {ui_wdata, ui_wstrb, ui_wlast} = w_dout;
    assign b_din = {ui_bid, ui_bresp};
    assign {core_bid, core_bresp} = b_dout;

    assign core_awready = core_reset_n && !aw_wr_rst_busy && !aw_full;
    assign w_pipe_pop = w_pipe_valid && !w_wr_rst_busy && !w_full;
    assign core_wready = core_reset_n && !w_wr_rst_busy
        && (!w_pipe_valid || !w_full);
    assign w_pipe_push = core_wvalid && core_wready;
    assign core_bvalid = core_reset_n && !b_rd_rst_busy && !b_empty;
    assign ui_awvalid = ui_reset_n && !ui_transaction_active
        && !aw_rd_rst_busy && !aw_empty;
    assign ui_wvalid = ui_reset_n && ui_transaction_active
        && !w_rd_rst_busy && !w_empty;
    assign ui_bready = ui_reset_n && ui_transaction_active
        && !b_wr_rst_busy && !b_full;

    always_ff @(posedge core_clk) begin
        if (!core_reset_n) begin
            w_pipe_valid <= 1'b0;
        end else begin
            case ({w_pipe_push, w_pipe_pop})
                2'b10: w_pipe_valid <= 1'b1;
                2'b01: w_pipe_valid <= 1'b0;
                default: w_pipe_valid <= w_pipe_valid;
            endcase
        end
    end
    // T80: load on every CORE_WREADY edge, not on WVALID&&WREADY. With
    // WREADY high the entry is either empty or popped on this same edge
    // (WREADY&&w_pipe_valid implies !w_full&&!w_wr_rst_busy), and without a
    // push w_pipe_valid falls, so a non-push load is never observed. The
    // client's WVALID decode leaves the 577-bit CE; WREADY already has reset.
    always_ff @(posedge core_clk)
        if (core_wready)
            w_pipe_payload <= {core_wdata, core_wstrb, core_wlast};

    always_ff @(posedge ui_clk) begin
        if (!ui_reset_n)
            ui_transaction_active <= 1'b0;
        else begin
            if (ui_awvalid && ui_awready)
                ui_transaction_active <= 1'b1;
            if (ui_bvalid && ui_bready)
                ui_transaction_active <= 1'b0;
        end
    end

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("auto"), .ECC_MODE("no_ecc"), .RELATED_CLOCKS(0),
        .FIFO_WRITE_DEPTH(16), .WRITE_DATA_WIDTH(AW_WIDTH),
        .READ_DATA_WIDTH(AW_WIDTH), .WR_DATA_COUNT_WIDTH(5),
        .RD_DATA_COUNT_WIDTH(5), .PROG_FULL_THRESH(10),
        .PROG_EMPTY_THRESH(5), .CDC_SYNC_STAGES(2), .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0), .FULL_RESET_VALUE(0), .DOUT_RESET_VALUE("0"),
        .USE_ADV_FEATURES("0000"), .WAKEUP_TIME(0), .SIM_ASSERT_CHK(0)
    ) aw_fifo (
        .rst(!core_reset_n), .wr_clk(core_clk),
        .wr_en(core_awvalid && core_awready), .din(aw_din), .full(aw_full),
        .rd_clk(ui_clk), .rd_en(ui_awvalid && ui_awready), .dout(aw_dout),
        .empty(aw_empty), .wr_rst_busy(aw_wr_rst_busy),
        .rd_rst_busy(aw_rd_rst_busy), .sleep(1'b0),
        .injectsbiterr(1'b0), .injectdbiterr(1'b0));

    // 32x577 is shallow enough for LUTRAM.  Keeping it in BRAM costs about
    // 8.5 RAMB36 per instance and needlessly crowds the local compute banks.
    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("distributed"), .ECC_MODE("no_ecc"), .RELATED_CLOCKS(0),
        .FIFO_WRITE_DEPTH(32), .WRITE_DATA_WIDTH(W_WIDTH),
        .READ_DATA_WIDTH(W_WIDTH), .WR_DATA_COUNT_WIDTH(6),
        .RD_DATA_COUNT_WIDTH(6), .PROG_FULL_THRESH(24),
        .PROG_EMPTY_THRESH(5), .CDC_SYNC_STAGES(2), .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0), .FULL_RESET_VALUE(0), .DOUT_RESET_VALUE("0"),
        .USE_ADV_FEATURES("0000"), .WAKEUP_TIME(0), .SIM_ASSERT_CHK(0)
    ) w_fifo (
        .rst(!core_reset_n), .wr_clk(core_clk),
        .wr_en(w_pipe_pop), .din(w_din), .full(w_full),
        .rd_clk(ui_clk), .rd_en(ui_wvalid && ui_wready), .dout(w_dout),
        .empty(w_empty), .wr_rst_busy(w_wr_rst_busy),
        .rd_rst_busy(w_rd_rst_busy), .sleep(1'b0),
        .injectsbiterr(1'b0), .injectdbiterr(1'b0));

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("auto"), .ECC_MODE("no_ecc"), .RELATED_CLOCKS(0),
        .FIFO_WRITE_DEPTH(16), .WRITE_DATA_WIDTH(B_WIDTH),
        .READ_DATA_WIDTH(B_WIDTH), .WR_DATA_COUNT_WIDTH(5),
        .RD_DATA_COUNT_WIDTH(5), .PROG_FULL_THRESH(10),
        .PROG_EMPTY_THRESH(5), .CDC_SYNC_STAGES(2), .READ_MODE("fwft"),
        .FIFO_READ_LATENCY(0), .FULL_RESET_VALUE(0), .DOUT_RESET_VALUE("0"),
        .USE_ADV_FEATURES("0000"), .WAKEUP_TIME(0), .SIM_ASSERT_CHK(0)
    ) b_fifo (
        .rst(!ui_reset_n), .wr_clk(ui_clk),
        .wr_en(ui_bvalid && ui_bready), .din(b_din), .full(b_full),
        .rd_clk(core_clk), .rd_en(core_bvalid && core_bready), .dout(b_dout),
        .empty(b_empty), .wr_rst_busy(b_wr_rst_busy),
        .rd_rst_busy(b_rd_rst_busy), .sleep(1'b0),
        .injectsbiterr(1'b0), .injectdbiterr(1'b0));
endmodule
