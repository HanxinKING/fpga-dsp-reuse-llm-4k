// 3B GENERATED CANDIDATE: not admitted for board use.
`timescale 1ns / 1ps

// Three-master, one-slave AXI4 read arbiter for the Sidewinder PL DDR path.
//
// Source 0 is reserved for the PS HPM loader, source 1 for model weights, and
// source 2 for KV traffic.  PS and KV remain single-outstanding.  The model
// source may have MODEL_MAX_OUTSTANDING same-source bursts outstanding so its
// 64-beat loader can hide DDR command latency; no other source is admitted
// until all responses finish, so response routing remains unambiguous.  Round-robin selection at
// source boundaries prevents model traffic from starving PS/KV traffic.
module axi512_read_arbiter_3to1 #(
    parameter integer MODEL_MAX_OUTSTANDING = 8
) (
    input  logic         clk,
    input  logic         reset_n,

    input  logic [3:0]   s0_arid,
    input  logic [33:0]  s0_araddr,
    input  logic [7:0]   s0_arlen,
    input  logic [2:0]   s0_arsize,
    input  logic [1:0]   s0_arburst,
    input  logic         s0_arlock,
    input  logic [3:0]   s0_arcache,
    input  logic [2:0]   s0_arprot,
    input  logic [3:0]   s0_arqos,
    input  logic         s0_arvalid,
    output logic         s0_arready,
    output logic [3:0]   s0_rid,
    output logic [511:0] s0_rdata,
    output logic [1:0]   s0_rresp,
    output logic         s0_rlast,
    output logic         s0_rvalid,
    input  logic         s0_rready,

    input  logic [3:0]   s1_arid,
    input  logic [33:0]  s1_araddr,
    input  logic [7:0]   s1_arlen,
    input  logic [2:0]   s1_arsize,
    input  logic [1:0]   s1_arburst,
    input  logic         s1_arlock,
    input  logic [3:0]   s1_arcache,
    input  logic [2:0]   s1_arprot,
    input  logic [3:0]   s1_arqos,
    input  logic         s1_arvalid,
    output logic         s1_arready,
    output logic [3:0]   s1_rid,
    output logic [511:0] s1_rdata,
    output logic [1:0]   s1_rresp,
    output logic         s1_rlast,
    output logic         s1_rvalid,
    input  logic         s1_rready,

    input  logic [3:0]   s2_arid,
    input  logic [33:0]  s2_araddr,
    input  logic [7:0]   s2_arlen,
    input  logic [2:0]   s2_arsize,
    input  logic [1:0]   s2_arburst,
    input  logic         s2_arlock,
    input  logic [3:0]   s2_arcache,
    input  logic [2:0]   s2_arprot,
    input  logic [3:0]   s2_arqos,
    input  logic         s2_arvalid,
    output logic         s2_arready,
    output logic [3:0]   s2_rid,
    output logic [511:0] s2_rdata,
    output logic [1:0]   s2_rresp,
    output logic         s2_rlast,
    output logic         s2_rvalid,
    input  logic         s2_rready,

    output logic [3:0]   m_arid,
    output logic [33:0]  m_araddr,
    output logic [7:0]   m_arlen,
    output logic [2:0]   m_arsize,
    output logic [1:0]   m_arburst,
    output logic         m_arlock,
    output logic [3:0]   m_arcache,
    output logic [2:0]   m_arprot,
    output logic [3:0]   m_arqos,
    output logic         m_arvalid,
    input  logic         m_arready,
    input  logic [3:0]   m_rid,
    input  logic [511:0] m_rdata,
    input  logic [1:0]   m_rresp,
    input  logic         m_rlast,
    input  logic         m_rvalid,
    output logic         m_rready,

    output logic [31:0]  source0_transactions_o,
    output logic [31:0]  source1_transactions_o,
    output logic [31:0]  source2_transactions_o,
    output logic [31:0]  source0_beats_o,
    output logic [31:0]  source1_beats_o,
    output logic [31:0]  source2_beats_o,
    output logic [31:0]  source0_wait_cycles_o,
    output logic [31:0]  source1_wait_cycles_o,
    output logic [31:0]  source2_wait_cycles_o,
    // Passive telemetry taps.  They are deliberately outputs of the already
    // registered arbitration decision and never feed READY/VALID.
    output logic [1:0]   accepted_source_o,
    output logic         accepted_source_valid_o,
    output logic [1:0]   response_source_o,
    output logic [7:0]   status_o
);
    logic       active = 1'b0;
    logic [1:0] active_source = 2'd0;
    localparam integer OUTSTANDING_W = $clog2(MODEL_MAX_OUTSTANDING + 1);
    logic [OUTSTANDING_W-1:0] outstanding = '0;
    logic [1:0] next_source = 2'd0;
    logic [1:0] candidate;
    logic       candidate_valid;
    logic       ar_fire;
    logic       response_last_fire;
    // Once ARVALID is presented, its owner must survive both newly arriving
    // higher-priority requests and the retirement of an active model epoch.
    // The selected upstream master holds its own payload until ARREADY, so
    // only the three grant bits need storage; no payload stage is inserted.
    logic       grant_locked = 1'b0;
    logic [1:0] locked_source = 2'd0;

    always_comb begin
        candidate = 2'd0;
        candidate_valid = 1'b0;
        if (active) begin
            // Only model requests can join an active ownership epoch.  PS/KV
            // requests wait for the complete ordered model response sequence.
            if (active_source==2'd1
                    && outstanding<MODEL_MAX_OUTSTANDING && s1_arvalid) begin
                candidate=2'd1;
                candidate_valid=1'b1;
            end
        end else begin
            case (next_source)
                2'd0: begin
                    if (s0_arvalid) begin candidate=2'd0; candidate_valid=1'b1; end
                    else if (s1_arvalid) begin candidate=2'd1; candidate_valid=1'b1; end
                    else if (s2_arvalid) begin candidate=2'd2; candidate_valid=1'b1; end
                end
                2'd1: begin
                    if (s1_arvalid) begin candidate=2'd1; candidate_valid=1'b1; end
                    else if (s2_arvalid) begin candidate=2'd2; candidate_valid=1'b1; end
                    else if (s0_arvalid) begin candidate=2'd0; candidate_valid=1'b1; end
                end
                default: begin
                    if (s2_arvalid) begin candidate=2'd2; candidate_valid=1'b1; end
                    else if (s0_arvalid) begin candidate=2'd0; candidate_valid=1'b1; end
                    else if (s1_arvalid) begin candidate=2'd1; candidate_valid=1'b1; end
                end
            endcase
        end

        if (grant_locked) begin
            candidate = locked_source;
            candidate_valid = 1'b1;
        end

        m_arid    = candidate==2'd0 ? s0_arid    : candidate==2'd1 ? s1_arid    : s2_arid;
        m_araddr  = candidate==2'd0 ? s0_araddr  : candidate==2'd1 ? s1_araddr  : s2_araddr;
        m_arlen   = candidate==2'd0 ? s0_arlen   : candidate==2'd1 ? s1_arlen   : s2_arlen;
        m_arsize  = candidate==2'd0 ? s0_arsize  : candidate==2'd1 ? s1_arsize  : s2_arsize;
        m_arburst = candidate==2'd0 ? s0_arburst : candidate==2'd1 ? s1_arburst : s2_arburst;
        m_arlock  = candidate==2'd0 ? s0_arlock  : candidate==2'd1 ? s1_arlock  : s2_arlock;
        m_arcache = candidate==2'd0 ? s0_arcache : candidate==2'd1 ? s1_arcache : s2_arcache;
        m_arprot  = candidate==2'd0 ? s0_arprot  : candidate==2'd1 ? s1_arprot  : s2_arprot;
        m_arqos   = candidate==2'd0 ? s0_arqos   : candidate==2'd1 ? s1_arqos   : s2_arqos;
        m_arvalid = candidate_valid;

        s0_arready = candidate_valid && candidate==2'd0 && m_arready;
        s1_arready = candidate_valid && candidate==2'd1 && m_arready;
        s2_arready = candidate_valid && candidate==2'd2 && m_arready;
        ar_fire = m_arvalid && m_arready;
        accepted_source_o = candidate;
        accepted_source_valid_o = ar_fire;
        response_source_o = active_source;

        s0_rid=m_rid; s1_rid=m_rid; s2_rid=m_rid;
        s0_rdata=m_rdata; s1_rdata=m_rdata; s2_rdata=m_rdata;
        s0_rresp=m_rresp; s1_rresp=m_rresp; s2_rresp=m_rresp;
        s0_rlast=m_rlast; s1_rlast=m_rlast; s2_rlast=m_rlast;
        s0_rvalid=active && active_source==2'd0 && m_rvalid;
        s1_rvalid=active && active_source==2'd1 && m_rvalid;
        s2_rvalid=active && active_source==2'd2 && m_rvalid;
        case (active_source)
            2'd0: m_rready = active && s0_rready;
            2'd1: m_rready = active && s1_rready;
            default: m_rready = active && s2_rready;
        endcase
        response_last_fire = m_rvalid && m_rready && m_rlast;
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            active <= 1'b0;
            active_source <= 2'd0;
            outstanding <= '0;
            next_source <= 2'd0;
            grant_locked <= 1'b0;
            locked_source <= 2'd0;
            source0_transactions_o <= '0;
            source1_transactions_o <= '0;
            source2_transactions_o <= '0;
            source0_beats_o <= '0;
            source1_beats_o <= '0;
            source2_beats_o <= '0;
            source0_wait_cycles_o <= '0;
            source1_wait_cycles_o <= '0;
            source2_wait_cycles_o <= '0;
            status_o <= '0;
        end else begin
            if (m_arvalid && !m_arready && !grant_locked) begin
                grant_locked <= 1'b1;
                locked_source <= candidate;
            end else if (ar_fire) begin
                grant_locked <= 1'b0;
            end

            if (candidate_valid && !m_arready) begin
                case (candidate)
                    2'd0: source0_wait_cycles_o <= source0_wait_cycles_o + 1'b1;
                    2'd1: source1_wait_cycles_o <= source1_wait_cycles_o + 1'b1;
                    default: source2_wait_cycles_o <= source2_wait_cycles_o + 1'b1;
                endcase
            end
            if (active) begin
                if (s0_arvalid && active_source!=2'd0)
                    source0_wait_cycles_o <= source0_wait_cycles_o + 1'b1;
                if (s1_arvalid && active_source!=2'd1)
                    source1_wait_cycles_o <= source1_wait_cycles_o + 1'b1;
                if (s2_arvalid && active_source!=2'd2)
                    source2_wait_cycles_o <= source2_wait_cycles_o + 1'b1;
                if (active_source==2'd1
                        && outstanding==MODEL_MAX_OUTSTANDING && s1_arvalid)
                    source1_wait_cycles_o <= source1_wait_cycles_o + 1'b1;
            end

            if (ar_fire) begin
                if (!active) begin
                    active <= 1'b1;
                    active_source <= candidate;
                    next_source <= candidate==2'd2 ? 2'd0 : candidate + 1'b1;
                end
                case (candidate)
                    2'd0: source0_transactions_o <= source0_transactions_o + 1'b1;
                    2'd1: source1_transactions_o <= source1_transactions_o + 1'b1;
                    default: source2_transactions_o <= source2_transactions_o + 1'b1;
                endcase
            end

            if (m_rvalid && !active)
                status_o[0] <= 1'b1;
            if (m_rvalid && active && m_rready) begin
                case (active_source)
                    2'd0: source0_beats_o <= source0_beats_o + 1'b1;
                    2'd1: source1_beats_o <= source1_beats_o + 1'b1;
                    default: source2_beats_o <= source2_beats_o + 1'b1;
                endcase
                if (m_rresp != 2'b00)
                    status_o[1] <= 1'b1;
            end

            case ({ar_fire,response_last_fire})
                2'b10: outstanding <= outstanding + 1'b1;
                2'b01: begin
                    outstanding <= outstanding - 1'b1;
                    if (outstanding==1)
                        active <= 1'b0;
                end
                // A new model burst can be accepted on the same edge that
                // the previous burst completes, preserving an active epoch.
                2'b11: outstanding <= outstanding;
                default: begin end
            endcase
        end
    end
endmodule
