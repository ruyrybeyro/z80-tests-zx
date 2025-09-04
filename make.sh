#!/bin/bash
zmakebas -a10 -nZ80TEST z80typeZX.bas
pasmo --tap z80typeZX.asm z80typeZX1.tap
cat out.tap z80typeZX1.tap > z80typeZX.tap
rm out.tap z80typeZX1.tap
