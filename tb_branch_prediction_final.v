`timescale 1ns/1ps

// (removed `include - all modules in design.sv)

// ================================================================
// tb_branch_prediction.v
//
// Verifies the Always-Not-Taken branch predictor in CPU.v.
//
// Strategy: use ROM.v's built-in loop program which contains a
// backward-taken branch (blt x6, x12, -12) that fires 3 times
// before falling through. The test checks:
//
//  1. CORRECTNESS — register values after execution must match
//     the expected results of the program, proving that mispredicted
//     branches flushed correctly and did not corrupt state.
//
//  2. PREDICTOR ACTIVE — BRANCH_MISPREDICT must have fired at
//     least once, proving the ANT predictor (not the old stall
//     logic) is in use.
//
//  3. MISPREDICT COUNT — the loop branch is taken 3 times and
//     not-taken once, so exactly 3 mispredictions are expected.
//
// ROM.v program recap:
//   memory[1]  addi x1,  x0, 1    ; x1  = 1  (base address)
//   memory[2]  addi x6,  x0, 1    ; x6  = 1
//   memory[3]  addi x12, x0, 4    ; x12 = 4  (loop limit)
//   memory[4]  sw   x6,  0(x1)    ; RAM[1] = 1
//   -- loop: --
//   memory[5]  lw   x6,  0(x1)    ; x6 = RAM[1]
//   memory[6]  addi x6,  x6, 1    ; x6++
//   memory[7]  sw   x6,  0(x1)    ; RAM[1] = x6
//   memory[8]  blt  x6,  x12, -12 ; if x6 < 4, jump to memory[5]
//   -- post-loop: --
//   memory[9]  addi x8, x0, 55    ; x8  = 55
//   memory[10] add  x8, x0, x8    ; x8  = x0 + x8 = x8 (data dep test)
//   memory[11] addi x8, x8, 1     ; x8  = 56
//
// Expected final state after loop exits (x6 reaches 4):
//   x1  = 1
//   x6  = 4
//   x8  = 56
//   x12 = 4
//   RAM[1] = 4
//   mispredict_count = 3  (branch taken 3 times, predicted not-taken)
// ================================================================

module tb_branch_prediction;

    reg CLK;

    wire BOOT_DONE;
    wire BOOT_FAIL;
    wire SECURITY_FAULT;

    integer error_count;
    integer mispredict_count;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    SecureSoCTop dut (
        .CLK(CLK),
        .BOOT_DONE(BOOT_DONE),
        .BOOT_FAIL(BOOT_FAIL),
        .SECURITY_FAULT(SECURITY_FAULT)
    );

    // ----------------------------------------------------------------
    // Clock: 10 ns period (100 MHz)
    // ----------------------------------------------------------------
    initial begin
        CLK = 1'b0;
        forever #5 CLK = ~CLK;
    end

    // ----------------------------------------------------------------
    // Count mispredictions by monitoring BRANCH_MISPREDICT wire.
    // This wire is inside CPU.v; we reference it via the hierarchy.
    // ----------------------------------------------------------------
    always @(posedge CLK) begin
        if (dut.cpu.BRANCH_MISPREDICT === 1'b1) begin
            mispredict_count = mispredict_count + 1;
            $display("[%0t] BRANCH_MISPREDICT fired. Count so far: %0d  PC_target=%0d",
                     $time, mispredict_count, dut.cpu.ALU_OUT[9:0]);
        end
    end

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    initial begin
        error_count      = 0;
        mispredict_count = 0;

        $dumpfile("branch_prediction.vcd");
        $dumpvars(0, tb_branch_prediction);

        $display("==============================================");
        $display(" Branch Prediction Test Started");
        $display("==============================================");
        $display(" Strategy: Always-Not-Taken static predictor");
        $display(" Expected mispredictions: 3 (loop taken 3x)");
        $display("==============================================");

        // ---- Wait for secure boot to complete (~15 cycles = 150 ns) ----
        #200;

        $display("");
        $display("--- Secure Boot Result ---");
        $display("BOOT_DONE = %b  BOOT_FAIL = %b", BOOT_DONE, BOOT_FAIL);

        if (BOOT_DONE !== 1'b1 || BOOT_FAIL !== 1'b0) begin
            $display("ERROR: Secure boot failed. Cannot proceed with branch test.");
            error_count = error_count + 1;
            $finish;
        end
        else begin
            $display("PASS: Secure boot succeeded.");
        end

        // ---- Reset CPU to PC=0 so it runs the full program cleanly ----
        // (The CPU executed NOPs during secure boot, so we restart it.
        //  This mirrors the approach used in tb_access_control.v.)
        $display("");
        $display("Resetting CPU to PC=0 for branch prediction test...");

        dut.cpu.PC = 10'd0;

        dut.cpu.PC_DECODE_2          = 10'd0;
        dut.cpu.INSTRUCTION_DECODE_2 = 32'h00000013;

        dut.cpu.PC_EXECUTE_3          = 10'd0;
        dut.cpu.INSTRUCTION_EXECUTE_3 = 32'h00000013;

        dut.cpu.PC_MEMORY_4          = 10'd0;
        dut.cpu.INSTRUCTION_MEMORY_4 = 32'h00000013;
        dut.cpu.ALU_OUT_MEMORY_4     = 64'd0;

        dut.cpu.INSTRUCTION_WRITEBACK_5      = 32'h00000013;
        dut.cpu.REG_WRITE_DATA_WRITEBACK_5   = 64'd0;
        dut.cpu.RAM_READ_DATA_WRITEBACK_5    = 64'd0;
        dut.cpu.RAM_WRITE_DATA               = 64'd0;

        dut.cpu.R1_PIPELINE[0] = 5'd0; dut.cpu.R1_PIPELINE[1] = 5'd0;
        dut.cpu.R1_PIPELINE[2] = 5'd0; dut.cpu.R1_PIPELINE[3] = 5'd0;

        dut.cpu.R2_PIPELINE[0] = 5'd0; dut.cpu.R2_PIPELINE[1] = 5'd0;
        dut.cpu.R2_PIPELINE[2] = 5'd0; dut.cpu.R2_PIPELINE[3] = 5'd0;

        dut.cpu.RD_PIPELINE[0] = 5'd0; dut.cpu.RD_PIPELINE[1] = 5'd0;
        dut.cpu.RD_PIPELINE[2] = 5'd0; dut.cpu.RD_PIPELINE[3] = 5'd0;

        dut.cpu.TYPE_PIPELINE[0] = dut.cpu.TYPE_IMMEDIATE;
        dut.cpu.TYPE_PIPELINE[1] = dut.cpu.TYPE_IMMEDIATE;
        dut.cpu.TYPE_PIPELINE[2] = dut.cpu.TYPE_IMMEDIATE;
        dut.cpu.TYPE_PIPELINE[3] = dut.cpu.TYPE_IMMEDIATE;

        // Patch ROM[1]: change "addi x1, x0, 1" to "addi x1, x0, 16"
        // so the loop stores to RAM[16] instead of RAM[1] (which is
        // in the protected region 0-15 and would be blocked by AccessControl).
        // addi x1, x0, 16 = 32'h01000093
        dut.rom.memory[1] = 32'h01000093;

        // Reset mispredict counter so we only count during actual program run.
        mispredict_count = 0;

        // ---- Run the program ----
        // Budget: 50 cycles (500 ns) is sufficient for:
        //   ~5 pre-loop instructions  + pipeline fill      (~9  cycles)
        //   3 loop iterations × ~7 cycles each             (~21 cycles)
        //   1 loop-exit branch check                       (~4  cycles)
        //   3 post-loop instructions  + pipeline drain     (~8  cycles)
        //   Total: ~42 cycles
        #500;

        // ---- Read final register state ----
        $display("");
        $display("--- Final Register State ---");
        $display("x1  (base addr)  = %0d  (expected 1)",  dut.cpu.regFile.REGISTERS[1]);
        $display("x6  (loop ctr)   = %0d  (expected 4)",  dut.cpu.regFile.REGISTERS[6]);
        $display("x8  (dep test)   = %0d  (expected 56)", dut.cpu.regFile.REGISTERS[8]);
        $display("x12 (loop limit) = %0d  (expected 4)",  dut.cpu.regFile.REGISTERS[12]);
        $display("RAM[16]          = %0d  (expected 4)",  dut.ram.memory[16]);
        $display("Mispredictions   = %0d  (expected 3)",  mispredict_count);
        $display("CPU PC           = %0d",                dut.cpu.PC);

        // ================================================================
        // TEST 1: x6 == 4
        // Loop increments x6 from 1 to 4 then exits.
        // Wrong value means branch flush corrupted the loop counter.
        // ================================================================
        $display("");
        $display("--- Test 1: Loop counter correctness (x6 == 4) ---");
        if (dut.cpu.regFile.REGISTERS[6] === 64'd4) begin
            $display("PASS: x6 = 4");
        end
        else begin
            $display("FAIL: x6 = %0d (expected 4)", dut.cpu.regFile.REGISTERS[6]);
            $display("      Branch flush may have corrupted pipeline state.");
            error_count = error_count + 1;
        end

        // ================================================================
        // TEST 2: x8 == 56
        // Post-loop data-dependency sequence:
        //   addi x8, x0, 55  → x8 = 55
        //   add  x8, x0, x8  → x8 = 55  (tests forwarding after branch)
        //   addi x8, x8, 1   → x8 = 56
        // Wrong value means instructions after the branch were squashed
        // or executed incorrectly.
        // ================================================================
        $display("");
        $display("--- Test 2: Post-branch execution correctness (x8 == 56) ---");
        if (dut.cpu.regFile.REGISTERS[8] === 64'd56) begin
            $display("PASS: x8 = 56");
        end
        else begin
            $display("FAIL: x8 = %0d (expected 56)", dut.cpu.regFile.REGISTERS[8]);
            $display("      Instructions after loop branch may not have executed.");
            error_count = error_count + 1;
        end

        // ================================================================
        // TEST 3: RAM[1] == 4
        // Each loop iteration stores x6 to RAM[1].
        // Final store should leave RAM[1] = 4.
        // ================================================================
        $display("");
        $display("--- Test 3: Memory write correctness (RAM[1] == 4) ---");
        if (dut.ram.memory[16] === 64'd4) begin
            $display("PASS: RAM[16] = 4");
        end
        else begin
            $display("FAIL: RAM[16] = %0d (expected 4)", dut.ram.memory[16]);
            $display("      Store instructions may have executed on wrong data.");
            error_count = error_count + 1;
        end

        // ================================================================
        // TEST 4: BRANCH_MISPREDICT fired at least once
        // Confirms that the ANT predictor is active in the new CPU.v.
        // If mispredict_count == 0, the old stall-only path is still in use.
        // ================================================================
        $display("");
        $display("--- Test 4: Predictor is active (mispredict_count > 0) ---");
        if (mispredict_count > 0) begin
            $display("PASS: BRANCH_MISPREDICT fired %0d time(s).", mispredict_count);
        end
        else begin
            $display("FAIL: BRANCH_MISPREDICT never fired.");
            $display("      The old CONTROL_HAZARD_STALL may still be active,");
            $display("      or BRANCH_MISPREDICT wire is not reachable.");
            error_count = error_count + 1;
        end

        // ================================================================
        // TEST 5: Exactly 3 mispredictions
        // The blt branch is taken 3 times (x6=2,3,4 < x12=4 ... wait,
        // x6=1→2 taken, x6=2→3 taken, x6=3→4 taken, x6=4 not taken).
        // So exactly 3 mispredictions expected.
        // ================================================================
        $display("");
        $display("--- Test 5: Mispredict count == 2 ---");
        // The loop branch fires 3 times total:
        //   iter 1: x6=2 < x12=4  -> taken  -> mispredict (count=1)
        //   iter 2: x6=3 < x12=4  -> taken  -> mispredict (count=2)
        //   iter 3: x6=4 < x12=4  -> NOT taken -> correct prediction (count stays 2)
        // memory[4] sw is NOT a branch, so the initial store does not add a mispredict.
        // Expected mispredictions = 2.
        if (mispredict_count === 2) begin
            $display("PASS: Exactly 2 mispredictions (2 taken loop branches).");
        end
        else begin
            $display("FAIL: mispredict_count = %0d (expected 2).", mispredict_count);
            $display("      Check waveform for BRANCH_MISPREDICT signal.");
            error_count = error_count + 1;
        end

        // ================================================================
        // Summary
        // ================================================================
        $display("");
        $display("==============================================");
        if (error_count == 0) begin
            $display("ALL BRANCH PREDICTION TESTS PASSED.");
            $display("Mispredictions detected: %0d", mispredict_count);
        end
        else begin
            $display("BRANCH PREDICTION TEST FAILED.");
            $display("error_count = %0d", error_count);
        end
        $display("==============================================");

        $finish;
    end

endmodule
