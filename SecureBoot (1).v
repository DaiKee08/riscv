module SecureBoot #(
    parameter CHECK_WORDS   = 13,
    parameter EXPECTED_HASH = 32'hFD74EB5F
)(
    input CLK,
    input RST,          // Synchronous active-high reset.
                        // In SecureSoCTop, this is tied to 1'b0.
                        // Exposed here so synthesis tools infer
                        // proper reset flops instead of relying
                        // on simulation-only `initial` blocks.
    input [31:0] ROM_DATA,

    output reg [9:0] ROM_ADDR,
    output reg BOOT_DONE,
    output reg BOOT_FAIL
);

    reg [31:0] hash;
    reg [9:0] count;
    reg [1:0] state;

    localparam S_READ  = 2'd0;
    localparam S_CHECK = 2'd1;
    localparam S_DONE  = 2'd2;
    localparam S_FAIL  = 2'd3;

    always @(posedge CLK) begin
        if (RST) begin
            // Synchronous reset: return to initial boot state.
            hash     <= 32'h00000000;
            count    <= 10'd0;
            ROM_ADDR <= 10'd0;
            BOOT_DONE <= 1'b0;
            BOOT_FAIL <= 1'b0;
            state    <= S_READ;
        end
        else begin
            case (state)
                S_READ: begin
                    hash <= hash ^ ROM_DATA ^ {22'd0, count};

                    if (count == CHECK_WORDS - 1) begin
                        state <= S_CHECK;
                    end
                    else begin
                        count    <= count + 1;
                        ROM_ADDR <= ROM_ADDR + 1;
                    end
                end

                S_CHECK: begin
                    if (hash == EXPECTED_HASH) begin
                        BOOT_DONE <= 1'b1;
                        BOOT_FAIL <= 1'b0;
                        state     <= S_DONE;
                    end
                    else begin
                        BOOT_DONE <= 1'b0;
                        BOOT_FAIL <= 1'b1;
                        state     <= S_FAIL;
                    end
                end

                S_DONE: begin
                    BOOT_DONE <= 1'b1;
                    BOOT_FAIL <= 1'b0;
                end

                S_FAIL: begin
                    BOOT_DONE <= 1'b0;
                    BOOT_FAIL <= 1'b1;
                end
            endcase
        end
    end

    // Simulation-only initialisation (supplements RST for testbenches
    // that do not drive RST explicitly).
    initial begin
        hash      = 32'h00000000;
        count     = 10'd0;
        ROM_ADDR  = 10'd0;
        BOOT_DONE = 1'b0;
        BOOT_FAIL = 1'b0;
        state     = S_READ;
    end

endmodule
