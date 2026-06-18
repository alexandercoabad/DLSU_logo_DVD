/*
 * Copyright (c) 2024 Tiny Tapeout LTD
 * SPDX-License-Identifier: Apache-2.0
 * Author: Uri Shaked / Optimization Edit
 * Fully balanced 3-stage pipeline fix for 25.179 MHz timing closure
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

  // VGA raw signals from generator
  wire hsync;
  wire vsync;
  wire video_active;
  wire [9:0] pix_x;
  wire [9:0] pix_y;
  reg  video_out;

  // Balanced 3-Stage Pipeline registers for VGA control signals
  reg hsync_r1, hsync_r2, hsync_r3;
  reg vsync_r1, vsync_r2, vsync_r3;
  reg video_active_r1, video_active_r2, video_active_r3;

  // TinyVGA PMOD mapping (Using the 3-cycle pipelined sync channels)
  assign uo_out = {hsync_r3, video_out, video_out, video_out, vsync_r3, video_out, video_out, video_out};

  assign uio_out = 8'b00000000;
  assign uio_oe  = 8'b00000000;

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
  
  // Explicitly keep intermediate registers to prevent Yosys collapsing
  (* keep = 1 *) reg [9:0] logo_right;
  (* keep = 1 *) reg [9:0] logo_bottom;
  
  reg dir_x;
  reg dir_y;

  wire pixel_value;

  // Pipeline Stage 1 registers for address math isolation
  (* keep = 1 *) reg [6:0] rom_addr_x;
  (* keep = 1 *) reg [6:0] rom_addr_y;
  (* keep = 1 *) reg [9:0] pix_x_r1;
  (* keep = 1 *) reg [9:0] pix_y_r1;
  (* keep = 1 *) reg [9:0] logo_left_r1;
  (* keep = 1 *) reg [9:0] logo_top_r1;

  // Pipeline Stage 2 registers for independent spatial matching
  (* keep = 1 *) reg x_match_r2;
  (* keep = 1 *) reg y_match_r2;
  
  // Pipeline Stage 3 register: Merged region tracking
  (* keep = 1 *) reg logo_region_r3;

  // Instantiate the ROM block (Addresses are pre-calculated in Stage 1, evaluated in Stage 2)
  bitmap_rom rom1 (
      .x(rom_addr_x),
      .y(rom_addr_y),
      .pixel(pixel_value)
  );

  // =========================================================================
  // PIPELINE STAGE 1: Isolate dynamic additions and subtractions
  // =========================================================================
  always @(posedge clk) begin
    if (~rst_n) begin
      logo_right      <= 0;
      logo_bottom     <= 0;
      rom_addr_x      <= 0;
      rom_addr_y      <= 0;
      pix_x_r1        <= 0;
      pix_y_r1        <= 0;
      logo_left_r1    <= 0;
      logo_top_r1     <= 0;
      hsync_r1        <= 1;
      vsync_r1        <= 1;
      video_active_r1 <= 0;
    end else begin
      // Pre-compute object boundaries
      logo_right      <= logo_left + LOGO_SIZE;
      logo_bottom     <= logo_top + LOGO_SIZE;

      // Isolate the offset address computation subtraction from the ROM lookups
      rom_addr_x      <= pix_x[6:0] - logo_left[6:0];
      rom_addr_y      <= pix_y[6:0] - logo_top[6:0];

      // Delay raw positions to match alignment
      pix_x_r1        <= pix_x;
      pix_y_r1        <= pix_y;
      logo_left_r1    <= logo_left;
      logo_top_r1     <= logo_top;

      // Pipeline Sync Control Signals - Stage 1
      hsync_r1        <= hsync;
      vsync_r1        <= vsync;
      video_active_r1 <= video_active;
    end
  end

  // =========================================================================
  // PIPELINE STAGE 2: Independent Axis Comparisons (Prevents logic cross-talk)
  // =========================================================================
  always @(posedge clk) begin
    if (~rst_n) begin
      x_match_r2      <= 0;
      y_match_r2      <= 0;
      hsync_r2        <= 1;
      vsync_r2        <= 1;
      video_active_r2 <= 0;
    end else begin
      // Split the massive 4-way boolean expression into two simple parallel paths
      x_match_r2      <= (pix_x_r1 >= logo_left_r1) && (pix_x_r1 < logo_right);
      y_match_r2      <= (pix_y_r1 >= logo_top_r1)  && (pix_y_r1 < logo_bottom);

      // Pipeline Sync Control Signals - Stage 2
      hsync_r2        <= hsync_r1;
      vsync_r2        <= vsync_r1;
      video_active_r2 <= video_active_r1;
    end
  end

  // =========================================================================
  // PIPELINE STAGE 3: Merge spatial hits
  // =========================================================================
  always @(posedge clk) begin
    if (~rst_n) begin
      logo_region_r3  <= 0;
      hsync_r3        <= 1;
      vsync_r3        <= 1;
      video_active_r3 <= 0;
    end else begin
      logo_region_r3  <= x_match_r2 && y_match_r2;

      // Pipeline Sync Control Signals - Stage 3
      hsync_r3        <= hsync_r2;
      vsync_r3        <= vsync_r2;
      video_active_r3 <= video_active_r2;
    end
  end

  // =========================================================================
  // PIPELINE STAGE 4: Final Gated Output Video
  // =========================================================================
  always @(posedge clk) begin
    if (~rst_n) begin
      video_out <= 0;
    end else begin
      // Both pixel_value (from ROM) and logo_region_r3 clear synchronously here
      video_out <= video_active_r3 && logo_region_r3 && pixel_value;
    end
  end

  // =========================================================================
  // Object Physics (Safe outside active drawing critical paths)
  // =========================================================================
  always @(posedge clk) begin
    if (~rst_n) begin
      logo_left <= 200;
      logo_top  <= 200;
      dir_y     <= 0;
      dir_x     <= 1;
      prev_y    <= 0;
    end else begin
      prev_y <= pix_y;
      if (pix_y == 0 && prev_y != pix_y) begin
        logo_left <= logo_left + (dir_x ? 1'd1 : -10'd1);
        logo_top  <= logo_top + (dir_y ? 1'd1 : -10'd1);

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
