module AccessControl #(
    parameter PROTECTED_START = 10'd0,
    parameter PROTECTED_END   = 10'd15
)(
    input BOOT_DONE,
    input BOOT_FAIL,

    input [9:0] CPU_RAM_ADDR,
    input CPU_RAM_WRITE_ENABLE,

    output RAM_WRITE_ALLOWED,
    output SECURITY_FAULT
);

    wire boot_not_ready;
    wire write_protected_region;

    assign boot_not_ready = !BOOT_DONE || BOOT_FAIL;

    assign write_protected_region =
        CPU_RAM_WRITE_ENABLE &&
        (CPU_RAM_ADDR >= PROTECTED_START) &&
        (CPU_RAM_ADDR <= PROTECTED_END);

    assign SECURITY_FAULT =
        CPU_RAM_WRITE_ENABLE &&
        (
            boot_not_ready ||
            write_protected_region
        );

    assign RAM_WRITE_ALLOWED =
        CPU_RAM_WRITE_ENABLE &&
        !boot_not_ready &&
        !write_protected_region;

endmodule