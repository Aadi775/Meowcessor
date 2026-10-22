`include "defines.v"

module imm_gen(
    input  wire [31:0] inst,
    output reg  [31:0] imm
);

    wire [6:0] opcode = inst[6:0];

    always @(*) begin
        case (opcode)
            `OP_LOAD, `OP_JALR, `OP_OP_IMM: begin
                // I-type
                imm = {{20{inst[31]}}, inst[31:20]};
            end

            `OP_STORE: begin
                // S-type
                imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            end

            `OP_BRANCH: begin
                // B-type
                imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
            end

            `OP_LUI, `OP_AUIPC: begin
                // U-type
                imm = {inst[31:12], 12'b0};
            end

            `OP_JAL: begin
                // J-type
                imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            end

            `OP_SYSTEM: begin
                // CSR I-type immediate (zimm is 5 bits zero-extended)
                imm = {27'b0, inst[19:15]};
            end

            default: begin
                imm = 32'b0;
            end
        endcase
    end

endmodule
