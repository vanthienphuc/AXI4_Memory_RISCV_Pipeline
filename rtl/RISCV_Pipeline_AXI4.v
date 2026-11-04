module RISCV_Pipeline_AXI4 (
    input wire clk,
    input wire rst_n
);

wire stall_axi;
wire axi_stall_request;
wire bridge_busy, rvalid_axi, wr_done_axi, rd_err, wr_err;
wire [31:0] rdata_axi;

wire stall_load;
wire PCSel_E;

wire flush_if_id;
wire bubble_id_ex;

assign flush_if_id = PCSel_E;
assign bubble_id_ex = PCSel_E || stall_load;

wire pc_en;
assign pc_en = !stall_axi && (PCSel_E || !stall_load);

// Stage IF
wire [31:0] PC_F, PC_Plus4_F, PC_in_F, Instr_F;
wire [31:0] Target_E;

// Stage ID
wire [31:0] PC_D, PC_Plus4_D, Instr_D;
wire [31:0] rf_DataA_D, rf_DataB_D;
wire [31:0] DataA_D, DataB_D, Imm_D;
wire [4:0]  addrA_D = Instr_D[19:15];
wire [4:0]  addrB_D = Instr_D[24:20];
wire [4:0]  addrD_D = Instr_D[11:7];
wire [2:0]  funct3_D = Instr_D[14:12];
wire [2:0]  ImmSel_D;
wire [3:0]  ALUSel_D;
wire [1:0]  WBSel_D;
wire        RegWEn_D, BrUn_D, ASel_D, BSel_D, MemRW_D;
wire        Is_Branch_D, Is_Jump_D, Is_JALR_D, Is_Load_D, UsesRs1_D, UsesRs2_D;

// Stage EX
wire [31:0] PC_E, PC_Plus4_E, DataA_E, DataB_E, Imm_E;
wire [4:0]  addrA_E, addrB_E, addrD_E;
wire [2:0]  funct3_E;
wire [3:0]  ALUSel_E;
wire [1:0]  WBSel_E;
wire        RegWEn_E, BrUn_E, ASel_E, BSel_E, MemRW_E;
wire        Is_Branch_E, Is_Jump_E, Is_JALR_E, Is_Load_E;

wire [1:0]  fwdA, fwdB;
reg  [31:0] fwd_DataA_E, fwd_DataB_E;
wire [31:0] Mux_ALU_DataA_E, Mux_ALU_DataB_E;
wire [31:0] ALU_out_E;
wire        BrEq_E, BrLT_E;

// Stage MEM
wire [31:0] ALU_out_M, DataB_M, PC_Plus4_M;
wire [4:0]  addrD_M;
wire [2:0]  funct3_M;
wire [1:0]  WBSel_M;
wire        RegWEn_M, MemRW_M;
wire [31:0] DataR_M;
wire [31:0] ForwardData_M;

// Stage WB
wire [31:0] ALU_out_W, DataR_W, PC_Plus4_W, DataD_W;
wire [4:0]  addrD_W;
wire [1:0]  WBSel_W;
wire        RegWEn_W;

// IF
assign PC_Plus4_F = PC_F + 32'd4;
assign PC_in_F = PCSel_E ? Target_E : PC_Plus4_F;
wire [31:0] Addr_instr_mem = {2'b0, PC_F[31:2]};

Program_Counter PC_inst (
    .clk    (clk),
    .rst_n  (rst_n),
    .en     (pc_en),
    .PC_in  (PC_in_F),
    .PC_out (PC_F)
);

Instruction_Memory IMEM_inst (
    .addr (Addr_instr_mem),
    .inst (Instr_F)
);

// IF/ID register
IF_ID_reg IF_ID_inst (
    .clk    (clk),
    .rst_n  (rst_n),
    .stall  (stall_load || stall_axi),
    .flush  (flush_if_id),
    .PC_in  (PC_F),
    .PC_Plus4_in(PC_Plus4_F),
    .Instr_in   (Instr_F),
    .PC_D       (PC_D),
    .PC_Plus4_D (PC_Plus4_D),
    .Instr_D    (Instr_D)
);

// ID
control_unit Control_logic_inst (
    .opcode_eff (Instr_D[6:2]),
    .funct7_fif (Instr_D[30]),
    .funct3     (funct3_D),
    .ImmSel     (ImmSel_D),
    .RegWEn     (RegWEn_D),
    .BrUn       (BrUn_D),
    .ASel       (ASel_D),
    .BSel       (BSel_D),
    .ALUSel     (ALUSel_D),
    .MemRW      (MemRW_D),
    .WBSel      (WBSel_D),
    .Is_Branch  (Is_Branch_D),
    .Is_Jump    (Is_Jump_D),
    .Is_JALR    (Is_JALR_D),
    .Is_Load    (Is_Load_D),
    .UsesRs1    (UsesRs1_D),
    .UsesRs2    (UsesRs2_D)
);

Immediate_Generator Imm_Gen_inst (
    .Inst       (Instr_D),
    .ImmSel     (ImmSel_D),
    .Imm        (Imm_D)
);

RegisterFile Reg_inst (
    .clk        (clk),
    .reset      (rst_n),
    .addrA      (addrA_D),
    .addrB      (addrB_D),
    .addrD      (addrD_W),
    .dataD      (DataD_W),
    .reg_write  (RegWEn_W),
    .dataA      (rf_DataA_D),
    .dataB      (rf_DataB_D)
);

assign DataA_D = (RegWEn_W && addrD_W != 5'b0 && addrD_W == addrA_D) ? DataD_W : rf_DataA_D;
assign DataB_D = (RegWEn_W && addrD_W != 5'b0 && addrD_W == addrB_D) ? DataD_W : rf_DataB_D;

hazard_detect Hazard_inst (
    .Is_Load_E  (Is_Load_E),
    .addrD_E    (addrD_E),
    .addrA_D    (addrA_D),
    .addrB_D    (addrB_D),
    .UsesRs1_D  (UsesRs1_D),
    .UsesRs2_D  (UsesRs2_D),
    .bridge_busy (axi_stall_request),
    .stall_load (stall_load),
    .stall_axi (stall_axi)
);

// ID/EX Register
ID_EX_reg ID_EX_inst (
    .clk        (clk),
    .rst_n      (rst_n),
    .bubble     (bubble_id_ex),
    .stall      (stall_axi),
    .PC_D       (PC_D),
    .PC_Plus4_D (PC_Plus4_D),
    .DataA_D    (DataA_D),
    .DataB_D    (DataB_D),
    .Imm_D      (Imm_D),
    .addrA_D    (addrA_D),
    .addrB_D    (addrB_D),
    .addrD_D    (addrD_D),
    .funct3_D   (funct3_D),
    .ALUSel_D   (ALUSel_D),
    .WBSel_D    (WBSel_D),
    .RegWEn_D   (RegWEn_D),
    .BrUn_D     (BrUn_D),
    .ASel_D     (ASel_D),
    .BSel_D     (BSel_D),
    .MemRW_D    (MemRW_D),
    .Is_Branch_D(Is_Branch_D),
    .Is_Jump_D  (Is_Jump_D),
    .Is_JALR_D  (Is_JALR_D),
    .Is_Load_D  (Is_Load_D),
    // ports out
    .PC_E       (PC_E),
    .PC_Plus4_E (PC_Plus4_E),
    .DataA_E    (DataA_E),
    .DataB_E    (DataB_E),
    .Imm_E      (Imm_E),
    .addrA_E    (addrA_E),
    .addrB_E    (addrB_E),
    .addrD_E    (addrD_E),
    .funct3_E   (funct3_E),
    .ALUSel_E   (ALUSel_E),
    .WBSel_E    (WBSel_E),
    .RegWEn_E   (RegWEn_E),
    .BrUn_E     (BrUn_E),
    .ASel_E     (ASel_E),
    .BSel_E     (BSel_E),
    .MemRW_E    (MemRW_E),
    .Is_Branch_E(Is_Branch_E),
    .Is_Jump_E  (Is_Jump_E),
    .Is_JALR_E  (Is_JALR_E),
    .Is_Load_E  (Is_Load_E)
);

// EX
forward_unit Forward_inst (
    .addrA_E    (addrA_E),
    .addrB_E    (addrB_E),
    .addrD_M    (addrD_M),
    .addrD_W    (addrD_W),
    .RegWEn_M   (RegWEn_M),
    .RegWEn_W   (RegWEn_W),
    .fwdA       (fwdA),
    .fwdB       (fwdB)
);

assign ForwardData_M = (WBSel_M == 2'b10) ? PC_Plus4_M : ALU_out_M;

always @(*) begin
    case (fwdA)
        2'b10:   fwd_DataA_E = ForwardData_M;
        2'b01:   fwd_DataA_E = DataD_W;
        default: fwd_DataA_E = DataA_E;
    endcase

    case (fwdB)
        2'b10:   fwd_DataB_E = ForwardData_M;
        2'b01:   fwd_DataB_E = DataD_W;
        default: fwd_DataB_E = DataB_E;
    endcase
end

assign Mux_ALU_DataA_E = ASel_E ? PC_E : fwd_DataA_E;
assign Mux_ALU_DataB_E = BSel_E ? Imm_E : fwd_DataB_E;

ALU ALU_mod_inst (
    .operand_0 (Mux_ALU_DataA_E),
    .operand_1 (Mux_ALU_DataB_E),
    .ALU_Sel   (ALUSel_E),
    .result    (ALU_out_E)
);

Branch_Comp Branch_Comp_inst (
    .operand_0 (fwd_DataA_E),
    .operand_1 (fwd_DataB_E),
    .BrUn      (BrUn_E),
    .BrEq      (BrEq_E),
    .BrLT      (BrLT_E)
);

Branch_Resolve BranchResolve_inst (
    .Is_Branch_E (Is_Branch_E),
    .Is_Jump_E   (Is_Jump_E),
    .funct3_E    (funct3_E),
    .BrEq_E       (BrEq_E), 
    .BrLt_E      (BrLT_E),
    .PCSel_E     (PCSel_E)
);

assign Target_E = Is_JALR_E ? {ALU_out_E[31:1], 1'b0} : ALU_out_E;

// EX/MEM Register
EX_MEM_reg EX_MEM_inst (
    .clk         (clk),
    .rst_n       (rst_n),
    .stall       (stall_axi),
    .ALU_out_E   (ALU_out_E),
    .DataB_fwd_E (fwd_DataB_E),
    .PC_Plus4_E  (PC_Plus4_E),
    .addrD_E     (addrD_E),
    .WBSel_E     (WBSel_E),
    .RegWEn_E    (RegWEn_E),
    .MemRW_E     (MemRW_E),
    .funct3_E    (funct3_E),
    // ports out
    .ALU_out_M   (ALU_out_M),
    .DataB_M     (DataB_M),
    .PC_Plus4_M  (PC_Plus4_M),
    .addrD_M     (addrD_M),
    .WBSel_M     (WBSel_M),
    .RegWEn_M    (RegWEn_M),
    .MemRW_M     (MemRW_M),
    .funct3_M    (funct3_M)
);

// AXI4
wire Is_Load_M = (WBSel_M == 2'b00) && RegWEn_M;

reg axi_active;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
        axi_active <= 1'b0;
    else if (rvalid_axi || wr_done_axi) 
        axi_active <= 1'b0; // Reset the flag when the Master signals completion
    else if ((Is_Load_M || MemRW_M) && !bridge_busy) 
        axi_active <= 1'b1; // Set the flag when starting to send the command
end

wire req_read  = Is_Load_M && !axi_active && !bridge_busy;
wire req_write = MemRW_M && !axi_active && !bridge_busy;

assign axi_stall_request = (Is_Load_M && !rvalid_axi) || (MemRW_M && !wr_done_axi);

reg [3:0]  wstrb_reg;
reg [31:0] wdata_reg;

always @(*) begin
    wstrb_reg = 4'b0000;
    wdata_reg = DataB_M;
    if (MemRW_M) begin
        case (funct3_M)
            3'b000: begin // Store Byte
                wstrb_reg = 4'b0001 << ALU_out_M[1:0];
                wdata_reg = {4{DataB_M[7:0]}};
            end
            3'b001: begin // Store Halfword
                wstrb_reg = ALU_out_M[1] ? 4'b1100 : 4'b0011;
                wdata_reg = {2{DataB_M[15:0]}};
            end
            3'b010: begin // Store Word
                wstrb_reg = 4'b1111;
                wdata_reg = DataB_M;
            end
            default: wstrb_reg = 4'b0000;
        endcase
    end
end

axi4_subsystem u_axi_subsystem (
        .clk(clk),
        .rst_n(rst_n),
        .rd_req(req_read),
        .wr_req(req_write),
        .addr(ALU_out_M),
        .wdata(wdata_reg),
        .wstrb(wstrb_reg),
        .bridge_busy(bridge_busy),
        .rvalid(rvalid_axi),
        .rdata(rdata_axi),
        .rd_err(rd_err),
        .wr_done(wr_done_axi),
        .wr_err(wr_err)
);

wire [7:0]  selected_byte = (ALU_out_M[1:0] == 2'b00) ? rdata_axi[7:0] :
                            (ALU_out_M[1:0] == 2'b01) ? rdata_axi[15:8] :
                            (ALU_out_M[1:0] == 2'b10) ? rdata_axi[23:16] : rdata_axi[31:24];
wire [15:0] selected_half = ALU_out_M[1] ? rdata_axi[31:16] : rdata_axi[15:0];

reg [31:0] DataR_M_reg;
always @(*) begin
    case (funct3_M)
        3'b000: DataR_M_reg = {{24{selected_byte[7]}}, selected_byte};
        3'b001: DataR_M_reg = {{16{selected_half[15]}}, selected_half};
        3'b010: DataR_M_reg = rdata_axi;
        3'b100: DataR_M_reg = {24'b0, selected_byte};
        3'b101: DataR_M_reg = {16'b0, selected_half};
        default: DataR_M_reg = 32'b0;
    endcase
end
assign DataR_M = DataR_M_reg;

// MEM/WB Register
MEM_WB_reg MEM_WB_inst (
    .clk         (clk),
    .rst_n       (rst_n),
    .stall       (stall_axi),
    .ALU_out_M   (ALU_out_M),
    .DataR_M     (DataR_M),
    .PC_Plus4_M  (PC_Plus4_M),
    .addrD_M     (addrD_M),
    .WBSel_M     (WBSel_M),
    .RegWEn_M    (RegWEn_M),
    // ports out
    .ALU_out_W   (ALU_out_W),
    .DataR_W     (DataR_W),
    .PC_Plus4_W  (PC_Plus4_W),
    .addrD_W     (addrD_W),
    .WBSel_W     (WBSel_W),
    .RegWEn_W    (RegWEn_W)
);

// WB
assign DataD_W = (WBSel_W == 2'b00) ? DataR_W :
                 (WBSel_W == 2'b01) ? ALU_out_W :
                 PC_Plus4_W;

endmodule


