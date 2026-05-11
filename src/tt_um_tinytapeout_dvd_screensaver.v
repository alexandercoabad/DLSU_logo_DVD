/*
 * Copyright (c) 2024 Tiny Tapeout LTD
 * SPDX-License-Identifier: Apache-2.0
 * Author: Uri Shaked
 */

`default_nettype none

parameter LOGO_SIZE = 128;  // Size of the logo in pixels
parameter DISPLAY_WIDTH = 640;  // VGA display width
parameter DISPLAY_HEIGHT = 480;  // VGA display height

module tt_um_tinytapeout_dvd_screensaver (
    input  wire [7:0] ui_in,    // Dedicated inputs - UNUSED
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path - UNUSED
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // VGA signals
  wire hsync;
  wire vsync;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;
  reg  video_out;

  // TinyVGA PMOD mapping (Single bit video_out tied to all color channels)
  assign uo_out = {hsync, video_out, video_out, video_out, vsync, video_out, video_out, video_out};

  // Set IOs to static outputs/disabled to remove input dependency
  assign uio_out = 8'b00000000;
  assign uio_oe  = 8'b00000000;

  // Explicitly ignore all inputs to satisfy linter/suppress warnings
  wire _unused_ok = &{ena, ui_in, uio_in};

  reg [9:0] prev_y;

  vga_sync_generator vga_sync_gen (
      .clk(clk),
      .reset(~rst_n),
      .hsync(hsync),
      .vsync(vsync),
      .display_on(video_active),
      .hpos(pix_x),
      .vpos(pix_y)
  );

  reg [9:0] logo_left;
  reg [9:0] logo_top;
  reg dir_x;
  reg dir_y;

  wire pixel_value;

  wire [9:0] x = pix_x - logo_left;
  wire [9:0] y = pix_y - logo_top;
  
  // Logic simplified: logo only renders within the 128x128 bounding box
  wire logo_region = (x[9:7] == 0 && y[9:7] == 0);

  bitmap_rom rom1 (
      .x(x[6:0]),
      .y(y[6:0]),
      .pixel(pixel_value)
  );

  // Video Output Logic
  always @(posedge clk) begin
    if (~rst_n) begin
      video_out <= 0;
    end else begin
      video_out <= video_active && logo_region && pixel_value;
    end
  end

  // Bouncing logic
  always @(posedge clk) begin
    if (~rst_n) begin
      logo_left <= 200;
      logo_top <= 200;
      dir_y <= 0;
      dir_x <= 1;
    end else begin
      prev_y <= pix_y;
      if (pix_y == 0 && prev_y != pix_y) begin
        logo_left <= logo_left + (dir_x ? 1 : -1);
        logo_top  <= logo_top + (dir_y ? 1 : -1);

        if (logo_left <= 1 && !dir_x) begin
          dir_x <= 1;
        end
        if (logo_left >= (DISPLAY_WIDTH - LOGO_SIZE - 1) && dir_x) begin
          dir_x <= 0;
        end
        if (logo_top <= 1 && !dir_y) begin
          dir_y <= 1;
        end
        if (logo_top >= (DISPLAY_HEIGHT - LOGO_SIZE - 1) && dir_y) begin
          dir_y <= 0;
        end
      end
    end
  end

endmodule
