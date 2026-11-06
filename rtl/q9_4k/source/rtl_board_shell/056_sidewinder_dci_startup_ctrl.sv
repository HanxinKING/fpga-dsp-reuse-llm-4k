// 3B GENERATED CANDIDATE: not admitted for board use.
// Post-configuration DCI calibration sequencer for UltraScale+ devices.
//
// AMD UG570/UG571 require designs that use DCI on multi-function pins to:
//   1. wait until the configuration start-up sequence reaches EOS;
//   2. pulse DCIRESET.RST;
//   3. keep the DCI interface idle until DCIRESET.LOCKED is asserted.
//
// The controller runs from STARTUPE3.CFGMCLK, so it does not depend on the
// DDR4 MIG clock that is held in reset by mig_sys_rst_o.
module sidewinder_dci_startup_ctrl #(
    parameter integer RESET_CYCLES = 16
) (
    input  wire cfgmclk_i,
    input  wire eos_i,
    input  wire dci_locked_i,
    output reg  dci_reset_o = 1'b0,
    output reg  mig_sys_rst_o = 1'b1,
    output reg  ready_o = 1'b0
);
    localparam [1:0] ST_WAIT_EOS  = 2'd0;
    localparam [1:0] ST_PULSE_RST = 2'd1;
    localparam [1:0] ST_WAIT_LOCK = 2'd2;
    localparam [1:0] ST_READY     = 2'd3;

    localparam integer COUNTER_WIDTH =
        (RESET_CYCLES <= 1) ? 1 : $clog2(RESET_CYCLES);

    // STARTUPE3.EOS and DCIRESET.LOCKED are status outputs rather than
    // cfgmclk_i-domain state.  Synchronize both before the startup FSM uses
    // them so metastability cannot release MIG reset or truncate DCIRESET.
    (* ASYNC_REG = "TRUE" *) reg eos_sync_q1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg eos_sync_q2 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg dci_locked_sync_q1 = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg dci_locked_sync_q2 = 1'b0;

    reg [1:0] state = ST_WAIT_EOS;
    reg [COUNTER_WIDTH-1:0] reset_count = {COUNTER_WIDTH{1'b0}};

    always @(posedge cfgmclk_i) begin
        eos_sync_q1        <= eos_i;
        eos_sync_q2        <= eos_sync_q1;
        dci_locked_sync_q1 <= dci_locked_i;
        dci_locked_sync_q2 <= dci_locked_sync_q1;
    end

    always @(posedge cfgmclk_i) begin
        // EOS can return Low only during a new configuration sequence.  This
        // branch also gives deterministic recovery without an external reset.
        if (!eos_sync_q2) begin
            state         <= ST_WAIT_EOS;
            reset_count   <= {COUNTER_WIDTH{1'b0}};
            dci_reset_o   <= 1'b0;
            mig_sys_rst_o <= 1'b1;
            ready_o       <= 1'b0;
        end else begin
            case (state)
                ST_WAIT_EOS: begin
                    reset_count   <= {COUNTER_WIDTH{1'b0}};
                    dci_reset_o   <= 1'b1;
                    mig_sys_rst_o <= 1'b1;
                    ready_o       <= 1'b0;
                    state         <= ST_PULSE_RST;
                end

                ST_PULSE_RST: begin
                    mig_sys_rst_o <= 1'b1;
                    ready_o       <= 1'b0;
                    if (reset_count == RESET_CYCLES - 1) begin
                        dci_reset_o <= 1'b0;
                        state       <= ST_WAIT_LOCK;
                    end else begin
                        dci_reset_o <= 1'b1;
                        reset_count <= reset_count + 1'b1;
                    end
                end

                ST_WAIT_LOCK: begin
                    dci_reset_o <= 1'b0;
                    if (dci_locked_sync_q2) begin
                        mig_sys_rst_o <= 1'b0;
                        ready_o       <= 1'b1;
                        state         <= ST_READY;
                    end
                end

                default: begin // ST_READY
                    dci_reset_o   <= 1'b0;
                    mig_sys_rst_o <= 1'b0;
                    ready_o       <= 1'b1;
                end
            endcase
        end
    end
endmodule
