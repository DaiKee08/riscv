transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+../../rtl/riscv tb_total_threat_model.v

vsim -voptargs=+acc work.tb_total_threat_model

add wave -r sim:/tb_total_threat_model/*

run -all

quit -f
