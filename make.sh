#!/bin/bash
# create out.tap from z80typeZX.bas
zmakebas -a10 -nZ80TEST z80typeZX.bas
# create z80typeZX.tap for all ZX Spectrum 
# and clones
pasmo --tap z80typeZX.asm z80typeZX1.tap
# z80typeZX.tap = out.tap + z80typeZX1.tap 
cat out.tap z80typeZX1.tap > z80typeZX.tap
rm out.tap z80typeZX1.tap z80typeZX.lst 2> /dev/null
