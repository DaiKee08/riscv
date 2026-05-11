module BranchPredictor #(
    parameter INDEX_BITS = 4
)(
    input CLK,

    input [9:0] QUERY_PC,
    output PREDICT_TAKEN,

    input UPDATE_EN,
    input [9:0] UPDATE_PC,
    input ACTUAL_TAKEN
);

    localparam ENTRY_COUNT = 1 << INDEX_BITS;

    reg bht [0:ENTRY_COUNT-1];

    wire [INDEX_BITS-1:0] query_index;
    wire [INDEX_BITS-1:0] update_index;

    assign query_index  = QUERY_PC[INDEX_BITS+1:2];
    assign update_index = UPDATE_PC[INDEX_BITS+1:2];

    assign PREDICT_TAKEN = bht[query_index];

    integer i;

    initial begin
        for (i = 0; i < ENTRY_COUNT; i = i + 1) begin
            bht[i] = 1'b0; // default: not taken
        end
    end

    always @(posedge CLK) begin
        if (UPDATE_EN) begin
            bht[update_index] <= ACTUAL_TAKEN;
        end
    end

endmodule
