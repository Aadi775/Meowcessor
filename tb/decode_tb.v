`timescale 1ns/1ps
`include "defines.v"

module decode_tb;

    reg [31:0] inst;

    // Outputs from imm_gen
    wire [31:0] imm;

    // Outputs from decoder
    wire [4:0] rs1_addr;
    wire [4:0] rs2_addr;
    wire [4:0] rd_addr;
    wire       reg_we;
    wire [1:0] alu_src_a;
    wire       alu_src_b;
    wire [4:0] alu_op;
    wire       mem_we;
    wire       mem_re;
    wire       branch;
    wire       jump;
    wire       jalr;
    wire [1:0] wb_sel;
    wire       csr_we;
    wire       csr_re;
    wire       illegal_inst;

    imm_gen u_imm_gen (
        .inst(inst),
        .imm (imm)
    );

    decoder u_decoder (
        .inst        (inst),
        .rs1_addr    (rs1_addr),
        .rs2_addr    (rs2_addr),
        .rd_addr     (rd_addr),
        .reg_we      (reg_we),
        .alu_src_a   (alu_src_a),
        .alu_src_b   (alu_src_b),
        .alu_op      (alu_op),
        .mem_we      (mem_we),
        .mem_re      (mem_re),
        .branch      (branch),
        .jump        (jump),
        .jalr        (jalr),
        .wb_sel      (wb_sel),
        .csr_we      (csr_we),
        .csr_re      (csr_re),
        .illegal_inst(illegal_inst)
    );

    initial begin
        $dumpfile("decode_tb.vcd");
        $dumpvars(0, decode_tb);

        // 1. ADDI x1, x2, 10
        // I-type: imm[11:0]=10, rs1=2, funct3=0, rd=1, opcode=0010011
        inst = {12'd10, 5'd2, 3'b000, 5'd1, 7'b0010011};
        #10;
        if (imm !== 32'd10 || alu_op !== `ALU_OP_ADD || alu_src_a !== 2'b00 || alu_src_b !== 1'b1 || reg_we !== 1'b1) $display("ADDI failed");

        // 2. LUI x5, 0x12345
        // U-type: imm[31:12]=0x12345, rd=5, opcode=0110111
        inst = {20'h12345, 5'd5, 7'b0110111};
        #10;
        if (imm !== 32'h12345000 || alu_src_a !== 2'b10 || reg_we !== 1'b1) $display("LUI failed");

        // 3. BEQ x1, x2, -4
        // B-type: imm=-4 (11111111111111111111111111111100)
        // inst[31]=1, inst[7]=1, inst[30:25]=111111, inst[11:8]=1110, rs2=2, rs1=1, funct3=0, opcode=1100011
        inst = {1'b1, 6'b111111, 5'd2, 5'd1, 3'b000, 4'b1110, 1'b1, 7'b1100011};
        #10;
        if (imm !== 32'hfffffffc || branch !== 1'b1 || alu_op !== `ALU_OP_SUB) $display("BEQ failed");

        // 4. LW x10, 8(x11)
        // I-type: imm=8, rs1=11, funct3=010, rd=10, opcode=0000011
        inst = {12'd8, 5'd11, 3'b010, 5'd10, 7'b0000011};
        #10;
        if (imm !== 32'd8 || mem_re !== 1'b1 || wb_sel !== 2'b01 || reg_we !== 1'b1) $display("LW failed");

        // 5. SW x12, 16(x13)
        // S-type: imm=16 (0x10), rs2=12, rs1=13, funct3=010, opcode=0100011
        // imm[11:5] = 0, imm[4:0] = 16 = 5'b10000
        inst = {7'b0000000, 5'd12, 5'd13, 3'b010, 5'b10000, 7'b0100011};
        #10;
        if (imm !== 32'd16 || mem_we !== 1'b1) $display("SW failed");

        // 6. CSRRS x1, mtvec, x2
        // I-type: imm=0x305, rs1=2, funct3=010, rd=1, opcode=1110011
        inst = {12'h305, 5'd2, 3'b010, 5'd1, 7'b1110011};
        #10;
        if (csr_re !== 1'b1 || csr_we !== 1'b1 || wb_sel !== 2'b11 || reg_we !== 1'b1) $display("CSRRS failed");

        // 7. CSRRS x1, mtvec, x0 (Read only)
        // rs1=0
        inst = {12'h305, 5'd0, 3'b010, 5'd1, 7'b1110011};
        #10;
        if (csr_re !== 1'b1 || csr_we !== 1'b0 || wb_sel !== 2'b11 || reg_we !== 1'b1) $display("CSRRS read-only failed");

        // 8. Illegal Instruction
        inst = 32'hFFFFFFFF;
        #10;
        if (illegal_inst !== 1'b1) $display("Illegal instruction failed");

        $display("All tests completed!");
        $finish;
    end

endmodule
