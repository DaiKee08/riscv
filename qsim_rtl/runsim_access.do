transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+../../rtl/riscv tb_access_control.v

vsim -voptargs=+acc work.tb_access_control

add wave -r sim:/tb_access_control/*

run -all

quit -f
