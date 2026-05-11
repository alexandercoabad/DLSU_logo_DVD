`default_nettype none
module palette (
    input  wire [0:0] color_index,
    output wire [5:0] rrggbb
);

  reg [5:0] palette[1:0];

  initial begin
    palette[1] = 6'b111111;  // white
  end

  assign rrggbb = palette[color_index];

endmodule
