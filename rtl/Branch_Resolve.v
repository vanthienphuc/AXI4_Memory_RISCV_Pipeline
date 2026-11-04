// Branch_Resolve.v – replaces the B-Type PCSel case in main_decoder
module Branch_Resolve(
    input           Is_Branch_E, Is_Jump_E, // class flags from ID/EX
    input   [2:0]   funct3_E,
    input           BrEq_E, BrLt_E,         // from Branch_Comp, now running in EX
    output reg      PCSel_E
);

    always @(*) begin
        if (Is_Jump_E) begin
            PCSel_E = 1'b1;                 // JAL / JALR: always taken
        end else if (Is_Branch_E) begin
            if (funct3_E[2]) begin          // BLT/BGE/BLTU/BGEU
                PCSel_E = BrLt_E ? ~funct3_E[0] : funct3_E[0];
            end else begin                  // beq / bne
                PCSel_E = BrEq_E ? ~funct3_E[0] : funct3_E[0];
            end
        end else begin
            PCSel_E = 1'b0;
        end
    end

endmodule



