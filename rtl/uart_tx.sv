// =============================================================================
// File        : uart_tx.sv
// Title       : UART Transmitter
// Description : 8N1 UART transmitter with parameterised baud-rate divider.
//               FSM: IDLE -> START -> DATA (8 bits) -> STOP -> IDLE
//               Produces a single-cycle tx_done pulse on completion.
// =============================================================================

module uart_tx #(
    parameter int CLKS_PER_BIT = 868   // clk_freq / baud_rate  (e.g. 100MHz/115200)
)(
    input  logic       clk,        // System clock
    input  logic       rst_n,      // Active-low synchronous reset
    input  logic       tx_start,   // Pulse high 1 cycle to begin transmission
    input  logic [7:0] tx_data,    // Byte to transmit (latched on tx_start)
    output logic       tx,         // Serial output line
    output logic       tx_busy,    // High while transmission in progress
    output logic       tx_done     // Single-cycle pulse when byte sent
);

    // -------------------------------------------------------------------------
    // FSM State Encoding
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE  = 3'b000,
        START = 3'b001,
        DATA  = 3'b010,
        STOP  = 3'b011
    } state_t;

    state_t state;

    // -------------------------------------------------------------------------
    // Internal Signals
    // -------------------------------------------------------------------------
    logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;   // Baud-rate clock counter
    logic [2:0]                       bit_idx;    // Current data bit (0-7)
    logic [7:0]                       tx_shift;   // Shift register

    // -------------------------------------------------------------------------
    // FSM + Datapath
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state   <= IDLE;
            tx      <= 1'b1;   // UART idle line is HIGH
            tx_busy <= 1'b0;
            tx_done <= 1'b0;
            clk_cnt <= '0;
            bit_idx <= '0;
            tx_shift <= '0;
        end else begin
            tx_done <= 1'b0;   // Default: pulse is one cycle only

            case (state)

                IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    if (tx_start) begin
                        tx_shift <= tx_data;   // Latch data
                        tx_busy  <= 1'b1;
                        state    <= START;
                    end
                end

                START: begin
                    tx <= 1'b0;   // Start bit = LOW
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        state   <= DATA;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

                DATA: begin
                    tx <= tx_shift[bit_idx];   // LSB first
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= '0;
                            state   <= STOP;
                        end else
                            bit_idx <= bit_idx + 1;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

                STOP: begin
                    tx <= 1'b1;   // Stop bit = HIGH
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= '0;
                        tx_done <= 1'b1;
                        tx_busy <= 1'b0;
                        state   <= IDLE;
                    end else
                        clk_cnt <= clk_cnt + 1;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Assertions
    // -------------------------------------------------------------------------

    // Start bit must be LOW
    A_UART_start_low: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == START) |=>  (tx == 1'b0)
    ) else $error("ASSERT FAIL: UART start bit not LOW at time %0t", $time);

    // Stop bit must be HIGH
    A_UART_stop_high: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == STOP) |=>  (tx == 1'b1)
    ) else $error("ASSERT FAIL: UART stop bit not HIGH at time %0t", $time);

    // tx_done is a single-cycle pulse
    A_UART_done_pulse: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(tx_done) |=> !tx_done
    ) else $error("ASSERT FAIL: UART tx_done held more than one cycle at time %0t", $time);

    // Idle line is HIGH
    A_UART_idle_high: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == IDLE) |-> (tx == 1'b1)
    ) else $error("ASSERT FAIL: UART tx not HIGH in IDLE at time %0t", $time);

endmodule