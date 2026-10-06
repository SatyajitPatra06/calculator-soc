`timescale 1ns/1ps
//=============================================================================
// seg7_driver.v
// 6-digit multiplexed 7-segment display driver.
//
//   digits 4..0 : decimal value (leading zeros blanked, digit 0 always shown)
//   digit  5    : '-' when `neg` is set, otherwise blank
//   err = 1     : shows "Err" on digits 2..0, everything else blank
//
// seg[6:0] = {g,f,e,d,c,b,a};  an[5:0] selects the digit (digit 0 = an[0]).
// ACTIVE_LOW = 1 for common-anode boards (Basys 3, Nexys, DE10 ...).
//=============================================================================
module seg7_driver #(
    parameter REFRESH_CYCLES = 50_000,    // clocks per digit (50 MHz -> 1 kHz digit rate)
    parameter ACTIVE_LOW     = 1
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [19:0] bcd,        // 5 BCD digits
    input  wire        neg,
    input  wire        err,
    output reg  [6:0]  seg,
    output reg  [5:0]  an
);
    // special symbol codes (0-9 are digits)
    localparam [3:0] C_BLANK = 4'hA, C_MINUS = 4'hB, C_E = 4'hC, C_R = 4'hD;

    // ---- build the six digit codes --------------------------------------
    reg [23:0] codes;               // {d5,d4,d3,d2,d1,d0}
    reg        lead;
    integer    i;

    always @* begin
        codes = {C_BLANK, bcd};
        if (neg) codes[23:20] = C_MINUS;

        // blank leading zeros (not digit 0)
        lead = 1'b1;
        for (i = 4; i >= 1; i = i - 1) begin
            if (lead && codes[4*i +: 4] == 4'd0)
                codes[4*i +: 4] = C_BLANK;
            else
                lead = 1'b0;
        end

        if (err) codes = {C_BLANK, C_BLANK, C_BLANK, C_E, C_R, C_R};
    end

    // ---- time multiplexing -----------------------------------------------
    reg [31:0] rcnt;
    reg [2:0]  sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rcnt <= 32'd0;
            sel  <= 3'd0;
        end else if (rcnt >= REFRESH_CYCLES - 1) begin
            rcnt <= 32'd0;
            sel  <= (sel == 3'd5) ? 3'd0 : sel + 3'd1;
        end else
            rcnt <= rcnt + 32'd1;
    end

    // ---- segment decode --------------------------------------------------
    reg [3:0] code_sel;
    reg [6:0] dec;

    always @* begin
        code_sel = codes[4*sel +: 4];
        case (code_sel)
            4'd0:    dec = 7'h3F;
            4'd1:    dec = 7'h06;
            4'd2:    dec = 7'h5B;
            4'd3:    dec = 7'h4F;
            4'd4:    dec = 7'h66;
            4'd5:    dec = 7'h6D;
            4'd6:    dec = 7'h7D;
            4'd7:    dec = 7'h07;
            4'd8:    dec = 7'h7F;
            4'd9:    dec = 7'h6F;
            C_MINUS: dec = 7'h40;
            C_E:     dec = 7'h79;
            C_R:     dec = 7'h50;
            default: dec = 7'h00;       // blank
        endcase
    end

    always @* begin
        seg = ACTIVE_LOW ? ~dec : dec;
        an  = ACTIVE_LOW ? ~(6'd1 << sel) : (6'd1 << sel);
    end
endmodule
