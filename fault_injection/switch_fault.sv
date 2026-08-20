
`timescale 1ns/1ps

module switch_fault (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [1:0]  proto_sel,
    input  logic        uart_done,
    input  logic        spi_done,
    input  logic        i2c_done,
    output logic        uart_en,
    output logic        spi_en,
    output logic        i2c_en,
    output logic [1:0]  active_proto,
    output logic        proto_ready,
    output logic        switching
);
    logic uart_en_raw, spi_en_raw, i2c_en_raw;

    protocol_switch u_switch (
        .clk         (clk),
        .rst_n       (rst_n),
        .proto_sel   (proto_sel),
        .uart_done   (uart_done),
        .spi_done    (spi_done),
        .i2c_done    (i2c_done),
        .uart_en     (uart_en_raw),
        .spi_en      (spi_en_raw),
        .i2c_en      (i2c_en_raw),
        .active_proto(active_proto),
        .proto_ready (proto_ready),
        .switching   (switching)
    );

    // Fault: all three enables forced HIGH simultaneously
    assign uart_en = 1'b1;
    assign spi_en  = 1'b1;
    assign i2c_en  = 1'b1;

endmodule


module switch_fault_tb;

    localparam real CLK_PERIOD = 10.0;

    logic        clk, rst_n;
    logic [1:0]  proto_sel;
    logic        uart_done, spi_done, i2c_done;
    logic        uart_en, spi_en, i2c_en;
    logic [1:0]  active_proto;
    logic        proto_ready, switching;

    switch_fault dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .proto_sel   (proto_sel),
        .uart_done   (uart_done),
        .spi_done    (spi_done),
        .i2c_done    (i2c_done),
        .uart_en     (uart_en),
        .spi_en      (spi_en),
        .i2c_en      (i2c_en),
        .active_proto(active_proto),
        .proto_ready (proto_ready),
        .switching   (switching)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------
    // Local assertions on faulted enable outputs
    // All three are stuck HIGH => every one-hot check below FAILS.
    // ------------------------------------------------------------------

    // At most one enable may be HIGH at a time
    A_LOCAL_one_hot: assert property (
        @(posedge clk) disable iff (!rst_n)
        $onehot0({uart_en, spi_en, i2c_en})
        ) else $error("[SWITCH FAULT DETECTED] A_LOCAL_one_hot\n\
    Expected : Only one protocol enable may be HIGH at a time\n\
    Observed : UART, SPI and I2C enables are HIGH simultaneously\n\
    Result   : Mutual exclusion violation detected (Time=%0t)", $time);

    // UART and SPI must not overlap
    A_LOCAL_uart_spi: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(uart_en && spi_en)
        ) else $error("[SWITCH FAULT DETECTED] A_LOCAL_uart_spi\n\
    Expected : UART and SPI enables must not overlap\n\
    Observed : uart_en and spi_en are HIGH simultaneously\n\
    Result   : Protocol overlap detected (Time=%0t)", $time);

    // SPI and I2C must not overlap
    A_LOCAL_spi_i2c: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(spi_en && i2c_en)
        ) else $error("[SWITCH FAULT DETECTED] A_LOCAL_spi_i2c\n\
    Expected : SPI and I2C enables must not overlap\n\
    Observed : spi_en and i2c_en are HIGH simultaneously\n\
    Result   : Protocol overlap detected (Time=%0t)", $time);

    // UART and I2C must not overlap
    A_LOCAL_uart_i2c: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(uart_en && i2c_en)
        ) else $error("[SWITCH FAULT DETECTED] A_LOCAL_uart_i2c\n\
    Expected : UART and I2C enables must not overlap\n\
    Observed : uart_en and i2c_en are HIGH simultaneously\n\
    Result   : Protocol overlap detected (Time=%0t)", $time);

    // When switching is deasserted exactly one enable must be active.
    // With fault all three are HIGH => also fails.
    A_LOCAL_single_active_no_switch: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!switching) |-> $onehot0({uart_en, spi_en, i2c_en})
        ) else $error("[SWITCH FAULT DETECTED] A_LOCAL_single_active_no_switch\n\
    Expected : Only one protocol may remain active when switching = 0\n\
    Observed : Multiple protocol enables remained HIGH\n\
    Result   : Invalid protocol switching detected (Time=%0t)", $time);

    initial begin
        $display("=== SWITCH FAULT TB: local assertions WILL FAIL (all enables forced HIGH) ===");
        rst_n     = 0;
        proto_sel = 2'b00;
        uart_done = 0;
        spi_done  = 0;
        i2c_done  = 0;

        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // UART phase
        proto_sel = 2'b00;
        repeat(5) @(posedge clk);
        uart_done = 1'b1; @(posedge clk); uart_done = 1'b0;

        // SPI phase
        proto_sel = 2'b01;
        repeat(5) @(posedge clk);
        spi_done  = 1'b1; @(posedge clk); spi_done  = 1'b0;

        // I2C phase
        proto_sel = 2'b10;
        repeat(5) @(posedge clk);
        i2c_done  = 1'b1; @(posedge clk); i2c_done  = 1'b0;

        repeat(10) @(posedge clk);
        $display("=== SWITCH FAULT TB COMPLETE (assertion failures expected above) ===");
        $finish;
    end

    initial begin
        #100_000;
        $display("[TIMEOUT] Switch fault TB timeout");
        $finish;
    end

endmodule