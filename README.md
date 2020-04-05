# verve
VERVE - a Verilog RISC V experiment

Is it possible to build a very stupid RISC V core (RV32I) in Verilog in a couple of hourse on a snowy weekend in Trondheim?

This is inspired by MicroCoreLabs very simply RISC V emulator in ca. 100 lines of C and the darkriscv core at https://github.com/darklife/darkriscv.
The Makefile is based on the example at https://github.com/osresearch/up5k - thanks!

WARNING:
This is incomplete, stupidly coded as a simple state machine, and probably very buggy. But it seems to work in iverilog and synthesized on an UPduino2 using yosys for very simple test programs.

Currently very incomplete:
- user mode only 
- ~~no shift instructions~~
- ~~no set instructions~~
- byte/halfword load/store always loads/stores 32 bit entities 
- not a lot else (ROM/RAM and optionally registers in block RAM)

This core uses the internal 48 MHz oscillator of the UP5k FPGA and generated an internal reset signal.
The only output right now is the RGB LED.

Directories:

* sim/     iverilog simulatable version
* synth/   yosys synthesizable version for UPduino2. 
           There are two versions: one with registers implemented as distributed RAM and one with registers in block RAM
           The BRAM version saves almost 50% of the FPGA space (ca. 2200 LUTs used right now)
           Simply type make rv_synth.flash or make rv_synth_bramregs.flash
          
* tests/   a simple test program (hacked to run standalone)
* tools/   bin2hex.sh, converts objcopy-generated binary to hex file readable by Verilog's $readmemh

