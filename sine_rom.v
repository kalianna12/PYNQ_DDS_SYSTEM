`timescale 1ns / 1ps

// Sine lookup table: 4096 x 14-bit, inferred BRAM via $readmemh
// Needs sine_4096x14.mem in the same source directory
module sine_rom (
    input  wire        clk,
    input  wire [11:0] addr,
    output reg  [13:0] dout
);

    (* ram_style = "block" *) reg [13:0] rom [0:4095];

    initial begin
        $readmemh("sine_4096x14.mem", rom);
    end

    always @(posedge clk) begin
        dout <= rom[addr];
    end

endmodule
