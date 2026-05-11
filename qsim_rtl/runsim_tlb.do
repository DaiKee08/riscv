transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+../../rtl/riscv tb_simple_tlb.v

vsim -voptargs=+acc work.tb_simple_tlb

run -all

quit -f
