`timescale 1ns / 1ps

module pynq_dds_system_top (
    input  wire        clk_125m,
    input  wire        rst_btn,

    // Debug LEDs
    // led0: heartbeat
    // led1: toggle on SPI CS falling edge
    // led2: toggle on DDS command accepted
    // led3: pulse on SPI frame error
    output wire        led0,
    output wire        led1,
    output wire        led2,
    output wire        led3,

    // SPI-B Slave from PYNQADC (PmodB P7-P10)
    input  wire        adc_spi_mosi,
    output wire        adc_spi_miso,
    input  wire        adc_spi_sclk,
    input  wire        adc_spi_cs_n,

    // AD9767 DAC interface
    output wire [13:0] dac_data,
    output wire        dac_clk,
    output wire        dac_wrt
);

    // ============================================================
    // Power-on reset
    // ============================================================
    reg [7:0] por_cnt = 8'd0;
    wire por_rst = (por_cnt < 8'd255) | rst_btn;

    always @(posedge clk_125m) begin
        if (por_cnt < 8'd255)
            por_cnt <= por_cnt + 1'b1;
    end

    // Forward declarations for signals used by status LEDs before the SPI and
    // command parser blocks below.
    wire [1023:0] spi_rx_frame;
    wire [1023:0] spi_tx_frame;
    wire spi_done;
    wire spi_active;
    wire spi_cs_fall;
    reg  dds_cmd_accepted = 1'b0;
    reg  spi_frame_err    = 1'b0;

    // ============================================================
    // LEDs
    // ============================================================
    localparam [23:0] LED_BLINK_TICKS = 24'd12_500_000; // ~100ms at 125MHz

    reg [26:0] heartbeat_cnt = 27'd0;
    reg        cs_fall_toggle = 1'b0;
    reg        cmd_ok_toggle = 1'b0;
    reg [23:0] frame_err_blink = 24'd0;

    always @(posedge clk_125m) begin
        if (por_rst) begin
            heartbeat_cnt <= 27'd0;
            cs_fall_toggle <= 1'b0;
            cmd_ok_toggle <= 1'b0;
            frame_err_blink <= 24'd0;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 27'd1;

            if (spi_cs_fall)
                cs_fall_toggle <= ~cs_fall_toggle;

            if (dds_cmd_accepted)
                cmd_ok_toggle <= ~cmd_ok_toggle;

            if (spi_frame_err)
                frame_err_blink <= LED_BLINK_TICKS;
            else if (frame_err_blink != 24'd0)
                frame_err_blink <= frame_err_blink - 24'd1;
        end
    end

    assign led0 = heartbeat_cnt[26];
    assign led1 = cs_fall_toggle;
    assign led2 = cmd_ok_toggle;
    assign led3 = (frame_err_blink != 24'd0);

    // ============================================================
    // SPI-B Slave
    // ============================================================
    spi_slave_128b u_spi_slave (
        .clk(clk_125m),
        .rst(por_rst),
        .tx_frame(spi_tx_frame),
        .mosi(adc_spi_mosi),
        .miso(adc_spi_miso),
        .sclk(adc_spi_sclk),
        .cs_n(adc_spi_cs_n),
        .rx_frame(spi_rx_frame),
        .done(spi_done),
        .active(spi_active),
        .cs_fall(spi_cs_fall)
    );

    // ============================================================
    // DDS Command registers & SPI frame parser (0xD1)
    // ============================================================
    reg [31:0] dds_cmd_seq    = 32'd0;
    reg [31:0] dds_cmd        = 32'd0;
    reg [31:0] dds_cmd_freq   = 32'd0;
    reg [31:0] dds_cmd_ampl   = 32'd1000;
    reg [31:0] dds_cmd_phase  = 32'd0;
    reg [31:0] dds_start_freq = 32'd0;
    reg [31:0] dds_stop_freq  = 32'd0;
    reg [31:0] dds_step_freq  = 32'd0;
    reg [31:0] dds_mode       = 32'd0;
    reg [31:0] dds_flags      = 32'd1; // bit0=ready

    reg [31:0] last_cmd_seq     = 32'hFFFFFFFF;

    // DDS command enum
    localparam [31:0] DDS_CMD_NOP          = 32'd0;
    localparam [31:0] DDS_CMD_SET_FREQ     = 32'd1;
    localparam [31:0] DDS_CMD_START_SWEEP  = 32'd2;
    localparam [31:0] DDS_CMD_STOP         = 32'd3;
    localparam [31:0] DDS_CMD_SET_SINGLE   = 32'd4;
    localparam [31:0] DDS_CMD_RECON_WAVE   = 32'd20;
    localparam [31:0] DDS_CMD_OUTPUT_RECON = 32'd21;

    integer pi;
    reg [7:0] pchk;

    wire [31:0] rx_cmd_seq = {
        spi_rx_frame[7*8 +: 8], spi_rx_frame[6*8 +: 8],
        spi_rx_frame[5*8 +: 8], spi_rx_frame[4*8 +: 8]};
    wire [31:0] rx_cmd = {
        spi_rx_frame[11*8 +: 8], spi_rx_frame[10*8 +: 8],
        spi_rx_frame[9*8 +: 8],  spi_rx_frame[8*8 +: 8]};
    wire [31:0] rx_cmd_freq = {
        spi_rx_frame[15*8 +: 8], spi_rx_frame[14*8 +: 8],
        spi_rx_frame[13*8 +: 8], spi_rx_frame[12*8 +: 8]};
    wire [31:0] rx_cmd_ampl = {
        spi_rx_frame[19*8 +: 8], spi_rx_frame[18*8 +: 8],
        spi_rx_frame[17*8 +: 8], spi_rx_frame[16*8 +: 8]};
    wire [31:0] rx_cmd_phase = {
        spi_rx_frame[23*8 +: 8], spi_rx_frame[22*8 +: 8],
        spi_rx_frame[21*8 +: 8], spi_rx_frame[20*8 +: 8]};
    wire [31:0] rx_start_freq = {
        spi_rx_frame[27*8 +: 8], spi_rx_frame[26*8 +: 8],
        spi_rx_frame[25*8 +: 8], spi_rx_frame[24*8 +: 8]};
    wire [31:0] rx_stop_freq = {
        spi_rx_frame[31*8 +: 8], spi_rx_frame[30*8 +: 8],
        spi_rx_frame[29*8 +: 8], spi_rx_frame[28*8 +: 8]};
    wire [31:0] rx_step_freq = {
        spi_rx_frame[35*8 +: 8], spi_rx_frame[34*8 +: 8],
        spi_rx_frame[33*8 +: 8], spi_rx_frame[32*8 +: 8]};
    wire [31:0] rx_mode = {
        spi_rx_frame[39*8 +: 8], spi_rx_frame[38*8 +: 8],
        spi_rx_frame[37*8 +: 8], spi_rx_frame[36*8 +: 8]};

    always @(posedge clk_125m) begin
        if (por_rst) begin
            dds_cmd_seq    <= 32'd0;
            dds_cmd        <= 32'd0;
            dds_cmd_freq   <= 32'd0;
            dds_cmd_ampl   <= 32'd1000;
            dds_cmd_phase  <= 32'd0;
            dds_start_freq <= 32'd0;
            dds_stop_freq  <= 32'd0;
            dds_step_freq  <= 32'd0;
            dds_mode       <= 32'd0;
            dds_flags      <= 32'd1;
            dds_cmd_accepted <= 1'b0;
            spi_frame_err  <= 1'b0;
            last_cmd_seq   <= 32'hFFFFFFFF;
        end else begin
            dds_cmd_accepted <= 1'b0;
            spi_frame_err <= 1'b0;

            if (spi_done) begin
                // Parse 0xD1 frame
                pchk = 8'd0;
                for (pi = 0; pi < 116; pi = pi + 1)
                    pchk = pchk ^ spi_rx_frame[pi*8 +: 8];

                if (spi_rx_frame[0*8 +: 8]  == 8'hA5 &&
                    spi_rx_frame[1*8 +: 8]  == 8'h5A &&
                    spi_rx_frame[2*8 +: 8]  == 8'hD1 &&
                    spi_rx_frame[3*8 +: 8]  == 8'd112 &&
                    spi_rx_frame[116*8 +: 8] == pchk) begin

                    // Extract fields (LE)
                    dds_cmd_seq    <= rx_cmd_seq;
                    dds_cmd        <= rx_cmd;
                    dds_cmd_freq   <= rx_cmd_freq;
                    dds_cmd_ampl   <= rx_cmd_ampl;
                    dds_cmd_phase  <= rx_cmd_phase;
                    dds_start_freq <= rx_start_freq;
                    dds_stop_freq  <= rx_stop_freq;
                    dds_step_freq  <= rx_step_freq;
                    dds_mode       <= rx_mode;

                    dds_flags <= 32'd3; // ready + freq_set_done

                    // Detect new command (seq changed)
                    if (rx_cmd_seq != last_cmd_seq && rx_cmd != DDS_CMD_NOP) begin
                        last_cmd_seq <= rx_cmd_seq;
                        dds_cmd_accepted <= 1'b1;
                    end
                end else begin
                    spi_frame_err <= 1'b1;
                end
            end
        end
    end

    // ============================================================
    // 0xD2 ACK frame builder (combinational)
    // ============================================================
    reg [1023:0]  d2_frame;
    integer bi;
    reg [7:0] bchk;

    always @* begin
        d2_frame = 1024'd0;
        d2_frame[0*8 +: 8] = 8'hA5;
        d2_frame[1*8 +: 8] = 8'h5A;
        d2_frame[2*8 +: 8] = 8'hD2;
        d2_frame[3*8 +: 8] = 8'd112;

        // seq (LE)
        d2_frame[4*8 +: 8] = dds_cmd_seq[7:0];
        d2_frame[5*8 +: 8] = dds_cmd_seq[15:8];
        d2_frame[6*8 +: 8] = dds_cmd_seq[23:16];
        d2_frame[7*8 +: 8] = dds_cmd_seq[31:24];

        // cmd echo (LE)
        d2_frame[8*8 +: 8]  = dds_cmd[7:0];
        d2_frame[9*8 +: 8]  = dds_cmd[15:8];
        d2_frame[10*8 +: 8] = dds_cmd[23:16];
        d2_frame[11*8 +: 8] = dds_cmd[31:24];

        // current freq (LE)
        d2_frame[12*8 +: 8] = dds_cmd_freq[7:0];
        d2_frame[13*8 +: 8] = dds_cmd_freq[15:8];
        d2_frame[14*8 +: 8] = dds_cmd_freq[23:16];
        d2_frame[15*8 +: 8] = dds_cmd_freq[31:24];

        // flags (LE)
        d2_frame[16*8 +: 8] = dds_flags[7:0];
        d2_frame[17*8 +: 8] = dds_flags[15:8];
        d2_frame[18*8 +: 8] = dds_flags[23:16];
        d2_frame[19*8 +: 8] = dds_flags[31:24];

        // checksum
        bchk = 8'd0;
        for (bi = 0; bi < 116; bi = bi + 1)
            bchk = bchk ^ d2_frame[bi*8 +: 8];
        d2_frame[116*8 +: 8] = bchk;
    end

    assign spi_tx_frame = d2_frame;

    // ============================================================
    // Frequency word calculator
    // FWORD = freq_hz * 2^32 / UPDATE_RATE_HZ
    // UPDATE_RATE_HZ = 25_000_000
    // Approx: FWORD = freq_hz * 171.79869 ≈ freq_hz * 172
    // For better accuracy: FWORD = freq_hz * 171 + (freq_hz * 20971) >> 15
    // But for Phase 1: FWORD = freq_hz * 172 (0.117% error)
    // ============================================================
    reg [31:0] dds_fword = 32'd172; // ~1Hz default

    always @(posedge clk_125m) begin
        if (por_rst) begin
            dds_fword <= 32'd172;
        end else if (dds_cmd == DDS_CMD_SET_FREQ || dds_cmd == DDS_CMD_SET_SINGLE) begin
            // FWORD = freq_hz * 171.8 ≈ freq_hz * 172
            dds_fword <= dds_cmd_freq * 32'd172;
        end else if (dds_cmd == DDS_CMD_STOP) begin
            // Output zero frequency (DC)
            dds_fword <= 32'd0;
        end
    end

    // ============================================================
    // DDS Core + AD9767 interface (verified)
    // ============================================================
    wire [13:0] dac_code;
    wire sample_tick;

    dds_core #(
        .FWORD(32'd172),
        .SWEEP_FWORD_MIN(32'd34360),
        .SWEEP_FWORD_MAX(32'd3435974),
        .SWEEP_FWORD_STEP(32'd34360),
        .SWEEP_HOLD_TICKS(32'd2500000)
    ) u_dds_core (
        .clk(clk_125m),
        .rst(por_rst),
        .dds_en(1'b1),
        .sample_tick(sample_tick),
        .wave_sel(3'b001),   // sine wave
        .t_group(1'b0),
        .fword(dds_fword),
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
