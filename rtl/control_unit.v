module control_unit (
    input  wire [4:0] opcode_eff,
    input  wire       funct7_fif,
    input  wire [2:0] funct3,
    /*input wire        BrEq,
    input wire        BrLT,
    output wire       PCsel,*/
    output wire [2:0] ImmSel,
    output wire       RegWEn,
    output wire       BrUn,
    output wire       ASel,
    output wire       BSel,
    output wire [3:0] ALUSel,
    output wire       MemRW,
    output wire [1:0] WBSel,

    output wire       Is_Branch,
    output wire       Is_Jump,
    output wire       Is_JALR,
    output wire       Is_Load,
    output wire       UsesRs1,
    output wire       UsesRs2
);

    wire arithmetic;
    wire i_type;
    wire pass_b;

    main_decoder main_decoder_inst (
        .opcode_eff (opcode_eff),
        .funct3     (funct3),
        /*.BrEq       (BrEq),
        .BrLT       (BrLT),
        .PCsel      (PCsel),*/
        .ImmSel     (ImmSel),
        .RegWEn     (RegWEn),
        .BrUn       (BrUn),
        .ASel       (ASel),
        .BSel       (BSel),
        .MemRW      (MemRW),
        .WBSel      (WBSel),
        .arithmetic (arithmetic),
        .i_type     (i_type),
        .pass_b     (pass_b),

        .Is_Branch  (Is_Branch),
        .Is_Jump    (Is_Jump)
    );

    ALU_decoder ALU_decoder_inst (
        .arithmetic (arithmetic),
        .pass_b     (pass_b),
        .funct3     (funct3),
        .funct7_fif (funct7_fif),
        .i_type     (i_type),
        .ALUSel     (ALUSel)
    );

endmodule


