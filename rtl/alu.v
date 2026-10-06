`timescale 1ns/1ps
//=============================================================================
// alu.v
// Combinational 8-bit ALU with 16-bit result.
//
//  op   operation        notes
//  000  ADD  a + b       up to 510
//  001  SUB  a - b       if a < b the magnitude (b - a) is returned, neg = 1
//  010  MUL  a * b       up to 65025
//  011  DIV  a / b       err = 1 when b == 0
//  100  AND  a & b
//  101  OR   a | b
//  110  XOR  a ^ b
//  111  MOD  a % b       err = 1 when b == 0
//=============================================================================
module alu #(
    parameter DATA_W = 8,
    parameter RES_W  = 16
) (
    input  wire [DATA_W-1:0] a,
    input  wire [DATA_W-1:0] b,
    input  wire [2:0]        op,
    output reg  [RES_W-1:0]  result,
    output reg               neg,     // result is negative (magnitude in `result`)
    output reg               err      // divide / modulo by zero
);
    localparam [2:0] OP_ADD = 3'd0, OP_SUB = 3'd1, OP_MUL = 3'd2, OP_DIV = 3'd3,
                     OP_AND = 3'd4, OP_OR  = 3'd5, OP_XOR = 3'd6, OP_MOD = 3'd7;

    always @* begin
        result = {RES_W{1'b0}};
        neg    = 1'b0;
        err    = 1'b0;
        case (op)
            OP_ADD: result = a + b;
            OP_SUB: begin
                if (a >= b) result = a - b;
                else begin
                    result = b - a;
                    neg    = 1'b1;
                end
            end
            OP_MUL: result = a * b;
            OP_DIV: begin
                if (b == 0) err = 1'b1;
                else        result = a / b;
            end
            OP_AND: result = a & b;
            OP_OR : result = a | b;
            OP_XOR: result = a ^ b;
            OP_MOD: begin
                if (b == 0) err = 1'b1;
                else        result = a % b;
            end
            default: ;
        endcase
    end
endmodule
