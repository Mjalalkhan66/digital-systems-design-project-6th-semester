`timescale 1ns / 1ps

// ---------------------------------------------------------------------
// TOP MODULE
// ---------------------------------------------------------------------
module top(
    input  wire clk,        // 100 MHz onboard clock  (UCF: clk)
    input  wire rst,        // push button, ACTIVE-LOW (UCF: rst, PULLUP)
    input  wire btn_left,   // push button, ACTIVE-LOW = move paddle left
    input  wire btn_right,  // push button, ACTIVE-LOW = move paddle right

    output wire hsync,      // horizontal sync
    output wire vsync,      // vertical sync
    output wire [2:0] red,  // 3-bit red   (8 levels)
    output wire [2:0] green,// 3-bit green (8 levels)
    output wire [1:0] blue  // 2-bit blue  (4 levels)
);

    // Board buttons/reset are pulled up -> read '1' when unpressed,
    // '0' when pressed. Invert here so the rest of the design can use
    // simple active-HIGH logic internally.
    wire reset_ah     = ~rst;
    wire btn_left_ah  = ~btn_left;
    wire btn_right_ah = ~btn_right;

    // ---------------- 25 MHz pixel clock from 100 MHz input ----------------
    reg [1:0] pix_clk_div = 2'd0;
    always @(posedge clk) begin
        pix_clk_div <= pix_clk_div + 2'd1;
    end
    wire pix_clk = pix_clk_div[1];   // toggles once every 4 clk cycles -> 25 MHz

    // ---------------- VGA sync + coordinates ----------------
    wire active_video;
    wire [9:0] px, py;
    wire hsync_i, vsync_i;
    wire [7:0] rgb_pixel; // {red[2:0], green[2:0], blue[1:0]}
    wire frame_tick;      // clean once-per-frame pulse from vga_sync

    // ---------------- synchronize buttons/reset into pix_clk domain --------
    wire btn_left_s, btn_right_s, reset_s;

    debounce_sync sync_left  (.clk(pix_clk), .in(btn_left_ah),  .out(btn_left_s));
    debounce_sync sync_right (.clk(pix_clk), .in(btn_right_ah), .out(btn_right_s));
    debounce_sync sync_reset (.clk(pix_clk), .in(reset_ah),     .out(reset_s));

    vga_sync vg(
        .pix_clk(pix_clk),
        .reset(reset_s),
        .hsync(hsync_i),
        .vsync(vsync_i),
        .active_video(active_video),
        .px(px),
        .py(py),
        .frame_tick(frame_tick)
    );

    game_core game(
        .pix_clk(pix_clk),
        .reset(reset_s),
        .frame_tick(frame_tick),
        .btn_left(btn_left_s),
        .btn_right(btn_right_s),
        .px(px),
        .py(py),
        .active_video(active_video),
        .rgb_out(rgb_pixel)
    );

    assign hsync = hsync_i;
    assign vsync = vsync_i;
    assign red   = rgb_pixel[7:5];
    assign green = rgb_pixel[4:2];
    assign blue  = rgb_pixel[1:0];

endmodule
