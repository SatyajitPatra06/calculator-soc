`timescale 1ns/1ps
//=============================================================================
// calculator_top.v
// Calculator SoC top level.
//
//   operand switches -> sync -> calc_ctrl (FSM + A/B/OP registers) -> alu
//   buttons          -> debounce -> enter / clear pulses
//   display value    -> bin2bcd -> seg7_driver -> 6-digit 7-segment display
//
// Board mapping (example, Basys 3-style):
//   sw[7:0]      slide switches   -- operand value
//   op_sel[2:0]  slide switches   -- operation select
//   btn_enter    push button      -- confirm current step
//   btn_clear    push button      -- abort / clear everything
//   seg, an      7-segment display (active low)
//   led_state    LEDs show the current FSM step
//=============================================================================
module calculator_top #(
    parameter DEBOUNCE_CYCLES = 500_000,   // 10 ms @ 50 MHz
    parameter REFRESH_CYCLES  = 50_000,    // 1 kHz digit scan @ 50 MHz
    parameter ACTIVE_LOW      = 1
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] sw,
    input  wire [2:0] op_sel,
    input  wire       btn_enter,
    input  wire       btn_clear,

    output wire [6:0] seg,
    output wire [5:0] an,
    output wire [2:0] led_state,

    // observation ports (handy for simulation / debug LEDs)
    output wire [15:0] dbg_result,
    output wire        dbg_neg,
    output wire        dbg_err
);
    // ---- synchronise slide switches -----------------------------------------
    reg [10:0] sw_meta, sw_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sw_meta <= 11'd0;
            sw_sync <= 11'd0;
        end else begin
            sw_meta <= {op_sel, sw};
            sw_sync <= sw_meta;
        end
    end
    wire [7:0] sw_s = sw_sync[7:0];
    wire [2:0] op_s = sw_sync[10:8];

    // ---- debounced buttons ----------------------------------------------------
    wire enter_pulse, clear_pulse;
    wire unused_a, unused_b;

    debounce #(.CYCLES(DEBOUNCE_CYCLES)) u_db_enter (
        .clk(clk), .rst_n(rst_n), .noisy(btn_enter),
        .clean(unused_a), .pressed(enter_pulse)
    );
    debounce #(.CYCLES(DEBOUNCE_CYCLES)) u_db_clear (
        .clk(clk), .rst_n(rst_n), .noisy(btn_clear),
        .clean(unused_b), .pressed(clear_pulse)
    );

    // ---- datapath + control ---------------------------------------------------
    wire [7:0]  reg_a, reg_b;
    wire [2:0]  reg_op;
    wire [15:0] alu_result, res_q, disp_value;
    wire        alu_neg, alu_err, neg_q, err_q, disp_neg, disp_err;

    alu u_alu (
        .a(reg_a), .b(reg_b), .op(reg_op),
        .result(alu_result), .neg(alu_neg), .err(alu_err)
    );

    calc_ctrl u_ctrl (
        .clk(clk), .rst_n(rst_n),
        .enter(enter_pulse), .clear(clear_pulse),
        .sw(sw_s), .op_sel(op_s),
        .reg_a(reg_a), .reg_b(reg_b), .reg_op(reg_op),
        .alu_result(alu_result), .alu_neg(alu_neg), .alu_err(alu_err),
        .state(led_state),
        .res_q(res_q), .neg_q(neg_q), .err_q(err_q),
        .disp_value(disp_value), .disp_neg(disp_neg), .disp_err(disp_err)
    );

    // ---- display path ---------------------------------------------------------
    wire [19:0] bcd;

    bin2bcd u_bcd (.bin(disp_value), .bcd(bcd));

    seg7_driver #(.REFRESH_CYCLES(REFRESH_CYCLES), .ACTIVE_LOW(ACTIVE_LOW)) u_seg (
        .clk(clk), .rst_n(rst_n),
        .bcd(bcd), .neg(disp_neg), .err(disp_err),
        .seg(seg), .an(an)
    );

    assign dbg_result = res_q;
    assign dbg_neg    = neg_q;
    assign dbg_err    = err_q;
endmodule
