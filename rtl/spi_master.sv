// =============================================================================
// File        : spi_master.sv
// Title       : SPI Master (Mode 0 - CPOL=0, CPHA=0)
// Description : FSM-based SPI master. Shifts 8 bits out on MOSI,
//               drives SCLK, and asserts CS_N low for the duration.
//               FSM: IDLE -> LOAD -> TRANSFER -> DONE -> IDLE
//               Produces a single-cycle done pulse on completion.
// =============================================================================

module spi_master #(
    parameter int CLK_DIV = 4    // SCLK = clk / (2 * CLK_DIV)
)(
    input  logic       clk,       // System clock
    input  logic       rst_n,     // Active-low synchronous reset
    input  logic       start,     // Pulse high 1 cycle to begin transfer
    input  logic [7:0] mosi_data, // Data to send on MOSI

    output logic       sclk,      // SPI clock (CPOL=0)
    output logic       mosi,      // Master-out slave-in
    output logic       cs_n,      // Chip select (active LOW)
    output logic       done,      // Single-cycle pulse on transfer complete
    output logic       busy       // High while transfer in progress
);

    // -------------------------------------------------------------------------
    // FSM State Encoding
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE     = 3'b000,
        LOAD     = 3'b001,
        TRANSFER = 3'b010,
        DONE_ST  = 3'b011
    } state_t;

    state_t state;

    // -------------------------------------------------------------------------
    // Internal Signals
    // -------------------------------------------------------------------------
    logic [7:0]              shift_reg;  // Transmit shift register
    logic [3:0]              bit_cnt;    // Counts 0..7 (bits remaining)
    logic [$clog2(CLK_DIV):0] clk_div_cnt; // Clock divider counter
    logic                    sclk_en;   // Internal SCLK toggle enable
    logic                    sclk_r;    // Registered SCLK

    // -------------------------------------------------------------------------
    // FSM + Datapath
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state       <= IDLE;
            cs_n        <= 1'b1;
            sclk_r      <= 1'b0;
            mosi        <= 1'b0;
            done        <= 1'b0;
            busy        <= 1'b0;
            shift_reg   <= '0;
            bit_cnt     <= '0;
            clk_div_cnt <= '0;
        end else begin
            done <= 1'b0;  // Default: pulse is one cycle

            case (state)

                // ---------------------------------------------------------
                IDLE: begin
                    cs_n   <= 1'b1;
                    sclk_r <= 1'b0;
                    mosi   <= 1'b0;
                    busy   <= 1'b0;
                    if (start) begin
                        shift_reg   <= mosi_data;
                        bit_cnt     <= 4'd7;
                        clk_div_cnt <= '0;
                        busy        <= 1'b1;
                        state       <= LOAD;
                    end
                end

                // ---------------------------------------------------------
                // Assert CS_N one cycle before first SCLK edge
                LOAD: begin
                    cs_n  <= 1'b0;
                    mosi  <= mosi_data[7];  // Pre-drive MSB
                    state <= TRANSFER;
                end

                // ---------------------------------------------------------
                // Toggle SCLK every CLK_DIV cycles, shift on rising edge
                TRANSFER: begin
                    if (clk_div_cnt == CLK_DIV - 1) begin
                        clk_div_cnt <= '0;
                        sclk_r      <= ~sclk_r;

                        if (!sclk_r) begin
                            // Rising edge: data already valid on MOSI
                            // (CPHA=0: data driven before rising edge)
                        end else begin
                            // Falling edge: shift next bit
                            if (bit_cnt == 4'd0) begin
                                state <= DONE_ST;
                            end else begin
                                bit_cnt   <= bit_cnt - 1;
                                shift_reg <= {shift_reg[6:0], 1'b0};
                                mosi      <= shift_reg[6];
                            end
                        end
                    end else
                        clk_div_cnt <= clk_div_cnt + 1;
                end

                // ---------------------------------------------------------
                DONE_ST: begin
                    cs_n   <= 1'b1;
                    sclk_r <= 1'b0;
                    mosi   <= 1'b0;
                    done   <= 1'b1;
                    busy   <= 1'b0;
                    state  <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Drive SCLK from registered value (zero when not in TRANSFER)
    assign sclk = (state == TRANSFER) ? sclk_r : 1'b0;

    // -------------------------------------------------------------------------
    // Assertions
    // -------------------------------------------------------------------------

    // CS_N must be LOW during TRANSFER
    A_SPI_cs_during_xfer: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == TRANSFER) |-> (cs_n == 1'b0)
    ) else $error("ASSERT FAIL: SPI CS_N not LOW during TRANSFER at time %0t", $time);

    // CS_N must be HIGH during IDLE
    A_SPI_cs_idle_high: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == IDLE) |-> (cs_n == 1'b1)
    ) else $error("ASSERT FAIL: SPI CS_N not HIGH during IDLE at time %0t", $time);

    // done is single-cycle pulse
    A_SPI_done_pulse: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(done) |=> !done
    ) else $error("ASSERT FAIL: SPI done held more than one cycle at time %0t", $time);

    // No SCLK without CS asserted
    A_SPI_no_sclk_without_cs: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(sclk) |-> (cs_n == 1'b0)
    ) else $error("ASSERT FAIL: SPI SCLK toggled without CS_N at time %0t", $time);

    // CS released after transfer completes
    A_SPI_cs_released: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(done) |=> (cs_n == 1'b1)
    ) else $error("ASSERT FAIL: SPI CS_N not released after done at time %0t", $time);

endmodule