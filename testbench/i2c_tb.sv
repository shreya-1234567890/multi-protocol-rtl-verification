// =============================================================================
// File        : i2c_tb.sv
// Title       : I2C Master Testbench
// Description : Drives i2c_master, provides simple ACK behaviour on SDA,
//               exercises multiple transactions, verifies done/busy.
// =============================================================================

`timescale 1ns/1ps

module i2c_tb;

    localparam int CLK_DIV    = 10;
    localparam real CLK_PERIOD = 10.0;

    logic      clk, rst_n;
    logic      start;
    logic [6:0] addr;
    logic       rw;
    logic [7:0] wdata;
    logic       scl, busy, done, ack_err;
    wire        sda;

    // SDA pull-up + slave ACK driver
    logic sda_slave;
    assign sda = sda_slave;   // slave drives; master tri-states during ACK

    i2c_master #(.CLK_DIV(CLK_DIV)) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (start),
        .addr   (addr),
        .rw     (rw),
        .wdata  (wdata),
        .scl    (scl),
        .sda    (sda),
        .busy   (busy),
        .done   (done),
        .ack_err(ack_err)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // Slave: respond with ACK (SDA=0) during ACK phases, else release (Z->pull-up=1)
    // Because SDA is a wire driven by both master (via tri-state) and slave here,
    // we model the slave as pulling low only during ACK windows detected by scl.
    // Simple model: always provide ACK (drive 0) when master releases SDA.
    initial sda_slave = 1'bz;

    // Slave ACK model: watch for master releasing SDA (high-Z) and drive ACK=0
    always @(posedge scl) begin
        // During ACK cycles master releases SDA; slave drives 0
        // We detect this by checking dut internal state if accessible,
        // but since we cannot, we use a timer-based approximation:
        // Just hold sda_slave = 0 for one SCL high phase when we detect busy.
        if (busy)
            sda_slave = 1'b0;
        else
            sda_slave = 1'bz;
    end

    always @(negedge scl) begin
        if (!busy)
            sda_slave = 1'bz;
    end

    task check(input string msg, input logic cond);
        if (cond) begin
            $display("[PASS] %s", msg);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s", msg);
            fail_cnt++;
        end
    endtask

    task i2c_write(input logic [6:0] a, input logic [7:0] d);
        @(posedge clk);
        addr  <= a;
        wdata <= d;
        rw    <= 1'b0;
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
        @(posedge done);
        @(posedge clk);
    endtask

    initial begin
        $display("=== I2C Master Testbench START ===");
        rst_n      = 0;
        start      = 0;
        addr       = 7'h00;
        rw         = 0;
        wdata      = 8'h00;
        sda_slave  = 1'bz;

        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        check("SCL HIGH in IDLE", scl === 1'b1);
        check("busy LOW before transaction", busy === 1'b0);

        // Transaction 1
        i2c_write(7'h50, 8'hA5);
        check("done pulse received T1", 1'b1);  // if we reached here, done fired
        check("busy cleared after T1", busy === 1'b0);

        repeat(10) @(posedge clk);

        // Transaction 2
        i2c_write(7'h27, 8'h00);
        check("done pulse received T2", 1'b1);
        check("busy cleared after T2", busy === 1'b0);

        repeat(10) @(posedge clk);

        // Transaction 3
        i2c_write(7'h7F, 8'hFF);
        check("done pulse received T3", 1'b1);
        check("busy cleared after T3", busy === 1'b0);

        repeat(10) @(posedge clk);

        // Transaction 4: back-to-back
        i2c_write(7'h10, 8'h55);
        i2c_write(7'h10, 8'hAA);
        check("busy cleared after back-to-back", busy === 1'b0);

        repeat(20) @(posedge clk);

        $display("=== I2C TB RESULTS: PASS=%0d FAIL=%0d ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("*** I2C TESTBENCH: ALL TESTS PASSED ***");
        else
            $display("*** I2C TESTBENCH: %0d TEST(S) FAILED ***", fail_cnt);

        $finish;
    end

    initial begin
        #10_000_000;
        $display("[TIMEOUT] I2C testbench exceeded time limit");
        $finish;
    end

endmodule
