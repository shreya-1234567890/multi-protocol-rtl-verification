// =============================================================================
// File        : uart_tb.sv
// Title       : UART Transmitter Testbench
// Description : Drives uart_tx with several test bytes, checks tx_done pulse,
//               verifies idle line level, and prints PASS/FAIL.
// =============================================================================

`timescale 1ns/1ps

module uart_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam int CLKS_PER_BIT = 10;   // Small value for fast simulation
    localparam real CLK_PERIOD  = 10.0; // 100 MHz

    // -------------------------------------------------------------------------
    // DUT Signals
    // -------------------------------------------------------------------------
    logic       clk, rst_n;
    logic       tx_start;
    logic [7:0] tx_data;
    logic       tx, tx_busy, tx_done;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (tx),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Helper Task: Send one byte and wait for tx_done
    // -------------------------------------------------------------------------
    task send_byte(input logic [7:0] data);
        @(posedge clk);
        tx_data  <= data;
        tx_start <= 1'b1;
        @(posedge clk);
        tx_start <= 1'b0;
        // Wait for tx_done
        @(posedge tx_done);
        @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Stimulus + Checking
    // -------------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    initial begin
        $display("=== UART TX Testbench START ===");
        rst_n    = 0;
        tx_start = 0;
        tx_data  = 8'h00;

        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Check idle line is HIGH before any transaction
        if (tx === 1'b1) begin
            $display("[PASS] TX line high in IDLE before first byte");
            pass_cnt++;
        end else begin
            $display("[FAIL] TX line NOT high in IDLE");
            fail_cnt++;
        end

        // Test 1: Send 0xA5
        send_byte(8'hA5);
        if (tx === 1'b1) begin
            $display("[PASS] TX returns to idle after 0xA5");
            pass_cnt++;
        end else begin
            $display("[FAIL] TX did not return to idle after 0xA5");
            fail_cnt++;
        end

        // Test 2: Send 0x00
        send_byte(8'h00);
        if (tx === 1'b1) begin
            $display("[PASS] TX returns to idle after 0x00");
            pass_cnt++;
        end else begin
            $display("[FAIL] TX did not return to idle after 0x00");
            fail_cnt++;
        end

        // Test 3: Send 0xFF
        send_byte(8'hFF);
        if (tx === 1'b1) begin
            $display("[PASS] TX returns to idle after 0xFF");
            pass_cnt++;
        end else begin
            $display("[FAIL] TX did not return to idle after 0xFF");
            fail_cnt++;
        end

        // Test 4: Rapid back-to-back
        send_byte(8'h55);
        send_byte(8'hAA);
        if (tx === 1'b1) begin
            $display("[PASS] TX idle after back-to-back");
            pass_cnt++;
        end else begin
            $display("[FAIL] TX not idle after back-to-back");
            fail_cnt++;
        end

        repeat(20) @(posedge clk);

        $display("=== UART TB RESULTS: PASS=%0d FAIL=%0d ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("*** UART TESTBENCH: ALL TESTS PASSED ***");
        else
            $display("*** UART TESTBENCH: %0d TEST(S) FAILED ***", fail_cnt);

        $finish;
    end

    // Timeout watchdog
    initial begin
        #1_000_000;
        $display("[TIMEOUT] UART testbench exceeded time limit");
        $finish;
    end

endmodule