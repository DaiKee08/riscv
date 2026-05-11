`include "CPU.v"
`include "ROM.v"
`include "RAM.v"
`include "SecureBoot.v"
`include "AccessControl.v"
`include "SimpleTLB.v"

module SecureSoCTop (
    input CLK,

    output BOOT_DONE,
    output BOOT_FAIL,
    output SECURITY_FAULT
);

    // ============================================================
    // CPU interface wires
    // ============================================================

    wire [9:0] cpu_instruction_addr;
    wire [31:0] cpu_instruction;

    // CPU-generated RAM address is treated as virtual address.
    wire [9:0] cpu_ram_addr;
    wire [63:0] cpu_ram_write_data;
    wire [63:0] cpu_ram_read_data;
    wire cpu_ram_write_enable;

    // ============================================================
    // ROM / secure boot wires
    // ============================================================

    wire [9:0] secure_rom_addr;
    wire [9:0] rom_addr;
    wire [31:0] rom_data;

    // During secure boot, ROM is read by SecureBoot.
    // After boot succeeds, ROM is read by CPU.
    assign rom_addr = BOOT_DONE ? cpu_instruction_addr : secure_rom_addr;

    // Before boot is complete, CPU only sees NOP.
    // RISC-V NOP = addi x0, x0, 0 = 32'h00000013.
    assign cpu_instruction = BOOT_DONE ? rom_data : 32'h00000013;

    // ============================================================
    // Address translation wires
    // ============================================================

    wire [9:0] phys_ram_addr;

    wire tlb_hit;
    wire tlb_fault;
    wire tlb_permission_fault;
    wire translation_fault;

    assign translation_fault = tlb_fault || tlb_permission_fault;

    // ============================================================
    // Access control wires
    // ============================================================

    wire access_ram_write_allowed;
    wire access_security_fault;
    wire ram_write_allowed;

    // Final security fault combines:
    // 1. physical memory access-control fault
    // 2. virtual-memory translation / permission fault
    assign SECURITY_FAULT = access_security_fault || translation_fault;

    // Final RAM write enable:
    // allowed only if AccessControl allows it and TLB does not fault.
    assign ram_write_allowed =
        access_ram_write_allowed &&
        !translation_fault;

    // ============================================================
    // CPU
    // ============================================================

    CPU cpu (
        .RAM_READ_DATA(cpu_ram_read_data),
        .INSTRUCTION(cpu_instruction),
        .CLK(CLK),

        .RAM_ADDR(cpu_ram_addr),
        .RAM_WRITE_DATA(cpu_ram_write_data),
        .RAM_WRITE_ENABLE(cpu_ram_write_enable),
        .INSTRUCTION_ADDR(cpu_instruction_addr)
    );

    // ============================================================
    // Secure boot peripheral
    // ============================================================

    SecureBoot #(
        .CHECK_WORDS(13),
        .EXPECTED_HASH(32'hFD74EB5F)
    ) secure_boot (
        .CLK(CLK),
        .ROM_DATA(rom_data),

        .ROM_ADDR(secure_rom_addr),
        .BOOT_DONE(BOOT_DONE),
        .BOOT_FAIL(BOOT_FAIL)
    );

    // ============================================================
    // Simple data-side TLB
    //
    // CPU_RAM_ADDR is interpreted as virtual address.
    // PHYS_ADDR is used to access RAM.
    // ============================================================

    SimpleTLB simple_tlb (
        .VIRT_ADDR(cpu_ram_addr),

        // This simplified version treats the data path as readable.
        // Write permission is checked when CPU issues a store.
        .READ_ENABLE(1'b1),
        .WRITE_ENABLE(cpu_ram_write_enable),

        .PHYS_ADDR(phys_ram_addr),
        .TLB_HIT(tlb_hit),
        .TLB_FAULT(tlb_fault),
        .PERMISSION_FAULT(tlb_permission_fault)
    );

    // ============================================================
    // Runtime access control
    //
    // Important:
    // AccessControl checks physical RAM address after translation.
    // ============================================================

    AccessControl #(
        .PROTECTED_START(10'd0),
        .PROTECTED_END(10'd15)
    ) access_control (
        .BOOT_DONE(BOOT_DONE),
        .BOOT_FAIL(BOOT_FAIL),

        .CPU_RAM_ADDR(phys_ram_addr),
        .CPU_RAM_WRITE_ENABLE(cpu_ram_write_enable),

        .RAM_WRITE_ALLOWED(access_ram_write_allowed),
        .SECURITY_FAULT(access_security_fault)
    );

    // ============================================================
    // ROM
    // ============================================================

    ROM rom (
        .ADDRESS(rom_addr),
        .DATA(rom_data)
    );

    // ============================================================
    // RAM
    //
    // RAM is indexed by physical address.
    // ============================================================

    RAM ram (
        .ADDRESS(phys_ram_addr),
        .DATA_IN(cpu_ram_write_data),
        .WRITE_ENABLE(ram_write_allowed),
        .CLK(CLK),

        .DATA_OUT(cpu_ram_read_data)
    );

endmodule
