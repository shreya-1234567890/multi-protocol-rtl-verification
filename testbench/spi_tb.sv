// =============================================================================
// File        : spi_tb.sv
// Title       : SPI Master Testbench
// Description : Drives spi_master with several transfers, checks done pulse,
//               CS_N behaviour, and prints PASS/FAIL summary.
// =============================================================================

`timescale 1ns/1ps

module spi_tb;

    localparam int CLK_DIV   = 4;
    localparam real CLK_PERIOD = 10.0;

    logic       clk, rst_n;
    logic       start;
    logic [7:0] mosi_data;
    logic       sclk, mosi, cs_n, done, busy;

    spi_master #(.CLK_DIV(CLK_DIV)) dut (
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

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task spi_transfer(input logic [7:0] data);
        @(posedge clk);
        mosi_data <= data;
        start     <= 1'b1;
        @(posedge clk);
        start     <= 1'b0;
        @(posedge done);
        @(posedge clk);
    endtask

    task check(input string msg, input logic cond);
        if (cond) begin
            $display("[PASS] %s", msg);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s", msg);
            fail_cnt++;
        end
    endtask

    initial begin
        $display("=== SPI Master Testbench START ===");
        rst_n     = 0;
        start     = 0;
        mosi_data = 8'h00;

        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        check("CS_N HIGH in IDLE before first transfer", cs_n === 1'b1);

        // Transfer 1: 0xA5
        fork
            spi_transfer(8'hA5);
            begin
                @(negedge cs_n);
                check("CS_N asserted LOW during transfer 0xA5", cs_n === 1'b0);
            end
        join
        check("CS_N released HIGH after transfer 0xA5", cs_n === 1'b1);
        check("busy deasserted after done 0xA5", busy === 1'b0);

        repeat(4) @(posedge clk);

        // Transfer 2: 0x00
        spi_transfer(8'h00);
        check("CS_N HIGH after transfer 0x00", cs_n === 1'b1);

        repeat(4) @(posedge clk);

        // Transfer 3: 0xFF
        spi_transfer(8'hFF);
        check("CS_N HIGH after transfer 0xFF", cs_n === 1'b1);

        repeat(4) @(posedge clk);

        // Transfer 4: 0x55
        spi_transfer(8'h55);
        check("CS_N HIGH after transfer 0x55", cs_n === 1'b1);

        repeat(4) @(posedge clk);

        // Transfer 5: back-to-back 0x12 then 0x34
        spi_transfer(8'h12);
        spi_transfer(8'h34);
        check("CS_N HIGH after back-to-back transfers", cs_n === 1'b1);
        check("busy clear after back-to-back", busy === 1'b0);

        repeat(20) @(posedge clk);

        $display("=== SPI TB RESULTS: PASS=%0d FAIL=%0d ===", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("*** SPI TESTBENCH: ALL TESTS PASSED ***");
        else
            $display("*** SPI TESTBENCH: %0d TEST(S) FAILED ***", fail_cnt);

        $finish;
    end

    initial begin
        #500_000;
        $display("[TIMEOUT] SPI testbench exceeded time limit");
        $finish;
    end

endmodule
