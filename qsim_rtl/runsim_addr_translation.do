transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+../../rtl/riscv tb_addr_translation_full.v

vsim -voptargs=+acc work.tb_addr_translation_full

add wave -r sim:/tb_addr_translation_full/*

run -all

quit -f
