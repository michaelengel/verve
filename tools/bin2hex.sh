#!/bin/sh
xxd -e -g 4 -c 4 $1.bin | awk -e '{print $2;}' > $1.hex
