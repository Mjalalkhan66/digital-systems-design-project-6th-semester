`timescale 1ns / 1ps

// ---------------------------------------------------------------------
// VGA sync generator for 640x480@60Hz
// ---------------------------------------------------------------------
module vga_sync(
    input  wire pix_clk,
    input  wire reset,
    output reg  hsync,
    output reg  vsync,
    output reg  active_video,
    output reg [9:0] px,
    output reg [9:0] py,
    output reg  frame_tick     // one pix_clk-wide pulse, exactly once per frame
);
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK; // 800

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK; // 525

    reg [9:0] hcount = 0;
    reg [9:0] vcount = 0;

    // FIX (issue 3): synchronous reset throughout - checked only at the
    // clock edge, never asynchronously.
    always @(posedge pix_clk) begin
        if (reset) begin
            hcount       <= 0;
            vcount       <= 0;
            hsync        <= 1;
            vsync        <= 1;
            active_video <= 0;
            px           <= 0;
            py           <= 0;
            frame_tick   <= 0;
        end else begin
            // Fires for exactly one pix_clk cycle per frame.
            frame_tick <= (hcount == H_TOTAL - 1) && (vcount == V_TOTAL - 1);

            if (hcount == H_TOTAL - 1) begin
                hcount <= 0;
                if (vcount == V_TOTAL - 1) vcount <= 0;
                else vcount <= vcount + 10'd1;
            end else begin
                hcount <= hcount + 10'd1;
            end

            if (hcount >= (H_VISIBLE + H_FRONT) && hcount < (H_VISIBLE + H_FRONT + H_SYNC))
                hsync <= 0;
            else
                hsync <= 1;

            if (vcount >= (V_VISIBLE + V_FRONT) && vcount < (V_VISIBLE + V_FRONT + V_SYNC))
                vsync <= 0;
            else
                vsync <= 1;

            px <= hcount;
            py <= vcount;
            active_video <= (hcount < H_VISIBLE) && (vcount < V_VISIBLE);
        end
    end
endmodule
