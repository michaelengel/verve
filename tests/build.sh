#!/bin/sh
riscv32-unknown-elf-gcc -mabi=ilp32 -march=rv32i -S t2a.c 
riscv32-unknown-elf-gcc -mabi=ilp32 -march=rv32i -o t2a t2a.c -nostdlib -e main
riscv32-unknown-elf-objcopy -O binary t2a t2a.bin
../tools/bin2hex.sh t2a
