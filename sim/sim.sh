#!/bin/sh
iverilog rv.v
./a.out 2>&1| head -4000 > log
