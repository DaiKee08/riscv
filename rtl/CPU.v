`include "ALU.v"
`include "RegFile.v"
`include "ImmediateExtractor.v"
`include "Encoders.v"
`include "BranchPredictor.v"

module CPU (
    input [63:0] RAM_READ_DATA,
    input [31:0] INSTRUCTION,
    input CLK,

    output [9:0] RAM_ADDR,
    output reg [63:0] RAM_WRITE_DATA,
    output RAM_WRITE_ENABLE,
    output [9:0] INSTRUCTION_ADDR
);

    // ============================================================
    // CONSTANTS
    // ============================================================

    integer OP_R_TYPE           = 7'h33;
    integer OP_R_TYPE_64        = 7'h3B;
    integer OP_I_TYPE_LOAD      = 7'h03;
    integer OP_I_TYPE_OTHER     = 7'h13;
    integer OP_I_TYPE_64        = 7'h1B;
    integer OP_I_TYPE_JUMP      = 7'h6F;
    integer OP_S_TYPE           = 7'h23;
    integer OP_B_TYPE           = 7'h63;
    integer OP_U_TYPE_LOAD      = 7'h37;
    integer OP_U_TYPE_JUMP      = 7'h67;
    integer OP_U_TYPE_AUIPC     = 7'h17;

    integer TYPE_REGISTER       = 0;
    integer TYPE_LOAD           = 1;
    integer TYPE_STORE          = 2;
    integer TYPE_IMMEDIATE      = 3;
    integer TYPE_UPPERIMMEDIATE = 4;
    integer TYPE_BRANCH         = 5;

    integer DECODE      = 0;
    integer EXECUTE     = 1;
    integer MEMORY      = 2;
    integer WRITEBACK   = 3;

    // ============================================================
    // PIPELINE REGISTERS
    // ============================================================

    reg [9:0] PC = 0;

    reg [9:0] PC_DECODE_2 = 0;
    reg [31:0] INSTRUCTION_DECODE_2 = 0;

    reg [9:0] PC_EXECUTE_3 = 0;
    reg [31:0] INSTRUCTION_EXECUTE_3 = 0;

    reg [9:0] PC_MEMORY_4 = 0;
    reg [31:0] INSTRUCTION_MEMORY_4 = 0;
    reg [63:0] ALU_OUT_MEMORY_4 = 0;

    reg [31:0] INSTRUCTION_WRITEBACK_5 = 0;
    reg [63:0] REG_WRITE_DATA_WRITEBACK_5 = 0;
    reg [63:0] RAM_READ_DATA_WRITEBACK_5 = 0;

    reg [4:0] R1_PIPELINE[3:0];
    reg [4:0] R2_PIPELINE[3:0];
    reg [4:0] RD_PIPELINE[3:0];
    reg [2:0] TYPE_PIPELINE[3:0];

    // ============================================================
    // BRANCH PREDICTION PIPELINE REGISTERS
    // ============================================================

    reg PRED_TAKEN_DECODE_2 = 1'b0;
    reg [9:0] PRED_PC_DECODE_2 = 10'd0;

    reg PRED_TAKEN_EXECUTE_3 = 1'b0;
    reg [9:0] PRED_PC_EXECUTE_3 = 10'd0;

    // ============================================================
    // INITIALIZATION
    // ============================================================

    integer init_i;

    initial begin
        PC = 10'd0;

        PC_DECODE_2 = 10'd0;
        INSTRUCTION_DECODE_2 = 32'h00000013;

        PC_EXECUTE_3 = 10'd0;
        INSTRUCTION_EXECUTE_3 = 32'h00000013;

        PC_MEMORY_4 = 10'd0;
        INSTRUCTION_MEMORY_4 = 32'h00000013;
        ALU_OUT_MEMORY_4 = 64'd0;

        INSTRUCTION_WRITEBACK_5 = 32'h00000013;
        REG_WRITE_DATA_WRITEBACK_5 = 64'd0;
        RAM_READ_DATA_WRITEBACK_5 = 64'd0;
        RAM_WRITE_DATA = 64'd0;

        PRED_TAKEN_DECODE_2 = 1'b0;
        PRED_PC_DECODE_2 = 10'd0;
        PRED_TAKEN_EXECUTE_3 = 1'b0;
        PRED_PC_EXECUTE_3 = 10'd0;

        for (init_i = 0; init_i < 4; init_i = init_i + 1) begin
            R1_PIPELINE[init_i] = 5'd0;
            R2_PIPELINE[init_i] = 5'd0;
            RD_PIPELINE[init_i] = 5'd0;
            TYPE_PIPELINE[init_i] = TYPE_IMMEDIATE;
        end
    end

    // ============================================================
    // FORWARD DECLARATIONS
    // ============================================================

   // Forwarding / hazard wires
wire DATA_DEPENDENCY_HAZARD_R1;
wire DATA_DEPENDENCY_HAZARD_R2;
wire DATA_DEPENDENCY_HAZARD_R1_WRITEBACK;
wire DATA_DEPENDENCY_HAZARD_R2_WRITEBACK;

// RegFile read data wires
wire signed [63:0] R1_DATA_EXECUTE_3;
wire signed [63:0] R2_DATA_EXECUTE_3;

// Forwarded operand wires
wire signed [63:0] R1_DATA;
wire signed [63:0] R2_DATA;
wire [63:0] R1_DATA_UNSIGNED;
wire [63:0] R2_DATA_UNSIGNED;

// ALU output wires.
// These must be declared before branch predictor logic uses ALU_OUT.
wire [63:0] ALU_OUT;
wire isALUEqual;

// Writeback selection
wire [1:0] REG_WRITEBACK_SELECTION;

    // ============================================================
    // BASIC DECODE WIRES
    // ============================================================

    wire [6:0] OPCODE   = INSTRUCTION_EXECUTE_3[6:0];
    wire [4:0] RD       = INSTRUCTION_WRITEBACK_5[11:7];
    wire [2:0] FUNCT3   = INSTRUCTION_EXECUTE_3[14:12];
    wire [4:0] R1       = INSTRUCTION_EXECUTE_3[19:15];
    wire [4:0] R2       = INSTRUCTION_EXECUTE_3[24:20];
    wire [6:0] FUNCT7   = INSTRUCTION_EXECUTE_3[31:25];

    wire R_TYPE         = OPCODE == OP_R_TYPE;
    wire R_TYPE_64      = OPCODE == OP_R_TYPE_64;
    wire I_TYPE_LOAD    = OPCODE == OP_I_TYPE_LOAD;
    wire I_TYPE_OTHER   = OPCODE == OP_I_TYPE_OTHER;
    wire I_TYPE_64      = OPCODE == OP_I_TYPE_64;
    wire I_TYPE_JUMP    = OPCODE == OP_I_TYPE_JUMP;
    wire I_TYPE         = I_TYPE_JUMP || I_TYPE_LOAD || I_TYPE_OTHER || I_TYPE_64;
    wire S_TYPE         = OPCODE == OP_S_TYPE;
    wire B_TYPE         = OPCODE == OP_B_TYPE;
    wire U_TYPE_LOAD    = OPCODE == OP_U_TYPE_LOAD;
    wire U_TYPE_JUMP    = OPCODE == OP_U_TYPE_JUMP;
    wire U_TYPE_AUIPC   = OPCODE == OP_U_TYPE_AUIPC;
    wire U_TYPE         = U_TYPE_JUMP || U_TYPE_LOAD || U_TYPE_AUIPC;

    // ============================================================
    // INSTRUCTION DECODING
    // ============================================================

    wire R_add      = R_TYPE && FUNCT3 == 3'h0 && FUNCT7 == 7'h00;
    wire R_sub      = R_TYPE && FUNCT3 == 3'h0 && FUNCT7 == 7'h20;
    wire R_sll      = R_TYPE && FUNCT3 == 3'h1 && FUNCT7 == 7'h00;
    wire R_slt      = R_TYPE && FUNCT3 == 3'h2 && FUNCT7 == 7'h00;
    wire R_sltu     = R_TYPE && FUNCT3 == 3'h3 && FUNCT7 == 7'h00;
    wire R_xor      = R_TYPE && FUNCT3 == 3'h4 && FUNCT7 == 7'h00;
    wire R_srl      = R_TYPE && FUNCT3 == 3'h5 && FUNCT7 == 7'h00;
    wire R_sra      = R_TYPE && FUNCT3 == 3'h5 && FUNCT7 == 7'h20;
    wire R_or       = R_TYPE && FUNCT3 == 3'h6 && FUNCT7 == 7'h00;
    wire R_and      = R_TYPE && FUNCT3 == 3'h7 && FUNCT7 == 7'h00;

    wire R_mul      = R_TYPE && FUNCT3 == 3'h0 && FUNCT7 == 7'h01;
    wire R_mulh     = R_TYPE && FUNCT3 == 3'h1 && FUNCT7 == 7'h01;
    wire R_rem      = R_TYPE && FUNCT3 == 3'h6 && FUNCT7 == 7'h01;
    wire R_div      = R_TYPE && FUNCT3 == 3'h4 && FUNCT7 == 7'h01;

    wire R_addw     = R_TYPE_64 && FUNCT3 == 3'h0 && FUNCT7 == 7'h00;
    wire R_subw     = R_TYPE_64 && FUNCT3 == 3'h0 && FUNCT7 == 7'h20;
    wire R_sllw     = R_TYPE_64 && FUNCT3 == 3'h1 && FUNCT7 == 7'h00;
    wire R_srlw     = R_TYPE_64 && FUNCT3 == 3'h5 && FUNCT7 == 7'h00;
    wire R_sraw     = R_TYPE_64 && FUNCT3 == 3'h5 && FUNCT7 == 7'h20;

    wire R_mulw     = R_TYPE_64 && FUNCT3 == 3'h0 && FUNCT7 == 7'h01;
    wire R_divw     = R_TYPE_64 && FUNCT3 == 3'h4 && FUNCT7 == 7'h01;
    wire R_remw     = R_TYPE_64 && FUNCT3 == 3'h6 && FUNCT7 == 7'h01;

    wire I_addi     = I_TYPE_OTHER && FUNCT3 == 3'h0;
    wire I_slli     = I_TYPE_OTHER && FUNCT3 == 3'h1 && FUNCT7 == 7'h00;
    wire I_slti     = I_TYPE_OTHER && FUNCT3 == 3'h2;
    wire I_sltiu    = I_TYPE_OTHER && FUNCT3 == 3'h3;
    wire I_xori     = I_TYPE_OTHER && FUNCT3 == 3'h4;
    wire I_srli     = I_TYPE_OTHER && FUNCT3 == 3'h5 && FUNCT7 == 7'h00;
    wire I_srai     = I_TYPE_OTHER && FUNCT3 == 3'h5 && FUNCT7 == 7'h10;
    wire I_ori      = I_TYPE_OTHER && FUNCT3 == 3'h6;
    wire I_andi     = I_TYPE_OTHER && FUNCT3 == 3'h7;

    wire I_addiw    = I_TYPE_64 && FUNCT3 == 3'h0;
    wire I_slliw    = I_TYPE_64 && FUNCT3 == 3'h1 && FUNCT7 == 7'h00;
    wire I_srliw    = I_TYPE_64 && FUNCT3 == 3'h5 && FUNCT7 == 7'h00;
    wire I_sraiw    = I_TYPE_64 && FUNCT3 == 3'h5 && FUNCT7 == 7'h20;

    wire I_lb       = INSTRUCTION_MEMORY_4[6:0] == OP_I_TYPE_LOAD && INSTRUCTION_MEMORY_4[14:12] == 3'h0;
    wire I_lh       = INSTRUCTION_MEMORY_4[6:0] == OP_I_TYPE_LOAD && INSTRUCTION_MEMORY_4[14:12] == 3'h1;
    wire I_lw       = INSTRUCTION_MEMORY_4[6:0] == OP_I_TYPE_LOAD && INSTRUCTION_MEMORY_4[14:12] == 3'h2;
    wire I_ld       = INSTRUCTION_MEMORY_4[6:0] == OP_I_TYPE_LOAD && INSTRUCTION_MEMORY_4[14:12] == 3'h3;

    wire I_jalr     = I_TYPE_JUMP;

    wire U_lui      = U_TYPE_LOAD;
    wire U_auipc    = U_TYPE_AUIPC;
    wire U_jal      = U_TYPE_JUMP;

    wire S_sb       = INSTRUCTION_MEMORY_4[6:0] == OP_S_TYPE && INSTRUCTION_MEMORY_4[14:12] == 3'h0;
    wire S_sh       = INSTRUCTION_MEMORY_4[6:0] == OP_S_TYPE && INSTRUCTION_MEMORY_4[14:12] == 3'h1;
    wire S_sw       = INSTRUCTION_MEMORY_4[6:0] == OP_S_TYPE && INSTRUCTION_MEMORY_4[14:12] == 3'h2;
    wire S_sd       = INSTRUCTION_MEMORY_4[6:0] == OP_S_TYPE && INSTRUCTION_MEMORY_4[14:12] == 3'h3;

    wire B_beq      = B_TYPE && FUNCT3 == 0;
    wire B_bne      = B_TYPE && FUNCT3 == 1;
    wire B_blt      = B_TYPE && FUNCT3 == 4;
    wire B_bge      = B_TYPE && FUNCT3 == 5;
    wire B_bltu     = B_TYPE && FUNCT3 == 6;
    wire B_bgeu     = B_TYPE && FUNCT3 == 7;

    // ============================================================
    // FETCH-STAGE BRANCH TARGET
    // ============================================================

    wire FETCH_IS_BRANCH;
    wire signed [63:0] FETCH_BRANCH_IMM;
    wire [9:0] FETCH_BRANCH_TARGET;

    assign FETCH_IS_BRANCH = INSTRUCTION[6:0] == OP_B_TYPE[6:0];

    assign FETCH_BRANCH_IMM = {
        {51{INSTRUCTION[31]}},
        INSTRUCTION[31],
        INSTRUCTION[7],
        INSTRUCTION[30:25],
        INSTRUCTION[11:8],
        1'b0
    };

    assign FETCH_BRANCH_TARGET = PC + FETCH_BRANCH_IMM[9:0];

    // ============================================================
    // BRANCH PREDICTOR
    // ============================================================

    wire bp_predict_taken;
    wire bp_update_en;
    wire bp_actual_taken;

    BranchPredictor branch_predictor (
        .CLK(CLK),

        .QUERY_PC(PC),
        .PREDICT_TAKEN(bp_predict_taken),

        .UPDATE_EN(bp_update_en),
        .UPDATE_PC(PC_EXECUTE_3),
        .ACTUAL_TAKEN(bp_actual_taken)
    );

    wire ACTUAL_IS_BRANCH;

    assign ACTUAL_IS_BRANCH = INSTRUCTION_EXECUTE_3[6:0] == OP_B_TYPE[6:0];

    assign bp_actual_taken =
                        (B_beq  && R1_DATA == R2_DATA)
                    ||  (B_bne  && R1_DATA != R2_DATA)
                    ||  (B_blt  && R1_DATA <  R2_DATA)
                    ||  (B_bge  && R1_DATA >= R2_DATA)
                    ||  (B_bltu && R1_DATA_UNSIGNED <  R2_DATA_UNSIGNED)
                    ||  (B_bgeu && R1_DATA_UNSIGNED >= R2_DATA_UNSIGNED);

    assign bp_update_en = ACTUAL_IS_BRANCH;

    wire [9:0] ACTUAL_BRANCH_TARGET;
    wire [9:0] CORRECT_NEXT_PC;
    wire BRANCH_MISPREDICT;

    assign ACTUAL_BRANCH_TARGET = ALU_OUT[9:0];

    assign CORRECT_NEXT_PC =
        bp_actual_taken ? ACTUAL_BRANCH_TARGET : PC_EXECUTE_3 + 10'd4;

    assign BRANCH_MISPREDICT =
        ACTUAL_IS_BRANCH &&
        (
            (PRED_TAKEN_EXECUTE_3 != bp_actual_taken) ||
            (bp_actual_taken && PRED_PC_EXECUTE_3 != ACTUAL_BRANCH_TARGET)
        );

    // ============================================================
    // PIPELINE HAZARD LOGIC
    // ============================================================

    assign DATA_DEPENDENCY_HAZARD_R1 =
                        R1_PIPELINE[EXECUTE] != 0
                    &&  TYPE_PIPELINE[EXECUTE] != TYPE_UPPERIMMEDIATE
                    &&  R1_PIPELINE[EXECUTE] == RD_PIPELINE[MEMORY];

    assign DATA_DEPENDENCY_HAZARD_R2 =
                        R2_PIPELINE[EXECUTE] != 0
                    &&  TYPE_PIPELINE[EXECUTE] != TYPE_UPPERIMMEDIATE
                    &&  TYPE_PIPELINE[EXECUTE] != TYPE_IMMEDIATE
                    &&  R2_PIPELINE[EXECUTE] == RD_PIPELINE[MEMORY];

    assign DATA_DEPENDENCY_HAZARD_R1_WRITEBACK =
                        R1_PIPELINE[EXECUTE] != 0
                    &&  TYPE_PIPELINE[EXECUTE] != TYPE_UPPERIMMEDIATE
                    &&  R1_PIPELINE[EXECUTE] == RD_PIPELINE[WRITEBACK];

    assign DATA_DEPENDENCY_HAZARD_R2_WRITEBACK =
                        R2_PIPELINE[EXECUTE] != 0
                    &&  TYPE_PIPELINE[EXECUTE] != TYPE_UPPERIMMEDIATE
                    &&  TYPE_PIPELINE[EXECUTE] != TYPE_IMMEDIATE
                    &&  R2_PIPELINE[EXECUTE] == RD_PIPELINE[WRITEBACK];

    wire LOAD_STALL =
                        TYPE_PIPELINE[EXECUTE] == TYPE_LOAD
                    &&  (
                            (
                                TYPE_PIPELINE[DECODE] != TYPE_UPPERIMMEDIATE
                            &&  TYPE_PIPELINE[DECODE] != TYPE_IMMEDIATE
                            &&  (
                                    (R1_PIPELINE[DECODE] != 0 && R1_PIPELINE[DECODE] == RD_PIPELINE[EXECUTE])
                                ||  (R2_PIPELINE[DECODE] != 0 && R2_PIPELINE[DECODE] == RD_PIPELINE[EXECUTE])
                                )
                            )
                        ||  (
                                TYPE_PIPELINE[DECODE] == TYPE_IMMEDIATE
                            &&  R1_PIPELINE[DECODE] != 0
                            &&  R1_PIPELINE[DECODE] == RD_PIPELINE[EXECUTE]
                            )
                        );

    wire CONTROL_HAZARD_STALL = 1'b0;

    // ============================================================
    // DATA FORWARDING
    // ============================================================

   assign R1_DATA =
                                    DATA_DEPENDENCY_HAZARD_R1 ? ALU_OUT_MEMORY_4 :
                                    DATA_DEPENDENCY_HAZARD_R1_WRITEBACK ?
                                        (REG_WRITEBACK_SELECTION == 3 ? RAM_READ_DATA_WRITEBACK_5 : REG_WRITE_DATA_WRITEBACK_5)
                                        : R1_DATA_EXECUTE_3;

assign R2_DATA =
                                    DATA_DEPENDENCY_HAZARD_R2 ? ALU_OUT_MEMORY_4 :
                                    DATA_DEPENDENCY_HAZARD_R2_WRITEBACK ?
                                        (REG_WRITEBACK_SELECTION == 3 ? RAM_READ_DATA_WRITEBACK_5 : REG_WRITE_DATA_WRITEBACK_5)
                                        : R2_DATA_EXECUTE_3;

assign R1_DATA_UNSIGNED = R1_DATA;
assign R2_DATA_UNSIGNED = R2_DATA;

    wire PC_ALU_SEL =
                        (B_beq  && R1_DATA == R2_DATA)
                    ||  (B_bne  && R1_DATA != R2_DATA)
                    ||  (B_blt  && R1_DATA <  R2_DATA)
                    ||  (B_bge  && R1_DATA >= R2_DATA)
                    ||  (B_bltu && R1_DATA_UNSIGNED <  R2_DATA_UNSIGNED)
                    ||  (B_bgeu && R1_DATA_UNSIGNED >= R2_DATA_UNSIGNED)
                    ||  I_jalr
                    ||  U_jal;

    // ============================================================
    // RAM INTERFACE
    // ============================================================

    assign RAM_WRITE_ENABLE = INSTRUCTION_MEMORY_4[6:0] == OP_S_TYPE;
    assign RAM_ADDR = ALU_OUT_MEMORY_4[9:0];

    // ============================================================
    // IMMEDIATE EXTRACTOR
    // ============================================================

    wire [63:0] IMMEDIATE_VALUE;
    wire [2:0] IMMEDIATE_SELECTION;
    wire [7:0] immediateSelectionInputs;

    assign immediateSelectionInputs[0] = 0;
    assign immediateSelectionInputs[1] = I_TYPE;
    assign immediateSelectionInputs[2] = U_TYPE_LOAD || U_TYPE_AUIPC;
    assign immediateSelectionInputs[3] = S_TYPE;
    assign immediateSelectionInputs[4] = B_TYPE;
    assign immediateSelectionInputs[5] = U_TYPE_JUMP;
    assign immediateSelectionInputs[6] = 0;
    assign immediateSelectionInputs[7] = 0;

    Encoder_8 immediateSelectionEncoder(
        immediateSelectionInputs,
        IMMEDIATE_SELECTION
    );

    ImmediateExtractor immediateExtractor(
        INSTRUCTION_EXECUTE_3,
        IMMEDIATE_SELECTION,
        IMMEDIATE_VALUE
    );

    // ============================================================
    // ALU OP SELECTION
    // ============================================================

    wire [15:0] aluOpEncoderInputs;
    wire [3:0] ALU_OP;

    assign aluOpEncoderInputs[0]  = R_add || R_addw || I_addi || I_addiw;
    assign aluOpEncoderInputs[1]  = R_sub || R_subw;
    assign aluOpEncoderInputs[2]  = R_and || I_andi;
    assign aluOpEncoderInputs[3]  = R_or || I_ori;
    assign aluOpEncoderInputs[4]  = R_xor || I_xori;
    assign aluOpEncoderInputs[5]  = R_sll || R_sllw || I_slli || I_slliw;
    assign aluOpEncoderInputs[6]  = R_srl || R_srlw || I_srli || I_srliw;
    assign aluOpEncoderInputs[7]  = R_sra || R_sraw || I_srai || I_sraiw;
    assign aluOpEncoderInputs[8]  = R_mul || R_mulw;
    assign aluOpEncoderInputs[9]  = R_mulh;
    assign aluOpEncoderInputs[10] = R_div || R_divw;
    assign aluOpEncoderInputs[11] = R_rem || R_remw;
    assign aluOpEncoderInputs[12] = R_slt || I_slti;
    assign aluOpEncoderInputs[13] = R_sltu || I_sltiu;
    assign aluOpEncoderInputs[14] = 0;
    assign aluOpEncoderInputs[15] = 0;

    Encoder_16 aluOpEncoder(
        aluOpEncoderInputs,
        ALU_OP
    );

    // ============================================================
    // ALU INPUT SELECTION
    // ============================================================

    wire [3:0] aluX1SelectionInputs;
    wire [3:0] aluX2SelectionInputs;
    wire [1:0] ALU_X1_SEL;
    wire [1:0] ALU_X2_SEL;

    assign aluX1SelectionInputs[0] = 1;
    assign aluX1SelectionInputs[1] = B_TYPE || U_TYPE_JUMP || U_TYPE_AUIPC || I_TYPE_JUMP;
    assign aluX1SelectionInputs[2] = U_TYPE_LOAD;
    assign aluX1SelectionInputs[3] = 0;

    assign aluX2SelectionInputs[0] = 1;
    assign aluX2SelectionInputs[1] = S_TYPE || I_TYPE || B_TYPE || U_TYPE;
    assign aluX2SelectionInputs[2] = 0;
    assign aluX2SelectionInputs[3] = 0;

    Encoder_4 aluX1SelectionEncoder(
        aluX1SelectionInputs,
        ALU_X1_SEL
    );

    Encoder_4 aluX2SelectionEncoder(
        aluX2SelectionInputs,
        ALU_X2_SEL
    );

    // ============================================================
    // ALU
    // ============================================================

reg [63:0] ALU_X1;
reg [63:0] ALU_X2;

    ALU alu(
        ALU_X1,
        ALU_X2,
        ALU_OP,
        ALU_OUT,
        isALUEqual
    );

    always @(*) begin
        case(ALU_X1_SEL)
            0: ALU_X1 = R1_DATA;
            1: ALU_X1 = PC_EXECUTE_3;
            default: ALU_X1 = 0;
        endcase

        case(ALU_X2_SEL)
            0: ALU_X2 = R2_DATA;
            1: ALU_X2 = IMMEDIATE_VALUE;
            default: ALU_X2 = 0;
        endcase
    end

    // ============================================================
    // REGFILE / WRITEBACK
    // ============================================================

    wire [6:0] OPCODE_WRITEBACK_5 = INSTRUCTION_WRITEBACK_5[6:0];

    wire WB_R_TYPE         = OPCODE_WRITEBACK_5 == OP_R_TYPE;
    wire WB_R_TYPE_64      = OPCODE_WRITEBACK_5 == OP_R_TYPE_64;
    wire WB_I_TYPE_LOAD    = OPCODE_WRITEBACK_5 == OP_I_TYPE_LOAD;
    wire WB_I_TYPE_OTHER   = OPCODE_WRITEBACK_5 == OP_I_TYPE_OTHER;
    wire WB_I_TYPE_64      = OPCODE_WRITEBACK_5 == OP_I_TYPE_64;
    wire WB_I_TYPE_JUMP    = OPCODE_WRITEBACK_5 == OP_I_TYPE_JUMP;
    wire WB_I_TYPE         = WB_I_TYPE_JUMP || WB_I_TYPE_LOAD || WB_I_TYPE_OTHER || WB_I_TYPE_64;
    wire WB_U_TYPE_LOAD    = OPCODE_WRITEBACK_5 == OP_U_TYPE_LOAD;
    wire WB_U_TYPE_JUMP    = OPCODE_WRITEBACK_5 == OP_U_TYPE_JUMP;
    wire WB_U_TYPE_AUIPC   = OPCODE_WRITEBACK_5 == OP_U_TYPE_AUIPC;
    wire WB_U_TYPE         = WB_U_TYPE_JUMP || WB_U_TYPE_LOAD || WB_U_TYPE_AUIPC;

    wire REG_WRITE_ENABLE = WB_R_TYPE || WB_R_TYPE_64 || WB_I_TYPE || WB_U_TYPE;

    wire [3:0] regWritebackSelectionInputs;

    assign regWritebackSelectionInputs[0] = 0;
    assign regWritebackSelectionInputs[1] = WB_R_TYPE || WB_R_TYPE_64 || WB_U_TYPE_LOAD || WB_I_TYPE_OTHER || WB_I_TYPE_64;
    assign regWritebackSelectionInputs[2] = WB_U_TYPE_JUMP || WB_I_TYPE_JUMP;
    assign regWritebackSelectionInputs[3] = WB_I_TYPE_LOAD;

    Encoder_4 writeBackSelectionEncoder(
        regWritebackSelectionInputs,
        REG_WRITEBACK_SELECTION
    );

    wire [63:0] REG_WRITE_DATA =
        REG_WRITEBACK_SELECTION == 3 ? RAM_READ_DATA_WRITEBACK_5 : REG_WRITE_DATA_WRITEBACK_5;

    RegFile regFile(
        R1,
        R2,
        RD,
        REG_WRITE_DATA,
        REG_WRITE_ENABLE,
        R1_DATA_EXECUTE_3,
        R2_DATA_EXECUTE_3
    );

    // ============================================================
    // PIPELINE STAGE 1: FETCH
    // ============================================================

    assign INSTRUCTION_ADDR = PC >> 2;

    always @(posedge CLK) begin
        if (BRANCH_MISPREDICT) begin
            PC <= CORRECT_NEXT_PC;
        end
        else if (PC_ALU_SEL == 1 && !ACTUAL_IS_BRANCH) begin
            PC <= ALU_OUT[9:0];
        end
        else begin
            if (LOAD_STALL == 1)
                PC <= PC;
            else if (FETCH_IS_BRANCH && bp_predict_taken)
                PC <= FETCH_BRANCH_TARGET;
            else
                PC <= PC + 4;
        end

        if (BRANCH_MISPREDICT) begin
            R1_PIPELINE[DECODE]      <= 0;
            R2_PIPELINE[DECODE]      <= 0;
            RD_PIPELINE[DECODE]      <= 0;
            TYPE_PIPELINE[DECODE]    <= TYPE_IMMEDIATE;
        end
        else begin
            R1_PIPELINE[DECODE] <= INSTRUCTION[19:15];
            R2_PIPELINE[DECODE] <= INSTRUCTION[24:20];
            RD_PIPELINE[DECODE] <= INSTRUCTION[11:7];

            if (INSTRUCTION[6:0] == OP_R_TYPE || INSTRUCTION[6:0] == OP_R_TYPE_64)
                TYPE_PIPELINE[DECODE] <= TYPE_REGISTER;
            else if (INSTRUCTION[6:0] == OP_I_TYPE_LOAD)
                TYPE_PIPELINE[DECODE] <= TYPE_LOAD;
            else if (INSTRUCTION[6:0] == OP_S_TYPE)
                TYPE_PIPELINE[DECODE] <= TYPE_STORE;
            else if (INSTRUCTION[6:0] == OP_I_TYPE_OTHER || INSTRUCTION[6:0] == OP_I_TYPE_64 || INSTRUCTION[6:0] == OP_I_TYPE_JUMP)
                TYPE_PIPELINE[DECODE] <= TYPE_IMMEDIATE;
            else if (INSTRUCTION[6:0] == OP_B_TYPE[6:0])
                TYPE_PIPELINE[DECODE] <= TYPE_BRANCH;
            else
                TYPE_PIPELINE[DECODE] <= TYPE_IMMEDIATE;
        end
    end

    // ============================================================
    // PIPELINE STAGE 2: DECODE
    // ============================================================

    always @(posedge CLK) begin
        if (BRANCH_MISPREDICT) begin
            INSTRUCTION_DECODE_2 <= 32'h00000013;
            PC_DECODE_2 <= PC_DECODE_2;
            PRED_TAKEN_DECODE_2 <= 1'b0;
            PRED_PC_DECODE_2 <= 10'd0;
        end
        else if (LOAD_STALL == 1) begin
            INSTRUCTION_DECODE_2 <= INSTRUCTION_DECODE_2;
            PC_DECODE_2 <= PC_DECODE_2;
            PRED_TAKEN_DECODE_2 <= PRED_TAKEN_DECODE_2;
            PRED_PC_DECODE_2 <= PRED_PC_DECODE_2;
        end
        else begin
            INSTRUCTION_DECODE_2 <= INSTRUCTION;
            PC_DECODE_2 <= PC;

            PRED_TAKEN_DECODE_2 <= FETCH_IS_BRANCH && bp_predict_taken;
            PRED_PC_DECODE_2 <=
                (FETCH_IS_BRANCH && bp_predict_taken) ? FETCH_BRANCH_TARGET : PC + 10'd4;
        end

        if (BRANCH_MISPREDICT) begin
            R1_PIPELINE[EXECUTE]      <= 0;
            R2_PIPELINE[EXECUTE]      <= 0;
            RD_PIPELINE[EXECUTE]      <= 0;
            TYPE_PIPELINE[EXECUTE]    <= TYPE_IMMEDIATE;
        end
        else begin
            if (INSTRUCTION_DECODE_2[6:0] == OP_R_TYPE || INSTRUCTION_DECODE_2[6:0] == OP_R_TYPE_64)
                TYPE_PIPELINE[EXECUTE] <= TYPE_REGISTER;
            else if (INSTRUCTION_DECODE_2[6:0] == OP_I_TYPE_LOAD)
                TYPE_PIPELINE[EXECUTE] <= TYPE_LOAD;
            else if (INSTRUCTION_DECODE_2[6:0] == OP_S_TYPE)
                TYPE_PIPELINE[EXECUTE] <= TYPE_STORE;
            else if (INSTRUCTION_DECODE_2[6:0] == OP_I_TYPE_OTHER || INSTRUCTION_DECODE_2[6:0] == OP_I_TYPE_64 || INSTRUCTION_DECODE_2[6:0] == OP_I_TYPE_JUMP)
                TYPE_PIPELINE[EXECUTE] <= TYPE_IMMEDIATE;
            else if (INSTRUCTION_DECODE_2[6:0] == OP_B_TYPE[6:0])
                TYPE_PIPELINE[EXECUTE] <= TYPE_BRANCH;
            else
                TYPE_PIPELINE[EXECUTE] <= TYPE_IMMEDIATE;

            R1_PIPELINE[EXECUTE] <= INSTRUCTION_DECODE_2[19:15];
            R2_PIPELINE[EXECUTE] <= INSTRUCTION_DECODE_2[24:20];
            RD_PIPELINE[EXECUTE] <= INSTRUCTION_DECODE_2[11:7];

            if (LOAD_STALL == 1) begin
                R1_PIPELINE[EXECUTE]      <= 0;
                R2_PIPELINE[EXECUTE]      <= 0;
                RD_PIPELINE[EXECUTE]      <= 0;
                TYPE_PIPELINE[EXECUTE]    <= TYPE_IMMEDIATE;
            end
        end
    end

    // ============================================================
    // PIPELINE STAGE 3: EXECUTE
    // ============================================================

    always @(posedge CLK) begin
        if (BRANCH_MISPREDICT) begin
            INSTRUCTION_EXECUTE_3 <= 32'h00000013;
            PC_EXECUTE_3 <= PC_EXECUTE_3;
            PRED_TAKEN_EXECUTE_3 <= 1'b0;
            PRED_PC_EXECUTE_3 <= 10'd0;
        end
        else if (LOAD_STALL == 1) begin
            INSTRUCTION_EXECUTE_3 <= 32'h00000013;
            PC_EXECUTE_3 <= PC_EXECUTE_3;
            PRED_TAKEN_EXECUTE_3 <= 1'b0;
            PRED_PC_EXECUTE_3 <= 10'd0;
        end
        else begin
            PC_EXECUTE_3 <= PC_DECODE_2;
            INSTRUCTION_EXECUTE_3 <= INSTRUCTION_DECODE_2;

            PRED_TAKEN_EXECUTE_3 <= PRED_TAKEN_DECODE_2;
            PRED_PC_EXECUTE_3 <= PRED_PC_DECODE_2;
        end

        if (INSTRUCTION_EXECUTE_3[6:0] == OP_R_TYPE || INSTRUCTION_EXECUTE_3[6:0] == OP_R_TYPE_64)
            TYPE_PIPELINE[MEMORY] <= TYPE_REGISTER;
        else if (INSTRUCTION_EXECUTE_3[6:0] == OP_I_TYPE_LOAD)
            TYPE_PIPELINE[MEMORY] <= TYPE_LOAD;
        else if (INSTRUCTION_EXECUTE_3[6:0] == OP_S_TYPE)
            TYPE_PIPELINE[MEMORY] <= TYPE_STORE;
        else if (INSTRUCTION_EXECUTE_3[6:0] == OP_I_TYPE_OTHER || INSTRUCTION_EXECUTE_3[6:0] == OP_I_TYPE_64 || INSTRUCTION_EXECUTE_3[6:0] == OP_I_TYPE_JUMP)
            TYPE_PIPELINE[MEMORY] <= TYPE_IMMEDIATE;
        else if (INSTRUCTION_EXECUTE_3[6:0] == OP_B_TYPE[6:0])
            TYPE_PIPELINE[MEMORY] <= TYPE_BRANCH;
        else
            TYPE_PIPELINE[MEMORY] <= TYPE_IMMEDIATE;

        R1_PIPELINE[MEMORY] <= INSTRUCTION_EXECUTE_3[19:15];
        R2_PIPELINE[MEMORY] <= INSTRUCTION_EXECUTE_3[24:20];
        RD_PIPELINE[MEMORY] <= INSTRUCTION_EXECUTE_3[11:7];
    end

    // ============================================================
    // PIPELINE STAGE 4: MEMORY
    // ============================================================

    always @(posedge CLK) begin
        INSTRUCTION_MEMORY_4 <= INSTRUCTION_EXECUTE_3;
        PC_MEMORY_4 <= PC_EXECUTE_3;

        ALU_OUT_MEMORY_4 <= ALU_OUT;
        RAM_WRITE_DATA <= R2_DATA;

        if (INSTRUCTION_MEMORY_4[6:0] == OP_R_TYPE || INSTRUCTION_MEMORY_4[6:0] == OP_R_TYPE_64)
            TYPE_PIPELINE[WRITEBACK] <= TYPE_REGISTER;
        else if (INSTRUCTION_MEMORY_4[6:0] == OP_I_TYPE_LOAD)
            TYPE_PIPELINE[WRITEBACK] <= TYPE_LOAD;
        else if (INSTRUCTION_MEMORY_4[6:0] == OP_S_TYPE)
            TYPE_PIPELINE[WRITEBACK] <= TYPE_STORE;
        else if (INSTRUCTION_MEMORY_4[6:0] == OP_I_TYPE_OTHER || INSTRUCTION_MEMORY_4[6:0] == OP_I_TYPE_64 || INSTRUCTION_MEMORY_4[6:0] == OP_I_TYPE_JUMP)
            TYPE_PIPELINE[WRITEBACK] <= TYPE_IMMEDIATE;
        else if (INSTRUCTION_MEMORY_4[6:0] == OP_B_TYPE[6:0])
            TYPE_PIPELINE[WRITEBACK] <= TYPE_BRANCH;
        else
            TYPE_PIPELINE[WRITEBACK] <= TYPE_IMMEDIATE;

        R1_PIPELINE[WRITEBACK] <= INSTRUCTION_MEMORY_4[19:15];
        R2_PIPELINE[WRITEBACK] <= INSTRUCTION_MEMORY_4[24:20];
        RD_PIPELINE[WRITEBACK] <= INSTRUCTION_MEMORY_4[11:7];
    end

    // ============================================================
    // PIPELINE STAGE 5: WRITEBACK
    // ============================================================

    always @(posedge CLK) begin
        INSTRUCTION_WRITEBACK_5 <= INSTRUCTION_MEMORY_4;
        RAM_READ_DATA_WRITEBACK_5 <= RAM_READ_DATA;

        case (REG_WRITEBACK_SELECTION)
            1: REG_WRITE_DATA_WRITEBACK_5 <= ALU_OUT_MEMORY_4;
            2: REG_WRITE_DATA_WRITEBACK_5 <= PC_MEMORY_4 + 4;
            default: REG_WRITE_DATA_WRITEBACK_5 <= REG_WRITE_DATA_WRITEBACK_5;
        endcase
    end

    // ============================================================
    // WAVE DEBUG HELPERS
    // ============================================================

    generate
        genvar idx;
        for(idx = 0; idx < 4; idx = idx + 1) begin: PIPELINE
            wire [4:0] R1_SHOW = R1_PIPELINE[idx];
            wire [4:0] R2_SHOW = R2_PIPELINE[idx];
            wire [4:0] RD_SHOW = RD_PIPELINE[idx];
            wire [2:0] TYPE_SHOW = TYPE_PIPELINE[idx];
        end
    endgenerate

endmodule
