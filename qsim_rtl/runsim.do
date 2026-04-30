# runsim.do

transcript on

# Clean work library
if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

# Compile testbench.
# +incdir+../rtl lets the compiler find SecureSoCTop.v and all included RTL files.
vlog -sv +incdir+../../rtl/riscv tb_secure_boot_full.v

# Simulate
vsim -voptargs=+acc work.tb_secure_boot_full

# Add waves
add wave -r sim:/tb_secure_boot_full/*

# Run simulation
run -all
