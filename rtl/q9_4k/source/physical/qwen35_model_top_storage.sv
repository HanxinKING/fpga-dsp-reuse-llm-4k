`timescale 1ns/1ps
// Generated board base map.  A header, not `set_property generic`, because
// LM_HEAD_PL_BASE is 0x10849C000 -- a 34-bit value -- and passing that through
// the TCL generic property as a string risks a tool-side parse of a value wider
// than 32 bits.  A missing or stale header is a compile error instead of a
// silent zero.  See scripts/New-Qwen35BoardBaseHeader.ps1.
`include "qwen35_board_bases.svh"
// Qwen3.5-9B board candidate; board acceptance still requires measured
// generation. Physical PS/MIG/DCI/pins are inherited from the verified
// Sidewinder shell; the compute path is qwen35_hybrid_board_core.
// The resource-priority candidate selects Fold 2; generic 1 is the same
// source with the full-width DOT. Only the selected branch is synthesized.
//
// Defaults come from the generated header.  HEAD_*_BASE, ATT_O_*_BASE and
// FFN_*_BASES deliberately stay ZERO: the attention Q/K/V/O and FFN bases are
// per-layer ROM tables inside qwen35_hybrid_board_core, which fails elaboration
// if a legacy scalar is set.
module qwen35_model_top #(
    parameter integer CONV_COEFF_DDR=QWEN35_BOARD_CONV_COEFF_DDR,
    parameter logic[63:0]GDN_COEFF_BASE={30'd0,QWEN35_BOARD_GDN_COEFF_BASE},
    parameter integer INT4_DOT_FOLD=1, GAMMA_DDR=1, GAMMA_PREFETCH=1,ROPE_DDR=1,
    parameter[33:0]ROPE_DDR_BASE=34'h1F3780000,
    parameter [33:0] GAMMA_DDR_BASE=QWEN35_BOARD_GAMMA_BASE,
    parameter [33:0] EMBEDDING_BASE=QWEN35_BOARD_EMBEDDING_BASE,
    parameter [33:0] HEAD_PL_BASE=34'd0,
    parameter [33:0] HEAD_PS_BASE=34'd0,
    parameter [33:0] LM_HEAD_PL_BASE=QWEN35_BOARD_LM_HEAD_PL_BASE,
    parameter [33:0] LM_HEAD_PS_BASE=QWEN35_BOARD_LM_HEAD_PS_BASE,
    parameter integer LM_HEAD_ROWS=QWEN35_BOARD_LM_HEAD_ROWS,
    parameter [33:0] ATT_RAW_BASE=QWEN35_BOARD_ATT_RAW_BASE,
    parameter [33:0] ATT_CODE_BASE=QWEN35_BOARD_ATT_CODE_BASE,
    parameter [33:0] ATT_PARAM_BASE=QWEN35_BOARD_ATT_PARAM_BASE,
    parameter [33:0] ATT_O_PL_BASE=34'd0,
    parameter [33:0] ATT_O_PS_BASE=34'd0,
    parameter [33:0] ATT_EXTREMA_BASE=QWEN35_BOARD_ATT_EXTREMA_BASE,
    parameter [101:0] FFN_PL_BASES=102'd0,
    parameter [101:0] FFN_PS_BASES=102'd0,
    parameter integer ATT_VALID_TOKENS=QWEN35_BOARD_ATT_VALID_TOKENS,
    parameter integer ATT_TOKEN_BASE=QWEN35_BOARD_ATT_TOKEN_BASE,
    // Each 32-bit recurrence beat occupies four 512-bit DDR beats: 48 MiB
    // over 24 layers.  Convolution history (24 x 96 KiB) starts at +48 MiB
    // inside the 50.25 MiB GDN_STATE region after the Q7-style raw KV tail.
    // The +36 MiB / 40 MiB numbers were the 18-bit-era geometry and were
    // stale for STATE_W=32: layers 18..23 collided with conv history and
    // crossed the old region end into ATT_CODE.
    parameter [63:0] GDN_REC_BASE = {30'd0, QWEN35_BOARD_GDN_STATE_BASE},
    parameter [63:0] GDN_CV_BASE  = {30'd0, (QWEN35_BOARD_GDN_STATE_BASE + 34'h0300_0000)}
) (
    input  wire        c0_sys_clk_p,
    input  wire        c0_sys_clk_n,
    output wire [16:0] c0_ddr4_adr,
    output wire [1:0]  c0_ddr4_ba,
    output wire [0:0]  c0_ddr4_bg,
    output wire [0:0]  c0_ddr4_cke,
    output wire [0:0]  c0_ddr4_cs_n,
    output wire [0:0]  c0_ddr4_odt,
    output wire        c0_ddr4_reset_n,
    output wire        c0_ddr4_act_n,
    output wire [0:0]  c0_ddr4_ck_c,
    output wire [0:0]  c0_ddr4_ck_t,
    inout  wire [7:0]  c0_ddr4_dm_dbi_n,
    inout  wire [63:0] c0_ddr4_dq,
    inout  wire [7:0]  c0_ddr4_dqs_c,
    inout  wire [7:0]  c0_ddr4_dqs_t,
    output wire        led0,
    output wire        led1,
    output wire        led2,
    output wire        led3
);
    // Evaluates the generated header's consistency checks at elaboration
    // (runtime regions must not overlap the weight region or leave PL).
    qwen35_board_bases_check bases_check();
    wire ui_clk,ui_clk_sync_rst; wire aresetn=~ui_clk_sync_rst;
    // T76 (port of T73 U2, which was edited in the unused rtl/ top): fabric
    // UI reset tree. One synchronous ui_clk register after the MIG
    // ui_clk_sync_rst, one root per consumer group. Fabric UI logic enters and
    // leaves reset one ui_clk after the MIG, BD bridge, clock wizard and the
    // MIG R landing slice, which keep aresetn. Roots may be replicated.
    //   [0] counters/window/snapshot CDCs [1] ps_reader [2] read arbiter
    //   [3] write arbiter [4] raw read/write CDC [5] PL read fault capture
    (* KEEP="TRUE",MAX_FANOUT=64 *) reg [5:0] ui_fabric_reset_n=6'd0;
    always @(posedge ui_clk) ui_fabric_reset_n<={6{aresetn}};
    // Use the verified nominal Sidewinder Clock Wizard output for the compute
    // path.  This candidate does not add a local divider; the diagnostics stay
    // in the same nominal clock domain as the model and control logic.
    wire core_clk,core_clk_locked;
    wire core_async_reset_n=aresetn&&core_clk_locked;
    wire core_reset_n;
    // The XPM synchronizer is DONT_TOUCH, so its final stage cannot be
    // replicated to drive the whole model.  Replicable local stages keep the
    // synchronous release contract while breaking the global reset fanout.
    (* DONT_TOUCH="TRUE",max_fanout=64 *) logic accelerator_reset_n=1'b0;
    (* DONT_TOUCH="TRUE",max_fanout=64 *) logic read_fabric_reset_n=1'b0;
    (* DONT_TOUCH="TRUE",max_fanout=64 *) logic control_reset_n=1'b0;
    wire init_calib_complete,cfgmclk,startup_eos,dci_reset,dci_locked,dci_ready,mig_sys_rst;
    wire init_calib_complete_core,dci_locked_core,dci_ready_core;
    wire address_window_error_core;

    wire [36:0] ps_awaddr,ps_araddr; wire [1:0] ps_awburst,ps_arburst;
    wire [3:0] ps_awcache,ps_arcache; wire [7:0] ps_awlen,ps_arlen;
    wire ps_awlock,ps_arlock; wire [2:0] ps_awprot,ps_arprot;
    wire [3:0] ps_awqos,ps_arqos; wire [2:0] ps_awsize,ps_arsize;
    wire [15:0] ps_awuser,ps_aruser; wire ps_awvalid,ps_awready;
    wire [511:0] ps_wdata,ps_rdata; wire [63:0] ps_wstrb;
    wire ps_wlast,ps_wvalid,ps_wready,ps_bready,ps_bvalid;
    wire [1:0] ps_bresp; wire ps_arvalid,ps_arready,ps_rlast,ps_rready,ps_rvalid;
    wire [1:0] ps_rresp;

    wire [3:0] runtime_awid,runtime_bid; wire [33:0] runtime_awaddr;
    wire [7:0] runtime_awlen; wire [2:0] runtime_awsize;
    wire [1:0] runtime_awburst; wire runtime_awlock;
    wire [3:0] runtime_awcache,runtime_awqos; wire [2:0] runtime_awprot;
    wire runtime_awvalid,runtime_awready; wire [511:0] runtime_wdata;
    wire [63:0] runtime_wstrb; wire runtime_wlast,runtime_wvalid,runtime_wready;
    wire [1:0] runtime_bresp; wire runtime_bvalid,runtime_bready;

    wire [31:0] ctrl_awaddr,ctrl_araddr,ctrl_wdata,ctrl_rdata;
    wire [1:0] ctrl_awburst,ctrl_arburst,ctrl_bresp,ctrl_rresp;
    wire [3:0] ctrl_awcache,ctrl_arcache,ctrl_awqos,ctrl_arqos,ctrl_wstrb;
    wire [7:0] ctrl_awlen,ctrl_arlen; wire ctrl_awlock,ctrl_arlock;
    wire [2:0] ctrl_awprot,ctrl_arprot,ctrl_awsize,ctrl_arsize;
    wire [15:0] ctrl_awuser,ctrl_aruser; wire ctrl_awvalid,ctrl_awready;
    wire ctrl_wlast,ctrl_wvalid,ctrl_wready,ctrl_bready,ctrl_bvalid;
    wire ctrl_arvalid,ctrl_arready,ctrl_rlast,ctrl_rready,ctrl_rvalid;

    wire [3:0] model_arid,model_rid; wire [33:0] model_araddr;
    wire dual_enable_core,dual_enable_ui;
    wire [127:0] dual_stats_core;
    wire [31:0] dual_pl_beats,dual_ps_beats,dual_overlap;
    wire [7:0] dual_errors;
    wire [3:0] hp_errors;
    wire [199:0] bank_araddr;wire [39:0] bank_arlen;
    wire [4:0] bank_arvalid,bank_arready,bank_rvalid,bank_rready,bank_rlast;
    wire [2559:0] bank_rdata;wire [9:0] bank_rresp;
    wire [159:0] hp_araddr;wire [31:0] hp_arlen;
    wire [3:0] hp_arvalid,hp_arready,hp_rvalid,hp_rready,hp_rlast;
    wire [511:0] hp_rdata;wire [7:0] hp_rresp;
    wire [7:0] model_arlen; wire [2:0] model_arsize;
    wire [1:0] model_arburst; wire model_arlock;
    wire [3:0] model_arcache,model_arqos; wire [2:0] model_arprot;
    wire model_arready,model_arvalid; wire [511:0] model_rdata;
    wire model_rlast;
    wire [31:0] kv_araddr; wire [1:0] kv_arburst;
    wire [3:0] kv_arcache; wire [5:0] kv_arid;
    wire [3:0] kv_arlen; wire [1:0] kv_arlock;
    wire [2:0] kv_arprot,kv_arsize;
    wire [3:0] kv_arqos; wire kv_arready,kv_arvalid;
    wire [63:0] kv_rdata; wire [5:0] kv_rid; wire kv_rlast;
    wire model_rready,kv_rready; wire [1:0] model_rresp,kv_rresp;
    wire model_rvalid,kv_rvalid;

    wire [3:0] mig_arid,mig_rid,mig_awid,mig_bid; wire [33:0] mig_araddr,mig_awaddr;
    wire [7:0] mig_arlen; wire [2:0] mig_arsize; wire [1:0] mig_arburst;
    wire mig_arlock; wire [3:0] mig_arcache,mig_arqos; wire [2:0] mig_arprot;
    wire mig_arvalid,mig_arready,mig_rlast,mig_rvalid,mig_rready;
    wire [511:0] mig_rdata; wire [1:0] mig_rresp;
    wire [7:0] mig_awlen; wire [2:0] mig_awsize; wire [1:0] mig_awburst;
    wire mig_awlock; wire [3:0] mig_awcache,mig_awqos; wire [2:0] mig_awprot;
    wire mig_awvalid,mig_awready; wire [511:0] mig_wdata; wire [63:0] mig_wstrb;
    wire mig_wlast,mig_wvalid,mig_wready,mig_bready,mig_bvalid;
    wire [1:0] mig_bresp;
    wire [31:0] ps_write_tx,runtime_write_tx,ps_write_beats,runtime_write_beats;
    wire [7:0] write_arb_status;

    wire [31:0] ps_tx,model_tx,kv_tx,ps_beats,model_beats,kv_beats;
    wire [31:0] ps_wait,model_wait,kv_wait,model_wide,kv_wide;
    wire [7:0] fabric_status;
    wire perf_clear,perf_enable,perf_snapshot,perf_snapshot_valid;
    wire [32*64-1:0] perf_snapshot_words;
    logic address_window_error=1'b0;

    wire sparse_busy,sparse_done,sparse_out_valid; wire [31:0] sparse_total_cycles;
    wire [31:0] sparse_stage1_cycles,sparse_attention_cycles,sparse_axi_bytes;
    wire [31:0] sparse_axi_bursts,sparse_cache_saved,sparse_prefetch_overlap;
    wire [15:0] sparse_cache_hits; wire [127:0] sparse_selected0,sparse_selected1;
    wire [7:0] sparse_status; wire [3:0] sparse_out_head;
    wire [6:0] sparse_out_dim; wire signed [15:0] sparse_out_data;


    localparam EXP_ROM="exp.mem",GAMMA_ROM="gamma.mem",DESCRIPTOR_ROM="descriptor.mem";
    localparam COS_ROM="q9_rope_cos_q14.mem",SIN_ROM="q9_rope_sin_q14.mem";
    wire cfg_write,cfg_ready;wire[9:0] cfg_address;wire[31:0] cfg_data;
    wire[63:0] full_cycles,first_token_cycles;wire[17:0] last_token;wire[13:0] position;wire[4:0] layer;
    wire[7:0] quant_warning_flags;wire[31:0] quant_warning_events;
    wire [511:0] fault_snapshot;
    // Keep all compute reset sinks on the same noninverting distribution
    // network. Automatic promotion previously left a 691-sink CE cone on
    // the unbuffered source register. CE is constant, so this adds no reset
    // qualification edge and preserves synchronous assertion/release.
    wire reset_n;
    wire[19:0]reset_parts49_n;
    qwen35_compute_reset49 #(.PARTS(20)) reset_partition49(
        .clk(core_clk),.core_reset_n(core_reset_n),.reset_parts_n(reset_parts49_n));
    (* DONT_TOUCH="TRUE" *) BUFGCE #(.CE_TYPE("ASYNC"),
        .IS_CE_INVERTED(1'b0),.IS_I_INVERTED(1'b0)) accelerator_reset_n_BUFG_inst(
        .I(accelerator_reset_n),.CE(1'b1),.O(reset_n));
wire[31:0] prefix_cycles;
wire[31:0] attention_cycles;
wire[31:0] o_cycles;
wire[31:0] ffn_cycles;
wire[31:0] attention_count;
wire[31:0] o_count;
wire[31:0] ffn_count;

    wire start,start_ready,busy,done;wire[5:0] phase;wire[13:0] debug_addr;wire[31:0] debug_data;
    wire[1:0]m_rvalid,m_rready;
    wire bw_start65,bw_done65;wire[31:0]bw_data65;
    reg[13:0]bw_debug_addr65;
    always @(posedge core_clk)bw_debug_addr65<=debug_addr;
    wire bw_select65=bw_debug_addr65>=14'd673&&bw_debug_addr65<14'd704;
    wire[31:0]mmio_debug65=bw_select65?bw_data65:debug_data;


    wire[7:0] q9_hp_errors;wire[31:0] board_errors;
wire [31:0] status;
wire [31:0] cycles;
wire [31:0] run_id;
wire [31:0] qkv_cycles;
wire [31:0] write_cycles;
wire [31:0] read_cycles;
wire [31:0] output_count;
wire [31:0] raw_count;
wire [31:0] pl_words;
wire [31:0] ps_words;
wire [31:0] write_bytes;
wire [31:0] read_bytes;
wire [31:0] qkv_checksum;
wire [31:0] raw_checksum;
wire [7:0] m_arid;
wire [67:0] m_araddr;
wire [15:0] m_arlen;
wire [5:0] m_arsize;
wire [3:0] m_arburst;
wire [1:0] m_arlock;
wire [7:0] m_arcache;
wire [5:0] m_arprot;
wire [7:0] m_arqos;
wire [1:0] m_arvalid;
wire [1:0] m_arready;
wire [7:0] m_rid;
wire [1023:0] m_rdata;
wire [3:0] m_rresp;
wire [1:0] m_rlast;


wire [3:0] raw_awid;
wire [33:0] raw_awaddr;
wire [7:0] raw_awlen;
wire [2:0] raw_awsize;
wire [1:0] raw_awburst;
wire raw_awvalid;
wire raw_awready;
wire [511:0] raw_wdata;
wire [63:0] raw_wstrb;
wire raw_wlast;
wire raw_wvalid;
wire raw_wready;
wire [3:0] raw_bid;
wire [1:0] raw_bresp;
wire raw_bvalid;
wire raw_bready;
wire [3:0] raw_arid;
wire [33:0] raw_araddr;
wire [7:0] raw_arlen;
wire [2:0] raw_arsize;
wire [1:0] raw_arburst;
wire raw_arvalid;
wire raw_arready;
wire [3:0] raw_rid;
wire [511:0] raw_rdata;
wire [1:0] raw_rresp;
wire raw_rlast;
wire raw_rvalid;
wire raw_rready;
wire [3:0] raw_ui_arid;
wire [33:0] raw_ui_araddr;
wire [7:0] raw_ui_arlen;
wire [2:0] raw_ui_arsize;
wire [1:0] raw_ui_arburst;
wire raw_ui_arvalid;
wire raw_ui_arready;
wire [3:0] raw_ui_rid;
wire [511:0] raw_ui_rdata;
wire [1:0] raw_ui_rresp;
wire raw_ui_rlast;
wire raw_ui_rvalid;
wire raw_ui_rready;
wire raw_ui_arlock;
wire [3:0] raw_ui_arcache;
wire [2:0] raw_ui_arprot;
wire [3:0] raw_ui_arqos;

    assign led0=init_calib_complete;
    assign led1=dci_ready;
    assign led2=busy;
    assign led3=(status!=0)||(board_errors!=0);
    assign ctrl_rlast=ctrl_rvalid;

    STARTUPE3 #(.PROG_USR("FALSE"),.SIM_CCLK_FREQ(0.0)) u_startupe3(
        .CFGCLK(),.CFGMCLK(cfgmclk),.DI(),.EOS(startup_eos),.PREQ(),
        .DO(4'b0),.DTS(4'hf),.FCSBO(1'b0),.FCSBTS(1'b1),.GSR(1'b0),
        .GTS(1'b0),.KEYCLEARB(1'b1),.PACK(1'b0),.USRCCLKO(1'b0),
        .USRCCLKTS(1'b1),.USRDONEO(1'b1),.USRDONETS(1'b1));
    sidewinder_dci_startup_ctrl #(.RESET_CYCLES(16)) dci_ctrl(
        .cfgmclk_i(cfgmclk),.eos_i(startup_eos),.dci_locked_i(dci_locked),
        .dci_reset_o(dci_reset),.mig_sys_rst_o(mig_sys_rst),.ready_o(dci_ready));
    DCIRESET dci_primitive(.LOCKED(dci_locked),.RST(dci_reset));
    sidewinder_core_clk_wiz core_clock(
        .clk_in1(ui_clk),.reset(!aresetn),.clk_out1(core_clk),.locked(core_clk_locked));

    // The MIG UI reset and Clock Wizard lock are asynchronous to core_clk.
    // XPM_CDC_ASYNC_RST asserts reset immediately and releases it only after
    // three clean core clock edges, while also installing the matching CDC
    // timing exception on the asynchronous assertion path.
    xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),
        .RST_ACTIVE_HIGH(0)) core_reset_cdc(
        .src_arst(core_async_reset_n),.dest_clk(core_clk),
        .dest_arst(core_reset_n));

    always_ff @(posedge core_clk) begin
        if(!core_reset_n) begin
            accelerator_reset_n<=1'b0;
            read_fabric_reset_n<=1'b0;
            control_reset_n<=1'b0;
        end else begin
            accelerator_reset_n<=1'b1;
            read_fabric_reset_n<=1'b1;
            control_reset_n<=1'b1;
        end
    end

    // Synchronize UI/CFGMCLK status before sampling it with the core-clocked
    // VIO.  These signals are observability only and are not in the control
    // path, but explicit synchronizers keep CDC signoff and captured values
    // deterministic.
    xpm_cdc_single #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0),.SRC_INPUT_REG(1)) cdc_calib_to_core(
        .src_clk(ui_clk),.src_in(init_calib_complete),.dest_clk(core_clk),
        .dest_out(init_calib_complete_core));
    xpm_cdc_single #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0),.SRC_INPUT_REG(1)) cdc_dci_locked_to_core(
        .src_clk(cfgmclk),.src_in(dci_locked),.dest_clk(core_clk),
        .dest_out(dci_locked_core));
    xpm_cdc_single #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0),.SRC_INPUT_REG(1)) cdc_dci_ready_to_core(
        .src_clk(cfgmclk),.src_in(dci_ready),.dest_clk(core_clk),
        .dest_out(dci_ready_core));
    xpm_cdc_single #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0),.SRC_INPUT_REG(1)) cdc_window_error_to_core(
        .src_clk(ui_clk),.src_in(address_window_error),.dest_clk(core_clk),
        .dest_out(address_window_error_core));

    // The read arbiter already registers model-source transaction/beat counts
    // in ui_clk. Count the two weight ports with the same OR-per-cycle
    // semantics as the legacy diagnostic words, then move the packed snapshot
    // through a handshake CDC.  A bitwise CDC of a binary counter could expose
    // a torn value while several bits toggle; the handshake keeps the payload
    // stable until the destination acknowledges it.
    logic [31:0] model_ar_count_ui,model_r_count_ui;
    wire model_ar_event_ui=(m_arvalid[0]&&m_arready[0])||
                           (m_arvalid[1]&&m_arready[1]);
    wire model_r_event_ui=(m_rvalid[0]&&m_rready[0])||
                          (m_rvalid[1]&&m_rready[1]);
    // T76 (port of T72): count registered events (one ui_clk later) so the
    // AXI handshake cone stays off the 64 counter CEs; totals are unchanged.
    logic model_ar_event_q=1'b0,model_r_event_q=1'b0;
    always_ff @(posedge ui_clk) begin
        model_ar_event_q<=model_ar_event_ui;
        model_r_event_q<=model_r_event_ui;
        if(!ui_fabric_reset_n[0]) begin
            model_ar_count_ui<=32'd0;
            model_r_count_ui<=32'd0;
        end else begin
            if(model_ar_event_q) model_ar_count_ui<=model_ar_count_ui+32'd1;
            if(model_r_event_q)  model_r_count_ui<=model_r_count_ui+32'd1;
        end
    end
    wire [63:0] model_activity_snapshot_core;
    wire [31:0] model_ar_count_core,model_r_count_core;
    wire model_activity_update_core;
    qwen35_ui_count_snapshot_cdc #(.WIDTH(64)) model_activity_cdc(
        .ui_clk(ui_clk),.ui_reset_n(ui_fabric_reset_n[0]),
        .ui_value({model_ar_count_ui,model_r_count_ui}),
        .core_clk(core_clk),.core_reset_n(read_fabric_reset_n),
        .core_value(model_activity_snapshot_core),
        .core_update(model_activity_update_core));
    assign model_ar_count_core=model_activity_snapshot_core[63:32];
    assign model_r_count_core=model_activity_snapshot_core[31:0];

    sidewinder_ps_dual_hpm_bridge_wrapper ps_bridge(
        .ui_clk,.aresetn,.ctrl_clk(core_clk),.ctrl_aresetn(control_reset_n),
        .S_AXI_PS0_araddr({9'd0,hp_araddr[0+:40]}),.S_AXI_PS0_arlen(hp_arlen[0+:8]),
        .S_AXI_PS0_arid(6'd0),.S_AXI_PS0_arsize(3'd4),.S_AXI_PS0_arburst(2'b01),
        .S_AXI_PS0_arlock(1'b0),.S_AXI_PS0_arcache(4'b0011),.S_AXI_PS0_arprot(3'b000),
        .S_AXI_PS0_arqos(4'd0),.S_AXI_PS0_aruser(1'b0),
        .S_AXI_PS0_arvalid(hp_arvalid[0]),.S_AXI_PS0_arready(hp_arready[0]),
        .S_AXI_PS0_rdata(hp_rdata[0+:128]),.S_AXI_PS0_rresp(hp_rresp[0+:2]),
        .S_AXI_PS0_rlast(hp_rlast[0]),.S_AXI_PS0_rvalid(hp_rvalid[0]),.S_AXI_PS0_rready(hp_rready[0]),.S_AXI_PS0_rid(),
        .S_AXI_PS0_awaddr(49'd0),.S_AXI_PS0_awlen(8'd0),.S_AXI_PS0_awid(6'd0),
        .S_AXI_PS0_awsize(3'd4),.S_AXI_PS0_awburst(2'b01),.S_AXI_PS0_awlock(1'b0),
        .S_AXI_PS0_awcache(4'b0011),.S_AXI_PS0_awprot(3'd0),.S_AXI_PS0_awqos(4'd0),.S_AXI_PS0_awuser(1'b0),
        .S_AXI_PS0_awvalid(1'b0),.S_AXI_PS0_awready(),.S_AXI_PS0_wdata(128'd0),
        .S_AXI_PS0_wstrb(16'd0),.S_AXI_PS0_wlast(1'b0),.S_AXI_PS0_wvalid(1'b0),.S_AXI_PS0_wready(),
        .S_AXI_PS0_bid(),.S_AXI_PS0_bresp(),.S_AXI_PS0_bvalid(),.S_AXI_PS0_bready(1'b1),
        .S_AXI_PS1_araddr({9'd0,hp_araddr[40+:40]}),.S_AXI_PS1_arlen(hp_arlen[8+:8]),
        .S_AXI_PS1_arid(6'd0),.S_AXI_PS1_arsize(3'd4),.S_AXI_PS1_arburst(2'b01),
        .S_AXI_PS1_arlock(1'b0),.S_AXI_PS1_arcache(4'b0011),.S_AXI_PS1_arprot(3'b000),
        .S_AXI_PS1_arqos(4'd0),.S_AXI_PS1_aruser(1'b0),
        .S_AXI_PS1_arvalid(hp_arvalid[1]),.S_AXI_PS1_arready(hp_arready[1]),
        .S_AXI_PS1_rdata(hp_rdata[128+:128]),.S_AXI_PS1_rresp(hp_rresp[2+:2]),
        .S_AXI_PS1_rlast(hp_rlast[1]),.S_AXI_PS1_rvalid(hp_rvalid[1]),.S_AXI_PS1_rready(hp_rready[1]),.S_AXI_PS1_rid(),
        .S_AXI_PS1_awaddr(49'd0),.S_AXI_PS1_awlen(8'd0),.S_AXI_PS1_awid(6'd0),
        .S_AXI_PS1_awsize(3'd4),.S_AXI_PS1_awburst(2'b01),.S_AXI_PS1_awlock(1'b0),
        .S_AXI_PS1_awcache(4'b0011),.S_AXI_PS1_awprot(3'd0),.S_AXI_PS1_awqos(4'd0),.S_AXI_PS1_awuser(1'b0),
        .S_AXI_PS1_awvalid(1'b0),.S_AXI_PS1_awready(),.S_AXI_PS1_wdata(128'd0),
        .S_AXI_PS1_wstrb(16'd0),.S_AXI_PS1_wlast(1'b0),.S_AXI_PS1_wvalid(1'b0),.S_AXI_PS1_wready(),
        .S_AXI_PS1_bid(),.S_AXI_PS1_bresp(),.S_AXI_PS1_bvalid(),.S_AXI_PS1_bready(1'b1),
        .S_AXI_PS2_araddr({9'd0,hp_araddr[80+:40]}),.S_AXI_PS2_arlen(hp_arlen[16+:8]),
        .S_AXI_PS2_arid(6'd0),.S_AXI_PS2_arsize(3'd4),.S_AXI_PS2_arburst(2'b01),
        .S_AXI_PS2_arlock(1'b0),.S_AXI_PS2_arcache(4'b0011),.S_AXI_PS2_arprot(3'b000),
        .S_AXI_PS2_arqos(4'd0),.S_AXI_PS2_aruser(1'b0),
        .S_AXI_PS2_arvalid(hp_arvalid[2]),.S_AXI_PS2_arready(hp_arready[2]),
        .S_AXI_PS2_rdata(hp_rdata[256+:128]),.S_AXI_PS2_rresp(hp_rresp[4+:2]),
        .S_AXI_PS2_rlast(hp_rlast[2]),.S_AXI_PS2_rvalid(hp_rvalid[2]),.S_AXI_PS2_rready(hp_rready[2]),.S_AXI_PS2_rid(),
        .S_AXI_PS2_awaddr(49'd0),.S_AXI_PS2_awlen(8'd0),.S_AXI_PS2_awid(6'd0),
        .S_AXI_PS2_awsize(3'd4),.S_AXI_PS2_awburst(2'b01),.S_AXI_PS2_awlock(1'b0),
        .S_AXI_PS2_awcache(4'b0011),.S_AXI_PS2_awprot(3'd0),.S_AXI_PS2_awqos(4'd0),.S_AXI_PS2_awuser(1'b0),
        .S_AXI_PS2_awvalid(1'b0),.S_AXI_PS2_awready(),.S_AXI_PS2_wdata(128'd0),
        .S_AXI_PS2_wstrb(16'd0),.S_AXI_PS2_wlast(1'b0),.S_AXI_PS2_wvalid(1'b0),.S_AXI_PS2_wready(),
        .S_AXI_PS2_bid(),.S_AXI_PS2_bresp(),.S_AXI_PS2_bvalid(),.S_AXI_PS2_bready(1'b1),
        .S_AXI_PS3_araddr({9'd0,hp_araddr[120+:40]}),.S_AXI_PS3_arlen(hp_arlen[24+:8]),
        .S_AXI_PS3_arid(6'd0),.S_AXI_PS3_arsize(3'd4),.S_AXI_PS3_arburst(2'b01),
        .S_AXI_PS3_arlock(1'b0),.S_AXI_PS3_arcache(4'b0011),.S_AXI_PS3_arprot(3'b000),
        .S_AXI_PS3_arqos(4'd0),.S_AXI_PS3_aruser(1'b0),
        .S_AXI_PS3_arvalid(hp_arvalid[3]),.S_AXI_PS3_arready(hp_arready[3]),
        .S_AXI_PS3_rdata(hp_rdata[384+:128]),.S_AXI_PS3_rresp(hp_rresp[6+:2]),
        .S_AXI_PS3_rlast(hp_rlast[3]),.S_AXI_PS3_rvalid(hp_rvalid[3]),.S_AXI_PS3_rready(hp_rready[3]),.S_AXI_PS3_rid(),
        .S_AXI_PS3_awaddr(49'd0),.S_AXI_PS3_awlen(8'd0),.S_AXI_PS3_awid(6'd0),
        .S_AXI_PS3_awsize(3'd4),.S_AXI_PS3_awburst(2'b01),.S_AXI_PS3_awlock(1'b0),
        .S_AXI_PS3_awcache(4'b0011),.S_AXI_PS3_awprot(3'd0),.S_AXI_PS3_awqos(4'd0),.S_AXI_PS3_awuser(1'b0),
        .S_AXI_PS3_awvalid(1'b0),.S_AXI_PS3_awready(),.S_AXI_PS3_wdata(128'd0),
        .S_AXI_PS3_wstrb(16'd0),.S_AXI_PS3_wlast(1'b0),.S_AXI_PS3_wvalid(1'b0),.S_AXI_PS3_wready(),
        .S_AXI_PS3_bid(),.S_AXI_PS3_bresp(),.S_AXI_PS3_bvalid(),.S_AXI_PS3_bready(1'b1),
        .M_AXI_DDR_awaddr(ps_awaddr),.M_AXI_DDR_awburst(ps_awburst),
        .M_AXI_DDR_awcache(ps_awcache),.M_AXI_DDR_awlen(ps_awlen),
        .M_AXI_DDR_awlock(ps_awlock),.M_AXI_DDR_awprot(ps_awprot),
        .M_AXI_DDR_awqos(ps_awqos),.M_AXI_DDR_awready(ps_awready),
        .M_AXI_DDR_awsize(ps_awsize),
        .M_AXI_DDR_awvalid(ps_awvalid),.M_AXI_DDR_wdata(ps_wdata),
        .M_AXI_DDR_wlast(ps_wlast),.M_AXI_DDR_wready(ps_wready),
        .M_AXI_DDR_wstrb(ps_wstrb),.M_AXI_DDR_wvalid(ps_wvalid),
        .M_AXI_DDR_bready(ps_bready),.M_AXI_DDR_bresp(ps_bresp),
        .M_AXI_DDR_bvalid(ps_bvalid),.M_AXI_DDR_araddr(ps_araddr),
        .M_AXI_DDR_arburst(ps_arburst),.M_AXI_DDR_arcache(ps_arcache),
        .M_AXI_DDR_arlen(ps_arlen),.M_AXI_DDR_arlock(ps_arlock),
        .M_AXI_DDR_arprot(ps_arprot),.M_AXI_DDR_arqos(ps_arqos),
        .M_AXI_DDR_arready(ps_arready),.M_AXI_DDR_arsize(ps_arsize),
        .M_AXI_DDR_arvalid(ps_arvalid),
        .M_AXI_DDR_rdata(ps_rdata),.M_AXI_DDR_rlast(ps_rlast),
        .M_AXI_DDR_rready(ps_rready),.M_AXI_DDR_rresp(ps_rresp),
        .M_AXI_DDR_rvalid(ps_rvalid),
        .M_AXI_CTRL_awaddr(ctrl_awaddr),.M_AXI_CTRL_awburst(ctrl_awburst),
        .M_AXI_CTRL_awcache(ctrl_awcache),.M_AXI_CTRL_awlen(ctrl_awlen),
        .M_AXI_CTRL_awlock(ctrl_awlock),.M_AXI_CTRL_awprot(ctrl_awprot),
        .M_AXI_CTRL_awqos(ctrl_awqos),.M_AXI_CTRL_awready(ctrl_awready),
        .M_AXI_CTRL_awsize(ctrl_awsize),.M_AXI_CTRL_awuser(ctrl_awuser),
        .M_AXI_CTRL_awvalid(ctrl_awvalid),.M_AXI_CTRL_wdata(ctrl_wdata),
        .M_AXI_CTRL_wlast(ctrl_wlast),.M_AXI_CTRL_wready(ctrl_wready),
        .M_AXI_CTRL_wstrb(ctrl_wstrb),.M_AXI_CTRL_wvalid(ctrl_wvalid),
        .M_AXI_CTRL_bready(ctrl_bready),.M_AXI_CTRL_bresp(ctrl_bresp),
        .M_AXI_CTRL_bvalid(ctrl_bvalid),.M_AXI_CTRL_araddr(ctrl_araddr),
        .M_AXI_CTRL_arburst(ctrl_arburst),.M_AXI_CTRL_arcache(ctrl_arcache),
        .M_AXI_CTRL_arlen(ctrl_arlen),.M_AXI_CTRL_arlock(ctrl_arlock),
        .M_AXI_CTRL_arprot(ctrl_arprot),.M_AXI_CTRL_arqos(ctrl_arqos),
        .M_AXI_CTRL_arready(ctrl_arready),.M_AXI_CTRL_arsize(ctrl_arsize),
        .M_AXI_CTRL_aruser(ctrl_aruser),.M_AXI_CTRL_arvalid(ctrl_arvalid),
        .M_AXI_CTRL_rdata(ctrl_rdata),.M_AXI_CTRL_rlast(ctrl_rlast),
        .M_AXI_CTRL_rready(ctrl_rready),.M_AXI_CTRL_rresp(ctrl_rresp),
        .M_AXI_CTRL_rvalid(ctrl_rvalid));

    qwen35_hybrid_board_core #(.PARTITION_RESET49(1),.SHARED_RAW_READER(1),.CONV_COEFF_DDR(CONV_COEFF_DDR),.GDN_COEFF_BASE(GDN_COEFF_BASE),
        .MAX_TOKENS(4096),.GDN_STREAM37(1),.ROPE_DDR(ROPE_DDR),.ROPE_DDR_BASE(ROPE_DDR_BASE),.MAC_LANES(128),.EXP_ROM(EXP_ROM),.GAMMA_ROM(GAMMA_ROM),.DESCRIPTOR_ROM(DESCRIPTOR_ROM),.COS_ROM(COS_ROM),.SIN_ROM(SIN_ROM),.INT4_DOT_FOLD(INT4_DOT_FOLD),.GAMMA_DDR(GAMMA_DDR),.GAMMA_PREFETCH(GAMMA_PREFETCH),.GAMMA_DDR_BASE(GAMMA_DDR_BASE),.EMBEDDING_BASE(EMBEDDING_BASE),.HEAD_PL_BASE(HEAD_PL_BASE),.HEAD_PS_BASE(HEAD_PS_BASE),.LM_HEAD_PL_BASE(LM_HEAD_PL_BASE),.LM_HEAD_PS_BASE(LM_HEAD_PS_BASE),.LM_HEAD_ROWS(LM_HEAD_ROWS),.FFN_PL_BASES(FFN_PL_BASES),.FFN_PS_BASES(FFN_PS_BASES),.ATT_RAW_BASE(ATT_RAW_BASE),.ATT_CODE_BASE(ATT_CODE_BASE),.ATT_PARAM_BASE(ATT_PARAM_BASE),.ATT_O_PL_BASE(ATT_O_PL_BASE),.ATT_O_PS_BASE(ATT_O_PS_BASE),.ATT_EXTREMA_BASE(ATT_EXTREMA_BASE),.ATT_VALID_TOKENS(ATT_VALID_TOKENS),.ATT_TOKEN_BASE(ATT_TOKEN_BASE),.GDN_REC_BASE(GDN_REC_BASE),.GDN_CV_BASE(GDN_CV_BASE),.STATE_W(32),.STATE_FRAC_W(26),.PRECISE_STATE(1),.WIDE_REDUCTION(1),.CORE_FRAC_W(16)) stage(
        .core_clk(core_clk),.ui_clk(ui_clk),.reset_n(reset_n),.reset_parts49_i(reset_parts49_n[11:0]),.reset_leaf65_i(reset_parts49_n[19:12]),.start_i(start),
        .ui_model_ar_count_i(model_ar_count_core),.ui_model_r_count_i(model_r_count_core),
        .start_ready_o(start_ready),
        .busy_o(busy),.done_o(done),.phase_o(phase),
        .fault_snapshot_o(fault_snapshot),
        .cfg_write_i(cfg_write),.cfg_ready_o(cfg_ready),.cfg_address_i(cfg_address),.cfg_data_i(cfg_data),
        .full_cycles_o(full_cycles),.first_token_cycles_o(first_token_cycles),.last_token_o(last_token),.position_o(position),.layer_o(layer),
        .quant_warning_flags_o(quant_warning_flags),.quant_warning_events_o(quant_warning_events),.bw_start65_o(bw_start65),.bw_done65_o(bw_done65),.debug_addr_i(debug_addr),.debug_data_o(debug_data),
        .prefix_cycles_o(prefix_cycles),.attention_cycles_o(attention_cycles),.o_cycles_o(o_cycles),.ffn_cycles_o(ffn_cycles),.attention_count_o(attention_count),.o_count_o(o_count),.ffn_count_o(ffn_count),.status_o(status),.cycles_o(cycles),.run_id_o(run_id),.qkv_cycles_o(qkv_cycles),.write_cycles_o(write_cycles),.read_cycles_o(read_cycles),.output_count_o(output_count),.raw_count_o(raw_count),.pl_words_o(pl_words),.ps_words_o(ps_words),.write_bytes_o(write_bytes),.read_bytes_o(read_bytes),.qkv_checksum_o(qkv_checksum),.raw_checksum_o(raw_checksum),
.m_arid(m_arid),
.m_araddr(m_araddr),
.m_arlen(m_arlen),
.m_arsize(m_arsize),
.m_arburst(m_arburst),
.m_arlock(m_arlock),
.m_arcache(m_arcache),
.m_arprot(m_arprot),
.m_arqos(m_arqos),
.m_arvalid(m_arvalid),
.m_arready(m_arready),
.m_rid(m_rid),
.m_rdata(m_rdata),
.m_rresp(m_rresp),
.m_rlast(m_rlast),
.m_rvalid(m_rvalid),
.m_rready(m_rready),
.raw_awid(raw_awid),
.raw_awaddr(raw_awaddr),
.raw_awlen(raw_awlen),
.raw_awsize(raw_awsize),
.raw_awburst(raw_awburst),
.raw_awvalid(raw_awvalid),
.raw_awready(raw_awready),
.raw_wdata(raw_wdata),
.raw_wstrb(raw_wstrb),
.raw_wlast(raw_wlast),
.raw_wvalid(raw_wvalid),
.raw_wready(raw_wready),
.raw_bid(raw_bid),
.raw_bresp(raw_bresp),
.raw_bvalid(raw_bvalid),
.raw_bready(raw_bready),
.raw_arid(raw_arid),
.raw_araddr(raw_araddr),
.raw_arlen(raw_arlen),
.raw_arsize(raw_arsize),
.raw_arburst(raw_arburst),
.raw_arvalid(raw_arvalid),
.raw_arready(raw_arready),
.raw_rid(raw_rid),
.raw_rdata(raw_rdata),
.raw_rresp(raw_rresp),
.raw_rlast(raw_rlast),
.raw_rvalid(raw_rvalid),
.raw_rready(raw_rready));
    wire [255:0] pl_read_fault_ui,pl_read_fault_core;
    wire [1:0] pl_read_accepted_source,pl_read_response_source;
    wire pl_read_accepted_source_valid;
    qwen35_pl_read_fault_capture #(.DEPTH(8)) pl_read_fault_capture(
        .clk(ui_clk),.reset_n(ui_fabric_reset_n[5]),
        .arvalid(mig_arvalid),.arready(mig_arready),.araddr(mig_araddr),
        .arlen(mig_arlen),.arsize(mig_arsize),.arid(mig_arid),
        .arsource(pl_read_accepted_source),.arsource_valid(pl_read_accepted_source_valid),
        .rvalid(mig_rvalid),.rready(mig_rready),.rresp(mig_rresp),
        .rid(mig_rid),.rlast(mig_rlast),.rsource(pl_read_response_source),
        .snapshot_o(pl_read_fault_ui));
    // Reuse the counter handshake: the complete immutable fault record is
    // transferred atomically, including its valid flag, to the MMIO domain.
    qwen35_ui_count_snapshot_cdc #(.WIDTH(256),.LOCAL_PAYLOAD_RESETS(1)) pl_read_fault_cdc(
        .ui_clk(ui_clk),.ui_reset_n(ui_fabric_reset_n[0]),.ui_value(pl_read_fault_ui),
        .core_clk(core_clk),.core_reset_n(control_reset_n),
        .core_reset_parent_n(core_reset_n),
        .core_value(pl_read_fault_core),.core_update());
qwen35_model_mmio #(.DETAIL_COUNTERS(CONV_COEFF_DDR?92:82)) control(.clk(core_clk),.reset_n(control_reset_n),
    .pl_read_fault_snapshot_i(pl_read_fault_core),
    .fault_snapshot_i(fault_snapshot),
    .awaddr(ctrl_awaddr[15:0]),.awvalid(ctrl_awvalid),.awready(ctrl_awready),
    .wdata(ctrl_wdata),.wstrb(ctrl_wstrb),.wvalid(ctrl_wvalid),.wready(ctrl_wready),
    .bresp(ctrl_bresp),.bvalid(ctrl_bvalid),.bready(ctrl_bready),
    .araddr(ctrl_araddr[15:0]),.arvalid(ctrl_arvalid),.arready(ctrl_arready),
    .rdata(ctrl_rdata),.rresp(ctrl_rresp),.rvalid(ctrl_rvalid),.rready(ctrl_rready),
    .start_o(start),.start_ready_i(start_ready),.busy_i(busy),.done_i(done),.phase_i(phase),
    .debug_addr_o(debug_addr),.debug_data_i(mmio_debug65),.board_errors_i(board_errors),
    .prefix_cycles_i(prefix_cycles),.attention_cycles_i(attention_cycles),.o_cycles_i(o_cycles),.ffn_cycles_i(ffn_cycles),.attention_count_i(attention_count),.o_count_i(o_count),.ffn_count_i(ffn_count),.cfg_write_o(cfg_write),.cfg_ready_i(cfg_ready),.cfg_address_o(cfg_address),.cfg_data_o(cfg_data),
        .full_cycles_i(full_cycles),.first_token_cycles_i(first_token_cycles),.last_token_i(last_token),.position_i(position),.layer_i(layer),
        .quant_warning_flags_i(quant_warning_flags),.quant_warning_events_i(quant_warning_events),.status_i(status),.cycles_i(cycles),.run_id_i(run_id),.qkv_cycles_i(qkv_cycles),.write_cycles_i(write_cycles),.read_cycles_i(read_cycles),.output_count_i(output_count),.raw_count_i(raw_count),.pl_words_i(pl_words),.ps_words_i(ps_words),.write_bytes_i(write_bytes),.read_bytes_i(read_bytes),.qkv_checksum_i(qkv_checksum),.raw_checksum_i(raw_checksum));
qwen35_ps_read_fabric ps_reader(.clk(ui_clk),.reset_n(ui_fabric_reset_n[1]),
    .s_arid(m_arid[7:4]),.s_araddr(m_araddr[67:34]),.s_arlen(m_arlen[15:8]),.s_arvalid(m_arvalid[1]),.s_arready(m_arready[1]),
    .s_rid(m_rid[7:4]),.s_rdata(m_rdata[1023:512]),.s_rresp(m_rresp[3:2]),.s_rlast(m_rlast[1]),.s_rvalid(m_rvalid[1]),.s_rready(m_rready[1]),
    .m_araddr(hp_araddr),.m_arlen(hp_arlen),.m_arvalid(hp_arvalid),.m_arready(hp_arready),.m_rdata(hp_rdata),.m_rresp(hp_rresp),
    .m_rlast(hp_rlast),.m_rvalid(hp_rvalid),.m_rready(hp_rready),.errors(q9_hp_errors),
    .accepted_requests(),.retired_requests(),.concurrent_response_cycles(),.port_responses());
    xpm_cdc_array_single #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.SRC_INPUT_REG(1),.WIDTH(32)) error_snapshot(
        .src_clk(ui_clk),.src_in({7'd0,address_window_error,q9_hp_errors,write_arb_status,fabric_status}),
        .dest_clk(core_clk),.dest_out(board_errors));
axi512_single_write_cdc raw_write_cdc(.core_clk(core_clk),.core_reset_n(read_fabric_reset_n),.ui_clk(ui_clk),.ui_reset_n(ui_fabric_reset_n[4]),
.core_awid(raw_awid),
.core_awaddr(raw_awaddr),
.core_awlen(raw_awlen),
.core_awsize(raw_awsize),
.core_awburst(raw_awburst),
.core_awvalid(raw_awvalid),
.core_awready(raw_awready),
.core_wdata(raw_wdata),
.core_wstrb(raw_wstrb),
.core_wlast(raw_wlast),
.core_wvalid(raw_wvalid),
.core_wready(raw_wready),
.core_bid(raw_bid),
.core_bresp(raw_bresp),
.core_bvalid(raw_bvalid),
.core_bready(raw_bready),
.core_awlock(1'b0),
.core_awcache(4'b0011),
.core_awprot(3'd0),
.core_awqos(4'd0),
.ui_awid(runtime_awid),
.ui_awaddr(runtime_awaddr),
.ui_awlen(runtime_awlen),
.ui_awsize(runtime_awsize),
.ui_awburst(runtime_awburst),
.ui_awvalid(runtime_awvalid),
.ui_awready(runtime_awready),
.ui_wdata(runtime_wdata),
.ui_wstrb(runtime_wstrb),
.ui_wlast(runtime_wlast),
.ui_wvalid(runtime_wvalid),
.ui_wready(runtime_wready),
.ui_bid(runtime_bid),
.ui_bresp(runtime_bresp),
.ui_bvalid(runtime_bvalid),
.ui_bready(runtime_bready),
.ui_awlock(runtime_awlock),
.ui_awcache(runtime_awcache),
.ui_awprot(runtime_awprot),
.ui_awqos(runtime_awqos));
axi512_single_read_cdc raw_read_cdc(.core_clk(core_clk),.core_reset_n(read_fabric_reset_n),.ui_clk(ui_clk),.ui_reset_n(ui_fabric_reset_n[4]),
.core_arid(raw_arid),
.core_araddr(raw_araddr),
.core_arlen(raw_arlen),
.core_arsize(raw_arsize),
.core_arburst(raw_arburst),
.core_arvalid(raw_arvalid),
.core_arready(raw_arready),
.core_rid(raw_rid),
.core_rdata(raw_rdata),
.core_rresp(raw_rresp),
.core_rlast(raw_rlast),
.core_rvalid(raw_rvalid),
.core_rready(raw_rready),
.core_arlock(1'b0),
.core_arcache(4'b0011),
.core_arprot(3'd0),
.core_arqos(4'd0),
.ui_arid(raw_ui_arid),
.ui_araddr(raw_ui_araddr),
.ui_arlen(raw_ui_arlen),
.ui_arsize(raw_ui_arsize),
.ui_arburst(raw_ui_arburst),
.ui_arvalid(raw_ui_arvalid),
.ui_arready(raw_ui_arready),
.ui_rid(raw_ui_rid),
.ui_rdata(raw_ui_rdata),
.ui_rresp(raw_ui_rresp),
.ui_rlast(raw_ui_rlast),
.ui_rvalid(raw_ui_rvalid),
.ui_rready(raw_ui_rready),
.ui_arlock(raw_ui_arlock),
.ui_arcache(raw_ui_arcache),
.ui_arprot(raw_ui_arprot),
.ui_arqos(raw_ui_arqos));
    axi512_write_arbiter_2to1 write_arbiter(
        .clk(ui_clk),.reset_n(ui_fabric_reset_n[3]),.s0_awid(4'd0),.s0_awaddr(ps_awaddr[33:0]),
        .s0_awlen(ps_awlen),.s0_awsize(ps_awsize),.s0_awburst(ps_awburst),
        .s0_awlock(ps_awlock),.s0_awcache(ps_awcache),.s0_awprot(ps_awprot),
        .s0_awqos(ps_awqos),.s0_awvalid(ps_awvalid),.s0_awready(ps_awready),
        .s0_wdata(ps_wdata),.s0_wstrb(ps_wstrb),.s0_wlast(ps_wlast),
        .s0_wvalid(ps_wvalid),.s0_wready(ps_wready),.s0_bid(),
        .s0_bresp(ps_bresp),.s0_bvalid(ps_bvalid),.s0_bready(ps_bready),
        .s1_awid(runtime_awid),.s1_awaddr(runtime_awaddr),.s1_awlen(runtime_awlen),
        .s1_awsize(runtime_awsize),.s1_awburst(runtime_awburst),
        .s1_awlock(runtime_awlock),.s1_awcache(runtime_awcache),
        .s1_awprot(runtime_awprot),.s1_awqos(runtime_awqos),
        .s1_awvalid(runtime_awvalid),.s1_awready(runtime_awready),
        .s1_wdata(runtime_wdata),.s1_wstrb(runtime_wstrb),
        .s1_wlast(runtime_wlast),.s1_wvalid(runtime_wvalid),
        .s1_wready(runtime_wready),.s1_bid(runtime_bid),
        .s1_bresp(runtime_bresp),.s1_bvalid(runtime_bvalid),
        .s1_bready(runtime_bready),.m_awid(mig_awid),.m_awaddr(mig_awaddr),
        .m_awlen(mig_awlen),.m_awsize(mig_awsize),.m_awburst(mig_awburst),
        .m_awlock(mig_awlock),.m_awcache(mig_awcache),.m_awprot(mig_awprot),
        .m_awqos(mig_awqos),.m_awvalid(mig_awvalid),.m_awready(mig_awready),
        .m_wdata(mig_wdata),.m_wstrb(mig_wstrb),.m_wlast(mig_wlast),
        .m_wvalid(mig_wvalid),.m_wready(mig_wready),.m_bid(mig_bid),
        .m_bresp(mig_bresp),.m_bvalid(mig_bvalid),.m_bready(mig_bready),
        .s0_transactions_o(ps_write_tx),.s1_transactions_o(runtime_write_tx),
        .s0_beats_o(ps_write_beats),.s1_beats_o(runtime_write_beats),
        .status_o(write_arb_status));

axi512_read_arbiter_3to1 #(.MODEL_MAX_OUTSTANDING(8)) read_arbiter(.clk(ui_clk),.reset_n(ui_fabric_reset_n[2]),
.s0_arid(4'd0),
.s1_arid(m_arid[3:0]),
.s2_arid(raw_ui_arid),
.m_arid(mig_arid),
.s0_araddr(ps_araddr[33:0]),
.s1_araddr(m_araddr[33:0]),
.s2_araddr(raw_ui_araddr),
.m_araddr(mig_araddr),
.s0_arlen(ps_arlen),
.s1_arlen(m_arlen[7:0]),
.s2_arlen(raw_ui_arlen),
.m_arlen(mig_arlen),
.s0_arsize(ps_arsize),
.s1_arsize(m_arsize[2:0]),
.s2_arsize(raw_ui_arsize),
.m_arsize(mig_arsize),
.s0_arburst(ps_arburst),
.s1_arburst(m_arburst[1:0]),
.s2_arburst(raw_ui_arburst),
.m_arburst(mig_arburst),
.s0_arvalid(ps_arvalid),
.s1_arvalid(m_arvalid[0]),
.s2_arvalid(raw_ui_arvalid),
.m_arvalid(mig_arvalid),
.s0_arready(ps_arready),
.s1_arready(m_arready[0]),
.s2_arready(raw_ui_arready),
.m_arready(mig_arready),
.s0_rid(),
.s1_rid(m_rid[3:0]),
.s2_rid(raw_ui_rid),
.m_rid(mig_rid),
.s0_rdata(ps_rdata),
.s1_rdata(m_rdata[511:0]),
.s2_rdata(raw_ui_rdata),
.m_rdata(mig_rdata),
.s0_rresp(ps_rresp),
.s1_rresp(m_rresp[1:0]),
.s2_rresp(raw_ui_rresp),
.m_rresp(mig_rresp),
.s0_rlast(ps_rlast),
.s1_rlast(m_rlast[0]),
.s2_rlast(raw_ui_rlast),
.m_rlast(mig_rlast),
.s0_rvalid(ps_rvalid),
.s1_rvalid(m_rvalid[0]),
.s2_rvalid(raw_ui_rvalid),
.m_rvalid(mig_rvalid),
.s0_rready(ps_rready),
.s1_rready(m_rready[0]),
.s2_rready(raw_ui_rready),
.m_rready(mig_rready),
.s0_arlock(ps_arlock),
.s1_arlock(m_arlock[0]),
.s2_arlock(raw_ui_arlock),
.m_arlock(mig_arlock),
.s0_arcache(ps_arcache),
.s1_arcache(m_arcache[3:0]),
.s2_arcache(raw_ui_arcache),
.m_arcache(mig_arcache),
.s0_arprot(ps_arprot),
.s1_arprot(m_arprot[2:0]),
.s2_arprot(raw_ui_arprot),
.m_arprot(mig_arprot),
.s0_arqos(ps_arqos),
.s1_arqos(m_arqos[3:0]),
.s2_arqos(raw_ui_arqos),
.m_arqos(mig_arqos),
.source0_transactions_o(ps_tx),
.source0_beats_o(ps_beats),
.source0_wait_cycles_o(ps_wait),
.source1_transactions_o(model_tx),
.source1_beats_o(model_beats),
.source1_wait_cycles_o(model_wait),
.source2_transactions_o(kv_tx),
.source2_beats_o(kv_beats),
.source2_wait_cycles_o(kv_wait),
.accepted_source_o(pl_read_accepted_source),
.accepted_source_valid_o(pl_read_accepted_source_valid),
.response_source_o(pl_read_response_source),
.status_o(fabric_status));
    wire [518:0] mig_raw_r68,mig_landed_r68;
    wire mig_raw_rvalid68,mig_raw_rready68;
    sidewinder_pl_ddr4 ddr4(
        .c0_init_calib_complete(init_calib_complete),.c0_sys_clk_p(c0_sys_clk_p),
        .c0_sys_clk_n(c0_sys_clk_n),.c0_ddr4_adr(c0_ddr4_adr),
        .c0_ddr4_ba(c0_ddr4_ba),.c0_ddr4_cke(c0_ddr4_cke),
        .c0_ddr4_cs_n(c0_ddr4_cs_n),.c0_ddr4_dm_dbi_n(c0_ddr4_dm_dbi_n),
        .c0_ddr4_dq(c0_ddr4_dq),.c0_ddr4_dqs_c(c0_ddr4_dqs_c),
        .c0_ddr4_dqs_t(c0_ddr4_dqs_t),.c0_ddr4_odt(c0_ddr4_odt),
        .c0_ddr4_bg(c0_ddr4_bg),.c0_ddr4_reset_n(c0_ddr4_reset_n),
        .c0_ddr4_act_n(c0_ddr4_act_n),.c0_ddr4_ck_c(c0_ddr4_ck_c),
        .c0_ddr4_ck_t(c0_ddr4_ck_t),.c0_ddr4_ui_clk(ui_clk),
        .c0_ddr4_ui_clk_sync_rst(ui_clk_sync_rst),.c0_ddr4_aresetn(aresetn),
        .c0_ddr4_s_axi_awid(mig_awid),.c0_ddr4_s_axi_awaddr(mig_awaddr[32:0]),
        .c0_ddr4_s_axi_awlen(mig_awlen),.c0_ddr4_s_axi_awsize(mig_awsize),
        .c0_ddr4_s_axi_awburst(mig_awburst),.c0_ddr4_s_axi_awlock(mig_awlock),
        .c0_ddr4_s_axi_awcache(mig_awcache),.c0_ddr4_s_axi_awprot(mig_awprot),
        .c0_ddr4_s_axi_awqos(mig_awqos),.c0_ddr4_s_axi_awvalid(mig_awvalid),
        .c0_ddr4_s_axi_awready(mig_awready),.c0_ddr4_s_axi_wdata(mig_wdata),
        .c0_ddr4_s_axi_wstrb(mig_wstrb),.c0_ddr4_s_axi_wlast(mig_wlast),
        .c0_ddr4_s_axi_wvalid(mig_wvalid),.c0_ddr4_s_axi_wready(mig_wready),
        .c0_ddr4_s_axi_bready(mig_bready),.c0_ddr4_s_axi_bid(mig_bid),
        .c0_ddr4_s_axi_bresp(mig_bresp),.c0_ddr4_s_axi_bvalid(mig_bvalid),
        .c0_ddr4_s_axi_arid(mig_arid),.c0_ddr4_s_axi_araddr(mig_araddr[32:0]),
        .c0_ddr4_s_axi_arlen(mig_arlen),.c0_ddr4_s_axi_arsize(mig_arsize),
        .c0_ddr4_s_axi_arburst(mig_arburst),.c0_ddr4_s_axi_arlock(mig_arlock),
        .c0_ddr4_s_axi_arcache(mig_arcache),.c0_ddr4_s_axi_arprot(mig_arprot),
        .c0_ddr4_s_axi_arqos(mig_arqos),.c0_ddr4_s_axi_arvalid(mig_arvalid),
        .c0_ddr4_s_axi_arready(mig_arready),.c0_ddr4_s_axi_rready(mig_raw_rready68),
        .c0_ddr4_s_axi_rlast(mig_raw_r68[0]),.c0_ddr4_s_axi_rvalid(mig_raw_rvalid68),
        .c0_ddr4_s_axi_rresp(mig_raw_r68[2:1]),.c0_ddr4_s_axi_rid(mig_raw_r68[518:515]),
        .c0_ddr4_s_axi_rdata(mig_raw_r68[514:3]),.sys_rst(mig_sys_rst));

    // T68 UI landing: the MIG R payload is a LUTRAM-FIFO output whose read
    // pointer fans out to every distant R consumer. Register it once beside
    // the MIG (pblock PB_UI_MIG68) with the existing two-entry elastic slice.
    // AXI R is latency-insensitive; all downstream consumers, monitors and
    // fault capture keep observing the same mig_r* handshake names.
    (* keep_hierarchy="yes" *) qwen7b_read_response_buffer #(.WIDTH(519)) mig_r_landing68(
        .clk(ui_clk),.reset_n(aresetn),.valid_i(mig_raw_rvalid68),.ready_o(mig_raw_rready68),
        .data_i(mig_raw_r68),.valid_o(mig_rvalid),.ready_i(mig_rready),.data_o(mig_landed_r68));
    assign mig_rid=mig_landed_r68[518:515];
    assign mig_rdata=mig_landed_r68[514:3];
    assign mig_rresp=mig_landed_r68[2:1];
    assign mig_rlast=mig_landed_r68[0];

    always_ff @(posedge ui_clk) begin
        if(!ui_fabric_reset_n[0])address_window_error<=1'b0;
        else begin
            if(ps_awvalid&&ps_awready&&(ps_awaddr[36:33]!=4'b1000))address_window_error<=1'b1;
            if(ps_arvalid&&ps_arready&&(ps_araddr[36:33]!=4'b1000))address_window_error<=1'b1;
        end
    end

    qwen35_bandwidth65 bandwidth65(
      .ui_clk(ui_clk),.ui_reset_n(aresetn),.core_clk(core_clk),.core_reset_n(control_reset_n),
      .start_i(bw_start65),.done_i(bw_done65),
      .ps_valid_i(hp_rvalid),.ps_ready_i(hp_rready),.ps_resp_i(hp_rresp),
      .pl_weight_valid_i(m_rvalid[0]),.pl_weight_ready_i(m_rready[0]),
      .pl_rvalid_i(mig_rvalid),.pl_rready_i(mig_rready),.pl_rresp_i(mig_rresp),
      .pl_wvalid_i(mig_wvalid),.pl_wready_i(mig_wready),.pl_wstrb_i(mig_wstrb),
      .pl_arvalid_i(mig_arvalid),.pl_arready_i(mig_arready),.pl_arsize_i(mig_arsize),
      .word_i(5'(bw_debug_addr65-14'd673)),.data_o(bw_data65));

sidewinder_qwen_status_vio status_vio(.clk(core_clk),
        .probe_in0(init_calib_complete_core),.probe_in1(dci_locked_core),.probe_in2(dci_ready_core),.probe_in3(address_window_error_core),
        .probe_in4(status[7:0]),.probe_in5(cycles),.probe_in6(qkv_cycles),.probe_in7(write_cycles),.probe_in8(read_cycles),
        .probe_in9(pl_words),.probe_in10(ps_words),.probe_in11(output_count),.probe_in12(raw_count),.probe_in13(qkv_checksum),.probe_in14(raw_checksum));
endmodule

// Atomic multi-bit counter snapshot between the UI and nominal compute clock
// domains.  The XPM handshake holds src_in stable for the whole transaction;
// the destination captures dest_out only on the request edge.  Counts may
// continue changing while a transfer is in flight; the source sends the most
// recent value after the current acknowledgement instead of tearing a binary
// word across the clock boundary.
module qwen35_ui_count_snapshot_cdc #(
    parameter integer WIDTH=64,
    parameter integer LOCAL_PAYLOAD_RESETS=0
) (
    input  wire             ui_clk,
    input  wire             ui_reset_n,
    input  wire [WIDTH-1:0] ui_value,
    input  wire             core_clk,
    input  wire             core_reset_n,
    input  wire             core_reset_parent_n=1'b0,
    output logic [WIDTH-1:0] core_value,
    output logic             core_update
);
    logic [WIDTH-1:0] src_hold,src_sent;
    logic src_send_q,src_busy_q,src_rcv_q;
    wire src_rcv;
    wire [WIDTH-1:0] dest_out;
    wire dest_req;
    logic dest_req_q;
    wire destination_ready_ui;
    logic resend_pending;
    // core clock-lock loss can reset the destination while the UI/DDR stays
    // alive. Stretch that reset into the UI domain and resend even an unchanged
    // sticky value. Do not abort an in-flight XPM transaction: finish its ACK,
    // wait for the low handshake phase, then deliver a fresh atomic snapshot.
    xpm_cdc_async_rst #(.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),.RST_ACTIVE_HIGH(0))
        destination_reset_to_ui(.src_arst(core_reset_n),.dest_clk(ui_clk),
                                .dest_arst(destination_ready_ui));

    xpm_cdc_handshake #(
        .DEST_EXT_HSK(0),.DEST_SYNC_FF(3),.INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0),.SRC_SYNC_FF(3),.WIDTH(WIDTH)
    ) snapshot_handshake (
        .src_clk(ui_clk),.src_in(src_hold),.src_send(src_send_q),
        .src_rcv(src_rcv),.dest_clk(core_clk),.dest_out(dest_out),
        .dest_req(dest_req),.dest_ack(1'b0));

    always_ff @(posedge ui_clk) begin
        if(!ui_reset_n) begin
            src_hold<='0;
            src_sent<='0;
            src_send_q<=1'b0;
            src_busy_q<=1'b0;
            src_rcv_q<=1'b0;
            resend_pending<=1'b1;
        end else begin
            if(!destination_ready_ui)resend_pending<=1'b1;
            src_rcv_q<=src_rcv;
            if(src_rcv&&!src_rcv_q) begin
                // XPM requires the request level to remain asserted until
                // acknowledgement; a single UI-cycle pulse can be lost by a
                // slower destination and violates its handshake contract.
                src_send_q<=1'b0;
                src_sent<=src_hold;
                src_busy_q<=1'b0;
            end
            // Internal-destination handshaking keeps src_rcv high until the
            // source drops src_send and that level has crossed back.  Wait
            // for the low phase before issuing the next snapshot.
            if(destination_ready_ui&&!src_busy_q&&!src_send_q&&!src_rcv&&
               (resend_pending||(ui_value!=src_sent))) begin
                src_hold<=ui_value;
                src_send_q<=1'b1;
                src_busy_q<=1'b1;
                resend_pending<=1'b0;
            end
        end
    end

    // The physical top's control_reset_n already samples core_reset_parent_n
    // on this edge. Four identical-D local leaves keep that exact assertion
    // and release edge for the 256-bit visible payload; no reset is removed
    // and no extra release cycle is introduced. Metadata retains its root.
    localparam integer RESET_GROUPS=(WIDTH+63)/64;
    for(genvar g=0;g<RESET_GROUPS;g=g+1)begin:g_payload_reset
        localparam integer BITS=(WIDTH-g*64>=64)?64:(WIDTH-g*64);
        wire payload_reset_n;
        if(LOCAL_PAYLOAD_RESETS)begin:g_local
            (* DONT_TOUCH="TRUE",KEEP="TRUE",MAX_FANOUT=64 *) reg local_reset_n=1'b0;
            always_ff @(posedge core_clk)begin
                if(!core_reset_parent_n)local_reset_n<=1'b0;
                else local_reset_n<=1'b1;
            end
            // synthesis translate_off
            always @(posedge core_clk)if(local_reset_n!==core_reset_n)
                $fatal(1,"SNAPSHOT_LOCAL_RESET_MUST_MATCH_ORIGINAL_EDGE" );
            // synthesis translate_on
            assign payload_reset_n=local_reset_n;
        end else begin:g_original
            assign payload_reset_n=core_reset_n;
        end
        always_ff @(posedge core_clk)begin
            if(!payload_reset_n)core_value[g*64+:BITS]<='0;
            else if(dest_req&&!dest_req_q)core_value[g*64+:BITS]<=dest_out[g*64+:BITS];
        end
    end
    always_ff @(posedge core_clk) begin
        if(!core_reset_n) begin
            core_update<=1'b0;
            dest_req_q<=1'b0;
        end else begin
            core_update<=1'b0;
            dest_req_q<=dest_req;
            if(dest_req&&!dest_req_q) core_update<=1'b1;
        end
    end
endmodule
