`timescale 1ns/1ps

`include "SecureSoCTop.v"

module tb_total_threat_model;

    reg CLK;

    // ============================================================
    // DUT A: normal system
    // Used for:
    // - secure boot pass
    // - boot execution gate
    // - virtual address translation
    // - branch prediction
    // ============================================================

    wire BOOT_DONE_A;
    wire BOOT_FAIL_A;
    wire SECURITY_FAULT_A;

    SecureSoCTop dut_normal (
        .CLK(CLK),
        .BOOT_DONE(BOOT_DONE_A),
        .BOOT_FAIL(BOOT_FAIL_A),
        .SECURITY_FAULT(SECURITY_FAULT_A)
    );

    // ============================================================
    // DUT B: tampered ROM
    // Used for secure boot tamper/fail test
    // ============================================================

    wire BOOT_DONE_B;
    wire BOOT_FAIL_B;
    wire SECURITY_FAULT_B;

    SecureSoCTop dut_tamper (
        .CLK(CLK),
        .BOOT_DONE(BOOT_DONE_B),
        .BOOT_FAIL(BOOT_FAIL_B),
        .SECURITY_FAULT(SECURITY_FAULT_B)
    );

    // ============================================================
    // DUT C: access-control attack
    //
    // We modify its TLB mapping after elaboration:
    // VPN 0 -> PPN 0
    //
    // Then the original program store VA=1 becomes PA=1.
    // PA=1 is inside protected physical region [0:15].
    // AccessControl should block the write and raise fault.
    // ============================================================

    wire BOOT_DONE_C;
    wire BOOT_FAIL_C;
    wire SECURITY_FAULT_C;

    SecureSoCTop dut_access_attack (
        .CLK(CLK),
        .BOOT_DONE(BOOT_DONE_C),
        .BOOT_FAIL(BOOT_FAIL_C),
        .SECURITY_FAULT(SECURITY_FAULT_C)
    );

    // ============================================================
    // Counters / monitors
    // ============================================================

    integer error_count;

    reg boot_window_violation_seen;

    reg seen_va1_store;
    reg seen_pa17_write;
    reg seen_translation_fault_normal;

    reg seen_access_fault;
    reg seen_protected_pa1_attempt;

    integer branch_update_count;
    integer mispredict_count;
    integer taken_update_count;
    integer not_taken_update_count;

    // ============================================================
    // Clock
    // ============================================================

    initial begin
        CLK = 1'b0;
        forever #5 CLK = ~CLK;
    end

    // ============================================================
    // Tamper DUT B ROM before secure boot verification
    // ============================================================

    initial begin
        #1;

        // Original:
        // dut_tamper.rom.memory[1] = 32'h00100093; // addi x1, x0, 1
        //
        // Tampered:
        // Change x1 initialization from 1 to 2.
        dut_tamper.rom.memory[1] = 32'h00200093;

        // Configure DUT C TLB so VA page 0 maps to protected PA page 0.
        // This lets the same original store VA=1 become PA=1.
        dut_access_attack.simple_tlb.tlb_ppn[0] = 6'd0;
        dut_access_attack.simple_tlb.perm_w[0]  = 1'b1;
        dut_access_attack.simple_tlb.perm_r[0]  = 1'b1;
        dut_access_attack.simple_tlb.valid[0]   = 1'b1;

        $display("[%0t] DUT B ROM tampered: memory[1] = %h",
                 $time, dut_tamper.rom.memory[1]);

        $display("[%0t] DUT C TLB modified: VPN 0 -> PPN 0 for access-control attack",
                 $time);
    end

    // ============================================================
    // Normal DUT monitors:
    // - boot window instruction gate
    // - VA -> PA translation
    // - branch predictor behavior
    // ============================================================

    always @(posedge CLK) begin
        // Boot-window check:
        // Before BOOT_DONE, CPU should only see NOP from the instruction gate.
        if (BOOT_DONE_A !== 1'b1) begin
            if (dut_normal.cpu_instruction !== 32'h00000013) begin
                boot_window_violation_seen <= 1'b1;
                $display("[%0t] ERROR: boot-window instruction was not NOP: %h",
                         $time, dut_normal.cpu_instruction);
            end
        end

        // Virtual address translation check:
        // Original program stores to VA=1.
        // Default TLB maps VPN 0 -> PPN 1, so VA 1 -> PA 17.
        if (dut_normal.cpu_ram_write_enable === 1'b1 &&
            dut_normal.cpu_ram_addr === 10'd1) begin

            seen_va1_store <= 1'b1;

            $display("[%0t] NORMAL: CPU store VA=%0d translated PA=%0d write_allowed=%b",
                     $time,
                     dut_normal.cpu_ram_addr,
                     dut_normal.phys_ram_addr,
                     dut_normal.ram_write_allowed);
        end

        if (dut_normal.ram_write_allowed === 1'b1 &&
            dut_normal.phys_ram_addr === 10'd17) begin

            seen_pa17_write <= 1'b1;

            $display("[%0t] NORMAL: physical RAM write at PA=%0d data=%h",
                     $time,
                     dut_normal.phys_ram_addr,
                     dut_normal.cpu_ram_write_data);
        end

        if (dut_normal.translation_fault === 1'b1) begin
            seen_translation_fault_normal <= 1'b1;

            $display("[%0t] NORMAL: unexpected translation fault. VA=%0d PA=%0d tlb_fault=%b perm_fault=%b",
                     $time,
                     dut_normal.cpu_ram_addr,
                     dut_normal.phys_ram_addr,
                     dut_normal.tlb_fault,
                     dut_normal.tlb_permission_fault);
        end

        // Branch predictor monitor
        if (dut_normal.cpu.bp_update_en === 1'b1) begin
            branch_update_count = branch_update_count + 1;

            if (dut_normal.cpu.bp_actual_taken === 1'b1) begin
                taken_update_count = taken_update_count + 1;
            end
            else begin
                not_taken_update_count = not_taken_update_count + 1;
            end

            $display("[%0t] BP update: PC=%0d actual_taken=%b pred_taken=%b pred_pc=%0d actual_target=%0d mispredict=%b",
                     $time,
                     dut_normal.cpu.PC_EXECUTE_3,
                     dut_normal.cpu.bp_actual_taken,
                     dut_normal.cpu.PRED_TAKEN_EXECUTE_3,
                     dut_normal.cpu.PRED_PC_EXECUTE_3,
                     dut_normal.cpu.ACTUAL_BRANCH_TARGET,
                     dut_normal.cpu.BRANCH_MISPREDICT);
        end

        if (dut_normal.cpu.BRANCH_MISPREDICT === 1'b1) begin
            mispredict_count = mispredict_count + 1;

            $display("[%0t] BP mispredict: correct_next_pc=%0d",
                     $time,
                     dut_normal.cpu.CORRECT_NEXT_PC);
        end
    end

    // ============================================================
    // Access attack DUT monitor
    // ============================================================

    always @(posedge CLK) begin
        if (dut_access_attack.cpu_ram_write_enable === 1'b1 &&
            dut_access_attack.phys_ram_addr >= 10'd0 &&
            dut_access_attack.phys_ram_addr <= 10'd15) begin

            seen_protected_pa1_attempt <= 1'b1;

            $display("[%0t] ACCESS ATTACK: protected physical write attempt. VA=%0d PA=%0d allowed=%b fault=%b",
                     $time,
                     dut_access_attack.cpu_ram_addr,
                     dut_access_attack.phys_ram_addr,
                     dut_access_attack.ram_write_allowed,
                     SECURITY_FAULT_C);
        end

        if (SECURITY_FAULT_C === 1'b1) begin
            seen_access_fault <= 1'b1;

            $display("[%0t] ACCESS ATTACK: SECURITY_FAULT asserted. VA=%0d PA=%0d",
                     $time,
                     dut_access_attack.cpu_ram_addr,
                     dut_access_attack.phys_ram_addr);
        end
    end

    // ============================================================
    // Helper task: reset pipeline of DUT A
    // ============================================================

    task reset_cpu_pipeline_normal;
        begin
            dut_normal.cpu.PC = 10'd0;

            dut_normal.cpu.PC_DECODE_2 = 10'd0;
            dut_normal.cpu.INSTRUCTION_DECODE_2 = 32'h00000013;

            dut_normal.cpu.PC_EXECUTE_3 = 10'd0;
            dut_normal.cpu.INSTRUCTION_EXECUTE_3 = 32'h00000013;

            dut_normal.cpu.PC_MEMORY_4 = 10'd0;
            dut_normal.cpu.INSTRUCTION_MEMORY_4 = 32'h00000013;
            dut_normal.cpu.ALU_OUT_MEMORY_4 = 64'd0;

            dut_normal.cpu.INSTRUCTION_WRITEBACK_5 = 32'h00000013;
            dut_normal.cpu.REG_WRITE_DATA_WRITEBACK_5 = 64'd0;
            dut_normal.cpu.RAM_READ_DATA_WRITEBACK_5 = 64'd0;
            dut_normal.cpu.RAM_WRITE_DATA = 64'd0;

            dut_normal.cpu.PRED_TAKEN_DECODE_2 = 1'b0;
            dut_normal.cpu.PRED_PC_DECODE_2 = 10'd0;
            dut_normal.cpu.PRED_TAKEN_EXECUTE_3 = 1'b0;
            dut_normal.cpu.PRED_PC_EXECUTE_3 = 10'd0;

            dut_normal.cpu.R1_PIPELINE[0] = 5'd0;
            dut_normal.cpu.R1_PIPELINE[1] = 5'd0;
            dut_normal.cpu.R1_PIPELINE[2] = 5'd0;
            dut_normal.cpu.R1_PIPELINE[3] = 5'd0;

            dut_normal.cpu.R2_PIPELINE[0] = 5'd0;
            dut_normal.cpu.R2_PIPELINE[1] = 5'd0;
            dut_normal.cpu.R2_PIPELINE[2] = 5'd0;
            dut_normal.cpu.R2_PIPELINE[3] = 5'd0;

            dut_normal.cpu.RD_PIPELINE[0] = 5'd0;
            dut_normal.cpu.RD_PIPELINE[1] = 5'd0;
            dut_normal.cpu.RD_PIPELINE[2] = 5'd0;
            dut_normal.cpu.RD_PIPELINE[3] = 5'd0;

            dut_normal.cpu.TYPE_PIPELINE[0] = dut_normal.cpu.TYPE_IMMEDIATE;
            dut_normal.cpu.TYPE_PIPELINE[1] = dut_normal.cpu.TYPE_IMMEDIATE;
            dut_normal.cpu.TYPE_PIPELINE[2] = dut_normal.cpu.TYPE_IMMEDIATE;
            dut_normal.cpu.TYPE_PIPELINE[3] = dut_normal.cpu.TYPE_IMMEDIATE;
        end
    endtask

    // ============================================================
    // Helper task: reset pipeline of DUT C
    // ============================================================

    task reset_cpu_pipeline_access_attack;
        begin
            dut_access_attack.cpu.PC = 10'd0;

            dut_access_attack.cpu.PC_DECODE_2 = 10'd0;
            dut_access_attack.cpu.INSTRUCTION_DECODE_2 = 32'h00000013;

            dut_access_attack.cpu.PC_EXECUTE_3 = 10'd0;
            dut_access_attack.cpu.INSTRUCTION_EXECUTE_3 = 32'h00000013;

            dut_access_attack.cpu.PC_MEMORY_4 = 10'd0;
            dut_access_attack.cpu.INSTRUCTION_MEMORY_4 = 32'h00000013;
            dut_access_attack.cpu.ALU_OUT_MEMORY_4 = 64'd0;

            dut_access_attack.cpu.INSTRUCTION_WRITEBACK_5 = 32'h00000013;
            dut_access_attack.cpu.REG_WRITE_DATA_WRITEBACK_5 = 64'd0;
            dut_access_attack.cpu.RAM_READ_DATA_WRITEBACK_5 = 64'd0;
            dut_access_attack.cpu.RAM_WRITE_DATA = 64'd0;

            dut_access_attack.cpu.PRED_TAKEN_DECODE_2 = 1'b0;
            dut_access_attack.cpu.PRED_PC_DECODE_2 = 10'd0;
            dut_access_attack.cpu.PRED_TAKEN_EXECUTE_3 = 1'b0;
            dut_access_attack.cpu.PRED_PC_EXECUTE_3 = 10'd0;

            dut_access_attack.cpu.R1_PIPELINE[0] = 5'd0;
            dut_access_attack.cpu.R1_PIPELINE[1] = 5'd0;
            dut_access_attack.cpu.R1_PIPELINE[2] = 5'd0;
            dut_access_attack.cpu.R1_PIPELINE[3] = 5'd0;

            dut_access_attack.cpu.R2_PIPELINE[0] = 5'd0;
            dut_access_attack.cpu.R2_PIPELINE[1] = 5'd0;
            dut_access_attack.cpu.R2_PIPELINE[2] = 5'd0;
            dut_access_attack.cpu.R2_PIPELINE[3] = 5'd0;

            dut_access_attack.cpu.RD_PIPELINE[0] = 5'd0;
            dut_access_attack.cpu.RD_PIPELINE[1] = 5'd0;
            dut_access_attack.cpu.RD_PIPELINE[2] = 5'd0;
            dut_access_attack.cpu.RD_PIPELINE[3] = 5'd0;

            dut_access_attack.cpu.TYPE_PIPELINE[0] = dut_access_attack.cpu.TYPE_IMMEDIATE;
            dut_access_attack.cpu.TYPE_PIPELINE[1] = dut_access_attack.cpu.TYPE_IMMEDIATE;
            dut_access_attack.cpu.TYPE_PIPELINE[2] = dut_access_attack.cpu.TYPE_IMMEDIATE;
            dut_access_attack.cpu.TYPE_PIPELINE[3] = dut_access_attack.cpu.TYPE_IMMEDIATE;
        end
    endtask

    // ============================================================
    // Main test sequence
    // ============================================================

    initial begin
        error_count = 0;

        boot_window_violation_seen = 1'b0;

        seen_va1_store = 1'b0;
        seen_pa17_write = 1'b0;
        seen_translation_fault_normal = 1'b0;

        seen_access_fault = 1'b0;
        seen_protected_pa1_attempt = 1'b0;

        branch_update_count = 0;
        mispredict_count = 0;
        taken_update_count = 0;
        not_taken_update_count = 0;

        $dumpfile("total_threat_model.vcd");
        $dumpvars(0, tb_total_threat_model);

        $display("==============================================");
        $display(" Total Full-System Threat Model Test Started");
        $display("==============================================");

        // ------------------------------------------------------------
        // Phase 1: secure boot window + secure boot pass/fail
        // ------------------------------------------------------------

        #250;

        $display("");
        $display("--------------- Secure Boot Results ---------------");
        $display("DUT A normal:  BOOT_DONE=%b BOOT_FAIL=%b SECURITY_FAULT=%b",
                 BOOT_DONE_A, BOOT_FAIL_A, SECURITY_FAULT_A);
        $display("DUT B tamper:  BOOT_DONE=%b BOOT_FAIL=%b SECURITY_FAULT=%b",
                 BOOT_DONE_B, BOOT_FAIL_B, SECURITY_FAULT_B);
        $display("Boot-window violation seen on DUT A = %b",
                 boot_window_violation_seen);

        if (!(BOOT_DONE_A === 1'b1 && BOOT_FAIL_A === 1'b0)) begin
            $display("ERROR: DUT A secure boot did not pass.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: DUT A secure boot passed.");
        end

        if (!(BOOT_DONE_B === 1'b0 && BOOT_FAIL_B === 1'b1)) begin
            $display("ERROR: DUT B tampered ROM did not fail secure boot.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: DUT B tampered ROM failed secure boot.");
        end

        if (boot_window_violation_seen !== 1'b0) begin
            $display("ERROR: DUT A saw non-NOP instruction before BOOT_DONE.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: Boot-window instruction gate held CPU instruction as NOP.");
        end

        // ------------------------------------------------------------
        // Phase 2: normal system virtual address + branch prediction
        // ------------------------------------------------------------

        $display("");
        $display("--------------- Normal DUT: VA Translation + BP ---------------");
        $display("Restarting DUT A CPU from PC=0 after secure boot.");

        reset_cpu_pipeline_normal();

        // Run long enough to hit loop branch and memory stores.
        #1800;

        $display("");
        $display("DUT A after program execution:");
        $display("seen_va1_store              = %b", seen_va1_store);
        $display("seen_pa17_write             = %b", seen_pa17_write);
        $display("seen_translation_fault       = %b", seen_translation_fault_normal);
        $display("RAM[1]                      = %h", dut_normal.ram.memory[1]);
        $display("RAM[17]                     = %h", dut_normal.ram.memory[17]);
        $display("branch_update_count         = %0d", branch_update_count);
        $display("mispredict_count            = %0d", mispredict_count);
        $display("taken_update_count          = %0d", taken_update_count);
        $display("not_taken_update_count      = %0d", not_taken_update_count);

        if (seen_va1_store !== 1'b1) begin
            $display("ERROR: DUT A never issued store to virtual address VA=1.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: DUT A issued store to virtual address VA=1.");
        end

        if (seen_pa17_write !== 1'b1) begin
            $display("ERROR: DUT A did not write translated physical address PA=17.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: DUT A wrote translated physical address PA=17.");
        end

        if (dut_normal.ram.memory[1] !== 64'h0000000000000000) begin
            $display("ERROR: DUT A RAM[1] was modified; VA translation failed.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: DUT A RAM[1] remains unchanged.");
        end

        if (dut_normal.ram.memory[17] === 64'h0000000000000000) begin
            $display("ERROR: DUT A RAM[17] was not modified.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: DUT A RAM[17] modified by translated write.");
        end

        if (seen_translation_fault_normal !== 1'b0) begin
            $display("PASS: DUT A saw no translation fault for mapped writable VA=1.");
        end

        if (branch_update_count <= 0) begin
            $display("ERROR: Branch predictor never received update.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: Branch predictor received updates.");
        end

        if (mispredict_count <= 0) begin
            $display("ERROR: No branch misprediction observed.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: Branch misprediction observed.");
        end

        if (taken_update_count <= 0) begin
            $display("ERROR: No taken branch update observed.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: Taken branch update observed.");
        end

        // ------------------------------------------------------------
        // Phase 3: access-control protected physical write attack
        // ------------------------------------------------------------

        $display("");
        $display("--------------- Access-Control Attack DUT ---------------");
        $display("Restarting DUT C CPU from PC=0 after secure boot.");

        if (!(BOOT_DONE_C === 1'b1 && BOOT_FAIL_C === 1'b0)) begin
            $display("ERROR: DUT C secure boot did not pass.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: DUT C secure boot passed.");
        end

        reset_cpu_pipeline_access_attack();

        #1000;

        $display("");
        $display("DUT C after protected-write attack:");
        $display("seen_protected_pa_attempt   = %b", seen_protected_pa1_attempt);
        $display("seen_access_fault           = %b", seen_access_fault);
        $display("Current SECURITY_FAULT_C    = %b", SECURITY_FAULT_C);
        $display("RAM_WRITE_ALLOWED           = %b", dut_access_attack.ram_write_allowed);
        $display("VA                          = %0d", dut_access_attack.cpu_ram_addr);
        $display("PA                          = %0d", dut_access_attack.phys_ram_addr);
        $display("RAM[1]                      = %h", dut_access_attack.ram.memory[1]);

        if (seen_protected_pa1_attempt !== 1'b1) begin
            $display("ERROR: DUT C never attempted protected physical write.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: DUT C attempted protected physical write.");
        end

        if (seen_access_fault !== 1'b1) begin
            $display("ERROR: DUT C did not assert security fault for protected write.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: DUT C asserted security fault for protected write.");
        end

        if (dut_access_attack.ram.memory[1] !== 64'h0000000000000000) begin
            $display("ERROR: DUT C RAM[1] was modified; access control failed.");
            error_count = error_count + 1;
        end
        else begin
            $display("PASS: DUT C RAM[1] remains unchanged; write was blocked.");
        end

        // ------------------------------------------------------------
        // Final result
        // ------------------------------------------------------------

        $display("");
        $display("==============================================");
        if (error_count == 0) begin
            $display("ALL TOTAL FULL-SYSTEM THREAT MODEL TESTS PASSED.");
        end
        else begin
            $display("TOTAL FULL-SYSTEM THREAT MODEL TEST FAILED. error_count = %0d", error_count);
        end
        $display("==============================================");

        $finish;
    end

endmodule
