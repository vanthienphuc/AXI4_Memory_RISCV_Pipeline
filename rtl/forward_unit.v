// forward_unit.v
module forward_unit(
    input  [4:0] addrA_E, addrB_E,    // rs1/rs2 of the instruction now in EX
    input  [4:0] addrD_M, addrD_W,    // rd of the instructions in EX_MEM / MEM_WB
    input        RegWEn_M, RegWEn_W,
    output reg [1:0] fwdA, fwdB       // 00=no fwd, 10=from EX_MEM, 01=from MEM_WB
);

    always @(*) begin
        fwdA = 2'b00;
        if (RegWEn_M && addrD_M != 5'b0 && addrD_M == addrA_E) fwdA = 2'b10;
        else if (RegWEn_W && addrD_W != 5'b0 && addrD_W == addrA_E) fwdA = 2'b01;

        fwdB = 2'b00;
        if (RegWEn_M && addrD_M != 5'b0 && addrD_M == addrB_E) fwdB = 2'b10;
        else if (RegWEn_W && addrD_W != 5'b0 && addrD_W == addrB_E) fwdB = 2'b01;
    end

endmodule