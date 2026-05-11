`timescale 1ns / 1ps

module pynq_dds_bridge_test_top #(
    parameter integer CLKS_PER_BIT = 1085
) (
    input  wire        clk_125m,
    input  wire        rst_btn,

    input  wire        uart_rx,
    output wire        uart_tx,

    // Debug LEDs on PYNQDDS board.
    // led0: heartbeat
    // led1: toggle on each completed 128-byte SPI transaction
    // led2: pulse on SPI frame parse error (header/type/length/checksum)
    // led3: pulse on successfully parsed new text seq from PYNQADC
    output wire        led0,
    output wire        led1,
    output wire        led2,
    output wire        led3,

    // SPI from PYNQADC through PmodB P7-P10. PYNQDDS is SPI Slave.
    input  wire        adc_spi_mosi,
    output wire        adc_spi_miso,
    input  wire        adc_spi_sclk,
    input  wire        adc_spi_cs_n,

    // Verified AD9767 P1/CH1 interface.
    output wire [13:0] dac_data,
    output wire        dac_clk,
    output wire        dac_wrt
);

    reg [7:0] por_cnt = 8'd0;
    wire por_rst = (por_cnt < 8'd255) | rst_btn;

    always @(posedge clk_125m) begin
        if (por_cnt < 8'd255) begin
            por_cnt <= por_cnt + 1'b1;
        end
    end

    // ============================================================
    // Debug LEDs
    // ============================================================
    localparam [23:0] LED_BLINK_TICKS = 24'd12_500_000;

    reg [26:0] heartbeat_cnt = 27'd0;
    reg        spi_done_toggle = 1'b0;
    reg        spi_done_d1 = 1'b0;
    reg [23:0] frame_err_blink_cnt = 24'd0;
    reg [23:0] new_text_blink_cnt = 24'd0;

    wire frame_err = spi_done_d1 && !adc_frame_valid;

    always @(posedge clk_125m) begin
        if (por_rst) begin
            heartbeat_cnt <= 27'd0;
            spi_done_toggle <= 1'b0;
            spi_done_d1 <= 1'b0;
            frame_err_blink_cnt <= 24'd0;
            new_text_blink_cnt <= 24'd0;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 27'd1;
            spi_done_d1 <= spi_done;

            if (spi_done)
                spi_done_toggle <= ~spi_done_toggle;

            if (frame_err)
                frame_err_blink_cnt <= LED_BLINK_TICKS;
            else if (frame_err_blink_cnt != 24'd0)
                frame_err_blink_cnt <= frame_err_blink_cnt - 24'd1;

            if (adc_frame_valid && adc_seq != 32'd0 && adc_seq != last_adc_seq)
                new_text_blink_cnt <= LED_BLINK_TICKS;
            else if (new_text_blink_cnt != 24'd0)
                new_text_blink_cnt <= new_text_blink_cnt - 24'd1;
        end
    end

    assign led0 = heartbeat_cnt[26];
    assign led1 = spi_done_toggle;
    assign led2 = (frame_err_blink_cnt != 24'd0);
    assign led3 = (new_text_blink_cnt != 24'd0);

    // ============================================================
    // UART line input from DDS-side PC. Type text + Enter, then return to ADC.
    // ============================================================
    wire [7:0] uart_rx_data;
    wire uart_rx_valid;

    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_uart_rx (
        .clk(clk_125m),
        .rst(por_rst),
        .rx(uart_rx),
        .data(uart_rx_data),
        .valid(uart_rx_valid)
    );

    reg [831:0] line_buf = 832'd0;
    reg [31:0]  line_len = 32'd0;
    reg [831:0] dds_text = 832'd0;
    reg [31:0]  dds_text_len = 32'd0;
    reg [31:0]  dds_seq = 32'd0;

    always @(posedge clk_125m) begin
        if (por_rst) begin
            line_buf <= 832'd0;
            line_len <= 32'd0;
            dds_text <= 832'd0;
            dds_text_len <= 32'd0;
            dds_seq <= 32'd0;
        end else if (uart_rx_valid) begin
            if (uart_rx_data == 8'h0D || uart_rx_data == 8'h0A) begin
                if (line_len != 32'd0) begin
                    dds_text <= line_buf;
                    dds_text_len <= line_len;
                    dds_seq <= (dds_seq == 32'hFFFFFFFF) ? 32'd1 : (dds_seq + 32'd1);
                    line_buf <= 832'd0;
                    line_len <= 32'd0;
                end
            end else if (line_len < 32'd104) begin
                line_buf[line_len*8 +: 8] <= uart_rx_data;
                line_len <= line_len + 32'd1;
            end
        end
    end

    // DDS -> ADC uses text frame 0xE2. ADC -> DDS uses text frame 0xE1.
    wire [1023:0] spi_tx_frame;
    text_frame_builder_param #(
        .FRAME_TYPE(8'hE2)
    ) u_spi_text_frame_builder (
        .seq(dds_seq),
        .text_len(dds_text_len),
        .text_bytes(dds_text),
        .frame(spi_tx_frame)
    );

    wire [1023:0] spi_rx_frame;
    wire spi_done;
    wire spi_active;

    spi_slave_128b u_spi_slave_128b (
        .clk(clk_125m),
        .rst(por_rst),
        .tx_frame(spi_tx_frame),
        .mosi(adc_spi_mosi),
        .miso(adc_spi_miso),
        .sclk(adc_spi_sclk),
        .cs_n(adc_spi_cs_n),
        .rx_frame(spi_rx_frame),
        .done(spi_done),
        .active(spi_active)
    );

    wire adc_frame_valid;
    wire [31:0] adc_seq;
    wire [31:0] adc_text_len;
    wire [831:0] adc_text_bytes;

    text_frame_parser_param #(
        .EXPECT_TYPE(8'hE1)
    ) u_adc_text_frame_parser (
        .clk(clk_125m),
        .rst(por_rst),
        .parse_en(spi_done),
        .frame(spi_rx_frame),
        .valid(adc_frame_valid),
        .seq(adc_seq),
        .text_len(adc_text_len),
        .text_bytes(adc_text_bytes)
    );

    reg [31:0] last_adc_seq = 32'd0;
    reg [831:0] print_text = 832'd0;
    reg [31:0] print_text_len = 32'd0;
    reg print_pending = 1'b0;

    always @(posedge clk_125m) begin
        if (por_rst) begin
            last_adc_seq <= 32'd0;
            print_text <= 832'd0;
            print_text_len <= 32'd0;
            print_pending <= 1'b0;
        end else if (adc_frame_valid && adc_seq != 32'd0 && adc_seq != last_adc_seq) begin
            last_adc_seq <= adc_seq;
            print_text <= adc_text_bytes;
            print_text_len <= adc_text_len;
            print_pending <= 1'b1;
        end else if (print_start_msg) begin
            print_pending <= 1'b0;
        end
    end

    // ============================================================
    // UART printer
    // ============================================================
    reg [7:0] uart_tx_data = 8'd0;
    reg uart_tx_start = 1'b0;
    wire uart_tx_busy;
    wire uart_tx_done;

    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_uart_tx (
        .clk(clk_125m),
        .rst(por_rst),
        .data(uart_tx_data),
        .start(uart_tx_start),
        .tx(uart_tx),
        .busy(uart_tx_busy),
        .done(uart_tx_done)
    );

    localparam [1:0] PRINT_READY = 2'd0;
    localparam [1:0] PRINT_MSG   = 2'd1;
    localparam [1:0] PRINT_ERR   = 2'd2;

    reg print_active = 1'b1;
    reg [1:0] print_mode = PRINT_READY;
    reg [7:0] print_index = 8'd0;
    reg print_start_msg = 1'b0;

    reg err_pending = 1'b0;
    reg [26:0] err_rate_cnt = 27'd0;

    function [7:0] ready_char;
        input [7:0] idx;
        begin
            case (idx)
            8'd0: ready_char = "P";  8'd1: ready_char = "Y";  8'd2: ready_char = "N";  8'd3: ready_char = "Q";
            8'd4: ready_char = "D";  8'd5: ready_char = "D";  8'd6: ready_char = "S";  8'd7: ready_char = " ";
            8'd8: ready_char = "A";  8'd9: ready_char = "D";  8'd10: ready_char = "C"; 8'd11: ready_char = " ";
            8'd12: ready_char = "S"; 8'd13: ready_char = "P"; 8'd14: ready_char = "I"; 8'd15: ready_char = " ";
            8'd16: ready_char = "R"; 8'd17: ready_char = "E"; 8'd18: ready_char = "A"; 8'd19: ready_char = "D"; 8'd20: ready_char = "Y";
            8'd21: ready_char = 8'h0D; 8'd22: ready_char = 8'h0A;
            default: ready_char = 8'h00;
            endcase
        end
    endfunction

    function [7:0] prefix_char;
        input [7:0] idx;
        begin
            case (idx)
            8'd0: prefix_char = "R"; 8'd1: prefix_char = "X"; 8'd2: prefix_char = "_"; 8'd3: prefix_char = "F";
            8'd4: prefix_char = "R"; 8'd5: prefix_char = "O"; 8'd6: prefix_char = "M"; 8'd7: prefix_char = "_";
            8'd8: prefix_char = "A"; 8'd9: prefix_char = "D"; 8'd10: prefix_char = "C"; 8'd11: prefix_char = ":"; 8'd12: prefix_char = " ";
            default: prefix_char = 8'h00;
            endcase
        end
    endfunction

    function [7:0] err_char;
        input [7:0] idx;
        begin
            case (idx)
            8'd0:  err_char = "S"; 8'd1:  err_char = "P"; 8'd2:  err_char = "I"; 8'd3:  err_char = "_";
            8'd4:  err_char = "F"; 8'd5:  err_char = "R"; 8'd6:  err_char = "A"; 8'd7:  err_char = "M";
            8'd8:  err_char = "E"; 8'd9:  err_char = "_"; 8'd10: err_char = "E"; 8'd11: err_char = "R";
            8'd12: err_char = "R"; 8'd13: err_char = 8'h0D; 8'd14: err_char = 8'h0A;
            default: err_char = 8'h00;
            endcase
        end
    endfunction

    always @(posedge clk_125m) begin
        if (por_rst) begin
            uart_tx_start <= 1'b0;
            uart_tx_data <= 8'd0;
            print_active <= 1'b1;
            print_mode <= PRINT_READY;
            print_index <= 8'd0;
            print_start_msg <= 1'b0;
            err_pending <= 1'b0;
            err_rate_cnt <= 27'd0;
        end else begin
            uart_tx_start <= 1'b0;
            print_start_msg <= 1'b0;

            // Rate-limited error capture
            if (err_rate_cnt != 27'd0) begin
                err_rate_cnt <= err_rate_cnt - 27'd1;
            end else if (frame_err) begin
                err_pending <= 1'b1;
                err_rate_cnt <= 27'd125_000_000;
            end

            if (!print_active) begin
                if (err_pending) begin
                    print_active <= 1'b1;
                    print_mode <= PRINT_ERR;
                    print_index <= 8'd0;
                    err_pending <= 1'b0;
                end else if (print_pending) begin
                    print_active <= 1'b1;
                    print_mode <= PRINT_MSG;
                    print_index <= 8'd0;
                    print_start_msg <= 1'b1;
                end
            end else if (print_active && !uart_tx_busy && !uart_tx_start) begin
                if (print_mode == PRINT_READY) begin
                    if (print_index < 8'd23) begin
                        uart_tx_data <= ready_char(print_index);
                        uart_tx_start <= 1'b1;
                        print_index <= print_index + 8'd1;
                    end else begin
                        print_active <= 1'b0;
                    end
                end else if (print_mode == PRINT_MSG) begin
                    if (print_index < 8'd13) begin
                        uart_tx_data <= prefix_char(print_index);
                        uart_tx_start <= 1'b1;
                        print_index <= print_index + 8'd1;
                    end else if (print_index < (8'd13 + print_text_len[7:0])) begin
                        uart_tx_data <= print_text[(print_index - 8'd13)*8 +: 8];
                        uart_tx_start <= 1'b1;
                        print_index <= print_index + 8'd1;
                    end else if (print_index == (8'd13 + print_text_len[7:0])) begin
                        uart_tx_data <= 8'h0D;
                        uart_tx_start <= 1'b1;
                        print_index <= print_index + 8'd1;
                    end else if (print_index == (8'd14 + print_text_len[7:0])) begin
                        uart_tx_data <= 8'h0A;
                        uart_tx_start <= 1'b1;
                        print_index <= print_index + 8'd1;
                    end else begin
                        print_active <= 1'b0;
                    end
                end else begin // PRINT_ERR
                    if (print_index < 8'd15) begin
                        uart_tx_data <= err_char(print_index);
                        uart_tx_start <= 1'b1;
                        print_index <= print_index + 8'd1;
                    end else begin
                        print_active <= 1'b0;
                    end
                end
            end
        end
    end

    // ============================================================
    // Keep verified DDS output running: default sine, 5 kHz FWORD from old top.
    // ============================================================
    wire [13:0] dac_code;
    wire sample_tick;

    dds_core #(
        .FWORD(32'd171799),
        .SWEEP_FWORD_MIN(32'd171799),
        .SWEEP_FWORD_MAX(32'd17179869),
        .SWEEP_FWORD_STEP(32'd171799),
        .SWEEP_HOLD_TICKS(32'd2500000)
    ) u_dds_core (
        .clk(clk_125m),
        .rst(por_rst),
        .dds_en(1'b1),
        .sample_tick(sample_tick),
        .wave_sel(3'b001),
        .t_group(1'b0),
        .dac_code(dac_code)
    );

    ad9767_parallel_if #(
        .CLK_FREQ_HZ(125_000_000),
        .UPDATE_RATE_HZ(25_000_000),
        .DDS_LATENCY_CLKS(3),
        .DATA_SETUP_CLKS(2),
        .PULSE_HIGH_CLKS(2)
    ) u_ad9767_if (
        .clk(clk_125m),
        .rst(por_rst),
        .sample_data(dac_code),
        .dac_data(dac_data),
        .dac_clk(dac_clk),
        .dac_wrt(dac_wrt),
        .sample_tick(sample_tick)
    );

endmodule
