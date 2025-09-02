# Z80 Microprocessor Variant Identification: Algorithmic Analysis and Implementation

This Z80 assembly implementation identifies processor variants using three detection algorithms. Sergey Kiselev originally developed the program in Intel 8080 assembly syntax for CP/M systems using Z80 SIO interrupt vector registers. Rui Ribeiro later translated and ported it to Timex 2068/2048 platforms, ZX Spectrum 128K/48K+AY systems, and ZX Spectrum 48K systems without AY.

## Historical Context

Intel began introducing CPUs with a proper `CPUID` instruction only in the mid-1990s, starting with the Pentium processor. Prior to this development, processor identification relied entirely on exploiting quirks and undocumented behaviors. This Z80 identification implementation exemplifies the techniques employed during that era—the systematic exploitation of implementation-specific behaviors, undocumented instructions, and silicon-level differences to create unique processor fingerprints. The methods documented herein represent the fundamental approach that was necessary for processor identification throughout the entire 8-bit and early 16-bit computing era.

After fifty years of community tinkering and reverse engineering, Z80 variants hold few hidden secrets and have been extensively documented by enthusiasts, researchers, and hardware developers. The detection methods presented here build upon decades of collective knowledge about silicon-level implementation differences, manufacturing variations, and undocumented instruction behaviors that the community has systematically catalogued and verified across countless processor specimens.

## Practical Applications

**Hardware Authentication**: Identifying counterfeit or remarked processors, including Chinese forgeries such as U880 processors relabeled with laser-etched Zilog markings. Such forgeries present a real issue in the vintage computing market, as U880 processors behave quite differently from genuine Zilog Z80s and can cause strange issues or failures in Z80 congruency tests. This is additionally useful when CPU markings have faded with age or have been intentionally defaced, making visual identification unreliable or impossible.

**Hardware Diagnostics**: Identifying dead or decaying chips, though vintage Z80 processors have generally proven more resilient to aging than initially expected.

**Retro Computing**: Determining which specific CPU variant is installed in Z80-based retro computers, which can be crucial for compatibility, performance optimization, and historical accuracy in restoration projects.

**Emulation Development**: Serving as a benchmark to evaluate the accuracy of Z80 emulation, helping emulator developers ensure their implementations correctly replicate the behavioral differences between various Z80 family members.

## 1. NMOS/CMOS Technology Detection (`TESTCMOS`)

**Algorithm**: Exploits implementation-specific behavior of undocumented opcode `EDh 71h` (`OUT (C),0`) to distinguish between NMOS and CMOS silicon technologies.

**Implementation Differences**:
- **NMOS implementations**: The undocumented instruction `OUT (C),0` writes the value `0x00` to the target port
- **CMOS implementations**: The undocumented instruction `OUT (C),0` writes the value `0xFF` to the target port
- **Exception**: The Sharp LH5080A (CMOS) exhibits NMOS-like behavior and is classified as NMOS

**Operational Protocol**:
The global `TESTCMOS` routine serves as the main entry point and orchestrates the entire NMOS/CMOS detection process:

1. **Platform Detection**: The `TESTCMOS` routine calls the `ZXTYPE` function to auto-detect the target platform:
   - `0` = Standard 48K Spectrum (no AY chip, no Timex hardware) → `TESTCMOS` calls `TESTCMOSZX`
   - `1` = Spectrum with AY sound chip (128K, retrofitted 48K, or clone) → `TESTCMOS` calls `TESTCMOSAY`  
   - `2` = Timex 2048/2068 (Timex-specific control register) → `TESTCMOS` calls `TESTCMOSTMX`
   - `3` = ZX Spectrum 48K ULA hysteresis test (experimental) → `TESTCMOS` calls `TESTCMOSHYST`
2. **Interrupt Management**: `TESTCMOS` disables interrupts with `DI`, then re-enables with `EI` after test completion
3. **Platform-Specific Execution**: `TESTCMOS` dispatches to the appropriate hardware-specific implementation based on the `ZXTYPE` result
4. **Result**: `TESTCMOS` returns `0x00` for NMOS technology, `0xFF` for CMOS technology

### Platform Auto-Detection Algorithm (`ZXTYPE`):

The `ZXTYPE` routine performs sequential hardware detection to identify the specific ZX Spectrum variant by testing for distinctive hardware features in order of complexity:

**Test #1 - Timex Control Register Detection** (executed only if the AY test fails):
- **Target port**: `0FFh` (Timex control register)
- **Test procedure**: Read original value → save for restoration → write test pattern `3Ch` → read back → verify match → write second pattern `C3h` → read back → verify match
- **Detection logic**: If both test patterns read back correctly, positive Timex identification is confirmed → returns `ZXTYPE = 2`
- **State preservation**: The original control register value is restored to prevent system instability
- **Hardware coverage**: Timex 2048/2068 systems with functional control register

**Test #2 - AY Sound Chip Detection**:
- **Target ports**: `0FFFDh` (AY register select) and `0BFFDh` (AY data port)
- **Test procedure**: Select AY register 1 (tone generator B fine tune) → write test pattern `0Fh` → read back value
- **Detection logic**: If the readback matches the written value (`0Fh`), the AY chip is present → returns `ZXTYPE = 1`
- **Hardware coverage**: ZX Spectrum 128K, retrofitted 48K models, and compatible clones with AY sound chip

**Test #3 - Hysteresis Compatibility Test** (executed only if both AY and Timex tests fail):
- **Target port**: `0FEh` (ULA port)
- **Test procedure**: Performs a 3-iteration hysteresis validation test using alternating `OUT (C),0FFh` and `OUT (C),0` operations
- **Detection method**: Tests whether the EAR input (bit 6) responds reliably to voltage level changes
- **Validation logic**: 
  - Writes `0FFh` to ULA → reads bit 6 → should be set for hysteresis compatibility
  - Writes `0` to ULA → reads bit 6 → should be clear for hysteresis compatibility
  - Repeats the test 3 times for reliability confirmation
- **Result**: If all hysteresis tests pass → returns `ZXTYPE = 3` (hysteresis-compatible hardware)
- **Hardware coverage**: ZX Spectrum 48K or clone with appropriate EAR/MIC and speaker circuit coupling

**Default Classification**:
- If AY, Timex, and hysteresis tests all fail → returns `ZXTYPE = 0` (Standard 48K Spectrum)
- **Hardware coverage**: ZX Spectrum 48K, plus other variants without AY retrofit or hysteresis compatibility

### Platform-Specific Implementations:

**TESTCMOSAY (AY Sound Chip Platforms)**:
- **Target**: AY register 1 (tone generator B fine tune) via ports `0FFFDH` (select) and `0BFFDH` (data)
- **Process**: Called by `TESTCMOS` when `ZXTYPE` returns 1. Selects AY register 1, executes `OUT (C),0`, then reads back the value via `IN A,(C)`
- **Value processing**: `AND 0FH` masks to the 4-bit range (AY registers store max `0FH`, YM2149 up to `1FH`)
- **Result logic**: A zero value indicates NMOS; non-zero indicates CMOS (converted to `0xFF`)

**TESTCMOSTMX (Timex 2048/2068 Platforms)**:
- **Target**: Timex Control Register at port `0FFH`
- **Process**: Called by `TESTCMOS` when `ZXTYPE` returns 2. Reads/saves original value → executes `OUT (C),0` → reads result → restores original value
- **State preservation**: A full register save/restore cycle to prevent system disruption
- **Direct result**: Returns the exact value written by the undocumented instruction

**TESTCMOSZX (ZX Spectrum 48K without AY)**:
- **Target**: ULA at port `0FEH` using visual border detection method
- **Process**: Called by `TESTCMOS` when `ZXTYPE` returns 0. Uses visual feedback for NMOS/CMOS detection
- **Detection method**: Executes `OUT (C),0` to ULA port `0FEH` and prompts user to observe border color
- **User interaction**: Displays message asking user to identify border color (black or white)
- **Key mapping**: W key = white border (CMOS), B key = black border (NMOS)
- **Result processing**: Returns `0x00` for NMOS (black border), `0xFF` for CMOS (white border)

**TESTCMOSHYST (ZX Spectrum 48K Hysteresis - Experimental)**:
- **Target**: ULA at port `0FEH`, exploiting electrical hysteresis characteristics
- **Process**: Called by `TESTCMOS` when `ZXTYPE` returns 3. Uses voltage level differences between NMOS and CMOS implementations
- **Prerequisites**: Hardware must pass the integrated hysteresis compatibility test in `ZXTYPE`
- **Experimental status**: Only tested on ZX Spectrum 48K
- **Voltage levels**: NMOS outputs 0.3V (bits 3,4 = 00), CMOS outputs 3.7V (bits 3,4 = 11)
- **Timing critical**: A 7-iteration `DJNZ` loop with `LD IX,0` provides 219 T-states (≈62.6μs) propagation delay
- **Detection mechanism**: Read ULA bit 6 (EAR input); `AND 040H` isolates the hysteresis state
- **Result processing**: Bit 6 clear = NMOS (`XOR A` → `0x00`); bit 6 set = CMOS (preset `0xFF`)

### Visual Border Detection Method (`TESTCMOSZX`)

The `TESTCMOSZX` routine implements a user-interactive visual detection method as the primary approach for ZX Spectrum 48K systems. This method provides reliable detection across all hardware revisions by leveraging the observable visual effects of the `OUT (C),0` instruction on the ULA's border generation.

**Visual Detection Principle**:
When the undocumented `OUT (C),0` instruction targets the ULA port (`0FEH`), different Z80 implementations produce visually distinct border colors due to their varying output voltage levels. The user observes the border color change and provides input to confirm the detection.

**Implementation Details**:
```assembly
TESTCMOSZX:
    PUSH    DE
    LD      DE,MESBW        ; Load "Border White/Black?" message
    CALL    PRINTSTR        ; Display user prompt
    POP     DE
    LD      C,0FEh          ; Target ULA port
    DB      0EDH, 071H      ; Execute OUT (C),0
                            ; NMOS: produces black border
                            ; CMOS: produces white border

wait_key:
    ; Check W key (White border - CMOS detection)
    ld   b,KBD_HROW_3       ; port FBFE (Q-W-E-R-T row)
    in   a,(c)              ; Read keyboard state
    scf                     ; Set carry flag for CMOS result
    bit  1,a                ; Test W key (bit 1)
    jr   z,key_pressed      ; Jump if W pressed

    ; Check B key (Black border - NMOS detection)  
    ld   b,KBD_HROW_8       ; port 7FFE (B-N-M-SS-Space row)
    in   a,(c)              ; Read keyboard state
    scf                     ; Set carry flag
    ccf                     ; Clear carry flag for NMOS result
    bit  4,a                ; Test B key (bit 4)
    jr   z,key_pressed      ; Jump if B pressed
    jr   wait_key           ; Continue polling

key_pressed:
    ld   a,$ff              ; Preset CMOS result
    jr   c,LEAVEZX          ; If carry set (W key), return CMOS
    xor  a                  ; Clear A for NMOS result
LEAVEZX:
    ret                     ; Return: A=0x00 for NMOS, A=0xFF for CMOS
```

**User Interface**:
- **Prompt message**: Displays instruction asking user to identify border color
- **Key mapping**: 
  - **W key**: White border observed → CMOS processor (returns `0xFF`)
  - **B key**: Black border observed → NMOS processor (returns `0x00`)
- **Keyboard scanning**: Uses standard ZX Spectrum keyboard matrix scanning
- **Visual confirmation**: Relies on user observation of the actual border color change

**Advantages of Visual Method**:
- **Universal compatibility**: Works on all ZX Spectrum 48K hardware revisions
- **Reliability**: Not affected by circuit variations between Issue 2/3 and later models
- **Simplicity**: Straightforward implementation without complex timing requirements
- **User verification**: Provides immediate visual confirmation of the test results

### Hysteresis Compatibility Test (`HYSTE` section in `ZXTYPE`)

The hysteresis compatibility test is integrated directly into the `ZXTYPE` routine and determines whether the hardware supports reliable hysteresis-based NMOS/CMOS detection. This experimental test is performed automatically when neither AY nor Timex hardware is detected, and is specifically designed for ZX Spectrum 48K hardware.

**Experimental Hardware Limitation**:
This hysteresis detection method is experimental and may be limited to early ZX Spectrum 48K hardware revisions due to their specific EAR/MIC circuit coupling characteristics. Additionally, **Brazilian TK clones (used in Latin America) present a unique compatibility constraint**: while they share similar EAR/MIC/Speaker circuitry with ZX Spectrum systems, hysteresis detection functions reliably only on Brazilian TK clones equipped with **Sinclair Ferranti ULAs**. Brazilian TK clones utilizing **Microdigital ULAs** do not exhibit the necessary hysteresis behavior for this detection method, despite possessing functionally identical audio circuits. This ULA-specific limitation demonstrates that the hysteresis technique depends upon the precise electrical characteristics of the Sinclair Ferranti ULA implementation rather than merely the surrounding analog circuitry. This hardware constraint precisely explains why the compatibility test exists—to determine whether the specific ULA supports reliable hysteresis detection before attempting automated detection, with visual detection serving as the guaranteed fallback method.

**Test Implementation**:
```assembly
HYSTE:  
    LD      B,3             ; 3-iteration validation test
HYSTEL1:
    PUSH    BC              ; Save loop counter
    
    ; Test high voltage state (should set EAR bit)
    LD      A,0FFh          ; High voltage output
    LD      BC,10FEh        ; B=1 iteration, C=FEh (ULA port)
HL2:
    OUT     (C),A           ; Write FFh to ULA
    DJNZ    HL2             ; Short propagation delay
    POP     BC              ; Restore loop counter  
    IN      A,(C)           ; Read ULA state
    AND     040h            ; Isolate EAR input (bit 6)
    JR      Z,RTYPE2        ; If bit 6 clear, hysteresis failed
    
    PUSH    BC              ; Save loop counter again
    
    ; Test low voltage state (should clear EAR bit)
    XOR     A               ; Low voltage output (0)
    LD      BC,10FEh        ; B=1 iteration, C=FEh (ULA port)  
HL3:
    OUT     (C),A           ; Write 0 to ULA
    DJNZ    HL3             ; Short propagation delay
    POP     BC              ; Restore loop counter
    IN      A,(C)           ; Read ULA state
    AND     040h            ; Isolate EAR input (bit 6)
    JR      NZ,RTYPE2       ; If bit 6 set, hysteresis failed
    
    DJNZ    HYSTEL1         ; Repeat test 3 times
    
    ; All hysteresis tests passed
    LD      E,3             ; Set ZXTYPE = 3 (hysteresis compatible)
```

**Validation Logic**:
- **High voltage test**: Writes `0FFh` to the ULA; expects the EAR bit to be set (indicating voltage above the hysteresis threshold)
- **Low voltage test**: Writes `0` to the ULA; expects the EAR bit to be clear (indicating voltage below the hysteresis threshold)
- **Triple validation**: Repeats the complete test sequence 3 times to ensure consistent behavior
- **Failure conditions**: If any single test iteration fails, the routine exits with `ZXTYPE = 0`

**Hardware Requirements**:
- **Experimental limitation**: Only ZX Spectrum 48K tested and expected to work reliably
**Brazilian TK clone compatibility**: Brazilian TK clones (used in Latin America), while sharing similar EAR/MIC/Speaker circuitry, only support hysteresis detection when equipped with a **Sinclair Ferranti ULA**. Systems with **Microdigital ULAs** do not exhibit the necessary hysteresis behavior for this detection method, despite having identical audio circuitry
- **ULA-specific behavior**: The hysteresis detection exploits specific electrical characteristics of the Sinclair Ferranti ULA implementation that are not replicated in other ULA variants
- **Circuit coupling**: Requires EAR/MIC input circuits with sufficient coupling to detect ULA output voltage changes
- **Voltage thresholds**: ULA must exhibit clear hysteresis behavior with predictable switching thresholds
- **Timing sensitivity**: Relies on brief `DJNZ` delays for voltage propagation through analog circuitry

**Hysteresis Principle**:
The ULA's EAR input (bit 6 of port `0FEH`) exhibits hysteresis behavior - it maintains its previous state when input voltages fall within an intermediate range. The technique leverages the fact that NMOS and CMOS Z80 variants output different voltage levels when executing the undocumented `OUT (C),0` instruction.

**Experimental Implementation**:
```assembly
; Experimental hysteresis detection sequence  
ld      bc,30FEh         ; B=48 iterations, C=FEh (ULA port)
LOOP:
DB      0EDH, 071H       ; UNDOCUMENTED OUT (C),0 INSTRUCTION
                         ; WRITE 00 OR FF TO ULA
                         ; out bit 3,4 = 00 next in bit 6=0 (NMOS)
                         ; out bit 3,4 = 11 next in bit 6=1 (CMOS)
djnz    LOOP             ; Decrement B, loop for reliability
in      a,(ULA_PORT)     ; Read ULA register final state
and     040h             ; Isolate EAR input (bit 6)
```

**Timing Analysis**:
- **Setup**: `LD BC,30FEh` → 10 T-states
- **Loop execution** (48 iterations):
  - `OUT (C),0` → 11 T-states per iteration  
  - `DJNZ` → 13 T-states when taken (47 times), 8 T-states when not taken (final)
  - Loop total: 47×(11+13) + (11+8) = 1128 + 19 = 1147 T-states
- **Final read**: `IN A,(ULA_PORT)` → 11 T-states
- **Total timing**: 10 + 1147 + 11 = **1168 T-states** (≈333.7μs at 3.5MHz)

**Detection Strategy**:
The implementation provides an intelligent three-tier detection approach for ZX Spectrum 48K systems with automatic fallback:

1. **Primary Method - Visual Detection (`TESTCMOSZX`)**: Universal compatibility fallback for all hardware revisions using user-interactive border color observation (`ZXTYPE = 0`)
2. **Experimental Method - Hysteresis Detection (`TESTCMOSHYST`)**: Automated detection for hardware that passes the integrated hysteresis compatibility test (`ZXTYPE = 3`) - this is experimental and limited to early hardware, which is why the compatibility test exists
3. **Platform-Specific Methods**: AY-based detection (`ZXTYPE = 1`) and Timex-based detection (`ZXTYPE = 2`) for respective hardware

## 2. U880 Detection (`TESTU880`)

**Algorithm**: Exploits the behavioral difference in the MME U880 processor's implementation of the `OUTI` instruction with regard to carry flag handling.

**Implementation Differences**:
- **Genuine Z80**: The `OUTI` instruction clears the carry flag (Zilog reference behavior)
- **U880 processors**: The `OUTI` instruction leaves the carry flag unchanged

**Test Procedure**:
1. **Setup edge case**: `HL = 0FFFFH` (special case where the Zilog implementation clears carry)
2. **Port configuration**: `BC = 001FFH` (B=01H for 1 iteration, C=FFH for Timex Control Register)
3. **State preservation**: Read and save the original Timex Control Register value
4. **Flag preparation**: Set the carry flag with `SCF`
5. **Critical instruction**: Execute `OUTI` (`DB 0EDH, 0A3H`) - outputs `(HL)` to port C
6. **State restoration**: Write the original register value back to the Timex Control Register
7. **Result evaluation**: Check the carry flag state after `OUTI` execution

**Hardware Interface**: 
- **Universal port targeting**: Uses port `0FFH` across all platforms
  - **Timex systems**: Targets the Timex Control Register with full state preservation
  - **Other platforms**: Writes to unused port `0FFH` (harmless no-operation)
- **State management**: Reads the original port value, executes the test, restores the original value
- The specific value written is irrelevant; only the carry flag behavior matters

**Result Logic**:
- **Carry flag set after `OUTI`**: U880 processor detected (returns `0x01`)
- **Carry flag clear after `OUTI`**: Genuine Z80 processor (returns `0x00`)

**Assembly Implementation Details**:
```assembly
ld hl,0FFFFH            ; Memory address for OUTI (edge case test)
ld bc,001FFH            ; B=1 iteration, C=port 0FFh (safe on all systems)
ld (hl),b               ; Store test value at (HL)
scf                     ; Set carry flag - this is the key test
outi                    ; OUTI instruction - bug test point
ld a,0                  ; Prepare result (clear A)
adc a,a                 ; Add carry to A (0=Z80, 1=U880)
```

This test leverages the fact that the U880's `OUTI` implementation does not conform to Zilog's carry flag clearing behavior in the edge case where `HL=0FFFFH`, thereby creating a reliable detection signature.

## 3. Undocumented Flag State Analysis (`TESTXY`)

**Algorithm**: Performs statistical analysis of undocumented flag bits XF (FLAGS.3) and YF (FLAGS.5) during `SCF` instruction execution to create implementation-specific fingerprints.

**Implementation Differences**:
Different Z80 silicon implementations exhibit different behavioral patterns regarding undocumented flag manipulation when the `SCF` instruction modifies processor state. The analysis examines four test vectors with statistical encoding of the resulting behavioral patterns.

**SCF Behavior Analysis**: The `SCF` (Set Carry Flag) instruction exhibits manufacturer-specific side effects on undocumented XF and YF flags. Different silicon implementations demonstrate varying degrees of deterministic versus random behavior when manipulating these undocumented flag bits, requiring statistical sampling to characterize implementation signatures accurately.

### Test Vector Configuration:
The XYRESULT byte encodes four test conditions in bits `[7:6][5:4][3:2][1:0]`:

**Test Vector 1 - FLAGS=0, A with specific bit patterns**:
- **YF test**: FLAGS=0, A=(C|0x20)&0xF7 (A.5=1, A.3=0) → Result encoded in bits [7:6]
- **XF test**: FLAGS=0, A=(C|0x08)&0xDF (A.3=1, A.5=0) → Result encoded in bits [5:4]

**Test Vector 2 - A=0, FLAGS with specific bit patterns**:
- **YF test**: A=0, FLAGS=(C|0x20)&0xF7 (F.5=1, F.3=0) → Result encoded in bits [3:2]  
- **XF test**: A=0, FLAGS=(C|0x08)&0xDF (F.3=1, F.5=0) → Result encoded in bits [1:0]

### Implementation Details:

**Sampling Loop Structure**:
```assembly
ld c,0FFH               ; 256-iteration counter (0xFF down to 0x00)
TESTXY1:
    ; Test Vector 1: FLAGS=0, A=(C|0x20)&0xF7
    ld e,00H            ; FLAGS = 0
    ld a,c
    or 020H             ; Set A.5 = 1
    and 0F7H            ; Clear A.3 = 0
    ld d,a              ; A = (C|0x20)&0xF7
    push de / pop af    ; Load A and FLAGS
    scf                 ; Execute SCF instruction
    call STOREYCOUNT    ; Count YF flag states
    
    ; [Similar pattern for other 3 test vectors]
    dec c
    jp nz,TESTXY1       ; Continue until C=0
```

**Flag Isolation and Counting**:
- **STOREYCOUNT**: Isolates YF (FLAGS.5) with `AND 20H`, then increments the counter at (HL) if the flag is set
- **STOREXCOUNT**: Isolates XF (FLAGS.3) with `AND 08H`, then increments the counter at (HL) if the flag is set
- **Counter array**: `XFYFCOUNT` - 4 bytes storing statistical counts for each test vector

### Statistical Classification Method:
Each test vector undergoes 256-iteration sampling with counter-based statistical aggregation. The classification applies the following threshold-based categorization:
- Counter = `0x00` → Binary encoding `00b` (flag never asserted)
- Counter = `0x01`-`0x7F` → Binary encoding `01b` (flag rarely asserted)  
- Counter = `0x80`-`0xFE` → Binary encoding `10b` (flag frequently asserted)
- Counter = `0xFF` → Binary encoding `11b` (flag always asserted)

**Result Encoding Process**:
```assembly
TESTXY2:
    rla / rla           ; Shift result left by 2 bits
    and 0FCH            ; Clear lower 2 bits
    ld b,a              ; Store shifted result
    ld a,(hl)           ; Load counter value
    cp 7FH              ; Compare with 0x7F threshold
    ; [Threshold logic determines 2-bit encoding]
    or b                ; Combine with previous results
    inc hl / dec c      ; Next counter
    jp nz,TESTXY2       ; Process all 4 counters
```

### Implementation-Specific Signatures:
- **`0xFF` (11111111b)**: XF/YF flags always asserted across all test vectors
- **`0x3F` (00111111b)**: YF flag never asserted when A.5=1 (Toshiba TMPZ84C00AP signature)
- **`0x30` (00110000b)**: Distinctive pattern of Sharp LH5080A silicon implementation
- **`0xFD` (11111101b)**: XF flag shows non-deterministic assertion when FLAGS.3=1 (NEC D780C signature)
- **`0xF4` (11110100b)**: Characteristic pattern of the KR1858VM1 silicon implementation
- **`0x00`-`0x1F`**: Complex random patterns requiring secondary validation (NEC D70008AC signatures)

## Documented Test Results

Based on the original repository's Results.md documentation, the implementation has been successfully validated across numerous Z80 variants with the following representative outcomes:

**Standard NMOS Z80 implementations** (Zilog Z8400APS, Mostek MK3880N):
- Raw results: CMOS: 00 U880: 00 XF/YF: FF
- XF/YF flags test: C000C000
- Classification: Zilog Z80, Zilog Z08400 or similar NMOS CPU (full Q register implementation with complete SCF/CCF behavior dependency)

**Standard CMOS Z80 implementations** (Zilog Z84C0010PEG):
- Raw results: CMOS: 2C U880: 00 XF/YF: FF
- XF/YF flags test: C000C000
- Classification: Zilog Z84C00 (CMOS implementation with enhanced timing stability and lower power consumption)

**Toshiba CMOS variants** (TMPZ84C00AP):
- Raw results: CMOS: 2C U880: 00 XF/YF: 3F
- XF/YF flags test: 8000C000
- Classification: Toshiba TMPZ84C00AP, ST Z84C00AB (hybrid SCF/CCF behavior - Y flag always from A register)

**NEC variants** demonstrating distinctive patterns:
- **NEC D780C**: Raw results: CMOS: 00 U880: 00 XF/YF: FD (lacks Q register implementation, simplified SCF/CCF flags)
- **NEC D70008AC**: Raw results: CMOS: 2C U880: 00 XF/YF: 1F and Raw results: CMOS: 2C U880: 00 XF/YF: 0D (clean-room design with 99.9% compatibility)

**Licensed and compatible variants**:
- **Mostek MK3880N**: Zilog-compatible behavior (licensed production)
- **SGS/ST Z80**: Zilog-compatible behavior (licensed production) 
- **Soviet КР1858ВМ1**: Generally Zilog-compatible but with quality variations depending on the manufacturing batch

## CPU Identification Logic

**Manufacturing Categories and Detection Implications**:

**Licensed Production**: Mostek, SGS, Sharp, and Siemens variants exhibit Zilog-compatible behavior across all three detection algorithms, typically yielding results identical to those of original Zilog processors.

**Clean-Room Compatible**: NEC implementations (D780C, D70008AC) demonstrate 99.9% compatibility with distinctive XF/YF flag patterns due to internal architecture differences, particularly the absence of Q register implementation in some variants.

**Eastern Bloc Clones**: Soviet КР1858ВМ1 and East German U880 processors exhibit varying quality control with generally compatible behavior but occasional deviations in undocumented instruction handling and timing precision.

**CMOS Enhancements**: Modern CMOS variants (Zilog Z84C00, ST Z84C00AB, Harris CD1400) provide enhanced timing stability and lower power consumption while maintaining full instruction compatibility.

### Decision Tree:
```
1. Primary evaluation: U880 variant assessment
   If U880 detected (ISU880 ≠ 0):
     └─ If XYRESULT = 0xFF → "Newer MME U880, Thesys Z80, Microelectronica MMN 80CPU"
     └─ Else → "Older MME U880"

2. Secondary evaluation: Technology assessment
   If NMOS detected (ISCMOS = 0):
     └─ If XYRESULT = 0x30 → "Sharp LH5080A"
     └─ If XYRESULT = 0xFF → "Zilog Z80, Zilog Z08400 or similar NMOS CPU
                              Mostek MK3880N, SGS/ST Z8400, Sharp LH0080A, KR1858VM1"
     └─ If XYRESULT = 0xFD → "NEC D780C, GoldStar Z8400, possibly KR1858VM1"
     └─ If XYRESULT = 0xF4 → "Overclocked KR1858VM1"
     └─ Else → "Unknown NMOS Z80 clone"

   If CMOS detected (ISCMOS ≠ 0):
     └─ If XYRESULT = 0xFF → "Zilog Z84C00"
     └─ If XYRESULT = 0x3F → "Toshiba TMPZ84C00AP, ST Z84C00AB"
     └─ If XYRESULT ≤ 0x1F AND (XYRESULT & 0x0F) ≥ 0x03 → "NEC D70008AC"
         (Complex logic: validates if low nibble ≥ 3 and high nibble ≤ 1)
     └─ Else → "Unknown CMOS Z80 clone"
```

**Key Insights**

**Why these tests work**:
1. **Undocumented instructions**: Different manufacturers implemented undocumented opcodes with varying behaviors
2. **Flag behavior**: The handling of undocumented XF/YF flags differs significantly between implementations  
3. **Implementation differences**: Behavioral differences (such as the `OUTI` flag handling between Z80 and U880) create unique identifying signatures
4. **Statistical approach**: Multiple iterations account for processors with inconsistent behavior patterns

**Advanced Detection Methods**:
- **Sharp LH5080A anomaly**: This CMOS processor exhibits NMOS-like behavior in the `OUT (C),0` test, requiring special handling within the NMOS branch
- **XYRESULT encoding**: Uses specific bit positions for different test combinations, enabling behavioral fingerprinting
- **NEC D70008AC detection**: Uses bit masking and range checking to identify this processor's inconsistent patterns
- **Hierarchical classification tree**: Implements a priority system—U880 detection first, followed by NMOS/CMOS branching with value matching

## Hardware Platform Implementations

**CP/M Implementation (Sergey Kiselev)**:
- Targets RS232 UART (SIO) interrupt vector registers within CP/M environments
- Uses Intel 8080 assembly syntax with the CP/M ASM assembler
- Supports RC2014 SIO modules and Small Computer Central RCBus architectures (SC725)
- Includes a modifiable SIOBC constant for RS232 UART hardware adaptation
- TESTCMOS uses RS232 UART interrupt vector registers with register pointer management
- TESTU880 uses the same RS232 UART hardware ports as TESTCMOS

**Unified Auto-Detection Implementation (Rui Ribeiro)**:
Rui Ribeiro's implementation provides a single binary that automatically detects the target platform and dispatches to the appropriate hardware-specific routine. The system uses the `ZXTYPE` function for platform identification and routes to specialized detection routines:

**TESTCMOSTMX Routine (Timex 2068/2048 platforms)**:
- **Target hardware**: Timex Control Register at port `0FFH` with full state preservation
- **Process flow**: Read original value → save to register B → execute `OUT (C),<immediate>` → read result to register C → restore original value → return result from register C
- **Platform detection**: Auto-detected by testing control register write/read functionality with two test patterns (0x3C and 0xC3)
- **Hardware migration**: Required two-stage adaptation from Z80 SIO interrupt vector registers to the Timex Control Register

**TESTCMOSAY Routine (ZX Spectrum 128K/48K+AY platforms)**:
- **Target hardware**: AY register 1 (tone generator B fine tune) for TESTCMOS latching
- **Port interface**: Uses ports `0FFFDH` (AY register select port) and `0BFFDH` (AY data port) with full 16-bit decoding
- **Detection method**: TESTCMOS writes and reads back the `OUT (C),0` result from AY register 1
- **Universal compatibility**: TESTU880 outputs to unused port `0FFH` since only carry flag behavior matters

**TESTCMOSZX Routine (ZX Spectrum 48K without AY)**:
- **Target hardware**: ULA at port `0FEH` using visual border detection method
- **Process flow**: Display user prompt → execute `OUT (C),0` → wait for user keypress → return result based on user input
- **Detection method**: Uses visual feedback for NMOS/CMOS detection by observing border color changes
- **User interaction**: Displays message asking user to identify border color (black or white)
- **Key mapping**: W key = white border (CMOS), B key = black border (NMOS)
- **Universal compatibility**: Works on all ZX Spectrum 48K hardware revisions regardless of circuit improvements

**TESTCMOSHYST Routine (ZX Spectrum 48K Hysteresis - Experimental)**:
- **Target hardware**: ULA electrical hysteresis at port `0FEH` using the undocumented `OUT (C),0` instruction
- **Process flow**: Execute `OUT (C),0` → timing critical delay → read EAR input → process hysteresis state → return result
- **NMOS behavior**: `OUT (C),0` outputs bits 3,4 = 00 (≈0.3V); subsequently `IN A,(0FEH)` bit 6 reads as 0
- **CMOS behavior**: `OUT (C),0` outputs bits 3,4 = 11 (≈3.7V); subsequently `IN A,(0FEH)` bit 6 reads as 1
- **Timing critical loop**: 7-iteration `DJNZ` loop with `LD IX,0` provides precise 219 T-states (≈62.6 microseconds) delay for electrical propagation
- **Result processing**: `AND 040H` isolates bit 6 (EAR input); returns `0x00` for NMOS or `0xFF` for CMOS
- **Hardware limitation**: Experimental method that might only work on ZX Spectrum 48K models
- **Fallback detection**: Auto-selected as automated method when hysteresis compatibility test passes (`ZXTYPE = 3`)

## Development Environment

**Original Platform and Adaptation**:
- Sergey's implementation uses Intel 8080 assembly syntax with the CP/M ASM assembler
- Designed for operation under CP/M and ZSDOS operating systems with Z80 SIO hardware ports

**Rui's Adaptations**:
- **Assembly syntax conversion**: Transformed from Intel 8080 assembly syntax to Zilog Z80 assembly syntax, including:
  - Register naming conventions (H,L → HL; D,E → DE; B,C → BC)
  - Instruction mnemonics (MOV → LD; CMP → CP; JMP → JP; CALL unchanged)
  - Addressing modes and operand syntax (MOV A,M → LD A,(HL))
  - Conditional jump syntax (JZ → JP Z; JNZ → JP NZ)
- **Development toolchain migration**: From the CP/M ASM assembler to the Pasmo assembler for Z80/ZX Spectrum compatibility
- **Hardware port adaptation**: Migration from Z80 SIO interrupt vector registers to platform-specific I/O ports
- **System call optimization**: Replaced CP/M BDOS wrapper with native platform-specific routines; ZX Spectrum version uses RST $10 for character printing
- **Machine code optimization**: Applied various Z80-specific optimizations to improve code efficiency and reduce size
- **Debugging and validation** were performed using the QtSpecem/debugZ80 development environment  
- Program entry point established at address `8000H` with optimized machine code utilizing Z80-specific enhancements
- During development, a bug in the `OUT (C),0` implementation in QtSpecem was identified and corrected, ensuring accurate NMOS/CMOS detection functionality

## Conclusion

This implementation demonstrates silicon-level hardware fingerprinting methods through systematic exploitation of undocumented processor behaviors and statistical validation techniques. **This represents CPU identification as accurate as possible with 1970s/1980s technology.** Unlike modern CPUID instructions that can be easily modified by CPU manufacturers, firmware, or hypervisors to display arbitrary values, these behavioral detection methods probe the actual silicon implementation and cannot be trivially spoofed. The statistical sampling, undocumented instruction exploitation, and electrical characteristic analysis employed here push the boundaries of deterministic processor identification using only the tools and techniques accessible to that technological era.

Test results documented in the original repository demonstrate the algorithm's effectiveness across multiple processor generations and manufacturing implementations, showcasing how systematic analysis of undocumented behaviors can create reliable identification signatures even in the absence of official processor identification mechanisms.

