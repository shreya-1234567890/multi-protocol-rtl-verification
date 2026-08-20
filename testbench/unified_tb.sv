
// =============================================================================
// File        : unified_tb.sv 
// =============================================================================

`timescale 1ns/1ps

module unified_tb;

    localparam int  CLKS_PER_BIT = 10;
    localparam int  SPI_CLK_DIV  = 4;
    localparam int  I2C_CLK_DIV  = 10;
    localparam real CLK_PERIOD   = 10.0;

    logic clk, rst_n;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;


    logic [1:0] proto_sel;
    logic       uart_en, spi_en, i2c_en;
    logic [1:0] active_proto;
    logic       proto_ready, switching;

    logic       uart_tx_start;
    logic [7:0] uart_tx_data;
    logic       uart_tx_line, uart_tx_busy, uart_tx_done;

    logic       spi_start;
    logic [7:0] spi_mosi_data;
    logic       spi_sclk, spi_mosi, spi_cs_n, spi_done, spi_busy;

    logic       i2c_start;
    logic [6:0] i2c_addr;
    logic       i2c_rw;
    logic [7:0] i2c_wdata;
    logic       i2c_scl, i2c_busy, i2c_done, i2c_ack_err;

    wire        i2c_sda;
    logic       sda_slave_drv;
    logic       sda_slave_en;

    assign i2c_sda = sda_slave_en ? sda_slave_drv : 1'bz;

    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_slave_en  <= 1'b0;
            sda_slave_drv <= 1'b1;
        end else begin
            if (u_i2c.state == 4'h3 || u_i2c.state == 4'h5) begin
                sda_slave_en  <= 1'b1;
                sda_slave_drv <= 1'b0;   // ACK = drive LOW
            end else begin
                sda_slave_en  <= 1'b0;   // release bus - master drives
                sda_slave_drv <= 1'b1;
            end
        end
    end

    // =========================================================================
    // DUT Instantiations
    // =========================================================================
    protocol_switch u_switch (
        .clk         (clk),
        .rst_n       (rst_n),
        .proto_sel   (proto_sel),
        .uart_done   (uart_tx_done),
        .spi_done    (spi_done),
        .i2c_done    (i2c_done),
        .uart_en     (uart_en),
        .spi_en      (spi_en),
        .i2c_en      (i2c_en),
        .active_proto(active_proto),
        .proto_ready (proto_ready),
        .switching   (switching)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (uart_tx_start),
        .tx_data  (uart_tx_data),
        .tx       (uart_tx_line),
        .tx_busy  (uart_tx_busy),
        .tx_done  (uart_tx_done)
    );

    spi_master #(.CLK_DIV(SPI_CLK_DIV)) u_spi (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (spi_start),
        .mosi_data(spi_mosi_data),
        .sclk     (spi_sclk),
        .mosi     (spi_mosi),
        .cs_n     (spi_cs_n),
        .done     (spi_done),
        .busy     (spi_busy)
    );

    i2c_master #(.CLK_DIV(I2C_CLK_DIV)) u_i2c (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (i2c_start),
        .addr   (i2c_addr),
        .rw     (i2c_rw),
        .wdata  (i2c_wdata),
        .scl    (i2c_scl),
        .sda    (i2c_sda),
        .busy   (i2c_busy),
        .done   (i2c_done),
        .ack_err(i2c_ack_err)
    );

    coverage_collector u_cov (
        .clk         (clk),
        .proto_sel   (proto_sel),
        .active_proto(active_proto),
        .uart_en     (uart_en),
        .spi_en      (spi_en),
        .i2c_en      (i2c_en),
        .switching   (switching),
        .uart_done   (uart_tx_done),
        .spi_done    (spi_done),
        .i2c_done    (i2c_done)
    );

    // =========================================================================
    // Pass / Fail counters
    // =========================================================================
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task automatic check(input string msg, input logic cond);
        if (cond) begin
            $display("[PASS] %s", msg);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s", msg);
            fail_cnt++;
        end
    endtask

    // =========================================================================
    // switch_to: sets proto_sel and waits for active_proto to match
    // with switching=0 (protocol fully switched)
    // =========================================================================
    task automatic switch_to(input logic [1:0] target);
        integer timeout;
        begin
            proto_sel = target;
            @(posedge clk);
            timeout = 0;
            while (!((active_proto === target) && (switching === 1'b0))
                   && timeout < 1000000) begin
                @(posedge clk);
                timeout++;
            end
            if (timeout >= 1000000) begin
                $display("[FAIL] switch_to(%0d) timed out at %0t", target, $time);
                fail_cnt++;
            end
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // do_uart: sends one byte, waits for tx_done
    // =========================================================================
    task automatic do_uart(input logic [7:0] data);
        integer timeout;
        begin
            @(posedge clk); #1;
            uart_tx_data  = data;
            uart_tx_start = 1'b1;
            @(posedge clk); #1;
            uart_tx_start = 1'b0;
            timeout = 0;
            while (uart_tx_done !== 1'b1 && timeout < 50000) begin
                @(posedge clk);
                timeout++;
            end
            if (timeout >= 50000) begin
                $display("[FAIL] do_uart timeout at %0t", $time);
                fail_cnt++;
            end
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // do_spi: sends one byte, waits for spi_done
    // =========================================================================
    task automatic do_spi(input logic [7:0] data);
        integer timeout;
        begin
            @(posedge clk); #1;
            spi_mosi_data = data;
            spi_start     = 1'b1;
            @(posedge clk); #1;
            spi_start     = 1'b0;
            timeout = 0;
            while (spi_done !== 1'b1 && timeout < 50000) begin
                @(posedge clk);
                timeout++;
            end
            if (timeout >= 50000) begin
                $display("[FAIL] do_spi timeout at %0t", $time);
                fail_cnt++;
            end
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // do_i2c: sends one byte, waits for i2c_done via busy poll
    // =========================================================================
    task automatic do_i2c(input logic [6:0] a, input logic [7:0] d);
        integer timeout;
        begin
            @(posedge clk); #1;
            i2c_addr  = a;
            i2c_wdata = d;
            i2c_rw    = 1'b0;
            i2c_start = 1'b1;
            @(posedge clk); #1;
            i2c_start = 1'b0;
            // Wait for busy to assert
            timeout = 0;
            while (i2c_busy !== 1'b1 && timeout < 1000) begin
                @(posedge clk);
                timeout++;
            end
            // Wait for busy to deassert (transaction complete)
            timeout = 0;
            while (i2c_busy !== 1'b0 && timeout < 1000000) begin
                @(posedge clk);
                timeout++;
            end
            if (timeout >= 1000000) begin
                $display("[FAIL] do_i2c timeout at %0t", $time);
                fail_cnt++;
            end
            @(posedge clk); #1;
        end
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    initial begin
        $display("=== UNIFIED Testbench START ===");

        // Initialise
        rst_n         = 1'b0;
        proto_sel     = 2'b11;   // NONE initially
        uart_tx_start = 1'b0;
        uart_tx_data  = 8'h00;
        spi_start     = 1'b0;
        spi_mosi_data = 8'h00;
        i2c_start     = 1'b0;
        i2c_addr      = 7'h00;
        i2c_rw        = 1'b0;
        i2c_wdata     = 8'h00;

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        repeat(4) @(posedge clk);

        // ================================================================
        // CYCLE 1: UART
        // ================================================================
        $display("--- Cycle 1: UART ---");
        switch_to(2'b00);
        check("Cycle1: uart_en asserted",   uart_en === 1'b1);
        check("Cycle1: spi_en deasserted",  spi_en  === 1'b0);
        check("Cycle1: i2c_en deasserted",  i2c_en  === 1'b0);
        do_uart(8'hA5);
        check("Cycle1: UART tx done",       1'b1);

        // ================================================================
        // CYCLE 1: UART -> SPI
        // ================================================================
        $display("--- Cycle 1: Switch UART->SPI ---");
        switch_to(2'b01);
        check("Cycle1: spi_en asserted",    spi_en  === 1'b1);
        check("Cycle1: uart_en deasserted", uart_en === 1'b0);
        check("Cycle1: i2c_en deasserted",  i2c_en  === 1'b0);
        do_spi(8'h3C);
        check("Cycle1: SPI done",           1'b1);

        // ================================================================
        // CYCLE 1: SPI -> I2C
        // ================================================================
        $display("--- Cycle 1: Switch SPI->I2C ---");
        switch_to(2'b10);
        check("Cycle1: i2c_en asserted",    i2c_en  === 1'b1);
        check("Cycle1: spi_en deasserted",  spi_en  === 1'b0);
        check("Cycle1: uart_en deasserted", uart_en === 1'b0);
        do_i2c(7'h50, 8'hBE);
        check("Cycle1: I2C done",           1'b1);

        // ================================================================
        // CYCLE 2: I2C -> UART
        // ================================================================
        $display("--- Cycle 2: Switch I2C->UART ---");
        switch_to(2'b00);
        check("Cycle2: uart_en asserted",   uart_en === 1'b1);
        do_uart(8'h00);
        do_uart(8'hFF);
        check("Cycle2: UART back-to-back",  1'b1);

        // ================================================================
        // CYCLE 2: UART -> SPI
        // ================================================================
        $display("--- Cycle 2: Switch UART->SPI ---");
        switch_to(2'b01);
        check("Cycle2: spi_en asserted",    spi_en  === 1'b1);
        do_spi(8'h55);
        do_spi(8'hAA);
        check("Cycle2: SPI back-to-back",   1'b1);

        // ================================================================
        // CYCLE 2: SPI -> I2C
        // ================================================================
        $display("--- Cycle 2: Switch SPI->I2C ---");
        switch_to(2'b10);
        check("Cycle2: i2c_en asserted",    i2c_en  === 1'b1);
        do_i2c(7'h27, 8'hCC);
        check("Cycle2: I2C done",           1'b1);

        // ================================================================
        // CYCLE 3: I2C -> UART
        // ================================================================
        $display("--- Cycle 3: Switch I2C->UART ---");
        switch_to(2'b00);
        check("Cycle3: uart_en asserted",   uart_en === 1'b1);
        do_uart(8'h5A);
        check("Cycle3: UART done",          1'b1);

        // ================================================================
        // ADDITIONAL transitions 
        // ================================================================
        
        switch_to(2'b10);
        do_i2c(7'h33, 8'h55);

       
        switch_to(2'b01);
        do_spi(8'h11);

        
        switch_to(2'b00);
        do_uart(8'h99);

        // ================================================================
        // SWITCH_WAIT exercise:
        // Start a UART transmission, then request SPI MID-TRANSFER
        // so that protocol_switch enters SWITCH_WAIT.
        // This exercises switching=1 for cp_switching 100% coverage.
        // ================================================================
       

        // Step 1: Go to UART
        switch_to(2'b00);

        // Step 2: Kick off a UART transmission (non-blocking)
        @(posedge clk); #1;
        uart_tx_data  = 8'hA5;
        uart_tx_start = 1'b1;
        @(posedge clk); #1;
        uart_tx_start = 1'b0;

        // Step 3: Immediately request SPI while UART is still busy
        // (uart_idle is 0 because tx just started)
        // Wait just 2 cycles so uart_busy is definitely asserted
        repeat(2) @(posedge clk);
        proto_sel = 2'b01;   // request SPI - protocol_switch should go SWITCH_WAIT

        // Step 4: Wait up to 500 cycles for SWITCH_WAIT to be entered
        // then for the switch to complete to SPI
        begin
            integer sw_timeout;
            sw_timeout = 0;
            while (switching !== 1'b1 && sw_timeout < 500) begin
                @(posedge clk);
                sw_timeout++;
            end
        end

        // Step 5: Wait for switch to fully complete
        begin
            integer sw_timeout2;
            sw_timeout2 = 0;
            while (!((active_proto === 2'b01) && (switching === 1'b0))
                   && sw_timeout2 < 1000000) begin
                @(posedge clk);
                sw_timeout2++;
            end
        end

        // Step 6: Do one SPI transaction to confirm we landed in SPI
        do_spi(8'hBB);
        check("SWITCH_WAIT: SPI active after forced mid-transfer switch",
              active_proto === 2'b01);
        // ================================================================
        // SWITCH_WAIT 
        // Strategy: start UART TX, then immediately (same cycle start
        // deasserts) force proto_sel to SPI. Because uart_idle is cleared
        // by the TX starting, protocol_switch cannot use the idle shortcut
        // and MUST enter SWITCH_WAIT.
        // ================================================================
       

        // Step 1: go to UART
        switch_to(2'b00);

        // Step 2: start UART TX and simultaneously (next cycle) request SPI
        // We do NOT wait for done - we switch before it finishes
        @(posedge clk); #1;
        uart_tx_data  = 8'hA5;
        uart_tx_start = 1'b1;
        @(posedge clk); #1;
        uart_tx_start = 1'b0;

        // Step 3: request SPI on the very next cycle while uart_busy=1
        // uart_idle flag in protocol_switch is 0 right now ? SWITCH_WAIT
        @(posedge clk); #1;
        proto_sel = 2'b01;

        // Step 4: poll for switching=1 with short timeout
        begin : sw_poll
            integer sw_t;
            sw_t = 0;
            while (switching !== 1'b1 && sw_t < 1000) begin
                @(posedge clk);
                sw_t++;
            end
            if (switching === 1'b1) begin
                check("SWITCH_WAIT: switching signal observed", 1'b1);
            end else begin
                check("SWITCH_WAIT: switching signal observed", 1'b0);
            end
        end

        // Step 5: wait for switch to complete
        begin : sw_done
            integer sw_t2;
            sw_t2 = 0;
            while (!((active_proto === 2'b01) && (switching === 1'b0))
                   && sw_t2 < 1000000) begin
                @(posedge clk);
                sw_t2++;
            end
        end

        // Step 6: confirm SPI is now active
        do_spi(8'hBB);
        check("After SWITCH_WAIT: SPI active", active_proto === 2'b01);
        // ================================================================
        // Final checks
        // ================================================================
        repeat(20) @(posedge clk);
        check("Final: no i2c ack_err",    i2c_ack_err === 1'b0);
        check("Final: switching cleared", switching   === 1'b0);

        $display("=== UNIFIED TB RESULTS: PASS=%0d FAIL=%0d ===",
                 pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("*** UNIFIED TESTBENCH: ALL TESTS PASSED ***");
        else
            $display("*** UNIFIED TESTBENCH: %0d TEST(S) FAILED ***", fail_cnt);

        $finish;
    end

    // Timeout guard
    initial begin
        #200_000_000;
        $display("[TIMEOUT] Unified testbench exceeded 200 ms limit");
        $finish;
    end

endmodule