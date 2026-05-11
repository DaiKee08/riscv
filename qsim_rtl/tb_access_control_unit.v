`timescale 1ns/1ps

`include "AccessControl.v"

module tb_access_control_unit;

    reg BOOT_DONE;
    reg BOOT_FAIL;
    reg [9:0] CPU_RAM_ADDR;
    reg CPU_RAM_WRITE_ENABLE;

    wire RAM_WRITE_ALLOWED;
    wire SECURITY_FAULT;

    integer error_count;

    AccessControl #(
        .PROTECTED_START(10'd0),
        .PROTECTED_END(10'd15)
    ) dut (
        .BOOT_DONE(BOOT_DONE),
        .BOOT_FAIL(BOOT_FAIL),
        .CPU_RAM_ADDR(CPU_RAM_ADDR),
        .CPU_RAM_WRITE_ENABLE(CPU_RAM_WRITE_ENABLE),
        .RAM_WRITE_ALLOWED(RAM_WRITE_ALLOWED),
        .SECURITY_FAULT(SECURITY_FAULT)
    );

    initial begin
        error_count = 0;

        $display("==============================================");
        $display(" AccessControl Unit Test Started");
        $display("==============================================");

        // ------------------------------------------------------------
        // Case 1: boot not done, write attempt should fault
        // ------------------------------------------------------------
        BOOT_DONE = 0;
        BOOT_FAIL = 0;
        CPU_RAM_ADDR = 10'd20;
        CPU_RAM_WRITE_ENABLE = 1;
        #10;

        $display("Case 1: boot not done write");
        $display("RAM_WRITE_ALLOWED = %b", RAM_WRITE_ALLOWED);
        $display("SECURITY_FAULT    = %b", SECURITY_FAULT);

        if (RAM_WRITE_ALLOWED !== 1'b0 || SECURITY_FAULT !== 1'b1) begin
            $display("ERROR: Case 1 failed.");
            error_count = error_count + 1;
        end

        // ------------------------------------------------------------
        // Case 2: boot fail, write attempt should fault
        // ------------------------------------------------------------
        BOOT_DONE = 0;
        BOOT_FAIL = 1;
        CPU_RAM_ADDR = 10'd20;
        CPU_RAM_WRITE_ENABLE = 1;
        #10;

        $display("");
        $display("Case 2: boot fail write");
        $display("RAM_WRITE_ALLOWED = %b", RAM_WRITE_ALLOWED);
        $display("SECURITY_FAULT    = %b", SECURITY_FAULT);

        if (RAM_WRITE_ALLOWED !== 1'b0 || SECURITY_FAULT !== 1'b1) begin
            $display("ERROR: Case 2 failed.");
            error_count = error_count + 1;
        end

        // ------------------------------------------------------------
        // Case 3: boot done, write protected region should fault
        // ------------------------------------------------------------
        BOOT_DONE = 1;
        BOOT_FAIL = 0;
        CPU_RAM_ADDR = 10'd1;
        CPU_RAM_WRITE_ENABLE = 1;
        #10;

        $display("");
        $display("Case 3: protected region write");
        $display("RAM_WRITE_ALLOWED = %b", RAM_WRITE_ALLOWED);
        $display("SECURITY_FAULT    = %b", SECURITY_FAULT);

        if (RAM_WRITE_ALLOWED !== 1'b0 || SECURITY_FAULT !== 1'b1) begin
            $display("ERROR: Case 3 failed.");
            error_count = error_count + 1;
        end

        // ------------------------------------------------------------
        // Case 4: boot done, legal write should pass
        // ------------------------------------------------------------
        BOOT_DONE = 1;
        BOOT_FAIL = 0;
        CPU_RAM_ADDR = 10'd20;
        CPU_RAM_WRITE_ENABLE = 1;
        #10;

        $display("");
        $display("Case 4: legal write");
        $display("RAM_WRITE_ALLOWED = %b", RAM_WRITE_ALLOWED);
        $display("SECURITY_FAULT    = %b", SECURITY_FAULT);

        if (RAM_WRITE_ALLOWED !== 1'b1 || SECURITY_FAULT !== 1'b0) begin
            $display("ERROR: Case 4 failed.");
            error_count = error_count + 1;
        end

        // ------------------------------------------------------------
        // Case 5: no write, no fault
        // ------------------------------------------------------------
        BOOT_DONE = 1;
        BOOT_FAIL = 0;
        CPU_RAM_ADDR = 10'd1;
        CPU_RAM_WRITE_ENABLE = 0;
        #10;

        $display("");
        $display("Case 5: no write");
        $display("RAM_WRITE_ALLOWED = %b", RAM_WRITE_ALLOWED);
        $display("SECURITY_FAULT    = %b", SECURITY_FAULT);

        if (RAM_WRITE_ALLOWED !== 1'b0 || SECURITY_FAULT !== 1'b0) begin
            $display("ERROR: Case 5 failed.");
            error_count = error_count + 1;
        end

        $display("");
        $display("==============================================");
        if (error_count == 0) begin
            $display("ALL ACCESSCONTROL UNIT TESTS PASSED.");
        end
        else begin
            $display("ACCESSCONTROL UNIT TEST FAILED. error_count = %0d", error_count);
        end
        $display("==============================================");

        $finish;
    end

endmodule
