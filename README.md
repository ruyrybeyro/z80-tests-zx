# Z80 CPU Type Detection Software - ZX port

**A lightweight utility for identifying Z80 CPU variants and clones**

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL%203.0-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

## Quick Download & Use

### ZX Spectrum - Ready to Use
- **Download**: [`z80typeZX.tap`](./z80typeZX.tap) - Complete program ready to load
- **Technical Details**: [`DOCUMENTATION.md`](./Documentation/DOCUMENTATION.md) - Complete specifications
- **Z80 ID Guide**: [`Z80ID.md`](./Documentation/Z80ID.md) - Z80 CPU Variant Identification Guide


```basic
LOAD ""
```

## Tested Hardware & Emulators

### Real Hardware ✅
| System | Model/Issue | CPU Detection | Notes |
|--------|-------------|---------------|-------|
| ZX Spectrum 48K | Issue 3 | ✅ Working | Hysteresis detection |
| ZX Spectrum 48K | Issue 4 | ✅ Working | Hysteresis detection |
| ZX Spectrum 48K | Issue 5 | ✅ Working | Hysteresis detection |
| ZX Spectrum 128K | - | ✅ Working | AY chip detection |
| Pentagon | Clone | ✅ Working | Russian clone |
| TK95 | Clone | ✅ Working | Brazilian clone |
| Timex TC 2048 | - | ✅ Working | Timex control register |
| Timex TC 2068 | - | ✅ Working | Timex control register |

### Emulators ✅

| Emulator | Status | Detection Method | Notes |
|----------|--------|------------------|-------|
| Fuse | ✅ Working | Hysteresis and AY | Cross-platform |
| QtSpecem | ✅ Working | Timex control register | Qt-based |
| ZXSP | ✅ Working | Hysteresis | macOS/Windows |

### CP/M Systems
- **Source**: Original CP/M version from [skiselev/z80-tests](https://github.com/skiselev/z80-tests)
```
A>ASM Z80TYPE
A>LOAD Z80TYPE
A>Z80TYPE /D    # Run with debug info
```

## What It Does

Identifies your Z80 CPU type with high accuracy:

- **NMOS Z80s**: Zilog Z80/Z8400, Sharp LH5080A, NEC D780C, NEC D780C-1, KR1858VM1
- **CMOS Z80s**: Zilog Z84C00, Toshiba TMPZ84C00AP, NEC D70008AC  
- **U880 Clones**: East German MME U880, Thesys Z80

**Verify authentic vs remarked CPUs** - Detect counterfeit or relabeled chips

## Example Output

```
Z80 Processor Type Detection (C) 2024 Sergey Kiselev
Detected CPU type: Zilog Z84C00
```

**ZX Spectrum**: Interactive border color test (press B for black, W for white) or automatic detection methods  
**CP/M with /D**: Shows raw test results and detailed flag analysis for research

## Building from Source

### ZX Spectrum
```bash
zmakebas -a10 -nZ80TEST z80typeZX.bas
pasmo --tap z80typeZX.asm z80typeZX1.tap
cat out.tap z80typeZX1.tap > z80typeZX.tap
```

### Requirements
- **ZX Spectrum**: Pasmo assembler, zmakebas
- **CP/M**: ASM.COM, LOAD.COM

## Supported Hardware

| System | Method | Notes |
|--------|--------|-------|
| ZX Spectrum 48K | ULA hysteresis / Visual fallback | Automatic, manual backup |
| ZX Spectrum 128K/+2/+3 | AY chip test | Automatic detection |
| Timex 2048/2068 | Control register | Automatic detection |
| CP/M Systems | SIO interrupt | RC2014, RCBus modules |

## How It Works

1. **Hardware Detection**: Automatically identifies available hardware
2. **Detection Method Selection** (in priority order):
   - **AY chip test** → For 128K/+2/+3 models or 48K with AY add-on (highest priority)
   - **Timex control register** → For TC2048/TC2068 systems  
   - **ULA hysteresis test** → For standard 48K models (automatic)
   - **Visual border test** → Manual fallback if needed
3. **CPU Analysis**: Uses undocumented instruction behavior for identification

Different Z80 variants handle undocumented instructions differently, creating unique "fingerprints" for identification.

### Usage Notes
- **Detection completes automatically** - results display immediately
- **ZX Spectrum**: Program returns to BASIC after showing results and pressing any key
- **CP/M**: Returns to command prompt, use /D for detailed output
- **Safe operation**: Non-destructive testing, won't affect system stability

### Known Limitations
- Some rare clones may show as "Unknown"
- Results may vary between individual CPU specimens
- Emulator accuracy depends on implementation quality

---

## Technical Details

### Detection Algorithm
```
Hardware Detection → CMOS/NMOS Test → U880 Bug Test → Flag Pattern Analysis → CPU ID
```

### CPU Signatures

#### Common CPUs
| CPU | CMOS | U880 | XF/YF | Notes |
|-----|------|------|-------|-------|
| Zilog Z80 | 00h | 0 | FFh | Standard NMOS |
| Zilog Z84C00 | FFh | 0 | FFh | Standard CMOS |
| Sharp LH5080A | 00h | 0 | 30h | CMOS-like NMOS |

#### Clone CPUs
| CPU | CMOS | U880 | XF/YF | Notes |
|-----|------|------|-------|-------|
| NEC D780C | 00h | 0 | FDh | NMOS clone |
| NEC D780C-1| 00h | 0 | F0h | NMOS clone |
| NEC D70008AC | FFh | 0 | <20h | CMOS clone |
| Toshiba TMPZ84C00AP | FFh | 0 | 3Fh | CMOS variant |
| KR1858VM1 | 00h | 0 | F4h | Soviet clone |

#### U880 Family
| CPU | CMOS | U880 | XF/YF | Notes |
|-----|------|------|-------|-------|
| U880 (new) | varies | 1 | FFh | Carry bug present |
| U880 (old) | varies | 1 | ≠FFh | Carry bug + variant flags |

### Files
- [`z80typeZX.asm`](./z80typeZX.asm) - ZX Spectrum assembly source
- [`z80typeZX.bas`](./z80typeZX.bas) - BASIC loader
- [`z80typeZX.tap`](./z80typeZX.tap) - Ready-to-use TAP file
- [`DOCUMENTATION.md`](./Documentation/DOCUMENTATION.md) - Complete technical specs
- [`Z80ID.md`](./Documentation/Z80ID.md) - Z80 CPU Variant Identification Guide
- [`Results.md`](./Documentation/Results.md) - Test results database

---

## Credits  
- Original: Sergey Kiselev (2024) — [z80-tests](https://github.com/skiselev/z80-tests)  
- ZX Spectrum Port: Rui Ribeiro (2025)  
- Spectrum Cassette, EAR and MIC Port behaviour documentation: Pera Putnik (1999)

## License

[GPL-3.0 License](https://www.gnu.org/licenses/gpl-3.0.en.html)

