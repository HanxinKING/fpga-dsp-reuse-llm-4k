module q9_accelerator_4k_impl(
    input wire  core_clk,
    input wire  ui_clk,
    input wire  core_aresetn,
    input wire [31:0] board_errors_i,
    output wire  busy_o,
    output wire  done_o,
    input wire [15:0] s_axi_ctrl_awaddr,
    input wire  s_axi_ctrl_awvalid,
    output wire  s_axi_ctrl_awready,
    input wire [31:0] s_axi_ctrl_wdata,
    input wire [3:0] s_axi_ctrl_wstrb,
    input wire  s_axi_ctrl_wvalid,
    output wire  s_axi_ctrl_wready,
    output wire [1:0] s_axi_ctrl_bresp,
    output wire  s_axi_ctrl_bvalid,
    input wire  s_axi_ctrl_bready,
    input wire [15:0] s_axi_ctrl_araddr,
    input wire  s_axi_ctrl_arvalid,
    output wire  s_axi_ctrl_arready,
    output wire [31:0] s_axi_ctrl_rdata,
    output wire [1:0] s_axi_ctrl_rresp,
    output wire  s_axi_ctrl_rvalid,
    input wire  s_axi_ctrl_rready,
    output wire [3:0] m_axi_weight_pl_arid,
    output wire [33:0] m_axi_weight_pl_araddr,
    output wire [7:0] m_axi_weight_pl_arlen,
    output wire [2:0] m_axi_weight_pl_arsize,
    output wire [1:0] m_axi_weight_pl_arburst,
    output wire  m_axi_weight_pl_arlock,
    output wire [3:0] m_axi_weight_pl_arcache,
    output wire [2:0] m_axi_weight_pl_arprot,
    output wire [3:0] m_axi_weight_pl_arqos,
    output wire  m_axi_weight_pl_arvalid,
    input wire  m_axi_weight_pl_arready,
    input wire [3:0] m_axi_weight_pl_rid,
    input wire [511:0] m_axi_weight_pl_rdata,
    input wire [1:0] m_axi_weight_pl_rresp,
    input wire  m_axi_weight_pl_rlast,
    input wire  m_axi_weight_pl_rvalid,
    output wire  m_axi_weight_pl_rready,
    output wire [3:0] m_axi_weight_ps_arid,
    output wire [33:0] m_axi_weight_ps_araddr,
    output wire [7:0] m_axi_weight_ps_arlen,
    output wire [2:0] m_axi_weight_ps_arsize,
    output wire [1:0] m_axi_weight_ps_arburst,
    output wire  m_axi_weight_ps_arlock,
    output wire [3:0] m_axi_weight_ps_arcache,
    output wire [2:0] m_axi_weight_ps_arprot,
    output wire [3:0] m_axi_weight_ps_arqos,
    output wire  m_axi_weight_ps_arvalid,
    input wire  m_axi_weight_ps_arready,
    input wire [3:0] m_axi_weight_ps_rid,
    input wire [511:0] m_axi_weight_ps_rdata,
    input wire [1:0] m_axi_weight_ps_rresp,
    input wire  m_axi_weight_ps_rlast,
    input wire  m_axi_weight_ps_rvalid,
    output wire  m_axi_weight_ps_rready,
    output wire [3:0] m_axi_state_awid,
    output wire [33:0] m_axi_state_awaddr,
    output wire [7:0] m_axi_state_awlen,
    output wire [2:0] m_axi_state_awsize,
    output wire [1:0] m_axi_state_awburst,
    output wire  m_axi_state_awvalid,
    input wire  m_axi_state_awready,
    output wire [511:0] m_axi_state_wdata,
    output wire [63:0] m_axi_state_wstrb,
    output wire  m_axi_state_wlast,
    output wire  m_axi_state_wvalid,
    input wire  m_axi_state_wready,
    input wire [3:0] m_axi_state_bid,
    input wire [1:0] m_axi_state_bresp,
    input wire  m_axi_state_bvalid,
    output wire  m_axi_state_bready,
    output wire [3:0] m_axi_state_arid,
    output wire [33:0] m_axi_state_araddr,
    output wire [7:0] m_axi_state_arlen,
    output wire [2:0] m_axi_state_arsize,
    output wire [1:0] m_axi_state_arburst,
    output wire  m_axi_state_arvalid,
    input wire  m_axi_state_arready,
    input wire [3:0] m_axi_state_rid,
    input wire [511:0] m_axi_state_rdata,
    input wire [1:0] m_axi_state_rresp,
    input wire  m_axi_state_rlast,
    input wire  m_axi_state_rvalid,
    output wire  m_axi_state_rready
);
localparam integer CONV_COEFF_DDR=1;
localparam logic[63:0]GDN_COEFF_BASE={30'd0,34'h1F3600000};
localparam integer INT4_DOT_FOLD=1, GAMMA_DDR=1, GAMMA_PREFETCH=1,ROPE_DDR=1;
localparam [33:0]ROPE_DDR_BASE=34'h1F3780000;
localparam [33:0] GAMMA_DDR_BASE=34'h1EFB40000;
localparam [33:0] EMBEDDING_BASE=34'h52064000;
localparam [33:0] HEAD_PL_BASE=34'd0;
localparam [33:0] HEAD_PS_BASE=34'd0;
localparam [33:0] LM_HEAD_PL_BASE=34'h15FBEE000;
localparam [33:0] LM_HEAD_PS_BASE=34'h080000000;
localparam integer LM_HEAD_ROWS=248320;
localparam [33:0] ATT_RAW_BASE=34'h1EFC00000;
localparam [33:0] ATT_CODE_BASE=34'h1f4000000;
localparam [33:0] ATT_PARAM_BASE=34'h1fc000000;
localparam [33:0] ATT_O_PL_BASE=34'd0;
localparam [33:0] ATT_O_PS_BASE=34'd0;
localparam [33:0] ATT_EXTREMA_BASE=34'h1fe000000;
localparam [101:0] FFN_PL_BASES=102'd0;
localparam [101:0] FFN_PS_BASES=102'd0;
localparam integer ATT_VALID_TOKENS=32;
localparam integer ATT_TOKEN_BASE=0;
localparam [63:0] GDN_REC_BASE = {30'd0, 34'h1F0400000};
localparam [63:0] GDN_CV_BASE  = {30'd0, (34'h1F0400000 + 34'h0300_0000)};
localparam EXP_ROM="exp.mem",GAMMA_ROM="gamma.mem",DESCRIPTOR_ROM="descriptor.mem",COS_ROM="q9_rope_cos_q14.mem",SIN_ROM="q9_rope_sin_q14.mem";
wire [31:0] raw_count_o;
wire [31:0] raw_checksum_o;
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
wire [1:0] m_rvalid;
wire [1:0] m_rready;
wire [3:0] raw_awid;
wire [33:0] raw_awaddr;
wire [7:0] raw_awlen;
wire [2:0] raw_awsize;
wire [1:0] raw_awburst;
wire  raw_awvalid;
wire  raw_awready;
wire [511:0] raw_wdata;
wire [63:0] raw_wstrb;
wire  raw_wlast;
wire  raw_wvalid;
wire  raw_wready;
wire [3:0] raw_bid;
wire [1:0] raw_bresp;
wire  raw_bvalid;
wire  raw_bready;
wire [3:0] raw_arid;
wire [33:0] raw_araddr;
wire [7:0] raw_arlen;
wire [2:0] raw_arsize;
wire [1:0] raw_arburst;
wire  raw_arvalid;
wire  raw_arready;
wire [3:0] raw_rid;
wire [511:0] raw_rdata;
wire [1:0] raw_rresp;
wire  raw_rlast;
wire  raw_rvalid;
wire  raw_rready;
wire [15:0] ctrl_awaddr;
wire ctrl_awvalid;
wire ctrl_awready;
wire [31:0] ctrl_wdata;
wire [3:0] ctrl_wstrb;
wire ctrl_wvalid;
wire ctrl_wready;
wire [1:0] ctrl_bresp;
wire ctrl_bvalid;
wire ctrl_bready;
wire [15:0] ctrl_araddr;
wire ctrl_arvalid;
wire ctrl_arready;
wire [31:0] ctrl_rdata;
wire [1:0] ctrl_rresp;
wire ctrl_rvalid;
wire ctrl_rready;
wire core_reset_n=core_aresetn;
wire reset_n;
wire compute_parent_reset_n=core_reset_n;
reg accelerator_reset_n=0,control_reset_n=0;
always @(posedge core_clk)begin accelerator_reset_n<=compute_parent_reset_n;control_reset_n<=core_reset_n;end
assign reset_n=accelerator_reset_n;
wire[19:0]reset_parts49_n;
qwen35_compute_reset49 #(.PARTS(20)) reset_partition49(.clk(core_clk),.core_reset_n(compute_parent_reset_n),.reset_parts_n(reset_parts49_n));




wire start,busy,done,start_ready,cfg_write,cfg_ready;wire[9:0]cfg_address;wire[31:0]cfg_data;
wire[31:0]status,cycles,run_id,qkv_cycles,write_cycles,read_cycles,output_count,raw_count,pl_words,ps_words,write_bytes,read_bytes,qkv_checksum,raw_checksum;
wire[31:0]prefix_cycles,attention_cycles,o_cycles,ffn_cycles,attention_count,o_count,ffn_count;
wire[63:0]full_cycles,first_token_cycles;wire[17:0]last_token;wire[13:0]position;wire[4:0]layer;wire[5:0]phase;
wire[7:0]quant_warning_flags;wire[31:0]quant_warning_events;
wire[13:0]debug_addr;wire[31:0]debug_data;wire[511:0]fault_snapshot;
wire[31:0]board_errors=board_errors_i;wire[255:0]pl_read_fault_core=0;wire[31:0]mmio_debug65=debug_data;
wire bw_start65,bw_done65;wire[31:0]model_ar_count_core=0,model_r_count_core=0;
assign busy_o=busy;assign done_o=done;

assign ctrl_awaddr=s_axi_ctrl_awaddr;
assign ctrl_awvalid=s_axi_ctrl_awvalid;
assign s_axi_ctrl_awready=ctrl_awready;
assign ctrl_wdata=s_axi_ctrl_wdata;
assign ctrl_wstrb=s_axi_ctrl_wstrb;
assign ctrl_wvalid=s_axi_ctrl_wvalid;
assign s_axi_ctrl_wready=ctrl_wready;
assign s_axi_ctrl_bresp=ctrl_bresp;
assign s_axi_ctrl_bvalid=ctrl_bvalid;
assign ctrl_bready=s_axi_ctrl_bready;
assign ctrl_araddr=s_axi_ctrl_araddr;
assign ctrl_arvalid=s_axi_ctrl_arvalid;
assign s_axi_ctrl_arready=ctrl_arready;
assign s_axi_ctrl_rdata=ctrl_rdata;
assign s_axi_ctrl_rresp=ctrl_rresp;
assign s_axi_ctrl_rvalid=ctrl_rvalid;
assign ctrl_rready=s_axi_ctrl_rready;
assign m_axi_weight_pl_arid=m_arid[0+:4];
assign m_axi_weight_pl_araddr=m_araddr[0+:34];
assign m_axi_weight_pl_arlen=m_arlen[0+:8];
assign m_axi_weight_pl_arsize=m_arsize[0+:3];
assign m_axi_weight_pl_arburst=m_arburst[0+:2];
assign m_axi_weight_pl_arlock=m_arlock[0+:1];
assign m_axi_weight_pl_arcache=m_arcache[0+:4];
assign m_axi_weight_pl_arprot=m_arprot[0+:3];
assign m_axi_weight_pl_arqos=m_arqos[0+:4];
assign m_axi_weight_pl_arvalid=m_arvalid[0+:1];
assign m_arready[0+:1]=m_axi_weight_pl_arready;
assign m_rid[0+:4]=m_axi_weight_pl_rid;
assign m_rdata[0+:512]=m_axi_weight_pl_rdata;
assign m_rresp[0+:2]=m_axi_weight_pl_rresp;
assign m_rlast[0+:1]=m_axi_weight_pl_rlast;
assign m_rvalid[0+:1]=m_axi_weight_pl_rvalid;
assign m_axi_weight_pl_rready=m_rready[0+:1];
assign m_axi_weight_ps_arid=m_arid[4+:4];
assign m_axi_weight_ps_araddr=m_araddr[34+:34];
assign m_axi_weight_ps_arlen=m_arlen[8+:8];
assign m_axi_weight_ps_arsize=m_arsize[3+:3];
assign m_axi_weight_ps_arburst=m_arburst[2+:2];
assign m_axi_weight_ps_arlock=m_arlock[1+:1];
assign m_axi_weight_ps_arcache=m_arcache[4+:4];
assign m_axi_weight_ps_arprot=m_arprot[3+:3];
assign m_axi_weight_ps_arqos=m_arqos[4+:4];
assign m_axi_weight_ps_arvalid=m_arvalid[1+:1];
assign m_arready[1+:1]=m_axi_weight_ps_arready;
assign m_rid[4+:4]=m_axi_weight_ps_rid;
assign m_rdata[512+:512]=m_axi_weight_ps_rdata;
assign m_rresp[2+:2]=m_axi_weight_ps_rresp;
assign m_rlast[1+:1]=m_axi_weight_ps_rlast;
assign m_rvalid[1+:1]=m_axi_weight_ps_rvalid;
assign m_axi_weight_ps_rready=m_rready[1+:1];
assign m_axi_state_awid=raw_awid;
assign m_axi_state_awaddr=raw_awaddr;
assign m_axi_state_awlen=raw_awlen;
assign m_axi_state_awsize=raw_awsize;
assign m_axi_state_awburst=raw_awburst;
assign m_axi_state_awvalid=raw_awvalid;
assign raw_awready=m_axi_state_awready;
assign m_axi_state_wdata=raw_wdata;
assign m_axi_state_wstrb=raw_wstrb;
assign m_axi_state_wlast=raw_wlast;
assign m_axi_state_wvalid=raw_wvalid;
assign raw_wready=m_axi_state_wready;
assign raw_bid=m_axi_state_bid;
assign raw_bresp=m_axi_state_bresp;
assign raw_bvalid=m_axi_state_bvalid;
assign m_axi_state_bready=raw_bready;
assign m_axi_state_arid=raw_arid;
assign m_axi_state_araddr=raw_araddr;
assign m_axi_state_arlen=raw_arlen;
assign m_axi_state_arsize=raw_arsize;
assign m_axi_state_arburst=raw_arburst;
assign m_axi_state_arvalid=raw_arvalid;
assign raw_arready=m_axi_state_arready;
assign raw_rid=m_axi_state_rid;
assign raw_rdata=m_axi_state_rdata;
assign raw_rresp=m_axi_state_rresp;
assign raw_rlast=m_axi_state_rlast;
assign raw_rvalid=m_axi_state_rvalid;
assign m_axi_state_rready=raw_rready;
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

endmodule

