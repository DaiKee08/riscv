`timescale 1ns/1ps

`include "SimpleTLB.v"

module tb_simple_tlb;

    reg [9:0] VIRT_ADDR;
    reg READ_ENABLE;
    reg WRITE_ENABLE;

    wire [9:0] PHYS_ADDR;
    wire TLB_HIT;
    wire TLB_FAULT;
    wire PERMISSION_FAULT;

    integer error_count;

    SimpleTLB dut (
        .VIRT_ADDR(VIRT_ADDR),
        .READ_ENABLE(READ_ENABLE),
        .WRITE_ENABLE(WRITE_ENABLE),

        .PHYS_ADDR(PHYS_ADDR),
        .TLB_HIT(TLB_HIT),
        .TLB_FAULT(TLB_FAULT),
        .PERMISSION_FAULT(PERMISSION_FAULT)
    );

    initial begin
        error_count = 0;

        $display("==============================================");
        $display(" SimpleTLB Unit Test Started");
        $display("==============================================");

        // ------------------------------------------------------------
        // Case 1:
        // VA 1 = VPN 0, offset 1.
        // VPN 0 -> PPN 1.
        // Expected PA = 16 + 1 = 17.
        // Write allowed.
        // ------------------------------------------------------------
        VIRT_ADDR = 10'd1;
        READ_ENABLE = 1'b0;
        WRITE_ENABLE = 1'b1;
        #10;

        $display("");
        $display("Case 1: VA 1 write");
        $display("VIRT_ADDR        = %0d", VIRT_ADDR);
        $display("PHYS_ADDR        = %0d", PHYS_ADDR);
        $display("TLB_HIT          = %b", TLB_HIT);
        $display("TLB_FAULT        = %b", TLB_FAULT);
        $display("PERMISSION_FAULT = %b", PERMISSION_FAULT);

        if (PHYS_ADDR !== 10'd17 ||
            TLB_HIT !== 1'b1 ||
            TLB_FAULT !== 1'b0 ||
            PERMISSION_FAULT !== 1'b0) begin
            $display("ERROR: Case 1 failed.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: VA 1 translated to PA 17.");
        end

        // ------------------------------------------------------------
        // Case 2:
        // VA 16 = VPN 1, offset 0.
        // VPN 1 -> PPN 2.
        // Expected PA = 32.
        // But VPN 1 is read-only, so write should fault.
        // ------------------------------------------------------------
        VIRT_ADDR = 10'd16;
        READ_ENABLE = 1'b0;
        WRITE_ENABLE = 1'b1;
        #10;

        $display("");
        $display("Case 2: VA 16 write to read-only page");
        $display("VIRT_ADDR        = %0d", VIRT_ADDR);
        $display("PHYS_ADDR        = %0d", PHYS_ADDR);
        $display("TLB_HIT          = %b", TLB_HIT);
        $display("TLB_FAULT        = %b", TLB_FAULT);
        $display("PERMISSION_FAULT = %b", PERMISSION_FAULT);

        if (PHYS_ADDR !== 10'd32 ||
            TLB_HIT !== 1'b1 ||
            TLB_FAULT !== 1'b0 ||
            PERMISSION_FAULT !== 1'b1) begin
            $display("ERROR: Case 2 failed.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: Read-only page write generated permission fault.");
        end

        // ------------------------------------------------------------
        // Case 3:
        // VA 48 = VPN 3, offset 0.
        // VPN 3 is invalid / unmapped.
        // Should trigger TLB fault.
        // ------------------------------------------------------------
        VIRT_ADDR = 10'd48;
        READ_ENABLE = 1'b0;
        WRITE_ENABLE = 1'b1;
        #10;

        $display("");
        $display("Case 3: VA 48 unmapped write");
        $display("VIRT_ADDR        = %0d", VIRT_ADDR);
        $display("PHYS_ADDR        = %0d", PHYS_ADDR);
        $display("TLB_HIT          = %b", TLB_HIT);
        $display("TLB_FAULT        = %b", TLB_FAULT);
        $display("PERMISSION_FAULT = %b", PERMISSION_FAULT);

        if (TLB_HIT !== 1'b0 ||
            TLB_FAULT !== 1'b1) begin
            $display("ERROR: Case 3 failed.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: Unmapped page generated TLB fault.");
        end

        // ------------------------------------------------------------
        // Case 4:
        // VA 18 = VPN 1, offset 2.
        // Read from read-only page should be allowed.
        // Expected PA = 34.
        // ------------------------------------------------------------
        VIRT_ADDR = 10'd18;
        READ_ENABLE = 1'b1;
        WRITE_ENABLE = 1'b0;
        #10;

        $display("");
        $display("Case 4: VA 18 read from read-only page");
        $display("VIRT_ADDR        = %0d", VIRT_ADDR);
        $display("PHYS_ADDR        = %0d", PHYS_ADDR);
        $display("TLB_HIT          = %b", TLB_HIT);
        $display("TLB_FAULT        = %b", TLB_FAULT);
        $display("PERMISSION_FAULT = %b", PERMISSION_FAULT);

        if (PHYS_ADDR !== 10'd34 ||
            TLB_HIT !== 1'b1 ||
            TLB_FAULT !== 1'b0 ||
            PERMISSION_FAULT !== 1'b0) begin
            $display("ERROR: Case 4 failed.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: Read-only page read is allowed.");
        end

        $display("");
        $display("==============================================");
        if (error_count == 0) begin
            $display("ALL SIMPLETLB UNIT TESTS PASSED.");
        end
        else begin
            $display("SIMPLETLB UNIT TEST FAILED. error_count = %0d", error_count);
        end
        $display("==============================================");

        $finish;
    end

endmodule
