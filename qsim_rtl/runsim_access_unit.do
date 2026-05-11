transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+../../rtl/riscv tb_access_control_unit.v

vsim -voptargs=+acc work.tb_access_control_unit

run -all

quit -f
