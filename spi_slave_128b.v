module spi_slave_128b (
    input  wire        clk,
    input  wire        rst,
    input  wire [1023:0] tx_frame,
    input  wire        mosi,
    output reg         miso,
    input  wire        sclk,
    input  wire        cs_n,
    output reg  [1023:0] rx_frame,
    output reg         done,
    output reg         active,
    output wire        cs_fall
);

    reg sclk_d1, sclk_d2;
    reg cs_d1, cs_d2;
    reg mosi_d1, mosi_d2;

    wire sclk_rise = (sclk_d2 == 1'b0) && (sclk_d1 == 1'b1);
    wire sclk_fall = (sclk_d2 == 1'b1) && (sclk_d1 == 1'b0);
    wire cs_rise   = (cs_d2 == 1'b0) && (cs_d1 == 1'b1);
    assign cs_fall = (cs_d2 == 1'b1) && (cs_d1 == 1'b0);

    reg [1023:0] tx_shift;
    reg [1023:0] rx_shift;
    reg [10:0] bit_count;
    wire [7:0] cur_byte = bit_count[10:3];
    wire [2:0] cur_bit  = 3'd7 - bit_count[2:0];
    wire [10:0] next_bit_count = bit_count + 11'd1;
    wire [7:0] next_byte = next_bit_count[10:3];
    wire [2:0] next_bit  = 3'd7 - next_bit_count[2:0];

    always @(posedge clk) begin
        if (rst) begin
            sclk_d1 <= 1'b0;
            sclk_d2 <= 1'b0;
            cs_d1 <= 1'b1;
            cs_d2 <= 1'b1;
            mosi_d1 <= 1'b0;
            mosi_d2 <= 1'b0;
        end else begin
            sclk_d1 <= sclk;
            sclk_d2 <= sclk_d1;
            cs_d1 <= cs_n;
            cs_d2 <= cs_d1;
            mosi_d1 <= mosi;
            mosi_d2 <= mosi_d1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            miso <= 1'b0;
            rx_frame <= 1024'd0;
            done <= 1'b0;
            active <= 1'b0;
            tx_shift <= 1024'd0;
            rx_shift <= 1024'd0;
            bit_count <= 11'd0;
        end else begin
            done <= 1'b0;

            if (cs_fall) begin
                active <= 1'b1;
                bit_count <= 11'd0;
                tx_shift <= tx_frame;
                rx_shift <= 1024'd0;
                miso <= tx_frame[0*8 + 7];
            end else if (active && cs_d1 == 1'b0) begin
                if (sclk_rise) begin
                    if (bit_count < 11'd1024) begin
                        rx_shift[cur_byte*8 + cur_bit] <= mosi_d2;
                        bit_count <= next_bit_count;
                    end
                end

                if (sclk_fall) begin
                    if (bit_count < 11'd1024) begin
                        miso <= tx_shift[cur_byte*8 + cur_bit];
                    end else begin
                        miso <= 1'b0;
                    end
                end
            end

            if (cs_rise) begin
                active <= 1'b0;
                if (bit_count >= 11'd1024) begin
                    rx_frame <= rx_shift;
                    done <= 1'b1;
                end
            end
        end
    end

endmodule
