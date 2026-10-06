//=============================================================================
// tb_calculator.sv  --  Self-checking testbench for the Calculator SoC
//
// What is verified
//   * Full key sequence  A -> ENTER -> OP -> ENTER -> B -> ENTER -> result
//   * All 8 ALU operations, incl. 16-bit results, negative subtraction and
//     divide/modulo-by-zero error flags
//   * Button debouncing: every press is applied with contact bounce; a glitch
//     shorter than the debounce window must be ignored
//   * CLEAR from mid-sequence and from the result state, and async reset
//   * 7-segment output: the testbench decodes the real `seg` / `an` pins and
//     compares them with the expected decimal string (blank leading zeros,
//     '-' sign digit, "Err")
//   * Directed corner cases + 300 constrained-random operations checked
//     against a behavioural reference model
//
// Prints "TEST PASSED" / "TEST FAILED" and an operation coverage summary.
//=============================================================================
`timescale 1ns/1ps

module tb_calculator;

    // small values so simulation is fast; behaviour is identical to hardware
    localparam DEB     = 16;     // debounce window (clocks)
    localparam REFRESH = 4;      // clocks per displayed digit

    // FSM state encodings (must match calc_ctrl.v)
    localparam [2:0] S_ENTER_A = 3'd0, S_ENTER_OP = 3'd1, S_ENTER_B = 3'd2,
                     S_COMPUTE = 3'd3, S_RESULT   = 3'd4;

    localparam [2:0] OP_ADD = 3'd0, OP_SUB = 3'd1, OP_MUL = 3'd2, OP_DIV = 3'd3,
                     OP_AND = 3'd4, OP_OR  = 3'd5, OP_XOR = 3'd6, OP_MOD = 3'd7;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg  [7:0] sw = 8'd0;
    reg  [2:0] op_sel = 3'd0;
    reg        btn_enter = 1'b0;
    reg        btn_clear = 1'b0;

    wire [6:0]  seg;
    wire [5:0]  an;
    wire [2:0]  led_state;
    wire [15:0] dbg_result;
    wire        dbg_neg, dbg_err;

    always #5 clk = ~clk;       // 100 MHz in simulation

    calculator_top #(
        .DEBOUNCE_CYCLES (DEB),
        .REFRESH_CYCLES  (REFRESH),
        .ACTIVE_LOW      (1)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .sw         (sw),
        .op_sel     (op_sel),
        .btn_enter  (btn_enter),
        .btn_clear  (btn_clear),
        .seg        (seg),
        .an         (an),
        .led_state  (led_state),
        .dbg_result (dbg_result),
        .dbg_neg    (dbg_neg),
        .dbg_err    (dbg_err)
    );

    // ------------------------------------------------------------------
    // Bookkeeping
    // ------------------------------------------------------------------
    integer errors = 0;
    integer tests  = 0;
    integer op_cnt [0:7];
    integer err_cnt = 0;
    integer neg_cnt = 0;

    task automatic fail(input [8*64-1:0] msg);
        begin
            errors = errors + 1;
            $display("[%0t] ERROR: %0s", $time, msg);
        end
    endtask

    // ------------------------------------------------------------------
    // Reference model: returns {err, neg, result[15:0]}
    // ------------------------------------------------------------------
    function [17:0] model(input [7:0] a, input [7:0] b, input [2:0] op);
        integer ia, ib;
        reg [15:0] r;
        reg        n, e;
        begin
            ia = a; ib = b; r = 16'd0; n = 1'b0; e = 1'b0;
            case (op)
                OP_ADD: r = ia + ib;
                OP_SUB: if (ia >= ib) r = ia - ib; else begin r = ib - ia; n = 1'b1; end
                OP_MUL: r = ia * ib;
                OP_DIV: if (ib == 0) e = 1'b1; else r = ia / ib;
                OP_AND: r = a & b;
                OP_OR : r = a | b;
                OP_XOR: r = a ^ b;
                OP_MOD: if (ib == 0) e = 1'b1; else r = ia % ib;
            endcase
            model = {e, n, r};
        end
    endfunction

    // ------------------------------------------------------------------
    // 7-segment helpers (independent of the RTL tables)
    // ------------------------------------------------------------------
    function [6:0] enc(input [3:0] c);   // active-high {g,f,e,d,c,b,a}
        begin
            case (c)
                4'd0: enc = 7'b0111111;
                4'd1: enc = 7'b0000110;
                4'd2: enc = 7'b1011011;
                4'd3: enc = 7'b1001111;
                4'd4: enc = 7'b1100110;
                4'd5: enc = 7'b1101101;
                4'd6: enc = 7'b1111101;
                4'd7: enc = 7'b0000111;
                4'd8: enc = 7'b1111111;
                4'd9: enc = 7'b1101111;
                4'hB: enc = 7'b1000000;   // '-'
                4'hC: enc = 7'b1111001;   // 'E'
                4'hD: enc = 7'b1010000;   // 'r'
                default: enc = 7'b0000000; // blank
            endcase
        end
    endfunction

    // expected digit codes {d5..d0}; A = blank, B = '-', C = 'E', D = 'r'
    function [23:0] exp_codes(input [15:0] v, input neg, input err);
        integer t, i;
        reg     lead;
        reg [23:0] r;
        begin
            if (err) begin
                r = {4'hA, 4'hA, 4'hA, 4'hC, 4'hD, 4'hD};
            end else begin
                t = v;
                r[3:0]   = t % 10; t = t / 10;
                r[7:4]   = t % 10; t = t / 10;
                r[11:8]  = t % 10; t = t / 10;
                r[15:12] = t % 10; t = t / 10;
                r[19:16] = t % 10;
                r[23:20] = neg ? 4'hB : 4'hA;
                lead = 1'b1;
                for (i = 4; i >= 1; i = i - 1) begin
                    if (lead && r[4*i +: 4] == 4'd0) r[4*i +: 4] = 4'hA;
                    else lead = 1'b0;
                end
            end
            exp_codes = r;
        end
    endfunction

    // Sample the multiplexed display for two full scans and compare
    task automatic check_display(input [15:0] v, input neg, input err);
        reg [41:0] cap;
        reg [23:0] ec;
        reg [5:0]  sel;
        integer    i, n;
        begin
            cap = {42{1'bx}};
            for (n = 0; n < (6 * REFRESH * 2 + 4); n = n + 1) begin
                @(posedge clk); #1;
                sel = ~an;
                if (sel == 6'd0 || (sel & (sel - 6'd1)) != 6'd0)
                    fail("an[] is not one-hot");
                for (i = 0; i < 6; i = i + 1)
                    if (sel[i]) cap[7*i +: 7] = ~seg;       // un-invert (active low)
            end
            ec = exp_codes(v, neg, err);
            for (i = 0; i < 6; i = i + 1)
                if (cap[7*i +: 7] !== enc(ec[4*i +: 4])) begin
                    errors = errors + 1;
                    $display("[%0t] ERROR: display digit %0d  exp=%b got=%b  (value=%0d neg=%0d err=%0d)",
                             $time, i, enc(ec[4*i +: 4]), cap[7*i +: 7], v, neg, err);
                end
        end
    endtask

    // ------------------------------------------------------------------
    // Button tasks (with contact bounce)
    // ------------------------------------------------------------------
    task automatic press_enter;
        begin
            btn_enter = 1'b1; repeat (3) @(posedge clk);     // bounce
            btn_enter = 1'b0; repeat (2) @(posedge clk);
            btn_enter = 1'b1; repeat (3) @(posedge clk);
            btn_enter = 1'b0; repeat (2) @(posedge clk);
            btn_enter = 1'b1; repeat (DEB * 3) @(posedge clk); // settled
            btn_enter = 1'b0; repeat (DEB * 3) @(posedge clk); // released
        end
    endtask

    task automatic press_clear;
        begin
            btn_clear = 1'b1; repeat (3) @(posedge clk);
            btn_clear = 1'b0; repeat (2) @(posedge clk);
            btn_clear = 1'b1; repeat (DEB * 3) @(posedge clk);
            btn_clear = 1'b0; repeat (DEB * 3) @(posedge clk);
        end
    endtask

    task automatic expect_state(input [2:0] s);
        begin
            if (led_state !== s) begin
                errors = errors + 1;
                $display("[%0t] ERROR: FSM state exp=%0d got=%0d", $time, s, led_state);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // One complete calculation
    // ------------------------------------------------------------------
    task automatic calc(input [7:0] a, input [2:0] op, input [7:0] b, input check_disp);
        reg [17:0] m;
        begin
            m = model(a, b, op);
            tests = tests + 1;
            op_cnt[op] = op_cnt[op] + 1;
            if (m[17]) err_cnt = err_cnt + 1;
            if (m[16]) neg_cnt = neg_cnt + 1;

            expect_state(S_ENTER_A);

            sw = a;        repeat (6) @(posedge clk);
            if (check_disp) check_display({8'd0, a}, 1'b0, 1'b0);   // live operand echo
            press_enter;
            expect_state(S_ENTER_OP);

            op_sel = op;   repeat (6) @(posedge clk);
            press_enter;
            expect_state(S_ENTER_B);

            sw = b;        repeat (6) @(posedge clk);
            press_enter;
            expect_state(S_RESULT);

            if (dbg_result !== m[15:0] || dbg_neg !== m[16] || dbg_err !== m[17]) begin
                errors = errors + 1;
                $display("[%0t] ERROR: %0d op%0d %0d  exp res=%0d neg=%0d err=%0d | got res=%0d neg=%0d err=%0d",
                         $time, a, op, b, m[15:0], m[16], m[17], dbg_result, dbg_neg, dbg_err);
            end
            if (check_disp) check_display(m[15:0], m[16], m[17]);

            press_enter;                       // start new calculation
            expect_state(S_ENTER_A);
        end
    endtask

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    integer seed = 32'hC0FFEE;
    integer i;
    reg [7:0] ra, rb;
    reg [2:0] rop;
    reg [31:0] rr;

    function [7:0] rand_operand(input integer sd_dummy);
        reg [31:0] x;
        begin
            x = $random(seed);
            case (x[3:0])
                4'd0:    rand_operand = 8'd0;
                4'd1:    rand_operand = 8'd255;
                4'd2:    rand_operand = 8'd1;
                4'd3:    rand_operand = {4'd0, x[11:8]};   // small
                default: rand_operand = x[23:16];
            endcase
        end
    endfunction

    initial begin
        for (i = 0; i < 8; i = i + 1) op_cnt[i] = 0;

        $dumpfile("calculator_tb.vcd");
        $dumpvars(0, tb_calculator);

        // ---- reset -------------------------------------------------------
        rst_n = 1'b0; repeat (5) @(posedge clk);
        rst_n = 1'b1; repeat (5) @(posedge clk);
        expect_state(S_ENTER_A);

        // ---- directed tests (with display checking) -----------------------
        $display("Directed tests ...");
        calc(8'd12,  OP_ADD, 8'd30,  1);   // 42
        calc(8'd200, OP_ADD, 8'd100, 1);   // 300  (>8 bit)
        calc(8'd255, OP_ADD, 8'd255, 1);   // 510
        calc(8'd50,  OP_SUB, 8'd20,  1);   // 30
        calc(8'd20,  OP_SUB, 8'd50,  1);   // -30
        calc(8'd77,  OP_SUB, 8'd77,  1);   // 0
        calc(8'd15,  OP_MUL, 8'd15,  1);   // 225
        calc(8'd255, OP_MUL, 8'd255, 1);   // 65025 (max, uses all 5 digits)
        calc(8'd100, OP_DIV, 8'd7,   1);   // 14
        calc(8'd5,   OP_DIV, 8'd9,   1);   // 0
        calc(8'd42,  OP_DIV, 8'd0,   1);   // Err
        calc(8'hF0,  OP_AND, 8'h3C,  1);
        calc(8'hF0,  OP_OR,  8'h0F,  1);
        calc(8'hAA,  OP_XOR, 8'hFF,  1);
        calc(8'd100, OP_MOD, 8'd7,   1);   // 2
        calc(8'd9,   OP_MOD, 8'd0,   1);   // Err

        // ---- button glitch shorter than debounce window must be ignored ----
        $display("Debounce glitch test ...");
        btn_enter = 1'b1; repeat (DEB / 4) @(posedge clk);
        btn_enter = 1'b0; repeat (DEB * 3) @(posedge clk);
        expect_state(S_ENTER_A);

        // ---- CLEAR in the middle of a sequence ----------------------------
        $display("Clear / reset tests ...");
        sw = 8'd99; repeat (6) @(posedge clk);
        press_enter;                       // -> ENTER_OP
        expect_state(S_ENTER_OP);
        press_clear;
        expect_state(S_ENTER_A);
        calc(8'd6, OP_MUL, 8'd7, 1);       // 42, calculator still works

        // ---- CLEAR from RESULT state --------------------------------------
        sw = 8'd9; repeat (6) @(posedge clk); press_enter;
        op_sel = OP_ADD; repeat (6) @(posedge clk); press_enter;
        sw = 8'd1; repeat (6) @(posedge clk); press_enter;
        expect_state(S_RESULT);
        press_clear;
        expect_state(S_ENTER_A);
        if (dbg_result !== 16'd0) fail("CLEAR did not clear result register");

        // ---- asynchronous reset in the middle of an operation --------------
        sw = 8'd3; repeat (6) @(posedge clk); press_enter;
        expect_state(S_ENTER_OP);
        #3 rst_n = 1'b0; #7 rst_n = 1'b1; repeat (3) @(posedge clk);
        expect_state(S_ENTER_A);

        // ---- constrained-random regression ---------------------------------
        $display("Random regression (300 ops) ...");
        for (i = 0; i < 300; i = i + 1) begin
            ra  = rand_operand(0);
            rb  = rand_operand(0);
            rr  = $random(seed);
            rop = rr[2:0];
            calc(ra, rop, rb, (i % 10) == 0);    // display check every 10th op
        end

        // ---- summary ---------------------------------------------------------
        repeat (10) @(posedge clk);
        $display("--------------------------------------------------");
        $display("Calculations run : %0d", tests);
        $display("Op coverage      : ADD=%0d SUB=%0d MUL=%0d DIV=%0d AND=%0d OR=%0d XOR=%0d MOD=%0d",
                 op_cnt[0], op_cnt[1], op_cnt[2], op_cnt[3], op_cnt[4], op_cnt[5], op_cnt[6], op_cnt[7]);
        $display("Negative results : %0d,  Div/Mod-by-zero errors: %0d", neg_cnt, err_cnt);
        $display("Errors           : %0d", errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED");
        $display("--------------------------------------------------");
        $finish;
    end

    // global watchdog
    initial begin
        #50_000_000;
        $display("TEST FAILED: global watchdog timeout");
        $finish;
    end
endmodule
