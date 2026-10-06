`timescale 1ns/1ps
//=============================================================================
// calc_ctrl.v
// Calculator control FSM + operand / opcode registers.
//
//   S_ENTER_A  -- set sw[7:0] to operand A, press ENTER
//   S_ENTER_OP -- set op_sel[2:0] to the operation, press ENTER
//   S_ENTER_B  -- set sw[7:0] to operand B, press ENTER
//   S_COMPUTE  -- 1 cycle: ALU result captured into result registers
//   S_RESULT   -- result displayed; ENTER starts a new calculation
//
//   CLEAR returns to S_ENTER_A from any state and clears all registers.
//=============================================================================
module calc_ctrl #(
    parameter DATA_W = 8,
    parameter RES_W  = 16
) (
    input  wire              clk,
    input  wire              rst_n,

    input  wire              enter,        // 1-cycle pulse (debounced)
    input  wire              clear,        // 1-cycle pulse (debounced)
    input  wire [DATA_W-1:0] sw,           // operand switches (synchronised)
    input  wire [2:0]        op_sel,       // operation switches (synchronised)

    // ALU interface
    output reg  [DATA_W-1:0] reg_a,
    output reg  [DATA_W-1:0] reg_b,
    output reg  [2:0]        reg_op,
    input  wire [RES_W-1:0]  alu_result,
    input  wire              alu_neg,
    input  wire              alu_err,

    // display / status
    output reg  [2:0]        state,
    output reg  [RES_W-1:0]  res_q,
    output reg               neg_q,
    output reg               err_q,
    output reg  [RES_W-1:0]  disp_value,
    output reg               disp_neg,
    output reg               disp_err
);
    localparam [2:0] S_ENTER_A  = 3'd0,
                     S_ENTER_OP = 3'd1,
                     S_ENTER_B  = 3'd2,
                     S_COMPUTE  = 3'd3,
                     S_RESULT   = 3'd4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_ENTER_A;
            reg_a  <= {DATA_W{1'b0}};
            reg_b  <= {DATA_W{1'b0}};
            reg_op <= 3'd0;
            res_q  <= {RES_W{1'b0}};
            neg_q  <= 1'b0;
            err_q  <= 1'b0;
        end else if (clear) begin
            state  <= S_ENTER_A;
            reg_a  <= {DATA_W{1'b0}};
            reg_b  <= {DATA_W{1'b0}};
            reg_op <= 3'd0;
            res_q  <= {RES_W{1'b0}};
            neg_q  <= 1'b0;
            err_q  <= 1'b0;
        end else begin
            case (state)
                S_ENTER_A: if (enter) begin
                    reg_a <= sw;
                    state <= S_ENTER_OP;
                end

                S_ENTER_OP: if (enter) begin
                    reg_op <= op_sel;
                    state  <= S_ENTER_B;
                end

                S_ENTER_B: if (enter) begin
                    reg_b <= sw;
                    state <= S_COMPUTE;
                end

                S_COMPUTE: begin
                    res_q <= alu_result;
                    neg_q <= alu_neg;
                    err_q <= alu_err;
                    state <= S_RESULT;
                end

                S_RESULT: if (enter) begin
                    state <= S_ENTER_A;
                end

                default: state <= S_ENTER_A;
            endcase
        end
    end

    // What the 7-segment display shows in each state
    always @* begin
        disp_value = {RES_W{1'b0}};
        disp_neg   = 1'b0;
        disp_err   = 1'b0;
        case (state)
            S_ENTER_A,
            S_ENTER_B:  disp_value = {{(RES_W-DATA_W){1'b0}}, sw};   // live operand
            S_ENTER_OP: disp_value = {{(RES_W-3){1'b0}}, op_sel};    // live opcode
            S_COMPUTE,
            S_RESULT: begin
                disp_value = res_q;
                disp_neg   = neg_q;
                disp_err   = err_q;
            end
            default: ;
        endcase
    end
endmodule
