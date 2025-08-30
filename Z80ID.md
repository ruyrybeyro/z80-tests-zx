# Z80 CPU Variant Identification Guide



## CPU Identification Matrix

### Authentic Zilog Z80 Family
| CPU | CMOS Test | U880 Test | XF/YF Pattern | Test Results | Notes |
|-----|-----------|-----------|---------------|--------------|--------|
| Zilog Z80 | 0x00 | Pass | 0xFF | CMOS:00 U880:00 XF/YF:FF | Original NMOS design |
| Zilog Z8400 | 0x00 | Pass | 0xFF | CMOS:00 U880:00 XF/YF:FF | Standard NMOS Z80 |
| Zilog Z8400APS | 0x00 | Pass | 0xFF | CMOS:00 U880:00 XF/YF:FF | NMOS variant |
| Zilog Z08400 | 0x00 | Pass | 0xFF | CMOS:00 U880:00 XF/YF:FF | Similar NMOS CPU |
| Zilog Z84C00 | 0xFF | Pass | 0xFF | CMOS:2C U880:00 XF/YF:FF | Standard CMOS |
| Zilog Z84C0010PEG | 0xFF | Pass | 0xFF | CMOS:2C U880:00 XF/YF:FF | CMOS with enhanced timing |

### Licensed Production Variants
| CPU | CMOS Test | U880 Test | XF/YF Pattern | Test Results | Notes |
|-----|-----------|-----------|---------------|--------------|--------|
| Mostek MK3880N | 0x00 | Pass | 0xFF | CMOS:00 U880:00 XF/YF:FF | Zilog-compatible (licensed) |
| SGS/ST Z8400 | 0x00 | Pass | 0xFF | CMOS:00 U880:00 XF/YF:FF | Licensed production |
| SGS/ST Z80 | 0x00 | Pass | 0xFF | CMOS:00 U880:00 XF/YF:FF | Licensed production |
| Sharp LH0080A | 0x00 | Pass | 0xFF | CMOS:00 U880:00 XF/YF:FF | Licensed production |
| ST Z84C00AB | 0xFF | Pass | 0x3F | CMOS:2C U880:00 XF/YF:3F | Hybrid SCF/CCF behavior |

### Sharp Silicon Variants
| CPU | CMOS Test | U880 Test | XF/YF Pattern | Test Results | Notes |
|-----|-----------|-----------|---------------|--------------|--------|
| Sharp LH5080A | 0x00 | Pass | 0x30 | CMOS:00 U880:00 XF/YF:30 | CMOS silicon, NMOS-like behavior |

### NEC Clean-Room Implementations
| CPU | CMOS Test | U880 Test | XF/YF Pattern | Test Results | Notes |
|-----|-----------|-----------|---------------|--------------|--------|
| NEC D780C | 0x00 | Pass | 0xFD | CMOS:00 U880:00 XF/YF:FD | NMOS, lacks Q register implementation, simplified SCF/CCF flags |
| NEC D70008AC | 0xFF | Pass | 0x1F | CMOS:2C U880:00 XF/YF:1F | CMOS clean-room design, 99.9% compatibility |
| NEC D70008AC | 0xFF | Pass | 0x0D | CMOS:2C U880:00 XF/YF:0D | Specimen variation, same architecture |

### Toshiba CMOS Variants
| CPU | CMOS Test | U880 Test | XF/YF Pattern | Test Results | Notes |
|-----|-----------|-----------|---------------|--------------|--------|
| Toshiba TMPZ84C00AP | 0xFF | Pass | 0x3F | CMOS:2C U880:00 XF/YF:3F | Y flag always from A register |

### Eastern European Clones
| CPU | CMOS Test | U880 Test | XF/YF Pattern | Test Results | Notes |
|-----|-----------|-----------|---------------|--------------|--------|
| KR1858VM1 (Soviet) | 0x00 | Pass | 0xFF | CMOS:00 U880:00 XF/YF:FF | Generally Zilog-compatible |
| KR1858VM1 (overclocked) | 0x00 | Pass | 0xF4 | CMOS:00 U880:00 XF/YF:F4 | Quality varies by batch |

### Korean Clones
| CPU | CMOS Test | U880 Test | XF/YF Pattern | Test Results | Notes |
|-----|-----------|-----------|---------------|--------------|--------|
| GoldStar Z8400 | 0x00 | Pass | 0xFD | CMOS:00 U880:00 XF/YF:FD | Similar to NEC D780C |

### East German U880 Family
| CPU | CMOS Test | U880 Test | XF/YF Pattern | Test Results | Notes |
|-----|-----------|-----------|---------------|--------------|--------|
| MME U880 (newer) | Varies | Fail | 0xFF | Various CMOS, U880:01, XF/YF:FF | Carry bug present |
| MME U880 (older) | Varies | Fail | ≠0xFF | Various CMOS, U880:01, XF/YF:≠FF | Carry bug + variant flags |
| Thesys Z80 | Varies | Fail | 0xFF | Various CMOS, U880:01, XF/YF:FF | U880-compatible |
| Microelectronica MMN 80CPU | Varies | Fail | 0xFF | Various CMOS, U880:01, XF/YF:FF | U880-compatible |

### Quality Classifications
- **Licensed Production**: Exact Zilog compatibility (Mostek, SGS, Sharp LH0080A)
- **Clean-Room Compatible**: 99.9% compatibility with distinctive patterns (NEC)
- **Eastern Bloc Clones**: Generally compatible, quality varies by batch (KR1858VM1, U880)
- **CMOS Enhancements**: Enhanced timing and power efficiency (Z84C00 series)

## Detection Decision Tree

### Primary Classification
```
Step 1: Execute U880 Test (OUTI carry flag behavior)
│
├─ CARRY PRESERVED → U880 Clone Family
│  │
│  ├─ XF/YF = 0xFF → Newer U880 variants
│  │  └─ Result: MME U880 (new), Thesys Z80, Microelectronica MMN 80CPU
│  │
│  └─ XF/YF ≠ 0xFF → Older U880 variants  
│     └─ Result: MME U880 (old production)
│
└─ CARRY CLEARED → Genuine Z80 Family
   │
   Step 2: Execute CMOS Test (OUT (C),0 behavior)
   │
   ├─ OUTPUT = 0x00 → NMOS Technology Branch
   │  │
   │  Step 3a: Analyze XF/YF Pattern
   │  ├─ 0x30 → Sharp LH5080A (CMOS silicon, NMOS behavior)
   │  ├─ 0xFF → Standard NMOS Z80
   │  │  └─ Zilog Z80/Z8400, Mostek MK3880N, SGS/ST Z8400, Sharp LH0080A, KR1858VM1
   │  ├─ 0xFD → NEC NMOS Compatible
   │  │  └─ NEC D780C, GoldStar Z8400, possibly KR1858VM1
   │  ├─ 0xF4 → Overclocked Soviet Clone
   │  │  └─ KR1858VM1 (specific batch/overclock variant)
   │  └─ Other → Unidentified NMOS clone
   │
   └─ OUTPUT = 0xFF → CMOS Technology Branch
      │
      Step 3b: Analyze XF/YF Pattern
      ├─ 0xFF → Standard CMOS Z80
      │  └─ Zilog Z84C00
      ├─ 0x3F → Toshiba/ST Variants
      │  └─ Toshiba TMPZ84C00AP, ST Z84C00AB
      ├─ 0x00-0x1F (with complexity check) → NEC CMOS Compatible
      │  └─ NEC D70008AC (requires additional validation)
      └─ Other → Unidentified CMOS clone
```

### NEC D70008AC Special Detection
```
For CMOS results with XF/YF patterns requiring complex analysis:

Step 1: Check if XF/YF ≤ 0x1F (32 decimal)
├─ NO → Not NEC D70008AC (likely other CMOS clone)
└─ YES → Continue to Step 2

Step 2: Isolate lower 4 bits (XF/YF & 0x0F)
├─ Result < 0x03 → Not NEC D70008AC
└─ Result ≥ 0x03 → Continue to Step 3

Step 3: Check final validation (XF/YF & 0x03)
├─ Result = 0x00 → Not NEC D70008AC
└─ Result ≠ 0x00 → NEC D70008AC confirmed

Example valid patterns:
- 0x1F & 0x0F = 0x0F (≥ 0x03) & 0x03 = 0x03 (≠ 0x00) ✓
- 0x0D & 0x0F = 0x0D (≥ 0x03) & 0x03 = 0x01 (≠ 0x00) ✓
- 0x07 & 0x0F = 0x07 (≥ 0x03) & 0x03 = 0x03 (≠ 0x00) ✓

Note: Different NEC D70008AC specimens may show varying
XF/YF patterns (0x1F, 0x0D documented), but all follow
the same validation logic.
```

### Confidence Levels
- **High Confidence (>99%)**: U880 test, Standard Z80/Z84C00 patterns
- **Good Confidence (95-99%)**: Sharp LH5080A, Toshiba variants, NEC D780C
- **Moderate Confidence (85-95%)**: NEC D70008AC, KR1858VM1 variants
- **Low Confidence (<85%)**: Unknown clones, specimens with anomalous patterns

