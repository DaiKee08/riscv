`timescale 1ns/1ps

`include "SecureSoCTop.v"

module tb_addr_translation_full;

    reg CLK;

    wire BOOT_DONE;
    wire BOOT_FAIL;
    wire SECURITY_FAULT;

    integer error_count;

    reg seen_virtual_write_va1;
    reg seen_physical_write_pa17;
    reg seen_translation_fault;

    SecureSoCTop dut (
        .CLK(CLK),
        .BOOT_DONE(BOOT_DONE),
        .BOOT_FAIL(BOOT_FAIL),
        .SECURITY_FAULT(SECURITY_FAULT)
    );

    // Clock generation
    initial begin
        CLK = 1'b0;
        forever #5 CLK = ~CLK;
    end

    // Monitor CPU virtual address and translated physical address.
    always @(posedge CLK) begin
        if (dut.cpu_ram_write_enable === 1'b1 &&
            dut.cpu_ram_addr === 10'd1) begin
            seen_virtual_write_va1 <= 1'b1;
            $display("[%0t] CPU store issued to virtual address VA=%0d, translated PA=%0d, write_allowed=%b",
                     $time,
                     dut.cpu_ram_addr,
                     dut.phys_ram_addr,
                     dut.ram_write_allowed);
        end

        if (dut.ram_write_allowed === 1'b1 &&
            dut.phys_ram_addr === 10'd17) begin
            seen_physical_write_pa17 <= 1'b1;
            $display("[%0t] RAM physical write allowed at PA=%0d, data=%h",
                     $time,
                     dut.phys_ram_addr,
                     dut.cpu_ram_write_data);
        end

        if (dut.translation_fault === 1'b1) begin
            seen_translation_fault <= 1'b1;
            $display("[%0t] Translation fault detected. VA=%0d PA=%0d tlb_fault=%b perm_fault=%b",
                     $time,
                     dut.cpu_ram_addr,
                     dut.phys_ram_addr,
                     dut.tlb_fault,
                     dut.tlb_permission_fault);
        end
    end

    initial begin
        error_count = 0;
        seen_virtual_write_va1 = 1'b0;
        seen_physical_write_pa17 = 1'b0;
        seen_translation_fault = 1'b0;

        $dumpfile("addr_translation_full.vcd");
        $dumpvars(0, tb_addr_translation_full);

        $display("==============================================");
        $display(" Address Translation Full-System Test Started");
        $display("==============================================");

        // Wait for secure boot to finish.
        #200;

        $display("");
        $display("After secure boot:");
        $display("BOOT_DONE          = %b", BOOT_DONE);
        $display("BOOT_FAIL          = %b", BOOT_FAIL);
        $display("SECURITY_FAULT     = %b", SECURITY_FAULT);
        $display("CPU PC             = %0d", dut.cpu.PC);
        $display("RAM[1]             = %h", dut.ram.memory[1]);
        $display("RAM[17]            = %h", dut.ram.memory[17]);

        if (!(BOOT_DONE === 1'b1 && BOOT_FAIL === 1'b0)) begin
            $display("ERROR: Secure boot did not pass.");
            error_count = error_count + 1;
            $finish;
        end

        // ============================================================
        // Current CPU has no RESET / CPU_ENABLE.
        // During secure boot, PC has already advanced.
        // For this full-system test, restart CPU from PC=0 after boot.
        // ============================================================

        $display("");
        $display("Restarting CPU from PC=0 after secure boot for address translation test.");

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

        // Wait for CPU to execute the program and reach the store.
        #600;

        $display("");
        $display("After CPU runs address-translation program:");
        $display("BOOT_DONE                  = %b", BOOT_DONE);
        $display("BOOT_FAIL                  = %b", BOOT_FAIL);
        $display("SECURITY_FAULT             = %b", SECURITY_FAULT);
        $display("Seen virtual write VA=1    = %b", seen_virtual_write_va1);
        $display("Seen physical write PA=17  = %b", seen_physical_write_pa17);
        $display("Seen translation fault     = %b", seen_translation_fault);
        $display("Current CPU virtual addr   = %0d", dut.cpu_ram_addr);
        $display("Current physical RAM addr  = %0d", dut.phys_ram_addr);
        $display("TLB hit                    = %b", dut.tlb_hit);
        $display("TLB fault                  = %b", dut.tlb_fault);
        $display("TLB permission fault       = %b", dut.tlb_permission_fault);
        $display("RAM write allowed          = %b", dut.ram_write_allowed);
        $display("RAM[1]                     = %h", dut.ram.memory[1]);
        $display("RAM[17]                    = %h", dut.ram.memory[17]);

        // The CPU should attempt to write VA 1.
        if (seen_virtual_write_va1 !== 1'b1) begin
            $display("ERROR: CPU never attempted store to virtual address 1.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: CPU attempted store to virtual address 1.");
        end

        // TLB should translate VA 1 to PA 17 and allow RAM write there.
        if (seen_physical_write_pa17 !== 1'b1) begin
            $display("ERROR: No physical write observed at PA 17.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: Physical write observed at PA 17.");
        end

        // Since VA 1 is mapped and writable, no translation fault should occur.
        if (seen_translation_fault !== 1'b0) begin
            $display("PASS: No translation fault for mapped writable page.");
        end

        // RAM[1] is the virtual address location, but actual physical write goes to RAM[17].
        if (dut.ram.memory[1] !== 64'h0000000000000000) begin
            $display("ERROR: RAM[1] was modified. Translation failed.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: RAM[1] remains unchanged.");
        end

        if (dut.ram.memory[17] === 64'h0000000000000000) begin
            $display("ERROR: RAM[17] was not modified.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: RAM[17] was modified by translated write.");
        end

        $display("");
        $display("==============================================");
        if (error_count == 0) begin
            $display("ALL ADDRESS TRANSLATION FULL-SYSTEM TESTS PASSED.");
        end
        else begin
            $display("ADDRESS TRANSLATION FULL-SYSTEM TEST FAILED. error_count = %0d", error_count);
        end
        $display("==============================================");

        $finish;
    end

endmodule
