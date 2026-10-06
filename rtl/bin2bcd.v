`timescale 1ns/1ps
//=============================================================================
// bin2bcd.v
// 16-bit binary to 5-digit BCD using the shift-and-add-3 (double dabble)
// algorithm. Purely combinational.
//=============================================================================
module bin2bcd (
    input  wire [15:0] bin,
    output reg  [19:0] bcd      // {d4,d3,d2,d1,d0}, 4 bits each
);
    integer i, j;
    always @* begin
        bcd = 20'd0;
        for (i = 15; i >= 0; i = i - 1) begin
            for (j = 0; j < 5; j = j + 1)
                if (bcd[4*j +: 4] >= 4'd5)
                    bcd[4*j +: 4] = bcd[4*j +: 4] + 4'd3;
            bcd = {bcd[18:0], bin[i]};
        end
    end
endmodule
