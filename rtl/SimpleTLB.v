module SimpleTLB (
    input [9:0] VIRT_ADDR,
    input READ_ENABLE,
    input WRITE_ENABLE,

    output reg [9:0] PHYS_ADDR,
    output reg TLB_HIT,
    output reg TLB_FAULT,
    output reg PERMISSION_FAULT
);

    // 10-bit address:
    // [9:4] = VPN
    // [3:0] = page offset
    wire [5:0] vpn;
    wire [3:0] offset;

    assign vpn = VIRT_ADDR[9:4];
    assign offset = VIRT_ADDR[3:0];

    // 4-entry static TLB
    reg valid [0:3];
    reg [5:0] tlb_vpn [0:3];
    reg [5:0] tlb_ppn [0:3];
    reg perm_r [0:3];
    reg perm_w [0:3];

    integer i;
    integer hit_index;

    initial begin
        // Default invalid
        for (i = 0; i < 4; i = i + 1) begin
            valid[i] = 1'b0;
            tlb_vpn[i] = 6'd0;
            tlb_ppn[i] = 6'd0;
            perm_r[i] = 1'b0;
            perm_w[i] = 1'b0;
        end

        // Entry 0:
        // VA page 0 maps to PA page 1.
        // VA 0~15 -> PA 16~31.
        // Read/write allowed.
        valid[0] = 1'b1;
        tlb_vpn[0] = 6'd0;
        tlb_ppn[0] = 6'd1;
        perm_r[0] = 1'b1;
        perm_w[0] = 1'b1;

        // Entry 1:
        // VA page 1 maps to PA page 2.
        // VA 16~31 -> PA 32~47.
        // Read-only. Store should fault.
        valid[1] = 1'b1;
        tlb_vpn[1] = 6'd1;
        tlb_ppn[1] = 6'd2;
        perm_r[1] = 1'b1;
        perm_w[1] = 1'b0;

        // Entry 2:
        // VA page 2 maps to PA page 3.
        // Read/write allowed.
        valid[2] = 1'b1;
        tlb_vpn[2] = 6'd2;
        tlb_ppn[2] = 6'd3;
        perm_r[2] = 1'b1;
        perm_w[2] = 1'b1;

        // Entry 3 remains invalid.
    end

    always @(*) begin
        PHYS_ADDR = 10'd0;
        TLB_HIT = 1'b0;
        TLB_FAULT = 1'b0;
        PERMISSION_FAULT = 1'b0;
        hit_index = -1;

        for (i = 0; i < 4; i = i + 1) begin
            if (valid[i] && tlb_vpn[i] == vpn) begin
                TLB_HIT = 1'b1;
                hit_index = i;
                PHYS_ADDR = {tlb_ppn[i], offset};
            end
        end

        if (!TLB_HIT && (READ_ENABLE || WRITE_ENABLE)) begin
            TLB_FAULT = 1'b1;
        end

        if (TLB_HIT) begin
            if (READ_ENABLE && !perm_r[hit_index]) begin
                PERMISSION_FAULT = 1'b1;
            end

            if (WRITE_ENABLE && !perm_w[hit_index]) begin
                PERMISSION_FAULT = 1'b1;
            end
        end
    end

endmodule
