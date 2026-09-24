`timescale 1ns / 1ps

// ---------------------------------------------------------------------
// 2-FF synchronizer for push buttons / reset
// ---------------------------------------------------------------------
module debounce_sync(
    input  wire clk,
    input  wire in,
    output reg  out
);
    reg ff1;
    always @(posedge clk) begin
        ff1 <= in;
        out <= ff1;
    end
endmodule
