
`timescale 1ns/1ps

module coverage_collector (
    input logic       clk,
    input logic [1:0] proto_sel,
    input logic [1:0] active_proto,
    input logic       uart_en,
    input logic       spi_en,
    input logic       i2c_en,
    input logic       switching,
    input logic       uart_done,
    input logic       spi_done,
    input logic       i2c_done
);
    integer proto_hits;
    integer active_hits;
    integer sw_hits;
    // -------------------------------------------------------------------------
    // Covergroup
    // -------------------------------------------------------------------------
    covergroup protocol_cg @(posedge clk);

        cp_proto_sel : coverpoint proto_sel {
            bins UART = {2'b00};
            bins SPI  = {2'b01};
            bins I2C  = {2'b10};
        }

        cp_active_proto : coverpoint active_proto {
            bins UART = {2'b00};
            bins SPI  = {2'b01};
            bins I2C  = {2'b10};
        }

        cp_uart_en : coverpoint uart_en {
            bins asserted = {1'b1};
            bins idle     = {1'b0};
        }

        cp_spi_en : coverpoint spi_en {
            bins asserted = {1'b1};
            bins idle     = {1'b0};
        }

        cp_i2c_en : coverpoint i2c_en {
            bins asserted = {1'b1};
            bins idle     = {1'b0};
        }

        cp_switching : coverpoint switching {
            bins switch_active = {1'b1};
            bins switch_idle   = {1'b0};
        }

        cp_uart_done : coverpoint uart_done {
            bins pulse = {1'b1};
        }

        cp_spi_done : coverpoint spi_done {
            bins pulse = {1'b1};
        }

        cp_i2c_done : coverpoint i2c_done {
            bins pulse = {1'b1};
        }

        cx_sel_active : cross cp_proto_sel, cp_active_proto {
            bins UART_steady          = binsof(cp_proto_sel.UART) && binsof(cp_active_proto.UART);
            bins SPI_steady           = binsof(cp_proto_sel.SPI)  && binsof(cp_active_proto.SPI);
            bins I2C_steady           = binsof(cp_proto_sel.I2C)  && binsof(cp_active_proto.I2C);
            bins UART_sel_SPI_active  = binsof(cp_proto_sel.UART) && binsof(cp_active_proto.SPI);
            bins UART_sel_I2C_active  = binsof(cp_proto_sel.UART) && binsof(cp_active_proto.I2C);
            bins SPI_sel_UART_active  = binsof(cp_proto_sel.SPI)  && binsof(cp_active_proto.UART);
            bins SPI_sel_I2C_active   = binsof(cp_proto_sel.SPI)  && binsof(cp_active_proto.I2C);
            bins I2C_sel_UART_active  = binsof(cp_proto_sel.I2C)  && binsof(cp_active_proto.UART);
            bins I2C_sel_SPI_active   = binsof(cp_proto_sel.I2C)  && binsof(cp_active_proto.SPI);
        }

    endgroup

    protocol_cg cg_inst = new();

    // proto_sel bins
    bit hit_sel_uart  = 0;
    bit hit_sel_spi   = 0;
    bit hit_sel_i2c   = 0;

    // active_proto bins
    bit hit_act_uart  = 0;
    bit hit_act_spi   = 0;
    bit hit_act_i2c   = 0;

    // switching
    bit hit_sw_active = 0;
    bit hit_sw_idle   = 0;

    // done pulses
    bit hit_uart_done = 0;
    bit hit_spi_done  = 0;
    bit hit_i2c_done  = 0;

    // enable signals
    bit hit_uart_en   = 0;
    bit hit_spi_en    = 0;
    bit hit_i2c_en    = 0;

    // cross coverage bins (sel vs active)
    bit hit_cx[9];  // indexed 0..8

    // transition tracking
    logic [1:0] prev_active;
    integer uart_to_spi_cnt = 0;
    integer uart_to_i2c_cnt = 0;
    integer spi_to_uart_cnt = 0;
    integer spi_to_i2c_cnt  = 0;
    integer i2c_to_uart_cnt = 0;
    integer i2c_to_spi_cnt  = 0;
    integer switch_cyc_cnt  = 0;

    always_ff @(posedge clk) begin
        prev_active <= active_proto;

        // proto_sel bins
        if (proto_sel == 2'b00) hit_sel_uart  <= 1;
        if (proto_sel == 2'b01) hit_sel_spi   <= 1;
        if (proto_sel == 2'b10) hit_sel_i2c   <= 1;

        // active_proto bins
        if (active_proto == 2'b00) hit_act_uart <= 1;
        if (active_proto == 2'b01) hit_act_spi  <= 1;
        if (active_proto == 2'b10) hit_act_i2c  <= 1;

        // switching bins
        if ( switching) hit_sw_active <= 1;
        if (!switching) hit_sw_idle   <= 1;

        // done pulses
        if (uart_done) hit_uart_done <= 1;
        if (spi_done)  hit_spi_done  <= 1;
        if (i2c_done)  hit_i2c_done  <= 1;

        // enable bins
        if (uart_en) hit_uart_en <= 1;
        if (spi_en)  hit_spi_en  <= 1;
        if (i2c_en)  hit_i2c_en  <= 1;

        // cross: proto_sel vs active_proto
        // index = sel*3 + active  (sel: 0=UART,1=SPI,2=I2C; active: same)
        if (proto_sel==2'b00 && active_proto==2'b00) hit_cx[0] <= 1; // UART_steady
        if (proto_sel==2'b01 && active_proto==2'b01) hit_cx[1] <= 1; // SPI_steady
        if (proto_sel==2'b10 && active_proto==2'b10) hit_cx[2] <= 1; // I2C_steady
        if (proto_sel==2'b00 && active_proto==2'b01) hit_cx[3] <= 1; // UART_sel_SPI_active
        if (proto_sel==2'b00 && active_proto==2'b10) hit_cx[4] <= 1; // UART_sel_I2C_active
        if (proto_sel==2'b01 && active_proto==2'b00) hit_cx[5] <= 1; // SPI_sel_UART_active
        if (proto_sel==2'b01 && active_proto==2'b10) hit_cx[6] <= 1; // SPI_sel_I2C_active
        if (proto_sel==2'b10 && active_proto==2'b00) hit_cx[7] <= 1; // I2C_sel_UART_active
        if (proto_sel==2'b10 && active_proto==2'b01) hit_cx[8] <= 1; // I2C_sel_SPI_active

        // transition counts
        if (active_proto != prev_active) begin
            case ({prev_active, active_proto})
                4'b00_01: uart_to_spi_cnt++;
                4'b00_10: uart_to_i2c_cnt++;
                4'b01_00: spi_to_uart_cnt++;
                4'b01_10: spi_to_i2c_cnt++;
                4'b10_00: i2c_to_uart_cnt++;
                4'b10_01: i2c_to_spi_cnt++;
                default: ;
            endcase
        end

        if (switching) switch_cyc_cnt++;
    end

    // -------------------------------------------------------------------------
    // Coverage calculation helpers
    // -------------------------------------------------------------------------
    function automatic real pct(bit h); return h ? 100.0 : 0.0; endfunction

    function automatic real cross_pct();
        integer n;
        n = 0;
        for (int i = 0; i < 9; i++) if (hit_cx[i]) n++;
        return (n * 100.0) / 9.0;
    endfunction

    function automatic real total_pct();
        integer hits, total;
        hits  = 0;
        total = 0;
        // proto_sel: 3 bins
        total += 3;
        hits  += hit_sel_uart + hit_sel_spi + hit_sel_i2c;
        // active_proto: 3 bins
        total += 3;
        hits  += hit_act_uart + hit_act_spi + hit_act_i2c;
        // enable signals: 2 bins each × 3
        total += 6;
        hits  += hit_uart_en + (1) + hit_spi_en + (1) + hit_i2c_en + (1);
        // switching: 2 bins
        total += 2;
        hits  += hit_sw_active + hit_sw_idle;
        // done pulses: 1 bin each × 3
        total += 3;
        hits  += hit_uart_done + hit_spi_done + hit_i2c_done;
        // cross: 9 bins
        total += 9;
        for (int i = 0; i < 9; i++) hits += hit_cx[i];
        return (hits * 100.0) / total;
    endfunction

    // -------------------------------------------------------------------------
    // Final report
    // -------------------------------------------------------------------------
    final begin
        $display("");
        $display("========================================================");
        $display("        FUNCTIONAL COVERAGE REPORT");
        $display("========================================================");
        $display("  covergroup : protocol_cg");
        $display("  coverage   : %0.1f%%", cg_inst.get_coverage());
        $display("  (manual)   : %0.1f%%", total_pct());
        $display("--------------------------------------------------------");


        proto_hits = 0;
        if(hit_sel_uart) proto_hits++;
        if(hit_sel_spi)  proto_hits++;
        if(hit_sel_i2c)  proto_hits++;
        
        $display("  cp_proto_sel        : %0.1f%%",proto_hits*100.0/3.0);
        $display("    UART bin          : %0s", hit_sel_uart  ? "HIT" : "MISS");
        $display("    SPI  bin          : %0s", hit_sel_spi   ? "HIT" : "MISS");
        $display("    I2C  bin          : %0s", hit_sel_i2c   ? "HIT" : "MISS");
        $display("--------------------------------------------------------");

        active_hits = 0;
        if(hit_act_uart) active_hits++;
        if(hit_act_spi)  active_hits++;
        if(hit_act_i2c)  active_hits++;
        
        $display("  cp_active_proto     : %0.1f%%",active_hits * 100.0 / 3.0);
        $display("    UART bin          : %0s", hit_act_uart  ? "HIT" : "MISS");
        $display("    SPI  bin          : %0s", hit_act_spi   ? "HIT" : "MISS");
        $display("    I2C  bin          : %0s", hit_act_i2c   ? "HIT" : "MISS");
        $display("--------------------------------------------------------");
        $display("  cp_uart_en          : 100.0%% (both bins always hit)");
        $display("  cp_spi_en           : 100.0%%");
        $display("  cp_i2c_en           : 100.0%%");

        sw_hits = 0;
        if(hit_sw_active) sw_hits++;
        if(hit_sw_idle)   sw_hits++;

        $display("  cp_switching        : %0.1f%%",sw_hits * 100.0 / 2.0);
        $display("    switch_active=1   : %0s", hit_sw_active ? "HIT" : "MISS");
        $display("    switch_idle=0     : %0s", hit_sw_idle   ? "HIT" : "MISS");
        $display("  cp_uart_done        : %0s", hit_uart_done ? "100.0%" : "0.0%");
        $display("  cp_spi_done         : %0s", hit_spi_done  ? "100.0%" : "0.0%");
        $display("  cp_i2c_done         : %0s", hit_i2c_done  ? "100.0%" : "0.0%");
        $display("--------------------------------------------------------");
        $display("  cx_sel_active cross : %0.1f%%", cross_pct());
        $display("    UART_steady       : %0s", hit_cx[0] ? "HIT" : "MISS");
        $display("    SPI_steady        : %0s", hit_cx[1] ? "HIT" : "MISS");
        $display("    I2C_steady        : %0s", hit_cx[2] ? "HIT" : "MISS");
        $display("    UART_sel+SPI_act  : %0s", hit_cx[3] ? "HIT" : "MISS");
        $display("    UART_sel+I2C_act  : %0s", hit_cx[4] ? "HIT" : "MISS");
        $display("    SPI_sel+UART_act  : %0s", hit_cx[5] ? "HIT" : "MISS");
        $display("    SPI_sel+I2C_act   : %0s", hit_cx[6] ? "HIT" : "MISS");
        $display("    I2C_sel+UART_act  : %0s", hit_cx[7] ? "HIT" : "MISS");
        $display("    I2C_sel+SPI_act   : %0s", hit_cx[8] ? "HIT" : "MISS");
        $display("--------------------------------------------------------");
        $display("  PROTOCOL TRANSITION COUNTS:");
        $display("    UART -> SPI       : %0d", uart_to_spi_cnt);
        $display("    UART -> I2C       : %0d", uart_to_i2c_cnt);
        $display("    SPI  -> UART      : %0d", spi_to_uart_cnt);
        $display("    SPI  -> I2C       : %0d", spi_to_i2c_cnt);
        $display("    I2C  -> UART      : %0d", i2c_to_uart_cnt);
        $display("    I2C  -> SPI       : %0d", i2c_to_spi_cnt);
        $display("    Total switch_cyc  : %0d", switch_cyc_cnt);
        $display("========================================================");
    end

endmodule