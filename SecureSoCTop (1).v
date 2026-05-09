`include "CPU.v"
`include "ROM.v"
`include "RAM.v"
`include "SecureBoot.v"
`include "AccessControl.v"

module SecureSoCTop (
    input CLK,

    output BOOT_DONE,
    output BOOT_FAIL,
    output SECURITY_FAULT
);

    wire [9:0] cpu_instruction_addr;
    wire [31:0] cpu_instruction;

    wire [9:0] cpu_ram_addr;
    wire [63:0] cpu_ram_write_data;
    wire [63:0] cpu_ram_read_data;
    wire cpu_ram_write_enable;

    wire [9:0] secure_rom_addr;
    wire [9:0] rom_addr;
    wire [31:0] rom_data;

    wire ram_write_allowed;

    assign rom_addr = BOOT_DONE ? cpu_instruction_addr : secure_rom_addr;

    assign cpu_instruction = BOOT_DONE ? rom_data : 32'h00000013;

    CPU cpu (
        .RAM_READ_DATA(cpu_ram_read_data),
        .INSTRUCTION(cpu_instruction),
        .CLK(CLK),

        .RAM_ADDR(cpu_ram_addr),
        .RAM_WRITE_DATA(cpu_ram_write_data),
        .RAM_WRITE_ENABLE(cpu_ram_write_enable),
        .INSTRUCTION_ADDR(cpu_instruction_addr)
    );

    SecureBoot #(
        .CHECK_WORDS(13),
        .EXPECTED_HASH(32'hFD74EB5F)
    ) secure_boot (
        .CLK(CLK),
        .RST(1'b0),     // Tied low in normal operation.
                        // RST is exposed on SecureBoot so that a
                        // system-level reset controller can re-run
                        // the boot sequence if needed. In this SoC
                        // the boot sequence runs once at power-on.
        .ROM_DATA(rom_data),

        .ROM_ADDR(secure_rom_addr),
        .BOOT_DONE(BOOT_DONE),
        .BOOT_FAIL(BOOT_FAIL)
    );

    AccessControl #(
        .PROTECTED_START(10'd0),
        .PROTECTED_END(10'd15)
    ) access_control (
        .BOOT_DONE(BOOT_DONE),
        .BOOT_FAIL(BOOT_FAIL),

        .CPU_RAM_ADDR(cpu_ram_addr),
        .CPU_RAM_WRITE_ENABLE(cpu_ram_write_enable),

        .RAM_WRITE_ALLOWED(ram_write_allowed),
        .SECURITY_FAULT(SECURITY_FAULT)
    );

    ROM rom (
        .ADDRESS(rom_addr),
        .DATA(rom_data)
    );

    RAM ram (
        .ADDRESS(cpu_ram_addr),
        .DATA_IN(cpu_ram_write_data),
        .WRITE_ENABLE(ram_write_allowed),
        .CLK(CLK),

        .DATA_OUT(cpu_ram_read_data)
    );

endmodule
