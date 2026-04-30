`timescale 1ns/1ps

// 如果你的 SecureSoCTop.v 里面已经 include 了 CPU/ROM/RAM/SecureBoot/AccessControl，
// 那这里只 include SecureSoCTop.v 就够了。
`include "SecureSoCTop.v"

module tb_secure_boot_full;

    reg CLK;

    wire BOOT_DONE_PASS;
    wire BOOT_FAIL_PASS;
    wire SECURITY_FAULT_PASS;

    wire BOOT_DONE_TAMPER;
    wire BOOT_FAIL_TAMPER;
    wire SECURITY_FAULT_TAMPER;

    integer error_count;

    // ============================================================
    // DUT 1: original ROM, should boot successfully
    // ============================================================
    SecureSoCTop dut_pass (
        .CLK(CLK),
        .BOOT_DONE(BOOT_DONE_PASS),
        .BOOT_FAIL(BOOT_FAIL_PASS),
        .SECURITY_FAULT(SECURITY_FAULT_PASS)
    );

    // ============================================================
    // DUT 2: tampered ROM, should fail secure boot
    // ============================================================
    SecureSoCTop dut_tamper (
        .CLK(CLK),
        .BOOT_DONE(BOOT_DONE_TAMPER),
        .BOOT_FAIL(BOOT_FAIL_TAMPER),
        .SECURITY_FAULT(SECURITY_FAULT_TAMPER)
    );

    // ============================================================
    // Clock generation: 100 MHz equivalent, period = 10 ns
    // ============================================================
    initial begin
        CLK = 1'b0;
        forever #5 CLK = ~CLK;
    end

    // ============================================================
    // Tamper ROM content
    // ============================================================
    initial begin
        // Wait 1 ns to make sure ROM initial block has finished.
        #1;

        // Original:
        // memory[1] = 32'h00100093; // addi x1, x0, 1
        //
        // Tampered:
        // Change immediate from 1 to 2.
        dut_tamper.rom.memory[1] = 32'h00200093;

        $display("[%0t] Tampered DUT ROM[1] changed to %h",
                 $time, dut_tamper.rom.memory[1]);
    end

    // ============================================================
    // Main test
    // ============================================================
    initial begin
        error_count = 0;

        $dumpfile("secure_boot_full.vcd");
        $dumpvars(0, tb_secure_boot_full);

        $display("==============================================");
        $display(" Secure Boot Test Started");
        $display("==============================================");

        // SecureBoot checks 13 words.
        // With 10 ns clock, boot decision should be ready around 140~150 ns.
        #200;

        $display("");
        $display("--------------- DUT PASS CASE ---------------");
        $display("BOOT_DONE      = %b", BOOT_DONE_PASS);
        $display("BOOT_FAIL      = %b", BOOT_FAIL_PASS);
        $display("SECURITY_FAULT = %b", SECURITY_FAULT_PASS);

        if (BOOT_DONE_PASS === 1'b1 && BOOT_FAIL_PASS === 1'b0) begin
            $display("PASS CASE RESULT: PASS");
        end
        else begin
            $display("PASS CASE RESULT: FAIL");
            error_count = error_count + 1;
        end

        $display("");
        $display("-------------- DUT TAMPER CASE --------------");
        $display("BOOT_DONE      = %b", BOOT_DONE_TAMPER);
        $display("BOOT_FAIL      = %b", BOOT_FAIL_TAMPER);
        $display("SECURITY_FAULT = %b", SECURITY_FAULT_TAMPER);

        if (BOOT_DONE_TAMPER === 1'b0 && BOOT_FAIL_TAMPER === 1'b1) begin
            $display("TAMPER CASE RESULT: PASS");
        end
        else begin
            $display("TAMPER CASE RESULT: FAIL");
            error_count = error_count + 1;
        end

        $display("");
        $display("==============================================");
        if (error_count == 0) begin
            $display("ALL SECURE BOOT TESTS PASSED.");
        end
        else begin
            $display("SECURE BOOT TEST FAILED. error_count = %0d", error_count);
        end
        $display("==============================================");

        $finish;
    end

endmodule
