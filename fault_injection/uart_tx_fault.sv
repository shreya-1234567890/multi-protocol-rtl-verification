`timescale 1ns/1ps

// Fault wrapper: exposes tx_raw so testbench can compare against faulted tx
module uart_tx_fault #(
    parameter int CLKS_PER_BIT = 10
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx,
    output logic       tx_raw,   // unfaulted DUT output (for TB comparison)
    output logic       tx_busy,
    output logic       tx_done
);
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (tx_raw),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    // Fault: whenever the DUT drives HIGH during a busy frame, force it LOW.
    // This corrupts every HIGH bit including the stop bit.
    assign tx = (tx_busy && tx_raw) ? 1'b0 : tx_raw;

endmodule


module uart_tx_fault_tb;

    localparam int  CLKS_PER_BIT = 10;
    localparam real CLK_PERIOD   = 10.0;

    logic       clk, rst_n, tx_start;
    logic [7:0] tx_data;
    logic       tx, tx_raw, tx_busy, tx_done;

    uart_tx_fault #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (tx),
        .tx_raw   (tx_raw),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------
    // Local assertions comparing faulted tx against raw DUT output
    // ------------------------------------------------------------------

    // Core fault assertion:
    // Whenever the raw DUT drives HIGH during a busy frame, the faulted
    // tx must still be HIGH (no suppression). Since the fault suppresses
    // it to LOW, this ALWAYS FAILS when tx_busy=1 and tx_raw=1.
    A_LOCAL_fault_suppresses_high: assert property (
        @(posedge clk) disable iff (!rst_n)
        (tx_busy && tx_raw) |-> (tx == 1'b1)
        ) else $error("[UART FAULT DETECTED] A_LOCAL_fault_suppresses_high\n\
    Expected : tx = HIGH during transmission\n\
    Observed : tx forced LOW by injected fault\n\
    Result   : Fault detected successfully (Time=%0t)", $time);

    // The faulted output must equal the raw output at all times.
    // This fails whenever the fault gate is active (tx_busy && tx_raw).
    A_LOCAL_tx_matches_raw: assert property (
        @(posedge clk) disable iff (!rst_n)
        (tx == tx_raw)
        ) else $error("[UART FAULT DETECTED] A_LOCAL_tx_matches_raw\n\
    Expected : tx == tx_raw\n\
    Observed : tx != tx_raw due to injected fault\n\
    Result   : Output corruption detected (Time=%0t)", $time);

    // During busy, tx must never be LOW when tx_raw is HIGH (stop bit check).
    A_LOCAL_no_suppression_during_busy: assert property (
        @(posedge clk) disable iff (!rst_n)
        tx_busy |-> !(tx_raw == 1'b1 && tx == 1'b0)
        ) else $error("[UART FAULT DETECTED] A_LOCAL_no_suppression_during_busy\n\
    Expected : HIGH bits remain unchanged during transmission\n\
    Observed : HIGH bit suppressed to LOW\n\
    Result   : Transmission fault detected (Time=%0t)", $time);

    initial begin
        $display("=== UART FAULT TB: local assertions WILL FAIL (stop-bit forced LOW) ===");
        rst_n    = 0;
        tx_start = 0;
        tx_data  = 8'hFF;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Transfer 1: 0xFF - all data bits HIGH, stop bit HIGH
        // Fault forces all of them LOW => assertions fire on every HIGH bit
        tx_data  <= 8'hFF;
        tx_start <= 1'b1;
        @(posedge clk);
        tx_start <= 1'b0;
        @(posedge tx_done);
        @(posedge clk);

        repeat(5) @(posedge clk);

        // Transfer 2: 0xA5 - mix of HIGH and LOW bits
        tx_data  <= 8'hA5;
        tx_start <= 1'b1;
        @(posedge clk);
        tx_start <= 1'b0;
        @(posedge tx_done);
        @(posedge clk);

        repeat(10) @(posedge clk);
        $display("=== UART FAULT TB COMPLETE (assertion failures expected above) ===");
        $finish;
    end

    initial begin
        #200_000;
        $display("[TIMEOUT] UART fault TB timeout");
        $finish;
    end

endmodule