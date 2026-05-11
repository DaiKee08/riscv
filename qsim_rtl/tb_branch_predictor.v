`timescale 1ns/1ps

`include "SecureSoCTop.v"

module tb_branch_predictor_system;

    reg CLK;

    wire BOOT_DONE;
    wire BOOT_FAIL;
    wire SECURITY_FAULT;

    integer error_count;

    integer branch_update_count;
    integer mispredict_count;
    integer taken_update_count;
    integer not_taken_update_count;

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

    always @(posedge CLK) begin
        if (dut.cpu.bp_update_en === 1'b1) begin
            branch_update_count = branch_update_count + 1;

            if (dut.cpu.bp_actual_taken === 1'b1) begin
                taken_update_count = taken_update_count + 1;
            end
            else begin
                not_taken_update_count = not_taken_update_count + 1;
            end

            $display("[%0t] BP update: PC=%0d actual_taken=%b pred_taken=%b pred_pc=%0d actual_target=%0d mispredict=%b",
                     $time,
                     dut.cpu.PC_EXECUTE_3,
                     dut.cpu.bp_actual_taken,
                     dut.cpu.PRED_TAKEN_EXECUTE_3,
                     dut.cpu.PRED_PC_EXECUTE_3,
                     dut.cpu.ACTUAL_BRANCH_TARGET,
                     dut.cpu.BRANCH_MISPREDICT);
        end

        if (dut.cpu.BRANCH_MISPREDICT === 1'b1) begin
            mispredict_count = mispredict_count + 1;

            $display("[%0t] BRANCH_MISPREDICT: correct_next_pc=%0d",
                     $time,
                     dut.cpu.CORRECT_NEXT_PC);
        end
    end

    task reset_cpu_pipeline;
        begin
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

            dut.cpu.PRED_TAKEN_DECODE_2 = 1'b0;
            dut.cpu.PRED_PC_DECODE_2 = 10'd0;
            dut.cpu.PRED_TAKEN_EXECUTE_3 = 1'b0;
            dut.cpu.PRED_PC_EXECUTE_3 = 10'd0;

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
        end
    endtask

    initial begin
        error_count = 0;

        branch_update_count = 0;
        mispredict_count = 0;
        taken_update_count = 0;
        not_taken_update_count = 0;

        $dumpfile("branch_predictor_system.vcd");
        $dumpvars(0, tb_branch_predictor_system);

        $display("==============================================");
        $display(" Branch Predictor System Test Started");
        $display("==============================================");

        #200;

        $display("");
        $display("After secure boot:");
        $display("BOOT_DONE      = %b", BOOT_DONE);
        $display("BOOT_FAIL      = %b", BOOT_FAIL);
        $display("SECURITY_FAULT = %b", SECURITY_FAULT);
        $display("CPU PC         = %0d", dut.cpu.PC);

        if (!(BOOT_DONE === 1'b1 && BOOT_FAIL === 1'b0)) begin
            $display("ERROR: Secure boot did not pass.");
            error_count = error_count + 1;
            $finish;
        end

        $display("");
        $display("Restarting CPU from PC=0 for branch predictor system test.");
        reset_cpu_pipeline();

        #1500;

        $display("");
        $display("After running branch loop:");
        $display("branch_update_count     = %0d", branch_update_count);
        $display("mispredict_count        = %0d", mispredict_count);
        $display("taken_update_count      = %0d", taken_update_count);
        $display("not_taken_update_count  = %0d", not_taken_update_count);
        $display("CPU PC                  = %0d", dut.cpu.PC);

        if (branch_update_count <= 0) begin
            $display("ERROR: Branch predictor was never updated.");
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

        $display("");
        $display("==============================================");
        if (error_count == 0) begin
            $display("ALL BRANCH PREDICTOR SYSTEM TESTS PASSED.");
        end
        else begin
            $display("BRANCH PREDICTOR SYSTEM TEST FAILED. error_count = %0d", error_count);
        end
        $display("==============================================");

        $finish;
    end

endmodule
