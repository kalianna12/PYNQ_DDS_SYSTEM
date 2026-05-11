`timescale 1ns / 1ps

module ad9767_parallel_if #(
    parameter integer CLK_FREQ_HZ       = 125_000_000,
    parameter integer UPDATE_RATE_HZ    = 25_000_000,
    parameter integer DDS_LATENCY_CLKS  = 3,
    parameter integer DATA_SETUP_CLKS   = 2,
    parameter integer PULSE_HIGH_CLKS   = 2
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [13:0] sample_data,

    output reg  [13:0] dac_data,
    output reg         dac_clk,
    output reg         dac_wrt,
    output reg         sample_tick
);

    localparam integer UPDATE_DIV = CLK_FREQ_HZ / UPDATE_RATE_HZ;

    reg [2:0] update_cnt = 3'd0;

    always @(posedge clk) begin
        if (rst) begin
            dac_data    <= 14'd0;
            dac_clk     <= 1'b0;
            dac_wrt     <= 1'b0;
            sample_tick <= 1'b0;
            update_cnt  <= 3'd0;
        end else begin
            sample_tick <= 1'b0;
            dac_clk     <= 1'b0;
            dac_wrt     <= 1'b0;

            if (update_cnt == UPDATE_DIV - 1)
                update_cnt <= 3'd0;
            else
                update_cnt <= update_cnt + 1'b1;

            case (update_cnt)
                3'd0: begin
                    dac_data    <= sample_data;
                    sample_tick <= 1'b1;
                end

                3'd1: begin
                    dac_clk <= 1'b1;
                    dac_wrt <= 1'b1;
                end

                3'd2: begin
                    dac_clk <= 1'b1;
                    dac_wrt <= 1'b1;
                end

                default: begin
                end
            endcase
        end
    end

endmodule
