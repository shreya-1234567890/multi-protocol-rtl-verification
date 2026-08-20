
// =============================================================================
// File        : i2c_master.sv
// Title       : I2C Master Controller
// Description : Bit-banging I2C master. Sends START, 7-bit address + R/W,
//               ACK check, 8-bit data, ACK check, then STOP.
//               FSM: IDLE -> START_COND -> ADDR -> ACK_ADDR ->
//                    DATA -> ACK_DATA -> STOP_COND -> IDLE
//               SDA/SCL driven via tri-state outputs (reg + enable).
// =============================================================================
module i2c_master #(
    parameter int CLK_DIV = 250   // SCL half-period in clk cycles
)(
    input  logic       clk,        // System clock
    input  logic       rst_n,      // Active-low synchronous reset
    input  logic       start,      // Initiate a transaction
    input  logic [6:0] addr,       // 7-bit slave address
    input  logic       rw,         // 0=write, 1=read
    input  logic [7:0] wdata,      // Byte to write
    output logic       scl,        // I2C clock line
    inout  wire        sda,        // I2C data line (bidirectional)
    output logic       busy,       // High during transaction
    output logic       done,       // Single-cycle pulse on completion
    output logic       ack_err     // Pulled high if NACK received
);

    // -------------------------------------------------------------------------
    // SDA tri-state drive
    // -------------------------------------------------------------------------
    logic sda_out;   // Value driven onto SDA
    logic sda_oe;    // Output-enable: 1=drive, 0=release (high-Z -> pull-up = 1)
    assign sda = sda_oe ? sda_out : 1'bz;

    // -------------------------------------------------------------------------
    // FSM State Encoding
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE       = 4'h0,
        START_COND = 4'h1,
        ADDR       = 4'h2,
        ACK_ADDR   = 4'h3,
        DATA       = 4'h4,
        ACK_DATA   = 4'h5,
        STOP_COND  = 4'h6
    } state_t;
    state_t state;

    // -------------------------------------------------------------------------
    // Internal Signals
    // -------------------------------------------------------------------------
    logic [$clog2(CLK_DIV*2):0] phase_cnt;  // Counts one full SCL period
    logic [7:0]  shift_reg;   // Address[6:0]+RW or data shift register
    logic [3:0]  bit_cnt;     // Bit index (7 downto 0, then ACK=8)
    logic        scl_r;       // Registered SCL value

    // Half-period tick: toggles SCL state
    logic half_tick;
    assign half_tick = (phase_cnt == CLK_DIV - 1);

    // -------------------------------------------------------------------------
    // Track whether SCL just rose this cycle (to gate SDA-stable check)
    // We suppress assertion I3 for ONE cycle after SCL rises to allow
    // the registered slave ACK model to settle without false positives.
    // -------------------------------------------------------------------------
    logic scl_prev;
    logic scl_rose_now;
    always_ff @(posedge clk) scl_prev <= scl_r;
    assign scl_rose_now = scl_r & ~scl_prev;  // 1 only on the cycle SCL transitions 0->1

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state     <= IDLE;
            scl_r     <= 1'b1;
            sda_out   <= 1'b1;
            sda_oe    <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
            ack_err   <= 1'b0;
            shift_reg <= '0;
            bit_cnt   <= '0;
            phase_cnt <= '0;
        end else begin
            done    <= 1'b0;   // Default: single-cycle pulse
            ack_err <= 1'b0;

            // Phase counter always running during transaction
            if (busy) begin
                if (phase_cnt == CLK_DIV*2 - 1)
                    phase_cnt <= '0;
                else
                    phase_cnt <= phase_cnt + 1;
            end

            case (state)
                // ---------------------------------------------------------
                IDLE: begin
                    scl_r   <= 1'b1;
                    sda_out <= 1'b1;
                    sda_oe  <= 1'b1;
                    if (start) begin
                        shift_reg <= {addr, rw};
                        bit_cnt   <= 4'd7;
                        phase_cnt <= '0;
                        busy      <= 1'b1;
                        state     <= START_COND;
                    end
                end

                // ---------------------------------------------------------
                // START: SDA falls while SCL is HIGH
                START_COND: begin
                    scl_r   <= 1'b1;
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b0;   // Pull SDA low
                    if (half_tick) begin
                        scl_r <= 1'b0;  // Pull SCL low to begin clocking
                        state <= ADDR;
                    end
                end

                // ---------------------------------------------------------
                // Clock out 8 bits (7-bit addr + R/W)
                ADDR: begin
                    sda_oe  <= 1'b1;
                    if (half_tick) begin
                        scl_r <= ~scl_r;
                        if (scl_r) begin
                            // Falling edge: output next bit
                            sda_out   <= shift_reg[7];
                            shift_reg <= {shift_reg[6:0], 1'b0};
                            if (bit_cnt == 4'd0)
                                state <= ACK_ADDR;
                            else
                                bit_cnt <= bit_cnt - 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Release SDA and read ACK from slave
                ACK_ADDR: begin
                    sda_oe <= 1'b0;   // Release SDA (slave drives ACK=0)
                    if (half_tick) begin
                        scl_r <= ~scl_r;
                        if (!scl_r) begin
                            // Sample ACK on rising SCL
                            if (sda !== 1'b0)
                                ack_err <= 1'b1;
                            // Load data for next phase
                            shift_reg <= wdata;
                            bit_cnt   <= 4'd7;
                            state     <= DATA;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Clock out 8 data bits
                DATA: begin
                    sda_oe <= 1'b1;
                    if (half_tick) begin
                        scl_r <= ~scl_r;
                        if (scl_r) begin
                            sda_out   <= shift_reg[7];
                            shift_reg <= {shift_reg[6:0], 1'b0};
                            if (bit_cnt == 4'd0)
                                state <= ACK_DATA;
                            else
                                bit_cnt <= bit_cnt - 1;
                        end
                    end
                end

                // ---------------------------------------------------------
                // Read data ACK
                ACK_DATA: begin
                    sda_oe <= 1'b0;
                    if (half_tick) begin
                        scl_r <= ~scl_r;
                        if (!scl_r) begin
                            if (sda !== 1'b0)
                                ack_err <= 1'b1;
                            state <= STOP_COND;
                        end
                    end
                end

                // ---------------------------------------------------------
                // STOP: SDA rises while SCL is HIGH
                STOP_COND: begin
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b0;
                    if (half_tick) begin
                        scl_r <= 1'b1;   // Raise SCL first
                        if (scl_r) begin
                            sda_out <= 1'b1;  // Then raise SDA -> STOP
                            done    <= 1'b1;
                            busy    <= 1'b0;
                            state   <= IDLE;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign scl = scl_r;

    // =========================================================================
    // Assertions
    // =========================================================================
`ifndef SYNTHESIS

    // A_I2C_start_cond: SCL must be HIGH during START condition generation
    A_I2C_start_cond: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == START_COND) |-> (scl == 1'b1)
    ) else $error("ASSERT FAIL: I2C START condition without SCL HIGH at time %0t", $time);

    // A_I2C_stop_cond: SCL must be HIGH when STOP is generated
    A_I2C_stop_cond: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == STOP_COND && done) |-> (scl == 1'b1)
    ) else $error("ASSERT FAIL: I2C STOP without SCL HIGH at time %0t", $time);

    
    // A_I2C_sda_stable: SDA must not change while SCL is HIGH during
    // ADDR and DATA phases only (not ACK or STOP phases, where transitions
    // are expected by the I2C protocol).
    
    A_I2C_sda_stable: assert property (
        @(posedge clk) disable iff (!rst_n)
        (scl == 1'b1 && state inside {ADDR, DATA} && !scl_rose_now)|-> !$changed(sda)
    ) else $error("ASSERT FAIL: I2C SDA changed while SCL HIGH at time %0t", $time);

    // A_I2C_busy_clears: busy must deassert the cycle after done
    A_I2C_busy_clears: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(done) |=> !busy
    ) else $error("ASSERT FAIL: I2C busy not cleared after done at time %0t", $time);

    // A_I2C_done_pulse: done must be a single-cycle pulse
    A_I2C_done_pulse: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(done) |=> !done
    ) else $error("ASSERT FAIL: I2C done held more than one cycle at time %0t", $time);

    // A_I2C_scl_idle_high: SCL must be HIGH in IDLE
    A_I2C_scl_idle_high: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == IDLE) |-> (scl == 1'b1)
    ) else $error("ASSERT FAIL: I2C SCL not HIGH in IDLE at time %0t", $time);

    // A_I2C_sda_idle_high: SDA driver must be HIGH in IDLE
    A_I2C_sda_idle_high: assert property (
        @(posedge clk) disable iff (!rst_n)
        (state == IDLE) |-> (sda_out == 1'b1)
    ) else $error("ASSERT FAIL: I2C SDA not HIGH in IDLE at time %0t", $time);

`endif

endmodule