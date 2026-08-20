

`timescale 1ns/1ps

module protocol_switch (
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

    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        RUN_UART    = 3'b001,
        RUN_SPI     = 3'b010,
        RUN_I2C     = 3'b011,
        SWITCH_WAIT = 3'b100
    } state_t;

    state_t curr_state, next_state;

    logic [1:0] pending_proto;
    logic [1:0] active_proto_r;

    logic uart_done_seen;   // 1 = UART has completed its current transfer
    logic spi_done_seen;
    logic i2c_done_seen;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            curr_state     <= IDLE;
            pending_proto  <= 2'b00;
            active_proto_r <= 2'b00;
            uart_done_seen <= 1'b1;   // idle at reset = "done"
            spi_done_seen  <= 1'b1;
            i2c_done_seen  <= 1'b1;
        end else begin
            curr_state <= next_state;

            // Track which protocol is running for SWITCH_WAIT
            case (curr_state)
                RUN_UART: active_proto_r <= 2'b00;
                RUN_SPI:  active_proto_r <= 2'b01;
                RUN_I2C:  active_proto_r <= 2'b10;
                default:  active_proto_r <= active_proto_r;
            endcase

            // Latch pending protocol when switch requested mid-run
            case (curr_state)
                RUN_UART: if (proto_sel != 2'b00) pending_proto <= proto_sel;
                RUN_SPI:  if (proto_sel != 2'b01) pending_proto <= proto_sel;
                RUN_I2C:  if (proto_sel != 2'b10) pending_proto <= proto_sel;
                SWITCH_WAIT: pending_proto <= pending_proto;
                default: ;
            endcase

            if (next_state == RUN_UART && curr_state != RUN_UART)
                uart_done_seen <= 1'b0;          // entering RUN_UART fresh
            else if (curr_state == RUN_UART && uart_done)
                uart_done_seen <= 1'b1;           // transfer completed
            else if (curr_state == SWITCH_WAIT && active_proto_r == 2'b00 && uart_done)
                uart_done_seen <= 1'b1;

            if (next_state == RUN_SPI && curr_state != RUN_SPI)
                spi_done_seen <= 1'b0;
            else if (curr_state == RUN_SPI && spi_done)
                spi_done_seen <= 1'b1;
            else if (curr_state == SWITCH_WAIT && active_proto_r == 2'b01 && spi_done)
                spi_done_seen <= 1'b1;

            if (next_state == RUN_I2C && curr_state != RUN_I2C)
                i2c_done_seen <= 1'b0;
            else if (curr_state == RUN_I2C && i2c_done)
                i2c_done_seen <= 1'b1;
            else if (curr_state == SWITCH_WAIT && active_proto_r == 2'b10 && i2c_done)
                i2c_done_seen <= 1'b1;
        end
    end
    
    always_comb begin
        next_state = curr_state;

        case (curr_state)

            IDLE: begin
                case (proto_sel)
                    2'b00:   next_state = RUN_UART;
                    2'b01:   next_state = RUN_SPI;
                    2'b10:   next_state = RUN_I2C;
                    default: next_state = IDLE;
                endcase
            end

            RUN_UART: begin
                if (proto_sel != 2'b00) begin
                    if (uart_done || uart_done_seen)
                        case (proto_sel)
                            2'b01:   next_state = RUN_SPI;
                            2'b10:   next_state = RUN_I2C;
                            default: next_state = RUN_UART;
                        endcase
                    else
                        next_state = SWITCH_WAIT;
                end
            end

            RUN_SPI: begin
                if (proto_sel != 2'b01) begin
                    if (spi_done || spi_done_seen)
                        case (proto_sel)
                            2'b00:   next_state = RUN_UART;
                            2'b10:   next_state = RUN_I2C;
                            default: next_state = RUN_SPI;
                        endcase
                    else
                        next_state = SWITCH_WAIT;
                end
            end

            RUN_I2C: begin
                if (proto_sel != 2'b10) begin
                    if (i2c_done || i2c_done_seen)
                        case (proto_sel)
                            2'b00:   next_state = RUN_UART;
                            2'b01:   next_state = RUN_SPI;
                            default: next_state = RUN_I2C;
                        endcase
                    else
                        next_state = SWITCH_WAIT;
                end
            end

            SWITCH_WAIT: begin
                case (active_proto_r)
                    2'b00: if (uart_done || uart_done_seen)
                               case (pending_proto)
                                   2'b01:   next_state = RUN_SPI;
                                   2'b10:   next_state = RUN_I2C;
                                   default: next_state = IDLE;
                               endcase
                    2'b01: if (spi_done || spi_done_seen)
                               case (pending_proto)
                                   2'b00:   next_state = RUN_UART;
                                   2'b10:   next_state = RUN_I2C;
                                   default: next_state = IDLE;
                               endcase
                    2'b10: if (i2c_done || i2c_done_seen)
                               case (pending_proto)
                                   2'b00:   next_state = RUN_UART;
                                   2'b01:   next_state = RUN_SPI;
                                   default: next_state = IDLE;
                               endcase
                    default: next_state = IDLE;
                endcase
            end

            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Output logic
    // -------------------------------------------------------------------------
    always_comb begin
        uart_en      = 1'b0;
        spi_en       = 1'b0;
        i2c_en       = 1'b0;
        active_proto = 2'b11;
        proto_ready  = 1'b0;
        switching    = 1'b0;

        case (curr_state)
            IDLE: begin
                active_proto = 2'b11;
                proto_ready  = 1'b1;
            end
            RUN_UART: begin
                uart_en      = 1'b1;
                active_proto = 2'b00;
                proto_ready  = uart_done | uart_done_seen;
            end
            RUN_SPI: begin
                spi_en       = 1'b1;
                active_proto = 2'b01;
                proto_ready  = spi_done | spi_done_seen;
            end
            RUN_I2C: begin
                i2c_en       = 1'b1;
                active_proto = 2'b10;
                proto_ready  = i2c_done | i2c_done_seen;
            end
            SWITCH_WAIT: begin
                case (active_proto_r)
                    2'b00: begin uart_en = 1'b1; active_proto = 2'b00; end
                    2'b01: begin spi_en  = 1'b1; active_proto = 2'b01; end
                    2'b10: begin i2c_en  = 1'b1; active_proto = 2'b10; end
                    default: ;
                endcase
                switching   = 1'b1;
                proto_ready = 1'b0;
            end
            default: proto_ready = 1'b1;
        endcase
    end

    // =========================================================================
    // SVA Assertions A1-A7
    // =========================================================================
    A1_one_hot: assert property (
        @(posedge clk) disable iff (!rst_n)
        $onehot0({uart_en, spi_en, i2c_en})
    ) else $error("ASSERT FAIL A1: Multiple protocols enabled at time %0t", $time);

    A2_uart_spi: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(uart_en && spi_en)
    ) else $error("ASSERT FAIL A2: UART+SPI active at time %0t", $time);

    A3_spi_i2c: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(spi_en && i2c_en)
    ) else $error("ASSERT FAIL A3: SPI+I2C active at time %0t", $time);

    A4_uart_i2c: assert property (
        @(posedge clk) disable iff (!rst_n)
        !(uart_en && i2c_en)
    ) else $error("ASSERT FAIL A4: UART+I2C active at time %0t", $time);

    A5_switch_after_done: assert property (
        @(posedge clk) disable iff (!rst_n)
        (curr_state != SWITCH_WAIT) ##1 (curr_state == SWITCH_WAIT) |->
            !( (active_proto_r == 2'b00 && uart_done_seen) ||
               (active_proto_r == 2'b01 && spi_done_seen)  ||
               (active_proto_r == 2'b10 && i2c_done_seen) )
    ) else $error("ASSERT FAIL A5: SWITCH_WAIT entered when already idle at time %0t", $time);

    A6_active_after_switch: assert property (
        @(posedge clk) disable iff (!rst_n)
        $fell(switching) |=> $onehot({uart_en, spi_en, i2c_en})
    ) else $error("ASSERT FAIL A6: No protocol active after switch at time %0t", $time);

    A7_no_overlap: assert property (
        @(posedge clk) disable iff (!rst_n)
        switching |-> $onehot0({uart_en, spi_en, i2c_en})
    ) else $error("ASSERT FAIL A7: Overlap during switching at time %0t", $time);


endmodule