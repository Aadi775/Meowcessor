`timescale 1ns/1ps

module lsu_tb;
    reg [31:0] effective_addr;
    reg [2:0] funct3;
    reg [31:0] store_data;
    reg [31:0] memory_rdata;
    wire [31:0] memory_addr;
    wire [31:0] memory_wdata;
    wire [3:0] memory_wstrb;
    wire [31:0] load_data;

    integer offset;
    reg [31:0] expected;

    lsu dut (
        .effective_addr(effective_addr),
        .funct3(funct3),
        .store_data(store_data),
        .memory_rdata(memory_rdata),
        .memory_addr(memory_addr),
        .memory_wdata(memory_wdata),
        .memory_wstrb(memory_wstrb),
        .load_data(load_data)
    );

    initial begin
        effective_addr = 32'h100;
        memory_rdata = 32'h80ff_7f01;
        store_data = 32'h0000_00a5;

        // Exercise byte load extraction and SB lane steering at every lane.
        for (offset = 0; offset < 4; offset = offset + 1) begin
            effective_addr = 32'h100 + offset;
            funct3 = 3'b100; // LBU
            #1;
            expected = (memory_rdata >> (offset * 8)) & 32'hff;
            if (load_data !== expected) $fatal(1, "LBU lane %0d mismatch", offset);

            funct3 = 3'b000; // SB
            #1;
            if (memory_wstrb !== (4'b0001 << offset))
                $fatal(1, "SB strobe lane %0d mismatch", offset);
            if (memory_wdata !== (store_data << (offset * 8)))
                $fatal(1, "SB data lane %0d mismatch", offset);
            if (memory_addr !== effective_addr) $fatal(1, "effective address changed");
        end

        // Signed/unsigned halfword extraction, both supported aligned lanes.
        effective_addr = 32'h100;
        funct3 = 3'b001; #1;
        if (load_data !== 32'h0000_7f01) $fatal(1, "LH positive sign extension failed");
        if (memory_wstrb !== 4'b0011) $fatal(1, "SH low-lane strobe failed");
        effective_addr = 32'h102;
        funct3 = 3'b001; #1;
        if (load_data !== 32'hffff_80ff) $fatal(1, "LH negative sign extension failed");
        if (memory_wstrb !== 4'b1100) $fatal(1, "SH high-lane strobe failed");
        funct3 = 3'b101; #1;
        if (load_data !== 32'h0000_80ff) $fatal(1, "LHU zero extension failed");

        // A word load/store uses the full word and all four lanes.
        effective_addr = 32'h100;
        funct3 = 3'b010; #1;
        if (load_data !== memory_rdata || memory_wstrb !== 4'b1111)
            $fatal(1, "LW/SW behavior failed");

        $display("PASS: LSU byte lanes, halfwords, words, and extension");
        $finish;
    end
endmodule
