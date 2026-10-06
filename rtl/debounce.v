`timescale 1ns/1ps
//=============================================================================
// debounce.v
// Push-button conditioner: 2-FF synchroniser + stable-time debounce filter
// + rising-edge detector.
//
//   clean   : debounced level
//   pressed : single-cycle pulse on each debounced press (rising edge)
//
// The input must stay at a new value for CYCLES clocks before `clean`
// follows it. 10 ms is a good value: CYCLES = CLK_HZ / 100.
//=============================================================================
module debounce #(
    parameter CYCLES = 500_000           // 10 ms @ 50 MHz
) (
    input  wire clk,
    input  wire rst_n,
    input  wire noisy,
    output reg  clean,
    output wire pressed
);
    reg        meta, sync;
    reg [31:0] cnt;
    reg        clean_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta    <= 1'b0;
            sync    <= 1'b0;
            clean   <= 1'b0;
            clean_d <= 1'b0;
            cnt     <= 32'd0;
        end else begin
            meta    <= noisy;
            sync    <= meta;
            clean_d <= clean;

            if (sync != clean) begin
                if (cnt >= CYCLES - 1) begin
                    clean <= sync;
                    cnt   <= 32'd0;
                end else
                    cnt <= cnt + 32'd1;
            end else
                cnt <= 32'd0;            // input bounced back: restart timer
        end
    end

    assign pressed = clean & ~clean_d;
endmodule
