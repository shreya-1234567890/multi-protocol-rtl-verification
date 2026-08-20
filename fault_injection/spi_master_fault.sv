`timescale 1ns/1ps

module spi_master_fault #(
    parameter int CLK_DIV = 4
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start,
    input  logic [7:0] mosi_data,
    output logic       sclk,
    output logic       mosi,
    output logic       cs_n,
    output logic       done,
    output logic       busy
);
    logic cs_n_raw;

    spi_master #(.CLK_DIV(CLK_DIV)) u_spi (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .mosi_data(mosi_data),
        .sclk     (sclk),
        .mosi     (mosi),
        .cs_n     (cs_n_raw),
        .done     (done),
        .busy     (busy)
    );

    // Fault: CS_N stuck HIGH regardless of transfer state
    assign cs_n = 1'b1;

endmodule


module spi_master_fault_tb;

    localparam int  CLK_DIV    = 4;
    localparam real CLK_PERIOD = 10.0;

    logic       clk, rst_n, start;
    logic [7:0] mosi_data;
    logic       sclk, mosi, cs_n, done, busy;

    spi_master_fault #(.CLK_DIV(CLK_DIV)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .mosi_data(mosi_data),
        .sclk     (sclk),
        .mosi     (mosi),
        .cs_n     (cs_n),
        .done     (done),
        .busy     (busy)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------
    // Local assertions on faulted output cs_n
    // ------------------------------------------------------------------

    // CS_N must be LOW while a transfer is in progress (busy=1).
    // Fault holds cs_n HIGH => FAILS every cycle busy is asserted.
    A_LOCAL_cs_low_while_busy: assert property (
        @(posedge clk) disable iff (!rst_n)
        busy |-> (cs_n == 1'b0)
        ) else $error("[SPI FAULT DETECTED] A_LOCAL_cs_low_while_busy\n\
    Expected : CS_N = LOW during active SPI transfer\n\
    Observed : CS_N remained HIGH (stuck-HIGH fault)\n\
    Result   : Chip Select fault detected (Time=%0t)", $time);


    // SCLK must not toggle when CS_N is HIGH.
    // Fault keeps cs_n HIGH so any SCLK edge is illegal.
    A_LOCAL_no_sclk_cs_high: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(sclk) |-> (cs_n == 1'b0)
        ) else $error("[SPI FAULT DETECTED] A_LOCAL_no_sclk_cs_high\n\
    Expected : SCLK activity only when CS_N is LOW\n\
    Observed : SCLK toggled while CS_N remained HIGH\n\
    Result   : Invalid SPI transaction detected (Time=%0t)", $time);


    // After done, cs_n must already be HIGH - here it was never LOW so
    // the transition (LOW->HIGH) never happened; assert it WAS LOW beforehand.
    A_LOCAL_cs_was_low_before_done: assert property (
        @(posedge clk) disable iff (!rst_n)
        $rose(done) |-> $past(cs_n, 2) == 1'b0
        ) else $error("[SPI FAULT DETECTED] A_LOCAL_cs_was_low_before_done\n\
    Expected : CS_N must go LOW before transfer completion\n\
    Observed : CS_N never asserted LOW before DONE\n\
    Result   : Transfer completion protocol violated (Time=%0t)", $time);


    initial begin
        $display("=== SPI FAULT TB: local assertions WILL FAIL (CS stuck HIGH) ===");
        rst_n     = 0;
        start     = 0;
        mosi_data = 8'hA5;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Transfer 1
        mosi_data <= 8'hA5;
        start     <= 1'b1;
        @(posedge clk);
        start     <= 1'b0;
        @(posedge done);
        @(posedge clk);

        repeat(4) @(posedge clk);

        // Transfer 2
        mosi_data <= 8'h3C;
        start     <= 1'b1;
        @(posedge clk);
        start     <= 1'b0;
        @(posedge done);
        @(posedge clk);

        repeat(10) @(posedge clk);
        $display("=== SPI FAULT TB COMPLETE (assertion failures expected above) ===");
        $finish;
    end

    initial begin
        #500_000;
        $display("[TIMEOUT] SPI fault TB timeout");
        $finish;
    end

endmodule