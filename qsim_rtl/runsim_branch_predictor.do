transcript on

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vmap work work

vlog -sv +incdir+../../rtl/riscv tb_branch_predictor.v

vsim -voptargs=+acc work.tb_branch_predictor_system

run -all

quit -f
