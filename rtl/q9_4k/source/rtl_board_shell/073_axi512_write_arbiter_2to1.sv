// 3B GENERATED CANDIDATE: not admitted for board use.
`timescale 1ns / 1ps

// Two-input, single-outstanding AXI4 write arbiter for the PL-DDR MIG port.
// A grant is chosen only for AW, then held through the complete W burst and B
// response.  This prevents PS provisioning writes and runtime K/V writes from
// interleaving.  Simultaneous requests use round-robin priority.
module axi512_write_arbiter_2to1 (
    input  logic clk,
    input  logic reset_n,

    input  logic [3:0] s0_awid,
    input  logic [33:0] s0_awaddr,
    input  logic [7:0] s0_awlen,
    input  logic [2:0] s0_awsize,
    input  logic [1:0] s0_awburst,
    input  logic s0_awlock,
    input  logic [3:0] s0_awcache,
    input  logic [2:0] s0_awprot,
    input  logic [3:0] s0_awqos,
    input  logic s0_awvalid,
    output logic s0_awready,
    input  logic [511:0] s0_wdata,
    input  logic [63:0] s0_wstrb,
    input  logic s0_wlast,
    input  logic s0_wvalid,
    output logic s0_wready,
    output logic [3:0] s0_bid,
    output logic [1:0] s0_bresp,
    output logic s0_bvalid,
    input  logic s0_bready,

    input  logic [3:0] s1_awid,
    input  logic [33:0] s1_awaddr,
    input  logic [7:0] s1_awlen,
    input  logic [2:0] s1_awsize,
    input  logic [1:0] s1_awburst,
    input  logic s1_awlock,
    input  logic [3:0] s1_awcache,
    input  logic [2:0] s1_awprot,
    input  logic [3:0] s1_awqos,
    input  logic s1_awvalid,
    output logic s1_awready,
    input  logic [511:0] s1_wdata,
    input  logic [63:0] s1_wstrb,
    input  logic s1_wlast,
    input  logic s1_wvalid,
    output logic s1_wready,
    output logic [3:0] s1_bid,
    output logic [1:0] s1_bresp,
    output logic s1_bvalid,
    input  logic s1_bready,

    output logic [3:0] m_awid,
    output logic [33:0] m_awaddr,
    output logic [7:0] m_awlen,
    output logic [2:0] m_awsize,
    output logic [1:0] m_awburst,
    output logic m_awlock,
    output logic [3:0] m_awcache,
    output logic [2:0] m_awprot,
    output logic [3:0] m_awqos,
    output logic m_awvalid,
    input  logic m_awready,
    output logic [511:0] m_wdata,
    output logic [63:0] m_wstrb,
    output logic m_wlast,
    output logic m_wvalid,
    input  logic m_wready,
    input  logic [3:0] m_bid,
    input  logic [1:0] m_bresp,
    input  logic m_bvalid,
    output logic m_bready,

    output logic [31:0] s0_transactions_o,
    output logic [31:0] s1_transactions_o,
    output logic [31:0] s0_beats_o,
    output logic [31:0] s1_beats_o,
    output logic [7:0] status_o
);
    typedef enum logic [1:0] {A_IDLE, A_DATA, A_RESP} state_t;
    state_t state = A_IDLE;
    logic grant = 1'b0;
    logic round_robin = 1'b0;
    logic idle_select;
    logic [8:0] accepted_beats = '0;
    logic [7:0] granted_awlen = '0;

    always_comb begin
        if (s0_awvalid && s1_awvalid)
            idle_select = round_robin;
        else
            idle_select = s1_awvalid;

        m_awid = idle_select ? s1_awid : s0_awid;
        m_awaddr = idle_select ? s1_awaddr : s0_awaddr;
        m_awlen = idle_select ? s1_awlen : s0_awlen;
        m_awsize = idle_select ? s1_awsize : s0_awsize;
        m_awburst = idle_select ? s1_awburst : s0_awburst;
        m_awlock = idle_select ? s1_awlock : s0_awlock;
        m_awcache = idle_select ? s1_awcache : s0_awcache;
        m_awprot = idle_select ? s1_awprot : s0_awprot;
        m_awqos = idle_select ? s1_awqos : s0_awqos;
        m_awvalid = state == A_IDLE && (idle_select ? s1_awvalid : s0_awvalid);
        s0_awready = state == A_IDLE && !idle_select && m_awready;
        s1_awready = state == A_IDLE && idle_select && m_awready;

        m_wdata = grant ? s1_wdata : s0_wdata;
        m_wstrb = grant ? s1_wstrb : s0_wstrb;
        m_wlast = grant ? s1_wlast : s0_wlast;
        m_wvalid = state == A_DATA && (grant ? s1_wvalid : s0_wvalid);
        s0_wready = state == A_DATA && !grant && m_wready;
        s1_wready = state == A_DATA && grant && m_wready;

        s0_bid = m_bid;
        s1_bid = m_bid;
        s0_bresp = m_bresp;
        s1_bresp = m_bresp;
        s0_bvalid = state == A_RESP && !grant && m_bvalid;
        s1_bvalid = state == A_RESP && grant && m_bvalid;
        m_bready = state == A_RESP && (grant ? s1_bready : s0_bready);
    end

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            state <= A_IDLE;
            grant <= 1'b0;
            round_robin <= 1'b0;
            accepted_beats <= '0;
            granted_awlen <= '0;
            s0_transactions_o <= '0;
            s1_transactions_o <= '0;
            s0_beats_o <= '0;
            s1_beats_o <= '0;
            status_o <= '0;
        end else begin
            case (state)
                A_IDLE: if (m_awvalid && m_awready) begin
                    grant <= idle_select;
                    granted_awlen <= idle_select ? s1_awlen : s0_awlen;
                    accepted_beats <= '0;
                    if (idle_select)
                        s1_transactions_o <= s1_transactions_o + 1'b1;
                    else
                        s0_transactions_o <= s0_transactions_o + 1'b1;
                    state <= A_DATA;
                end
                A_DATA: if (m_wvalid && m_wready) begin
                    accepted_beats <= accepted_beats + 1'b1;
                    if (grant)
                        s1_beats_o <= s1_beats_o + 1'b1;
                    else
                        s0_beats_o <= s0_beats_o + 1'b1;
                    if (m_wlast) begin
                        // AWLEN is zero based; the accepted-beat count before
                        // this edge must equal AWLEN.
                        if (accepted_beats != granted_awlen)
                            status_o[0] <= 1'b1;
                        state <= A_RESP;
                    end
                end
                A_RESP: if (m_bvalid && m_bready) begin
                    if (m_bresp != 2'b00)
                        status_o[1] <= 1'b1;
                    round_robin <= !grant;
                    state <= A_IDLE;
                end
                default: begin
                    status_o[7] <= 1'b1;
                    state <= A_IDLE;
                end
            endcase
        end
    end
endmodule
