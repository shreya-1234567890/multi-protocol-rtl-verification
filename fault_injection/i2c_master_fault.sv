
// =============================================================================
// File        : i2c_master_fault.sv
// Fault       : SDA glitch injected while SCL HIGH ? triggers A_I2C_sda_stable
// =============================================================================

`timescale 1ns/1ps

module i2c_master_fault #(
    parameter int CLK_DIV = 10
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start,
    input  logic [6:0] addr,
    input  logic       rw,
    input  logic [7:0] wdata,
    output logic       scl,
    inout  wire        sda,
    output logic       busy,
    output logic       done,
    output logic       ack_err
);

    logic glitch;
    logic sda_fault_oe;
    logic sda_fault_val;
    logic scl_d;

    always_ff @(posedge clk) scl_d <= scl;

    logic [3:0] glitch_cnt;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            glitch_cnt    <= '0;
            glitch        <= 1'b0;
            sda_fault_oe  <= 1'b0;
            sda_fault_val <= 1'b0;
        end else begin
            if (scl && !scl_d && busy) begin
                glitch_cnt    <= 4'd4;
                glitch        <= 1'b1;
                sda_fault_oe  <= 1'b1;
                sda_fault_val <= 1'b0;
            end else if (glitch_cnt > 0) begin
                glitch_cnt <= glitch_cnt - 1;
                if (glitch_cnt == 4'd2) sda_fault_val <= 1'b1;
                if (glitch_cnt == 4'd1) begin
                    sda_fault_oe <= 1'b0;
                    glitch       <= 1'b0;
                end
            end
        end
    end

    assign sda = sda_fault_oe ? sda_fault_val : 1'bz;

    i2c_master #(.CLK_DIV(CLK_DIV)) u_i2c (
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

endmodule


module i2c_master_fault_tb;

    localparam int  CLK_DIV    = 10;
    localparam real CLK_PERIOD = 10.0;

    logic       clk, rst_n, start;
    logic [6:0] addr;
    logic       rw;
    logic [7:0] wdata;
    logic       scl, busy, done, ack_err;

    wire  sda;
    logic sda_slave_drv;
    logic sda_slave_en;

    assign sda = sda_slave_en ? sda_slave_drv : 1'bz;

    i2c_master_fault #(.CLK_DIV(CLK_DIV)) dut (
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
    always #(CLK_PERIOD/2.0) clk = ~clk;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_slave_en  <= 1'b0;
            sda_slave_drv <= 1'b1;
        end else begin
            if (dut.u_i2c.state == 4'h3 ||   // ACK_ADDR
                dut.u_i2c.state == 4'h5) begin // ACK_DATA
                sda_slave_en  <= 1'b1;
                sda_slave_drv <= 1'b0;         // ACK = pull SDA LOW
            end else begin
                sda_slave_en  <= 1'b0;         // release - master/fault drives
                sda_slave_drv <= 1'b1;
            end
        end
    end

    initial begin
        $display("=== I2C FAULT TB: Expecting A_I2C_sda_stable assertion FAILURE ===");

        rst_n = 1'b0;
        start = 1'b0;
        addr  = 7'h50;
        rw    = 1'b0;
        wdata = 8'hA5;

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // Transaction 1
        @(posedge clk); #1;
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;
        // Wait for busy to go high then low (robust done detection)
        @(posedge clk iff (busy === 1'b1));
        @(posedge clk iff (busy === 1'b0));
        repeat(5) @(posedge clk);

        // Transaction 2 - different data to get more assertion hits
        wdata = 8'hFF;
        @(posedge clk); #1;
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;
        @(posedge clk iff (busy === 1'b1));
        @(posedge clk iff (busy === 1'b0));
        repeat(5) @(posedge clk);

        // Transaction 3
        addr  = 7'h27;
        wdata = 8'h5A;
        @(posedge clk); #1;
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;
        @(posedge clk iff (busy === 1'b1));
        @(posedge clk iff (busy === 1'b0));
        repeat(10) @(posedge clk);

        $display("=== I2C FAULT TB COMPLETE (assertion failures expected above) ===");
        $finish;
    end
    
    // ------------------------------------------------------------------
    // Local assertion: detect SDA glitch while SCL is HIGH
    // ------------------------------------------------------------------
    
    A_LOCAL_sda_glitch_detected: assert property (
        @(posedge clk) disable iff (!rst_n)
        (busy && scl) |-> !$changed(sda)
    )
    else $error(
    "[I2C FAULT DETECTED] A_LOCAL_sda_glitch_detected\n\
    Expected : SDA must remain stable while SCL is HIGH\n\
    Observed : SDA changed due to injected glitch\n\
    Result   : I2C protocol violation detected (Time=%0t)",$time);


    initial begin
        #10_000_000;
        $display("[TIMEOUT] I2C fault TB timeout");
        $finish;
    end

endmodule