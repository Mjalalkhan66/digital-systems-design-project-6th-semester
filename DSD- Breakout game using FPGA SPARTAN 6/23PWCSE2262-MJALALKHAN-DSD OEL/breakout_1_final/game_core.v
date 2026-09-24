`timescale 1ns / 1ps

// ---------------------------------------------------------------------
// Game core: paddle, ball, bricks, collision, pixel color generation.
// ---------------------------------------------------------------------
module game_core(
    input  wire pix_clk,
    input  wire reset,
    input  wire frame_tick,
    input  wire btn_left,
    input  wire btn_right,
    input  wire [9:0] px,
    input  wire [9:0] py,
    input  wire active_video,
    output reg  [7:0] rgb_out   // {red[2:0], green[2:0], blue[1:0]}
);
    localparam [9:0] SCREEN_W = 10'd640;
    localparam [9:0] SCREEN_H = 10'd480;
    localparam       BORDER   = 4;     // thickness of the screen-edge frame

    localparam [9:0] PADDLE_W = 10'd96;
    localparam [9:0] PADDLE_H = 10'd12;
    localparam [9:0] PADDLE_Y = 10'd440;
    localparam [9:0] PADDLE_SPEED = 10'd4;

    localparam [9:0] BALL_SIZE = 10'd8;
    localparam signed [9:0] BALL_DX_INIT =  10'sd2;
    localparam signed [9:0] BALL_DY_INIT = -10'sd2;

    localparam BR_ROWS = 5;
    localparam BR_COLS = 10;
    localparam BR_W = 64;  // 640 / 10
    localparam BR_H = 16;
    localparam BR_XOFF = 0;
    localparam BR_YOFF = 40;
    localparam BR_GAP  = 2;   // visual gap between bricks

    reg [9:0] paddle_x = (640 - 96) / 2;
    reg [9:0] ball_x   = (640/2) - (8/2);
    reg [9:0] ball_y   = 440 - 32;
    reg signed [9:0] ball_dx = 10'sd2;
    reg signed [9:0] ball_dy = -10'sd2;

    reg bricks [0:BR_ROWS-1][0:BR_COLS-1];
    reg [5:0] bricks_left = BR_ROWS*BR_COLS;   // counts bricks still standing
    wire       last_brick_cleared = hit_brick && (bricks_left == 6'd1);

    integer i, j, bx, by;
    reg brick_drawn;
    reg [2:0] r3, g3;
    reg [1:0] b2;

    //-------------------------------------------------------------------
    // FIXES (issues 1 & 2): all ball movement/collision for this frame is
    // predicted here, combinationally, from the CURRENT state - nothing
    // in this block writes to a register. Exactly one place (the
    // always @(posedge pix_clk) below) does the actual latching, so
    // there's no possibility of one branch reading a value that another
    // branch "already changed but hasn't taken effect yet".
    //-------------------------------------------------------------------
    reg signed [11:0] tmp_x, tmp_y;      // extra headroom bits - can never wrap
    reg signed [9:0]  new_dx, new_dy;
    reg  [9:0]        final_x, final_y;
    reg               hit_brick;
    reg  [2:0]        hit_row;
    reg  [3:0]        hit_col;
    reg               ball_lost;
    reg  [3:0]        found_row;

    always @(*) begin
        // Start from "keep going the way we're already going". Using a
        // signed, wider temporary means a step that WOULD go negative
        // (or past the far edge) shows up as a clean negative/over-range
        // number here - never as an unsigned wraparound.
        tmp_x = $signed({2'b00, ball_x}) + ball_dx;
        tmp_y = $signed({2'b00, ball_y}) + ball_dy;
        new_dx = ball_dx;
        new_dy = ball_dy;
        hit_brick = 1'b0;
        hit_row = 0;
        hit_col = 0;
        ball_lost = 1'b0;

        // ---- Left / right walls ----
        if (tmp_x < 0) begin
            tmp_x  = 0;
            new_dx = -ball_dx;
        end else if (tmp_x > (SCREEN_W - BALL_SIZE)) begin
            tmp_x  = SCREEN_W - BALL_SIZE;
            new_dx = -ball_dx;
        end

        // ---- Top wall ----
        if (tmp_y < 0) begin
            tmp_y  = 0;
            new_dy = -ball_dy;
        end

        // ---- Paddle (only while heading down, only near paddle height) ----
        if (ball_dy > 0 &&
            (tmp_y + BALL_SIZE >= PADDLE_Y) &&
            (tmp_y             <= PADDLE_Y + PADDLE_H) &&
            (tmp_x + BALL_SIZE >= paddle_x) &&
            (tmp_x             <  paddle_x + PADDLE_W)) begin
            tmp_y  = PADDLE_Y - BALL_SIZE;
            new_dy = -ball_dy;
        end
        // ---- Missed - fell past the bottom ----
        else if (ball_dy > 0 && (tmp_y + BALL_SIZE >= SCREEN_H)) begin
            ball_lost = 1'b1;
        end

        // ---- Bricks (checked against the ball's CURRENT box) ----
        found_row = 4'd15;
        if      (ball_y >= BR_YOFF+0*BR_H && ball_y < BR_YOFF+1*BR_H) found_row = 0;
        else if (ball_y >= BR_YOFF+1*BR_H && ball_y < BR_YOFF+2*BR_H) found_row = 1;
        else if (ball_y >= BR_YOFF+2*BR_H && ball_y < BR_YOFF+3*BR_H) found_row = 2;
        else if (ball_y >= BR_YOFF+3*BR_H && ball_y < BR_YOFF+4*BR_H) found_row = 3;
        else if (ball_y >= BR_YOFF+4*BR_H && ball_y < BR_YOFF+5*BR_H) found_row = 4;

        if (!ball_lost && found_row != 4'd15) begin
            hit_row = found_row[2:0];
            hit_col = ball_x[9:6];   // BR_W = 64 = 2^6, so this is exactly ball_x/64
            if (hit_col < BR_COLS && bricks[hit_row][hit_col]) begin
                hit_brick = 1'b1;
                // Read ball_dy exactly once here to decide BOTH the new
                // direction and which side of the brick to rest against -
                // moving down (dy>0) means we hit the brick's TOP, so we
                // rest just above it; moving up (dy<0) means we hit its
                // BOTTOM, so we rest just below it.
                if (ball_dy > 0) begin
                    new_dy = -ball_dy;
                    tmp_y  = (BR_YOFF + hit_row*BR_H) - BALL_SIZE;
                end else begin
                    new_dy = -ball_dy;
                    tmp_y  = (BR_YOFF + hit_row*BR_H) + BR_H;
                end
            end
        end

        final_x = tmp_x[9:0];
        final_y = tmp_y[9:0];
    end

    //-------------------------------------------------------------------
    // The ONE place that actually writes to the game-state registers.
    //-------------------------------------------------------------------
    always @(posedge pix_clk) begin
        if (reset) begin
            paddle_x <= (SCREEN_W - PADDLE_W) / 2;
            ball_x   <= (SCREEN_W/2) - (BALL_SIZE/2);
            ball_y   <= PADDLE_Y - 32;
            ball_dx  <= BALL_DX_INIT;
            ball_dy  <= BALL_DY_INIT;
            bricks_left <= BR_ROWS*BR_COLS;
            for (i = 0; i < BR_ROWS; i = i + 1)
                for (j = 0; j < BR_COLS; j = j + 1)
                    bricks[i][j] <= 1'b1;
        end else if (frame_tick) begin

            // ---- Full game reset: triggered when the paddle misses the
            // ball, OR when the last brick has just been cleared. Both
            // put paddle, ball and the whole brick wall back to their
            // starting state, exactly like the external `reset` input. ----
            if (ball_lost || last_brick_cleared) begin
                paddle_x    <= (SCREEN_W - PADDLE_W) / 2;
                ball_x      <= (SCREEN_W/2) - (BALL_SIZE/2);
                ball_y      <= PADDLE_Y - 32;
                ball_dx     <= BALL_DX_INIT;
                ball_dy     <= BALL_DY_INIT;
                bricks_left <= BR_ROWS*BR_COLS;
                for (i = 0; i < BR_ROWS; i = i + 1)
                    for (j = 0; j < BR_COLS; j = j + 1)
                        bricks[i][j] <= 1'b1;
            end else begin
                // Paddle
                if (btn_left && !btn_right) begin
                    if (paddle_x > PADDLE_SPEED) paddle_x <= paddle_x - PADDLE_SPEED;
                    else paddle_x <= 0;
                end else if (btn_right && !btn_left) begin
                    if (paddle_x < SCREEN_W - PADDLE_W - PADDLE_SPEED) paddle_x <= paddle_x + PADDLE_SPEED;
                    else paddle_x <= SCREEN_W - PADDLE_W;
                end

                // Ball (ball_lost already handled above)
                ball_x  <= final_x;
                ball_y  <= final_y;
                ball_dx <= new_dx;
                ball_dy <= new_dy;

                // Bricks
                if (hit_brick) begin
                    bricks[hit_row][hit_col] <= 1'b0;
                    bricks_left              <= bricks_left - 1'b1;
                end
            end
        end
    end

    // Pixel color generation (combinational).
    always @(*) begin
        r3 = 3'b000; g3 = 3'b000; b2 = 2'b00;
        brick_drawn = 0;

        if (!active_video) begin
            r3 = 3'b000; g3 = 3'b000; b2 = 2'b00;
        end else begin
            for (i = 0; i < BR_ROWS; i = i + 1) begin
                for (j = 0; j < BR_COLS; j = j + 1) begin
                    if (bricks[i][j]) begin
                        bx = BR_XOFF + j * BR_W;
                        by = BR_YOFF + i * BR_H;
                        if ( (px >= bx) && (px < bx + BR_W - BR_GAP) &&
                             (py >= by) && (py < by + BR_H - BR_GAP) ) begin
                            brick_drawn = 1;
                            case (i)
                                0: begin r3 = 3'b111; g3 = 3'b000; b2 = 2'b00; end // red
                                1: begin r3 = 3'b111; g3 = 3'b100; b2 = 2'b00; end // orange
                                2: begin r3 = 3'b111; g3 = 3'b111; b2 = 2'b00; end // yellow
                                3: begin r3 = 3'b000; g3 = 3'b111; b2 = 2'b00; end // green
                                default: begin r3 = 3'b000; g3 = 3'b011; b2 = 2'b11; end // teal
                            endcase
                        end
                    end
                end
            end

            if (!brick_drawn) begin
                if ( (px >= paddle_x) && (px < paddle_x + PADDLE_W) && (py >= PADDLE_Y) && (py < PADDLE_Y + PADDLE_H) ) begin
                    r3 = 3'b000; g3 = 3'b111; b2 = 2'b11; // cyan paddle
                end else if ( (px >= ball_x) && (px < ball_x + BALL_SIZE) && (py >= ball_y) && (py < ball_y + BALL_SIZE) ) begin
                    r3 = 3'b111; g3 = 3'b111; b2 = 2'b11; // white ball
                end else if ( (px < BORDER) || (px >= SCREEN_W-BORDER) ||
                              (py < BORDER) || (py >= SCREEN_H-BORDER) ) begin
                    r3 = 3'b111; g3 = 3'b111; b2 = 2'b11; // white border
                end else begin
                    r3 = 3'b000; g3 = 3'b000; b2 = 2'b00; // black background
                end
            end
        end

        rgb_out = {r3, g3, b2};
    end

endmodule
