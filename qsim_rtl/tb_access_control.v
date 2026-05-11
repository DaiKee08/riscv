`timescale 1ns/1ps

`include "SecureSoCTop.v"

module tb_access_control;

    reg CLK;

    wire BOOT_DONE;
    wire BOOT_FAIL;
    wire SECURITY_FAULT;

    integer error_count;
    integer cycle_count;
    reg seen_security_fault;
    reg seen_protected_write_attempt;

    SecureSoCTop dut (
        .CLK(CLK),
        .BOOT_DONE(BOOT_DONE),
        .BOOT_FAIL(BOOT_FAIL),
        .SECURITY_FAULT(SECURITY_FAULT)
    );

    initial begin
        CLK = 1'b0;
        forever #5 CLK = ~CLK;
    end

    // Monitor whether SECURITY_FAULT ever appears.
    always @(posedge CLK) begin
        cycle_count <= cycle_count + 1;

        if (SECURITY_FAULT === 1'b1) begin
            seen_security_fault <= 1'b1;
            $display("[%0t] SECURITY_FAULT asserted. CPU_RAM_ADDR=%0d CPU_RAM_WE=%b RAM_WRITE_ALLOWED=%b",
                     $time, dut.cpu_ram_addr, dut.cpu_ram_write_enable, dut.ram_write_allowed);
        end

        if (dut.cpu_ram_write_enable === 1'b1 &&
            dut.cpu_ram_addr >= 10'd0 &&
            dut.cpu_ram_addr <= 10'd15) begin
            seen_protected_write_attempt <= 1'b1;
            $display("[%0t] Protected write attempt detected. addr=%0d data=%h allowed=%b fault=%b",
                     $time, dut.cpu_ram_addr, dut.cpu_ram_write_data,
                     dut.ram_write_allowed, SECURITY_FAULT);
        end
    end

    initial begin
        error_count = 0;
        cycle_count = 0;
        seen_security_fault = 0;
        seen_protected_write_attempt = 0;

        $dumpfile("access_control.vcd");
        $dumpvars(0, tb_access_control);

        $display("==============================================");
        $display(" Access Control Full-System Test Started");
        $display("==============================================");

        // Wait for secure boot.
        #200;

        $display("");
        $display("After secure boot:");
        $display("BOOT_DONE      = %b", BOOT_DONE);
        $display("BOOT_FAIL      = %b", BOOT_FAIL);
        $display("SECURITY_FAULT = %b", SECURITY_FAULT);
        $display("CPU PC         = %0d", dut.cpu.PC);
        $display("RAM[1]         = %h", dut.ram.memory[1]);

        if (!(BOOT_DONE === 1'b1 && BOOT_FAIL === 1'b0)) begin
            $display("ERROR: Secure boot did not pass.");
            error_count = error_count + 1;
            $finish;
        end

        // ============================================================
        // Important:
        // Because current CPU has no RESET/CPU_ENABLE, it runs NOPs
        // during secure boot and PC moves forward.
        // For this full-system test, restart CPU from PC=0 after boot.
        // ============================================================

        $display("");
        $display("Restarting CPU from PC=0 after secure boot for access-control test.");

        dut.cpu.PC = 10'd0;

        dut.cpu.PC_DECODE_2 = 10'd0;
        dut.cpu.INSTRUCTION_DECODE_2 = 32'h00000013;

        dut.cpu.PC_EXECUTE_3 = 10'd0;
        dut.cpu.INSTRUCTION_EXECUTE_3 = 32'h00000013;

        dut.cpu.PC_MEMORY_4 = 10'd0;
        dut.cpu.INSTRUCTION_MEMORY_4 = 32'h00000013;
        dut.cpu.ALU_OUT_MEMORY_4 = 64'd0;

        dut.cpu.INSTRUCTION_WRITEBACK_5 = 32'h00000013;
        dut.cpu.REG_WRITE_DATA_WRITEBACK_5 = 64'd0;
        dut.cpu.RAM_READ_DATA_WRITEBACK_5 = 64'd0;
        dut.cpu.RAM_WRITE_DATA = 64'd0;

        dut.cpu.R1_PIPELINE[0] = 5'd0;
        dut.cpu.R1_PIPELINE[1] = 5'd0;
        dut.cpu.R1_PIPELINE[2] = 5'd0;
        dut.cpu.R1_PIPELINE[3] = 5'd0;

        dut.cpu.R2_PIPELINE[0] = 5'd0;
        dut.cpu.R2_PIPELINE[1] = 5'd0;
        dut.cpu.R2_PIPELINE[2] = 5'd0;
        dut.cpu.R2_PIPELINE[3] = 5'd0;

        dut.cpu.RD_PIPELINE[0] = 5'd0;
        dut.cpu.RD_PIPELINE[1] = 5'd0;
        dut.cpu.RD_PIPELINE[2] = 5'd0;
        dut.cpu.RD_PIPELINE[3] = 5'd0;

        dut.cpu.TYPE_PIPELINE[0] = dut.cpu.TYPE_IMMEDIATE;
        dut.cpu.TYPE_PIPELINE[1] = dut.cpu.TYPE_IMMEDIATE;
        dut.cpu.TYPE_PIPELINE[2] = dut.cpu.TYPE_IMMEDIATE;
        dut.cpu.TYPE_PIPELINE[3] = dut.cpu.TYPE_IMMEDIATE;

        // Wait for CPU to execute:
        // ROM[1] addi x1, x0, 1
        // ROM[2] addi x6, x0, 1
        // ROM[3] addi x12, x0, 4
        // ROM[4] sw x6, 0(x1)
        // In a 5-stage pipeline, give it enough cycles.
        #500;

        $display("");
        $display("After CPU runs protected-write program:");
        $display("BOOT_DONE                  = %b", BOOT_DONE);
        $display("BOOT_FAIL                  = %b", BOOT_FAIL);
        $display("Current SECURITY_FAULT      = %b", SECURITY_FAULT);
        $display("Seen SECURITY_FAULT         = %b", seen_security_fault);
        $display("Seen protected write attempt= %b", seen_protected_write_attempt);
        $display("CPU PC                      = %0d", dut.cpu.PC);
        $display("CPU RAM_ADDR                = %0d", dut.cpu_ram_addr);
        $display("CPU RAM_WE                  = %b", dut.cpu_ram_write_enable);
        $display("RAM_WRITE_ALLOWED           = %b", dut.ram_write_allowed);
        $display("RAM[1]                      = %h", dut.ram.memory[1]);

        if (seen_protected_write_attempt !== 1'b1) begin
            $display("ERROR: CPU never attempted a protected write.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: CPU attempted protected write.");
        end

        if (seen_security_fault !== 1'b1) begin
            $display("ERROR: SECURITY_FAULT was never asserted.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: SECURITY_FAULT was asserted.");
        end

        if (dut.ram.memory[1] !== 64'h0000000000000000) begin
            $display("ERROR: RAM[1] was modified. Access control failed.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: RAM[1] remains unchanged.");
        end

        $display("");
        $display("==============================================");
        if (error_count == 0) begin
            $display("ALL ACCESS CONTROL FULL-SYSTEM TESTS PASSED.");
        end
        else begin
            $display("ACCESS CONTROL FULL-SYSTEM TEST FAILED. error_count = %0d", error_count);
        end
        $display("==============================================");

        $finish;
    end

endmodule
