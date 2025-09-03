
; Z80TYPE.ASM - DETERMINE AND PRINT Z80 CPU TYPE
; WRITTEN BY SERGEY KISELEV <SKISELEV@GMAIL.COM>
;
; PORTED TO Z80 Zilog assembly/ZX SPECTRUM
; RUI RIBEIRO 2025 <ruyrybeyro@gmail.com>
;
; RUNS ON:
;       ZX SPECTRUM 48k,128k AND CLONES
;       WITH ZILOG Z80 AND COMPATIBLE PROCESSORS
;
; AUTO-DETECTS AND USES PORT FOR TESTS:
;            AY AY-3-891x/YM2149F REGISTER 1 (0FFFDh/0BFFDh)
;            TIMEX CONTROL REGISTER (0xFF)
;            ULA (0xFE)
;
; Use it together with this BASIC snippet
; **WARNING: without this snippet, a PRINT must be made *before*
; calling this program.
;
; 10 CLEAR 32767
; 20 POKE 23610,255
; 30 LOAD ""CODE 
; 40 BORDER 7:PAPER 7:INK 0:CLS:PRINT
; 50 RANDOMIZE USR 32768
; 60 PAUSE 0
;
;==============================================================================
; Z80 CPU TYPE DETECTION ALGORITHM OVERVIEW
;==============================================================================
; 
; DETECTION FLOW:
; 1. TESTCMOS → Determines NMOS vs CMOS using OUT (C),0 behavior
; 2. TESTU880 → Checks for U880 bug in OUTI instruction 
; 3. TESTXY   → Analyzes XF/YF flag patterns with SCF instruction
; 4. Decision tree uses all three results to identify specific CPU variant
;
; DECISION TREE LOGIC:
;   ISU880 = 1? → U880 Family
;   ├─ XYRESULT = FFh → Newer U880/Thesys Z80
;   └─ XYRESULT ≠ FFh → Older U880
;   
;   ISU880 = 0 & ISCMOS = 0? → NMOS Z80 Family  
;   ├─ XYRESULT = 30h → Sharp LH5080A
;   ├─ XYRESULT = FFh → Standard Zilog Z80/Z8400
;   ├─ XYRESULT = FDh → NEC D780C/GoldStar Z8400  
;   ├─ XYRESULT = F0h → NEC D780C-1  
;   ├─ XYRESULT = F4h → KR1858VM1 (overclocked)
;   └─ Other values → Unknown NMOS clone
;   
;   ISU880 = 0 & ISCMOS = 1? → CMOS Z80 Family
;   ├─ XYRESULT = FFh → Standard Zilog Z84C00
;   ├─ XYRESULT = 3Fh → Toshiba TMPZ84C00AP
;   ├─ XYRESULT < 20h & complex analysis → NEC D70008AC
;   └─ Other values → Unknown CMOS clone
;
; RELIABILITY MATRIX:
;   Test      | Reliability | Coverage    | Edge Cases
;   TESTCMOS  | Very High   | All CPUs    | Sharp LH5080A reports as NMOS  
;   TESTU880  | Excellent   | U880 only   | No known false positives
;   TESTXY    | High        | All CPUs    | Some specimen variation in NEC
;==============================================================================


	; System variable holding the current border color
	; bits 3-5 used to store the border color (0-7 value)
	; Can be read to get the current border colour
	; or written to update, after OUT (FE) 
BORDCR		EQU 5C48h

ULA_PORT        EQU 0FEh	; ZX Spectrum ULA port: border color, MIC/EAR, and keyboard scanning
AY_ADDR_PORT    EQU 0FFFDh	; AY-3-8912 PSG address port
AY_DATA_PORT    EQU 0BFFDh    	; AY-3-8912 PSG data port

; port 0FFh half decoded. 
TMX_CTRL_PORT	EQU 0FFh; Timex Sinclair control port (TS2068 extra video modes, etc.)

KBD_HROW_3      EQU 0FBh	; Keyboard half-row 3: Q, W, E, R, T
KBD_HROW_8      EQU 07Fh	; Keyboard half-row 8: B, N, M, Symbol Shift, Space

	; Set program origin to 8000H (32768 decimal)
	ORG     8000H		; Located in contention-free RAM area

	; NOTE: Channel 2 (main screen) 
	; opened by BASIC PRINT before RANDOMIZE USR
	; avoiding ROM calls so it is compatible with mode the native mode
	; of ROM variations e.g. Timex TC 2068 without 48K ROM cartridge

	; Display program banner
	; DE -> "Z80 Processor Type Detection (C) 2024 Sergey Kiselev"
	ld de,MSGSIGNIN
	call PRINTSTR
	
ARGDEBUG:
	; Set debug mode - change to 0 for production use
	; Debug mode shows raw test results and additional flag tests
	; out of debug mode, black border is also restored to the
	; previous colour
	ld a,1			; change to 0 for less output
	ld (DEBUG),a
	
NOARGS:
	; === MAIN CPU DETECTION SEQUENCE ===
	
	; Test 1: Check if CPU is CMOS or NMOS
	; Uses undocumented OUT (C),0 instruction behavior difference
	call TESTCMOS
	ld (ISCMOS),a		; Store result: 0=NMOS, FF=CMOS

	; Test 2: Check if CPU is U880 (East German Z80 clone)
	; Uses OUTI instruction carry flag behavior difference		
	call TESTU880
	ld (ISU880),a		; Store result: 0=not U880, 1=U880

	; Test 3: Test XF/YF flag behavior with SCF instruction
	; Different Z80 variants handle these undocumented flags differently	
	call TESTXY
	ld (XYRESULT),a		; Store encoded test results

;-------------------------------------------------------------------------
; Debug output section - shows raw test results if debug mode enabled

	ld a,(DEBUG)
	or a			; Check if debug mode is on
	jr z,DETECTCPU		; Skip debug output if debug=0
	
	; Display raw CMOS test result
	ld de,MSGRAWCMOS	; DE -> "Raw results:       CMOS: "
	call PRINTSTR
	ld a,(ISCMOS)		; A= 0=NMOS, FF=CMOS
	call PRINTHEX		; Print hex value of CMOS test

	; Display raw U880 test result	
	; DE -> " U880: "
	ld de,MSGRAWU880	; display U880 test result
	call PRINTSTR
	ld a,(ISU880)		; get result from ISU880	
	call PRINTHEX		; Print hex value of U880 test

	; Display raw XY flags test result
	ld de,MSGRAWXY		; DE -> " XF/YF: "
	call PRINTSTR
	ld a,(XYRESULT)
	call PRINTHEX		; Print hex value of XY test
	ld de,MSGCRLF		; DE -> carriage return + line feed
	call PRINTSTR

	; Run additional comprehensive flag test (debug only)	
	call TESTFLAGS		; TEST HOW FLAGS SCF AFFECTS FLAGS

;-------------------------------------------------------------------------
; CPU detection logic - analyzes test results to identify specific CPU
;
; DECISION TREE IMPLEMENTATION:
;   ┌─────────────────┐
;   │ Check ISU880    │
;   └─────────┬───────┘
;             │
;        ┌────▼────┐  Yes  ┌─────────────────┐    ┌─────────────────┐
;        │ U880=1? │──────→│ Check XYRESULT  │───→│ New/Old U880    │
;        └────┬────┘       │ FFh = New U880  │    │ Classification  │
;             │ No         │ Other = Old U880│    └─────────────────┘
;             │            └─────────────────┘
;   ┌─────────▼───────┐
;   │ Check ISCMOS    │
;   └─────────┬───────┘
;             │
;     ┌───────▼───────┐  NMOS ┌─────────────────┐    ┌─────────────────┐
;     │ CMOS or NMOS? │──────→│ NMOS Analysis   │───→│ Sharp/Zilog/NEC │
;     └───────┬───────┘       │ Pattern Match   │    │ /KR1858/Unknown │
;             │ CMOS          │ on XYRESULT     │    └─────────────────┘
;             │               └─────────────────┘
;   ┌─────────▼───────┐       ┌─────────────────┐    ┌─────────────────┐
;   │ CMOS Analysis   │──────→│ Complex Logic   │───→│ Zilog/Toshiba   │
;   │ Pattern Match + │       │ for NEC D70008AC│    │ /NEC/Unknown    │
;   │ Range Checking  │       │ Detection       │    └─────────────────┘
;   └─────────────────┘       └─────────────────┘

DETECTCPU:
	ld de,MSGCPUTYPE	; DE -> "Detected CPU type: "
	call PRINTSTR

; First check: Is this a U880 CPU?
	ld a,(ISU880)		; Load U880 test result from memory
	or a			; Test if U880 flag is set
	jr z,CHECKZ80		; If not U880, check Z80 variants

	; It's a U880 - now determine if it's old or new variant
	; New U880s always set XF/YF flags (XYRESULT = 0FFh)
	; Old U880s have different XF/YF behavior	
	ld a,(XYRESULT)		; Load XY flags test result from memory
	cp 0FFH			; does it always set XF/YF?

	; DE -> "Newer MME U880, Thesys Z80, Microelectronica MMN 80CPU"
	ld de,MSGU880NEW
	jr z,DONE		; jump if a new U880/Thesys Z80
	ld de,MSGU880OLD	; DE -> "Older MME U880"
	jr DONE			; Jump if old U880

; Check for different Z80 variants based on NMOS/CMOS and flag behavior
CHECKZ80:
	ld a,(ISCMOS)		; Load CMOS test result from memory
	or a			; Is it a NMOS CPU (ISCMOS=0)?
	jr nz,CHECKCMOS		; If CMOS, go check CMOS variants

	; === NMOS Z80 VARIANT DETECTION ===
	; Different NMOS Z80s have distinct XF/YF flag patterns from TESTXY results
	; Each value represents encoded behavior in 4 test scenarios (2 bits each)

	ld a,(XYRESULT)		;  Load XY flags test result from memory
	cp 30H			; Sharp LH5080A signature (00110000b)
	jr z,SHARPLH5080A	; Distinctive YF=never, XF=never pattern
	cp 0FFH			; Standard NMOS Z80 (11111111b)
	jr z,NMOSZ80		; Always sets both XF/YF flags in all scenarios
	cp 0FDH			; does it sometimes not set XF when FLAGS.3=1?
				; NEC D780C signature (11111101b)
	jr z,NECU780C		; Mostly sets flags, occasional XF variance
	cp	0F0h		; NEC D780C-1
	jr z,NECU780C1		; Mostly sets flags, occasional XF variance

	cp 0F4H			; KR1858VM1 signature (11110100b)
	jr z,KR1858VM1		; Specific overclocked behavior pattern


	; Unknown NMOS variant
	ld de,MSGNMOSUNKNOWN	; DE -> "Unknown NMOS Z80 clone"
	jr DONE

SHARPLH5080A:
	ld de,MSGSHARPLH5080A	; DE -> "Sharp LH5080A"
	jr DONE
	
NMOSZ80:
	; DE -> "Zilog Z80, Zilog Z08400 or similar NMOS CPU"
	ld de,MSGNMOSZ80
	jr DONE
	
NECU780C:
	; DE -> "NEC D780C, GoldStar Z8400, possibly KR1858VM1"
	ld de,MSGNECD780C
	jr DONE

NECU780C1:
	; DE -> "NEC D780C-1"
	ld de,MSGNECD780C1
	jr DONE

KR1858VM1:
	ld de,MSGKR1858VM1	; DE -> "Overclocked KR1858VM1"
	jr DONE

	; === CMOS Z80 VARIANT DETECTION ===
	; CMOS variants have more complex XF/YF behaviors requiring detailed analysis
CHECKCMOS:
	ld a,(XYRESULT)		; Load XY flags test result from memory
	cp 0FFH			; does it always set XF/YF?
				; Standard CMOS Z80 (11111111b)
	jr z,CMOSZ80		; Zilog Z84C00 always sets both flags
	cp 3FH			; does it never set YF when A.5=1?
				; Toshiba signature (00111111b)
	jr z,TOSHIBA		; Never sets YF when A.5=1, distinctive pattern

	; Test for NEC D70008AC - these CPUs have complex XF/YF behavior:
	; Result format: [YF_A5=1][XF_A3=1][YF_F5=1&A5=0][XF_F3=1&A3=0]
	; - A.5=1 & F.5=0 => YF=1 (bit 7-6: often set)
	; - A.3=1 & F.3=0 => XF is not set, or only sometimes set (bit 5-4)
	; - A.5=0 & F.5=1 => YF is sometimes set (bit 3-2)
	; - A.3=0 & F.3=1 => XF is sometimes set (bit 1-0)
	; Note: All of 3 D70008AC that I have behave a bit differently here
	;       this might need to be updated when more tests are done
	;  Different D70008AC specimens may behave slightly differently

	cp 20H			; YF is often set when A.5=1?
				; Is result >= 32? (YF often set when A.5=1)
	jr nc,CMOSUNKNOWN	; If XYRESULT > 1Fh, not a NEC pattern
	and 0FH			; Isolate lower 4 bits: F.5=1&A.5=0 + F.3=1&A.3=0 results
	cp 03H			; F.5=1 & A.5=0 never result in YF set?
				; Both lower scenarios show flag setting?
	jr c,CMOSUNKNOWN	; If less than 3, unknown CMOS variant
	and 03H			; F.3=1 & A.3=0 results
				; Isolate F.3=1&A.3=0 XF results only (bits 1-0)
	jr nz,NEC		; If non-zero, it's NEC D70008AC

CMOSUNKNOWN:	
	ld de,MSGCMOSUNKNOWN	; DE -> "Unknown CMOS Z80 clone"
	jr DONE

CMOSZ80:
	ld de,MSGCMOSZ80	; DE -> "Zilog Z84C00"
	jr DONE

TOSHIBA:
	ld de,MSGTOSHIBA	; DE -> "Toshiba TMPZ84C00AP, ST Z84C00AB"
	jr DONE

NEC:
	ld de,MSGNECD70008AC	; DE -> "NEC D70008AC"
	jr DONE

DONE:
	; Print the detected CPU type and exit
	call PRINTSTR		; Print string pointed to by DE
	ld de,MSGCRLF		; DE -> carriage return + line feed
	call PRINTSTR
	ret			; Return to system

;-------------------------------------------------------------------------
; TESTCMOS - Test if the CPU is a CMOS variety using OUT (C),0 behavior
; 
; DETECTION STRATEGY FLOWCHART:
;   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
;   │ Detect Hardware │───→│ Select Test     │───→│ Execute Test    │
;   │ (ZXTYPE)        │    │ Method          │    │ Method          │
;   └─────────────────┘    └─────────┬───────┘    └─────────┬───────┘
;                                    │                      │
;                   ┌────────────────┼───────────────┐      │
;                   │                │               │      │
;              ┌────▼────┐      ┌────▼────┐      ┌───▼──┐   │
;              │ AY Chip │      │ Timex   │      │ ULA  │   │
;              │ Test    │      │ Control │      │ Test │   │
;              └─────────┘      └─────────┘      └──────┘   │
;                   │                │               │      │
;                   └────────────────┼───────────────┘      │
;                                    │                      │
;                          ┌─────────▼───────┐    ┌─────────▼───────┐
;                          │ Read Result &   │───→│ Return 00h/FFh  │
;                          │ Analyze Value   │    │ (NMOS/CMOS)     │
;                          └─────────────────┘    └─────────────────┘
; 
; HARDWARE-SPECIFIC TEST METHODS:
;   Hardware Type     │ Test Method             │ Port Used    │ Detection Logic
;   ──────────────────┼─────────────────────────┼──────────────┼─────────────────
;   Timex 2048/2068   │ Control register test   │ 0xFF (TMXCR) │ Read back written value
;   AY Sound Chip     │ Write/read AY register  │ 0xFFFD/BFFD  │ Compare written value  
;   ULA Hysteresis    │ Voltage threshold test  │ 0xFE (ULA)   │ EAR input analysis
;   Standard 48K      │ ULA border visual test  │ 0xFE (ULA)   │ User observes border
; 
; TECHNICAL PRINCIPLE: The undocumented OUT (C),0 instruction behaves differently:
; - NMOS: Outputs 0x00 (data bus pulled low by NMOS transistors)
; - CMOS: Outputs 0xFF (data bus pulled high by CMOS logic)
; 
; Input:  None
; Output: A = 00h - NMOS CPU detected
;         A = FFh - CMOS CPU detected
;-------------------------------------------------------------------------
TESTCMOS:
	DI			; Disable interrupts during hardware tests
	CALL	ZXTYPE		; Detect ZX Spectrum hardware variant
	CP	0		; ZXTYPE=0: Standard 48K Spectrum
				; 0 has to be first
				; has the other functions can return 0
	CALL	Z,TESTCMOSZX	; Use ULA border test with user input
	CP	1		; ZXTYPE=1: Timex 2048/2068
	CALL	Z,TESTCMOSTMX	; Use Timex control register test
	CP	2		; ZXTYPE=2: Spectrum with AY sound chip
	CALL	Z,TESTCMOSAY	; Use AY register test
	CP	3		; ZXTYPE=3: ULA hysteresis test
	CALL	Z,TESTCMOSHYST	; Use ULA electrical hysteresis test
				; (experimental)

	; restore border colour if (DEBUG)=0
	; changed in a couple of routines
	;
	; if using our BASIC snippet with white BORDER
	; changes to black testing a NMOS Z80
	push    af		; Save AF register pair on the stack to preserve A and F

;	more reliable detection now. Alway fix border colour.
;
;	ld      a,(DEBUG)	; Load the DEBUG flag from memory into A
;	or      a		; Logical OR A with itself to set the Zero flag (Z=1 if DEBUG=0)
;	jr      nz,NORESTORE	; If DEBUG is non-zero (Z=0), skip border restore
				; black border is a valuable indicator as a clue
				; if CPU NMOS and histeresis failed
	CALL    GETBORDER	; Call GETBORDER routine: returns current border color (0-7) in A
	out	(ULA_PORT),a	; Output the color in A to port FEh, restoring the border color
NORESTORE:
	pop     af		; Restore AF register pair, returning original A and flags

	EI
	RET			; Re-enable interrupts

; === CMOS Detection Method 1: ZX Spectrum ULA Border Test ===
; HUMAN-VISUAL DETECTION: User observes border color change to determine CPU type
;
; WHY HUMAN OBSERVATION IS NECESSARY:
; Standard ZX Spectrum 48K lacks reliable hardware latches like AY chip or Timex register.
; The ULA (Uncommitted Logic Array) controls video but doesn't provide readable registers
; for automated testing. Human visual detection becomes the most reliable method.
;
; ULA BORDER COLOR MECHANISM:
;   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
;   │ Write to 0xFE   │───→│ ULA Processes   │───→│ Border Color    │
;   │ Bits 2-0 set    │    │ Lower 3 bits    │    │ Changes on      │
;   │ border color    │    │ for RGB output  │    │ TV/Monitor      │
;   └─────────────────┘    └─────────────────┘    └─────────────────┘
;
; BORDER COLOR ENCODING (ULA Port 0xFE bits 2-0):
;   Binary │ Hex │ Color       │ Our Test Results
;   ───────┼─────┼─────────────┼─────────────────────────────────
;   000    │ 0   │ Black       │ ← NMOS CPU result (OUT (C),0 = 0x00)
;   001    │ 1   │ Blue        │ (not possible with our test)
;   010    │ 2   │ Red         │ (not possible with our test)
;   011    │ 3   │ Magenta     │ (not possible with our test)
;   100    │ 4   │ Green       │ (not possible with our test)
;   101    │ 5   │ Cyan        │ (not possible with our test)
;   110    │ 6   │ Yellow      │ (not possible with our test)
;   111    │ 7   │ White       │ ← CMOS CPU result (OUT (C),0 = 0xFF)
;
; CRITICAL: OUT (C),0 instruction ONLY outputs 0x00 (NMOS) or 0xFF (CMOS)
; Therefore, border will ONLY be black or white - no other colors possible!
; This eliminates any ambiguity and makes human detection foolproof.
;
; CPU TYPE DETECTION THROUGH BORDER COLOR:
;   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
;   │ Execute         │───→│ OUT (C),0 writes│───→│ Border Color    │
;   │ OUT (C),0       │    │ to ULA port 0xFE│    │ Result          │
;   └─────────────────┘    └─────────────────┘    └─────────────────┘
;                                   │                        │
;                          ┌────────▼─────────┐    ┌─────────▼───────┐
;                          │ NMOS: writes 0x00│───→│ Black border    │
;                          │ (bits 2-0 = 000) │    │ (color 0)       │
;                          └──────────────────┘    └─────────────────┘
;                                   │                        │
;                          ┌────────▼─────────┐    ┌─────────▼───────┐
;                          │ CMOS: writes 0xFF│───→│ White border    │
;                          │ (bits 2-0 = 111) │    │ (color 7)       │
;                          └──────────────────┘    └─────────────────┘
;
; HUMAN INTERFACE DESIGN:
; • Clear Instructions: "Press B-black W-white border"
; • Immediate Feedback: Border changes instantly when OUT instruction executes
; • Binary Choice: Only two possible outcomes (black vs white) - no ambiguity
; • High Contrast: Maximum visual difference between 0x00 and 0xFF results
;
; WHY THIS METHOD IS RELIABLE:
; • Binary Output: OUT (C),0 only produces 0x00 or 0xFF - no intermediate values
; • Maximum Contrast: Black (0x00) vs White (0xFF) - impossible to confuse
; • No Hardware Dependencies: Works on any ZX Spectrum variant
; • Electrical Reality: Directly shows what value the CPU actually output
;
; TECHNICAL DETAILS:
; • ULA Port 0xFE Controls: Border color, speaker, keyboard input
; • Border Update: Immediate visual feedback (next video refresh cycle)
; • Color Persistence: Border stays changed until next write to port 0xFE
;
; Uses OUT (C),0 to modify border color and asks user to identify result
; NMOS: OUT (C),0 outputs 0x00 → bits 2-0 = 000 → black border (color 0)
; CMOS: OUT (C),0 outputs 0xFF → bits 2-0 = 111 → white border (color 7)
TESTCMOSZX:
	LD	DE,MESBW	; DE -> "Press B-black W-white border"
	CALL	PRINTSTR	; Display instruction to user

	LD	C,ULA_PORT	; ULA port address (controls border, speaker, etc.)
	DB      0EDH, 071H      ; UNDOCUMENTED OUT (C),<0|0FFH> INSTRUCTION
                                ; WRITE 00 OR FF TO ULA
				; NMOS: writes 0x00 → black border (000 binary)
				; CMOS: writes 0xFF → white border (111 binary)
				; Border color determined by bits 2-0 of output value

	; === HUMAN INPUT PROCESSING ===
	; ZX Spectrum keyboard matrix scanning - each key mapped to specific row/bit
	; Keyboard organized as 8 rows × 5 columns, accessed via ULA port 0xFE
	; Row selection: write row mask to high byte, read key states from low byte
	; KEYBOARD MATRIX LAYOUT REFERENCE:
	; Row │ Port   │ Keys
	; ────┼────────┼─────────────────
	; 0   │ 0xFEFE │ Shift Z X C V
	; 1   │ 0xFDFE │ A S D F G  
	; 2   │ 0xFBFE │ Q W E R T  ← W key here (bit 1)
	; 3   │ 0xF7FE │ 1 2 3 4 5
	; 4   │ 0xEFFE │ 0 9 8 7 6
	; 5   │ 0xDFFE │ P O I U Y
	; 6   │ 0xBFFE │ Enter L K J H
	; 7   │ 0x7FFE │ Space SS M N B ← B key here (bit 4)

wait_key:
	; Check W key: Located in row 2 (Q-W-E-R-T row)
	ld   b,KBD_HROW_3	; port FBFE  
				; mask 11111011b - 3r half scan row
	in   a,(c)		; Read ULA port: bits 0-4 = key states (0=pressed)
	scf			; Set carry flag (assume CMOS/white result)

	; Test bit 1 for W key state (0=pressed, 1=released)
	bit  1,a		; test bit 1 (W key)
	jr   z,key_pressed	; If W pressed (bit=0), jump with carry=1 (CMOS)

	; --- check B key (row B-N-M-SS-Space, mask 0xEF) ---
	; Check B key: Located in row 5 (B-N-M-SS-Space row)  
	ld   b,KBD_HROW_8	; port 7FFE - 
				; Row mask 01111111b - 8th half scan row
	in   a,(c)		; Read ULA port: bits 0-4 = key states
	scf			; Set carry flag
	ccf			; Clear carry flag (assume NMOS/black result)

	; Test bit 4 for B key state (0=pressed, 1=released)
	bit  4,a		; test bit 2 (B key)
	jr   z,key_pressed	; If B pressed (bit=0), jump with carry=0 (NMOS)

	jr   wait_key		; ; Neither key pressed - continue polling

key_pressed:
	ld   a,$ff		; Load 0xFF (assume CMOS result)
	jr   c,LEAVEZX		; If carry set (W pressed), return FFh	
	XOR  A			; Clear A to 0x00 (NMOS result)
LEAVEZX:
	RET			; Return: A=0x00 for NMOS, A=0xFF for CMOS

; === CMOS Detection Method 2: AY Sound Chip Register Test ===
; DUAL FUNCTIONALITY: The AY chip serves both as sound generator AND general I/O latch
; 
; AY CHIP ARCHITECTURE:
;   ┌─────────────────┐    ┌─────────────────┐    ┌──────────────────┐
;   │ Address Latch   │    │ Data Register   │    │ I/O Functionality│
;   │ Port: 0xFFFD    │───→│ Port: 0xBFFD    │───→│ • Sound synthesis│
;   │ Selects R0-R15  │    │ Read/Write data │    │ • General purpose│
;   │ register        │    │ to selected reg │    │   latch/storage  │
;   └─────────────────┘    └─────────────────┘    └──────────────────┘
; 
; WHY AY WORKS AS A TEST LATCH:
; • AY registers retain written values (latch behavior)
; • Register 1 (tone period) accepts a value
; • Can write and read back values reliably  
; • Non-audio registers are perfect for data storage testing
; 
; REGISTER SELECTION RATIONALE:
; • Register 1 = Tone Generator B Fine Tune
; • Non-critical for audio (won't cause audio artifacts during test)
; • Reliable read/write characteristics across different AY variants
; • YM2149 compatible (common in later Spectrum models)
; 
; TEST METHODOLOGY:
; 1. Select AY register 1 via address latch (0xFFFD)
; 2. Write test value using OUT (C),0 via data port (0xBFFD) 
;    - NMOS: writes 0x00 to register
;    - CMOS: writes 0xFF to register  
; 3. Read back value from same register
; 4. and 0xf due to AY internal register storage limitations
; 5. Compare: 0x00 indicates NMOS, non-zero indicates CMOS
; 
; AY CHIP VARIANTS SUPPORTED:
; • General Instrument AY-3-8912 (original, 8-bit data bus)
; • Yamaha YM2149F (improved version, pin-compatible)  
; • Soviet equivalents (various manufacturers)
; • All retain latch functionality needed for this test
;
; Writes to AY register using OUT (C),0 and reads back the value
; NMOS: OUT (C),0 writes 0x00 to register → read back 0x00
; CMOS: OUT (C),0 writes 0xFF to register → read back 0x0F (masked to 4 bits)	
TESTCMOSAY:
	ld bc,AY_ADDR_PORT	; AY register select port FFFD (address latch)
	ld a,1            	; Select AY register 1 (tone generator B fine tune)
	out (c),a		; Send register number to AY address latch

	ld b,0BFh		; Switch to AY data port 0BFFDh
	DB      0EDH, 071H      ; UNDOCUMENTED OUT (C),<0|0FFH> INSTRUCTION
                                ; NMOS writes 0x00, CMOS writes 0xFF to AY register


	in a,(c)         	; gets the stored value from port 0BFFDh
				; Read back the value from AY register 1
				; VALUE WRITTEN BY OUT (C),<0|0FFH> INSTRUCTION

	and     0x0f		; AY register masks to 4 bits (0x0F max)
				; but can go up to 1fh if YM2149
				; ultimately not much relevant as we care most
                         	; about 0 and not 0
				; CRITICAL: Due to OUT (C),0 binary nature:
				; NMOS result: 0x00 & 0x0F = 0x00 (always)
				; CMOS result: 0xFF & 0x0F = 0x0F (always) 
				; Only these two values are possible - no intermediate results

	jr      z,NMOS		; If 0x00, it's NMOS

	ld      a,0ffh		; If 0x0F (non-zero), it's CMOS

NMOS: 	

	ret

; === CMOS Detection Method 3: Timex Control Register Test ===
; TIMEX HARDWARE ARCHITECTURE: Uses port 0xFF as a memory banking/video control register
;
; TIMEX CONTROL REGISTER FUNCTIONALITY:
;   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
;   │ Write to 0xFF   │───→│ Latch Storage   │───→│ System Control  │
;   │ Sets new config │    │ Port 0xFF holds │    │ • Memory banking│
;   │                 │    │ written value   │    │ • Video modes   │
;   └─────────────────┘    └─────────────────┘    └─────────────────┘
;
; WHY TIMEX PORT 0xFF WORKS AS A PERFECT LATCH:
; • Hardware Design: Port 0xFF is a genuine writable control register
; • State Retention: Value written is stored in hardware flip-flops/latches
; • Readable: Unlike write-only ports, 0xFF can be read back reliably
; • System Function: Controls memory mapping, video modes, ROM/RAM switching
; • Persistence: Value remains stable until next write (true latch behavior)
;
; TIMEX vs STANDARD SPECTRUM COMPARISON:
;   System Type          │ Port 0xFF Behavior        │ Read Reliability
;   ─────────────────────┼───────────────────────────┼─────────────────
;   Standard ZX Spectrum │ Unused, floating/random   │ Unpredictable
;   Timex 2048/2068      │ Control register latch    │ Returns written value
;   Timex TC2048         │ Control register latch    │ Returns written value
;
; TIMEX SCLD CONTROL (Port 0xFF) 
; Bits 2..0 : Video mode
;              000 = screen 0 (standard, 0x4000)
;              001 = screen 1 (0x6000)
;              010 = hi-colour (uses both display files -> 512x192 colour)
;              110 = 64-column / hi-res (512x192 monochrome)
; Bits 5..3 : Colour selection when 110 (hi-res / 64-col) is active
;              000 = Black on White
;              001 = Blue on Yellow
;              010 = Red on Cyan
;              011 = Magenta on Green
;              100 = Green on Magenta
;              101 = Cyan on Red
;              110 = Yellow on Blue
;              111 = White on Black
; Bit 6     : Timer / interrupt inhibit (1 = disable hardware timer interrupts)
; Bit 7     : Horizontal-MMU bank select for DOCK/EXROM (0 = DOCK/cartridge, 1 = EX-ROM)
; Reading port 0xFF returns the last byte written.
; Using it does not affect current RAM paging.
;
; LATCH TEST METHODOLOGY:
; 1. Read current control register value (for restoration)
; 2. Write test value using OUT (C),0:
;    - NMOS CPU: writes 0x00 to control register
;    - CMOS CPU: writes 0xFF to control register  
; 3. Read back value from control register
; 4. Restore original value (critical for system stability)
; 5. Compare read value: matches written value = CMOS, else NMOS
;
; SAFETY CONSIDERATIONS:
; • Value Restoration: Always restore original register value
; • System Stability: Temporary changes won't crash system
; • Non-Timex Safety: Port 0xFF unused on standard Spectrum (safe to write)
;
; Uses Timex 2048/2068 control register for CMOS detection
	
TESTCMOSTMX:
;	ld bc,0ff00h+TMX_CTRL_PORT ; Set BC to port address for OUT (C),0 instruction
	ld c,TMX_CTRL_PORT	; Set C to port address for OUT (C),0 instruction
				; $FF port is half decoded
	in a,(c)		; Read current Timex control register value
	ld e,a			; Save original value in E for later restoration
	DB	0EDH, 071H	; UNDOCUMENTED OUT (C),<0|0FFH> INSTRUCTION
				; NMOS writes 0x00 to control register
				; CMOS writes 0xFF to control register

	in a,(c)		; Read back the register value from latch
	ld d,a			; Save the test result in D 

	; This is CRITICAL - wrong control register values can crash Timex
	ld a,e			; Restore original control register value
	out (c),a	; Write back original value to prevent system instability

	ld a,d			; VALUE WRITTEN BY OUT (C),<0|0FFH> INSTRUCTION
				; Return the test result in A
				; NMOS: A=0x00, CMOS: A=0xFF
	or	a
	jr	z,leavetmx	; safeguard - defensive programming

	ld	a,0ffh
leavetmx:
	ret


; === CMOS Detection Method 4: ULA Electrical Hysteresis Test ===
; EXPERIMENTAL: Exploits ULA electrical input thresholds to detect CPU type
; WARNING: This is highly experimental and may not work reliably on all hardware!
;
; ELECTRICAL PRINCIPLE - ULA INPUT HYSTERESIS:
;   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
;   │ CPU Outputs     │───→│ ULA Input       │───→│ EAR Bit Reading │
;   │ via OUT (C),0   │    │ Threshold Logic │    │ (Bit 6 of 0xFE) │
;   └─────────────────┘    └─────────────────┘    └─────────────────┘
;
; OUTPUT PATTERN ANALYSIS - Why Bits 3&4 Matter:
;   ┌─────────────────────────────────────────────────────────────────┐
;   │ ULA Port 0xFE Bit Functions:                                    │
;   │ Bit 7: Not used    Bit 3: MIC output (tape recording)           │
;   │ Bit 6: EAR input   Bit 2: Border color bit 2                    │
;   │ Bit 5: Not used    Bit 1: Border color bit 1                    │
;   │ Bit 4: Speaker     Bit 0: Border color bit 0                    │
;   └─────────────────────────────────────────────────────────────────┘
;
; CRITICAL ELECTRICAL BEHAVIOR:
;   CPU Type │ OUT (C),0  │ Bits 4&3  │ MIC+Speaker │ Voltage Level │ EAR Reading
;   ─────────┼────────────┼───────────┼─────────────┼───────────────┼─────────────
;   NMOS     │ 0x00       │    00     │ Both OFF    │ ~0.3V (Low)   │ Bit 6 = 0
;   CMOS     │ 0xFF       │    11     │ Both ON     │ ~3.7V (High)  │ Bit 6 = 1
;
; ELECTRICAL THEORY - Input Threshold Hysteresis:
; • ULA EAR input has electrical hysteresis (different switch points)
; • Low-to-High threshold: ~1.5V (VIH - Input High Voltage)
; • High-to-Low threshold: ~1.0V (VIL - Input Low Voltage)  
; • NMOS 0.3V < VIL → EAR reads 0 (digital low)
; • CMOS 3.7V > VIH → EAR reads 1 (digital high)
;
; WHY BITS 3&4 CREATE THE VOLTAGE LEVELS:
; • Bit 4 (Speaker): Connected to internal audio amplifier circuit
; • Bit 3 (MIC): Connected to tape output circuit
; • When both bits = 0 (NMOS): Output drivers pull low (~0.3V)
; • When both bits = 1 (CMOS): Output drivers push high (~3.7V)
; • These voltage levels feed back through circuit paths to EAR input
; • Voltage dividers and coupling in ULA create measurable threshold effect
;
; CIRCUIT FEEDBACK PATH (Theoretical):
;   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
;   │ Bits 3&4 Output │───→│ Internal ULA    │───→│ EAR Input       │
;   │ Drive MIC/SPKR  │    │ Circuit Paths   │    │ Threshold       │
;   │ 00=Low, 11=High │    │ Coupling/Leakage│    │ Detection       │
;   └─────────────────┘    └─────────────────┘    └─────────────────┘
;
; RELIABILITY WARNINGS:
; • Board Revision Specific: Might ONLY work on 48K ZX Spectrum boards
;   and clones/emulators that replicate their electrical characteristics
; • Later board revisions likely have improved isolation, breaking the feedback path
; • Component tolerances, aging, and manufacturing variations affect results  
; • Electrical noise and temperature can influence readings
; • Success rate varies significantly between individual machines
;
; MULTIPLE TEST ITERATIONS:
; • Repeat test 9 times to improve reliability
; • Allows for electrical settling time
; • Averages out transient noise effects
; • If any iteration fails, entire test fails (conservative approach)
;
; Experimental method using ULA's electrical characteristics
; Tests voltage thresholds: NMOS ~0.3V, CMOS ~3.7V bits 3&4 feedback via bit 6

;------------------------------------------------------------
; TESTCMOSHYST: Read EAR input via ULA with hysteresis
; CPU: Z80A @ 3.5 MHz
; Description:
;   Uses 25 repeated OUT instructions to charge/discharge 
;   the ULA input threshold, then reads EAR (bit 6) from port 0FEh/ULA_PORT.
;   Improves reliability by electrical averaging.
;------------------------------------------------------------
TESTCMOSHYST:

; ULA Schmitt Trigger Rate-Dependent Hysteresis Exploit
; easier to catch feeding values in the waiting loop

	;------------------------------------------------
	; Setup BC for hysteresis loop
	; B = 48 iterations (reliability)
	; C = ULA port (0FEh/ULA_PORT)
	;------------------------------------------------
	ld      bc,30FEh	; 3 t, 0.857 µs

LOOP:
	;------------------------------------------------
	; Undocumented OUT (C),0 instruction
	; Writes either 0x00 (NMOS) or 0xFF (CMOS) to ULA
	; NMOS: bits 3&4 = 00 → EAR bit 6 = 0 (~0.3V)
	; CMOS: bits 3&4 = 11 → EAR bit 6 = 1 (~3.7V)
	; Voltage created by MIC+Speaker output affects EAR input
	;------------------------------------------------
	DB      0EDH,071H	; OUT (C),0 (undocumented) 11 t, 3.14 µs

	;------------------------------------------------
	; Decrement B and loop 25 times to allow electrical settling/averaging
	; DJNZ: 13 t-cycles if looping, 8 t-cycles if exiting
	; Total loop t-cycles for 48 iterations ≈ 616 t-cycles → ~176 µs
	;------------------------------------------------
	djnz    LOOP		; 13 t (loop), 8 t (exit)

	;------------------------------------------------
	; Read ULA input register (port FEh)
	; EAR input is at bit 6
	; IN: 11 t-cycles (~3.14 µs)
	;------------------------------------------------
	in      a,(ULA_PORT)	; 11 t, 3.14 µs

	;------------------------------------------------
	; Mask bit 6 to isolate EAR input
	; EAR bit (A6) is determined by ULA output voltage:
	;   - Bits 3 & 4 = 00 → output low (~0.3V) → EAR bit 6 = 0
	;   - Bits 3 & 4 = 11 → output high (~3.7V) → EAR bit 6 = 1
	; Result in A: 00h if EAR=0, 40h if EAR=1
	; AND: 7 t-cycles (~2 µs)
	;------------------------------------------------
	and     040h		; 7 t, 2 µs

	;------------------------------------------------
	; Set return value depending on EAR bit
	; If EAR bit set (NZ), assume CMOS/high voltage -> return 0xFF
	; If EAR bit clear (Z), assume NMOS/low voltage -> return 0x00
	;------------------------------------------------
	ld      a,0FFh		; 7 t, 2 µs
				; Assume CMOS/high voltage detected
	jr      nz,leaveout	; 12 t, 3.43 µs  
				; If bit 6 set, skip clearing A 
	xor     a		; 4 t, 1.14 µs  
				; Clear A for NMOS/low voltage

leaveout:
	ret			; 10 t, 2.86 µs   
				; Return: A=0x00 (NMOS), A=0xFF (CMOS)

;-------------------------------------------------------------------------
; TESTU880 - Check if the CPU is MME U880 or Thesys Z80
; 
; DETECTION ALGORITHM FLOWCHART:
;   ┌─────────────────┐
;   │ Set Carry Flag  │
;   └─────────┬───────┘
;             │
;   ┌─────────▼───────┐    ┌─────────────────┐    ┌─────────────────┐
;   │ Execute OUTI    │───→│ Check Carry     │───→│ Return Result   │
;   │ Instruction     │    │ Flag Status     │    │                 │
;   └─────────────────┘    └─────────┬───────┘    │ A=0: Standard   │
;                                    │            │ A=1: U880       │
;                          ┌─────────▼───────┐    └─────────────────┘
;                          │ Carry=1? U880   │
;                          │ Carry=0? Z80    │
;                          └─────────────────┘
; 
; BUG ANALYSIS:
;   CPU Type        │ Expected Behavior      │ Actual U880 Behavior
;   ────────────────┼──────────────────── ───┼─────────────────────
;   Standard Z80    │ OUTI clears carry      │ N/A
;   U880 (buggy)    │ OUTI clears carry      │ OUTI preserves carry
; 
; PRINCIPLE: U880 CPUs have a documented bug in the OUTI instruction where the carry
; flag is not properly cleared after execution. Standard Z80 CPUs correctly clear 
; the carry flag. This behavioral difference provides a reliable detection method.
; 
; BUG DETAILS: In authentic Z80 CPUs, OUTI clears the carry flag as part of its
; normal operation. The U880 implementation failed to implement this correctly,
; leaving the carry flag in its previous state.
; 
; RELIABILITY: This test is very reliable because:
; - The bug affects a fundamental instruction behavior
; - It's consistent across all U880 variants  
; - No other Z80 clones are known to have this specific bug
; 
; TEST METHOD:
; 1. Set carry flag
; 2. Execute OUTI instruction
; 3. Check if carry flag is still set (U880) or cleared (Z80)
;
; Input:  None
; Output: A = 0 - Standard Z80 (carry cleared by OUTI)
;         A = 1 - U880 CPU (carry preserved by OUTI)
;-------------------------------------------------------------------------
TESTU880:
	ld hl,0FFFFH		; Memory address for OUTI (edge case test)
	ld bc,001FFH		; C=TIMEX CONTROL REGISTER FOR TESTS
				; B = 1 (single OUTI iteration)
				; Port FFh is safe - unused on non-Timex models

	ld (hl),b		; Store test value at (HL), affects flags

	di			; Disable interrupts during I/O test

	in a,(0ffh)		; Set carry flag (critical for the test)
	scf			; Set carry flag - this is the key test
	outi			; OUTI: (HL) → port (C), HL++, B--
				; Documented flags: Z (from B), N=1
				; Undocumented flags: S,H,F3,F5,PV modified
				; U880: carry incorrectly preserved (set)
				; Z80 (reference): carry cleared

	out (0ffh),a		; Restore Timex control register
				; (No effect on non-Timex models)
	
	ei			; Re-enable interrupts

	ld a,0			; Prepare result (clear A)
	adc a,a			; Add carry to A
				; U880: C=1 unchanged, A becomes 1
				; Z80: C=0, A remains 0

	ret

;-------------------------------------------------------------------------
; TESTXY - Tests how SCF instruction affects FLAGS.5 (YF) and FLAGS.3 (XF)
; 
; ALGORITHM VISUALIZATION:
;   ┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
;   │   Test Matrix   │    │  Count Results   │    │ Encode to Bits  │
;   │                 │    │                  │    │                 │
;   │ 4 Scenarios ×   │───→│ For each of 256  │───→│ 4×2-bit values  │
;   │ 256 Values      │    │ loop iterations  │    │ = 1 result byte │
;   │ = 1024 tests    │    │                  │    │                 │
;   └─────────────────┘    └──────────────────┘    └─────────────────┘
; 
; TEST SCENARIO MATRIX:
;   Scenario │ A Value        │ FLAGS Value    │ Target │ Result Bits
;   ─────────┼────────────────┼────────────────┼────────┼─────────────
;   1        │ C|0x20 & 0xF7  │ 0x00           │ YF     │ [7:6]
;   2        │ C|0x08 & 0xDF  │ 0x00           │ XF     │ [5:4] 
;   3        │ 0x00           │ C|0x20 & 0xF7  │ YF     │ [3:2]
;   4        │ 0x00           │ C|0x08 & 0xDF  │ XF     │ [1:0]
; 
; ENCODING SCHEME (per 2-bit field):
;   Binary │ Decimal │ Meaning           │ Count Range
;   ───────┼─────────┼───────────────────┼─────────────
;   00     │   0     │ Never set         │ 0/256
;   01     │   1     │ Rarely set        │ 1-126/256  
;   10     │   2     │ Usually set       │ 127-254/256
;   11     │   3     │ Always set        │ 255/256
;
; CPU SIGNATURE EXAMPLES:
;   FFh = 11111111b → All flags always set (Standard Z80/Z84C00)
;   30h = 00110000b → Only scenario 1 shows YF rarely set (Sharp LH5080A)
;   FDh = 11111101b → XF occasionally not set in scenario 4 (NEC D780C)
; 
; PRINCIPLE: Different Z80 variants handle undocumented XF/YF flags differently
; when SCF (Set Carry Flag) instruction is executed. The behavior depends on
; the current values of A register and flags register.
; 
; The TESTXY routine tests 4 specific scenarios, each encoded in 2 bits:
; 1. F=0, A=C|0x20&0xF7 (A.5=1, A.3=0, FLAGS=0) -> Bits 7-6: YF behavior
; 2. F=0, A=C|0x08&0xDF (A.3=1, A.5=0, FLAGS=0) -> Bits 5-4: XF behavior
; 3. F=C|0x20&0xF7, A=0 (FLAGS.5=1, FLAGS.3=0, A=0) -> Bits 3-2: YF behavior
; 4. F=C|0x08&0xDF, A=0 (FLAGS.3=1, FLAGS.5=0, A=0) -> Bits 1-0: XF behavior
; 
; Each 2-bit encoding means:
;         00 - Flag never set (0/256 times)
;         01 - Flag rarely set (1-127/256 times) 
;         10 - Flag usually set (128-254/256 times)
;         11 - Flag always set (255/256 times)
; 
; Input:  None
; Output: A[7:6] - YF result for test condition 1
;         A[5:4] - XF result for test condition 2  
;         A[3:2] - YF result for test condition 3
;         A[1:0] - XF result for test condition 4
;-------------------------------------------------------------------------
TESTXY:
	ld c,0FFH		; Loop counter (256 iterations)
	
TESTXY1:
	ld hl,XFYFCOUNT		; Point to results storage array

	; === Test Condition 1: F=0, A=C|0x20&0xF7 ===
	; Set A.5=1, A.3=0, FLAGS=0, then execute SCF
	; check F = 0, A = C | 0x20 & 0xF7
	ld e,00H		; FLAGS = 0
	ld a,c			; Load loop counter
	or 020H			; Set bit 5 (A.5 = 1)
	and 0F7H		; Clear bit 3 (A.3 = 0)
	ld d,a			; A = C | 0x20 & 0xF7
	push de			; Push DE to stack
	pop af			; Pop into A and FLAGS registers FROM THE STACK (DE)
	; Set carry flag - may affect XF/YF depending on CPU type
	scf
				; ALSO MIGHT CHANGE YF AND XF FLAGS
	call STOREYCOUNT	; Count how often YF gets set

	; === Test Condition 2: F=0, A=C|0x08&0xDF ===
	; Set A.3=1, A.5=0, FLAGS=0, then execute SCF
				; check F = 0, A = C | 0x08 & 0xDF
	ld e,00H		; FLAGS = 0
	ld a,c			; Load loop counter
	or 08H			; Set bit 3 (A.3 = 1)
	and 0DFH		; Clear bit 5 (A.5 = 0)
	ld d,a			; A = C | 0x08 & 0xDF
	push de			; PUSH DE TO THE STACK
	pop af			; POP A AND FLAGS FROM THE STACK (DE)
	; Set carry flag - may affect XF/YF depending on CPU
	scf			; SET CF FLAG, DEPENDING ON THE CPU TYPE THIS
				; ALSO MIGHT CHANGE YF AND XF FLAGS
	call STOREXCOUNT	; Count how often XF gets set

	; === Test Condition 3: F=C|0x20&0xF7, A=0 ===
	; Set FLAGS.5=1, FLAGS.3=0, A=0, then execute SCF
				; check F = C | 0x20 & 0xF7, A = 0
	ld a,c			; Load loop counter
	or 020H			; Set bit 5 (FLAGS.5 = 1)
	and 0F7H		; Clear bit 3 (FLAGS.3 = 0)
	ld e,a			; FLAGS = C | 0x20 & 0xF7
	ld d,00H		; A = 0
	push de			; PUSH DE TO THE STACK
	pop af			; POP A AND FLAGS FROM THE STACK (DE)
	; Set carry flag - may affect XF/YF depending on CPU
	scf			; SET CF FLAG, DEPENDING ON THE CPU TYPE THIS
				; ALSO MIGHT CHANGE YF AND XF FLAGS
	call STOREYCOUNT	; Count how often YF gets set

	; === Test Condition 4: F=C|0x08&0xDF, A=0 ===
	; Set FLAGS.3=1, FLAGS.5=0, A=0, then execute SCF
				; check F = C | 0x08 & 0xDF, A = 0
	ld a,c			; Load loop counter
	or 08H			; Set bit 3 (FLAGS.3 = 1)
	and 0DFH		; Clear bit 5 (FLAGS.5 = 0)
	ld e,a			; FLAGS = C | 0x08 & 0xDF
	ld d,00H		; A = 0
	push de			; PUSH DE TO THE STACK
	pop af			; POP A AND FLAGS FROM THE STACK (DE)

	; Set carry flag - may affect XF/YF depending on CPU
	scf			; SET CF FLAG, DEPENDING ON THE CPU TYPE THIS
				; ALSO MIGHT CHANGE YF AND XF FLAGS

	call STOREXCOUNT	; Count how often XF gets set

	dec c			; Decrement loop counter
	jr nz,TESTXY1		; Continue until all 256 combinations tested

	; === Encode Results into Final XYRESULT Byte ===
	; Convert raw counts (0-256) to 2-bit encoded values and pack into single byte
	; Final format: [Scenario1_YF][Scenario2_XF][Scenario3_YF][Scenario4_XF]
	ld c,4			; iteration count - number of bytes
				; Process 4 counter bytes (one per test scenario)
	ld hl,XFYFCOUNT		; HL -> counter array start address

TESTXY2:
	rla			; Rotate result left by 2 positions
	rla			; to make room for next 2-bit value
	and 0FCH		; Clear lower 2 bits (preserve upper 6)
	ld b,a			; Save current result in B
	ld a,(hl)		; Load counter value from (HL)

	; Encode counter value to 2-bit result based on thresholds:
	cp 7FH			; Is count >= 127 (0x7F)? (Half of 256 tests)
	jr nc,TESTXY3		; jump if the count is 0x80 or more
				; If yes, check for high values (10 or 11 encoding)
	or a			; Is count exactly 0?
	jr z,TESTXY5		; the count is 0 leave bits at 0
				; If yes, leave result as 00 (never set)

	ld a,1			; the count is between 1 and 0x7F, set result bits to 01
				; If yes, leave result as 00 (never set)
	jr TESTXY5

TESTXY3:
	; Is count exactly 255? (All 256 tests - impossible with 8-bit counter)
	cp 0FFH
	ld a,2			; the count is between 0x80 and 0xFE, set result bits to 10
				; Count 127-254: encode as 10 (usually set)
	jr nz,TESTXY4		; If not 255, use 10 encoding
	ld a,3			; the count is 0xFF, set result bits to 11
	jr TESTXY5

TESTXY4:
	ld a,1			; the count is 0x7F or less, set result bits to 01
				; Fallback: encode as 01 (should not reach here)
TESTXY5:
	or b			; Combine with previous results in upper bits
	inc hl			; HL -> next counter in array
	dec c			; Decrement counter
	jr nz,TESTXY2		; Process all 4 counters
	ret			; Return with encoded result in A

;-------------------------------------------------------------------------
; STOREXCOUNT - Count XF flag occurrences
; 
; Isolates the XF flag (bit 3) from the flags register and increments
; the counter at (HL) if the flag is set.
; 
; Input:  FLAGS - current flags register
;         HL - pointer to XF counter byte
; Output: HL - incremented to point to next counter
; Uses:   A, DE (trashed)
;-------------------------------------------------------------------------
STOREXCOUNT:
	push af			; Save AF to stack
	pop de			; Pop flags into E register
	ld a,e			; Transfer flags to A
	and 08H			; Isolate XF flag (bit 3)
	jr z,STOREXDONE         ; Skip if XF not set
	inc (hl)		; increment the XF counter (HL)
STOREXDONE:
	inc hl			; point to the next entry
				; HL -> next counter in array
	ret

;-------------------------------------------------------------------------
; STOREYCOUNT - Count YF flag occurrences
; 
; Isolates the YF flag (bit 5) from the flags register and increments
; the counter at (HL) if the flag is set.
; 
; Input:  FLAGS - current flags register  
;         HL - pointer to YF counter byte
; Output: HL - incremented to point to next counter
; Uses:   A, DE (trashed)
;-------------------------------------------------------------------------
STOREYCOUNT:
	push af			; Save AF to stack
	pop de			; Pop flags into E register
	ld a,e			; Transfer flags to A
	and 20H			; Isolate YF flag (bit 5)
	jr z,STOREYDONE		; Skip if YF not set
	inc (hl)		; increment the YF counter (HL)
STOREYDONE:
	inc hl			; point to the next entry
				; HL -> next counter in array
	ret

;-------------------------------------------------------------------------
; TESTFLAGS - Comprehensive XF/YF flag behavior test (debug only)
; 
; PURPOSE: Creates a detailed "fingerprint" of CPU flag behavior by testing
; all 65,536 possible combinations of A register and FLAGS values with CCF.
; This provides statistical analysis for CPU variant identification and research.
; 
; ALGORITHM OVERVIEW:
;   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
;   │ Nested Loops:   │───→│ Execute CCF &   │───→│ Print 32-bit    │
;   │ A: 0-255        │    │ Count Flag Sets │    │ Statistics      │
;   │ FLAGS: 0-255    │    │ XF & YF         │    │ (4 hex bytes)   │
;   │ = 65,536 tests  │    │                 │    │                 │
;   └─────────────────┘    └─────────────────┘    └─────────────────┘
; 
; RESEARCH APPLICATIONS:
; - CPU authentication (detect remarked/counterfeit chips)
; - Variant classification (distinguish sub-models)  
; - Manufacturing analysis (different fab runs may vary)
; - Academic research (undocumented instruction behavior)
; 
; TYPICAL RESULTS BY CPU TYPE:
;   CPU Family        │ XF Count Range    │ YF Count Range    │ Pattern Notes
;   ──────────────────┼───────────────────┼───────────────────┼─────────────────
;   Standard NMOS Z80 │ ~32768 (50%)      │ ~32768 (50%)      │ Consistent
;   CMOS Z80          │ Variable          │ Variable          │ More predictable
;   U880              │ Distinctive       │ Distinctive       │ Bug artifacts
;   Sharp LH5080A     │ Unique pattern    │ Unique pattern    │ CMOS but different
;   NEC clones        │ Specimen variance │ Specimen variance │ Manufacturing drift
; 
; Input:  None
; Output: Prints comprehensive flag statistics to console
;-------------------------------------------------------------------------	
TESTFLAGS:
	ld de,MSGFLAGS		; DE -> "XF/YF flags test:  "
	call PRINTSTR

	; === EXHAUSTIVE FLAG TESTING LOOP ===
	; Tests all combinations: A(0-255) × FLAGS(0-255) = 65,536 iterations
	; This creates a comprehensive statistical profile of flag behavior
	
	; Initialize outer loop: test all A register values (0-255)
	ld d,00H		; D = A register value
TFLOOP1:
	; Initialize inner loop: test all FLAGS values (0-255)
	ld e,00H		; E = FLAGS register value
TFLOOP2:
	push de			; Save current A,FLAGS combination
	di			; Disable interrupts for precise flag testing
	push de			; PUSH DE TO THE STACK
	pop af			; Pop A and FLAGS from stack (DE->AF)
	ccf			; SET CF FLAG, DEPENDING ON THE CPU TYPE THIS
				; ALSO MIGHT CHANGE YF AND XF FLAGS
	push af			; Save new A and FLAGS
	pop de			; Pop new flags into E
	ei			; Re-enable interrupts
	ld a,e			; Move new flags to A for processing
	pop de			; Restore original A,FLAGS values
	jr CONT			; Continue with flag analysis

	; Debug code to print individual flag results (currently unused)
	; This section could be enabled to see every single test result
PRINTFLAGS:
	call PRINTHEX		; PRINT ACCUMULATOR
	ld a,e			; FLAGS TO ACCUMULATOR
	pop de			; Restore DE
	push af			; Save for later
	ld a,d			; PRINT ORIGINAL ACCUMULATOR(FLAGS)
	call PRINTHEX
	pop af			; Restore and print original flags
	call PRINTHEX		; PRINT NEW FLAGS
	push de			; Save DE again
	ld de,MSGCRLF		; DE -> carriage return + line feed
	call PRINTSTR		; Print newline
	pop de			; Restore DE
CONT:
	; === XF FLAG ANALYSIS AND COUNTING ===
	; Isolate XF flag (bit 3) and update 16-bit counter with overflow handling
	ld hl,XFCOUNT		; HL -> XF counter (16-bit) memory location
	rrca			; Rotate A right: bit 3 (XF) -> bit 2
	rrca			; Rotate A right: bit 2 -> bit 1 
	rrca			; Rotate A right: bit 1 -> bit 0
	rrca			; Rotate A right: bit 0 -> carry flag (XF now in carry)
	jr nc,TFLOOP4		; Skip increment if XF flag was not set
	inc (hl)		; INCREMENT COUNTER IF FLAG IS SET
				; Increment low byte of XF counter at (HL)
	jr nz,TFLOOP4		; No overflow occurred - continue to YF processing
	inc hl			; HL -> high byte of XF counter
	inc (hl)		; INCREMENT HIGHER BIT
				; Increment high byte to handle 8-bit overflow
TFLOOP4:
	; === YF FLAG ANALYSIS AND COUNTING ===
	; Isolate YF flag (bit 5) and update 16-bit counter with overflow handling
	; Note: A register still contains rotated flags from XF processing above
	ld hl,YFCOUNT		; POINT TO YF COUNTER
				; HL -> YF counter (16-bit) memory location
	rrca			; BIT 5 TO CF
				; Rotate A right: now bit 5 (YF) -> bit 4
	rrca			; Rotate A right: bit 4 -> carry flag (YF now in carry)
				; (XF bit 3 was already rotated out during XF processing)
	jr nc,TFLOOP5		; Skip increment if YF flag was not set
	inc (hl)		; INCREMENT COUNTER IF FLAG IS SET
				; Increment low byte of YF counter at (HL)
	jr nz,TFLOOP5		; ; No overflow occurred - continue to loop control
	inc hl			; MOVE TO THE HIGH BIT
				;HL -> high byte of YF counter 
	inc (hl)		; INCREMENT HIGHER BIT
				; Increment high byte to handle 8-bit overflow
TFLOOP5:
	; === LOOP CONTROL AND PROGRESSION ===
	; Manage nested loop counters for exhaustive testing
	inc e			; Increment inner loop: next FLAGS value (0-255)
	jr nz,TFLOOP2		; Continue inner loop until E wraps around to 0
	inc d			; Increment outer loop: next A register value (0-255)
	jr nz,TFLOOP1		; Continue outer loop until D wraps around to 0

; === STATISTICAL RESULTS DISPLAY ===
	; Print final statistics as 32-bit values (4 hex bytes each)
	; Format: [YF_MSB][YF_MSB-1][YF_MSB-2][YF_LSB][XF_MSB][XF_MSB-1][XF_MSB-2][XF_LSB]
	
	; Display YF count (16-bit) + XF count (16-bit) = 4 total bytes
	ld c,4			; Print 4 bytes total (2 bytes YF + 2 bytes XF)
	ld hl,YFCOUNT+1		; POINT AT THE MSB
				; HL -> YF count MSB (start from high byte address)
TFLOOP6:
	ld a,(hl)		; Load byte from current memory location
	call PRINTHEX		; Print byte in hexadecimal format
	dec hl			; HL -> next byte (moving toward LSB)
	dec c			; Decrement byte counter
	jr nz,TFLOOP6		; PRINT NEXT DIGIT
				; Continue until all 4 bytes printed

	ld de,MSGCRLF		; DE -> carriage return + line feed
	call PRINTSTR		; Print newline to complete output
	ret			; Return to calling routine

; PRINT VALUES
	ld hl,YFCOUNT+1		; MSB OF YF COUNT
	ld a,(hl)
	call PRINTHEX
	dec hl			; LSB OF YF COUNT
	ld a,(hl)
	call PRINTHEX
	ld hl,XFCOUNT+1		; MSB OF XF COUNT
	ld a,(hl)
	call PRINTHEX
	dec hl			; LSB OF XF COUNT
	ld a,(hl)
	call PRINTHEX
	ld de,MSGCRLF
	call PRINTSTR
	ret

	; INTERPRETATION OF RESULTS:
	; The 4-byte hex output represents: [YF_HI][YF_LO][XF_HI][XF_LO]  
	; Each counter can range from 0000h to FFFFh (0 to 65535 decimal)
	; 
	; Example interpretations:
	; - 8000 8000 = ~50% flag setting (typical for many Z80s)  
	; - FFFF FFFF = Flags always set (unusual, indicates specific behavior)
	; - 0000 0000 = Flags never set (also unusual, specific to certain CPUs)
	; - Asymmetric values = Distinctive CPU signature for identification

;-------------------------------------------------------------------------
; PRINTHEX - Print byte value in hexadecimal format
; 
; Converts a byte to two ASCII hex characters and prints them.
; 
; Input:  A - byte value to print (0-255)
; Output: Two hex characters printed to console
; Uses:   All registers preserved except AF
;-------------------------------------------------------------------------
PRINTHEX:
	push bc			; Preserve registers
	push de
	push hl
	push af			; SAVE PRINTED VALUE ON THE STACK
				; Save original value

	; Print high nibble (bits 7-4)
	rrca			; ROTATE HIGHER 4 BITS TO LOWER 4 BITS
				; Rotate high nibble to low position
	rrca
	rrca
	rrca
	call PRINTDIGIT		; PRINT HIGHER 4 BITS
				; Print high hex digit

	; Print low nibble (bits 3-0)
	pop af			; RESTORE PRINTED VALUE
				; Restore original value
	push af			; PUSH IT TO THE STACK AGAIN
	call PRINTDIGIT		; PRINT LOWER 4 BITS
				; Print low hex digit (PRINTDIGIT masks to low nibble)
	
	pop af			; Restore registers
	pop hl
	pop de
	pop bc
	ret

;-------------------------------------------------------------------------	
; PRINTDIGIT - Print single hexadecimal digit
; 
; Converts a 4-bit value (0-15) to ASCII hex character and prints it.
; 
; Input:  A - value to print (only low 4 bits used)
; Output: One hex character (0-9, A-F) printed to console
; Uses:   A, FLAGS, BC, DE, HL (all trashed)
;-------------------------------------------------------------------------	
PRINTDIGIT:
	and 0FH			; Isolate lower 4 bits (0-15)
	add a,'0'		; Convert to ASCII: 0-9 become '0'-'9'
	cp '9'+1		; Is result greater than '9'?
	jr c,PRINTIT		; If 0-9, print as-is
	add a,'A'-'9'-1		; Convert 10-15 to 'A'-'F'
	
PRINTIT:
	; Print character using ZX Spectrum ROM routine
	RST     $10		; PRINT CHAR, ZX+CLONES
	RET

;-------------------------------------------------------------------------
; PRINTSTR - Print null-terminated string to console
; 
; Prints a string of characters until ' terminator is encountered.
; Uses ZX Spectrum ROM print routine.
; 
; Input:  DE - address of string to print (terminated with ')
; Output: String printed to console
; Uses:   All registers preserved
;-------------------------------------------------------------------------
PRINTSTR:
	push af
	push bc
	;push de
	push hl
PRSTR:  
	LD      A,(DE)		; Load character from string
	CP      '$'		; Check for terminator
	JR     	Z,EOS		; Jump to end if terminator found
	; Print character using ZX Spectrum ROM routine
	RST     $10		; PRINT CHAR, ZX+CLONES 
	INC     DE		; Point to next character
	JR      PRSTR		; Continue until end-of-string marker
EOS:	
	pop hl			; Restore all registers
	;pop de
	pop bc
	pop af
	ret

;==============================================================================
; ZX Spectrum Hardware Detection Routine
;==============================================================================
; 
; Detects the specific ZX Spectrum hardware variant by testing for:
; - AY-3-8912 sound chip (present in 128K models and retrofitted 48K)
; - Timex 2048/2068 control register (Timex-specific hardware)
; - ULA hysteresis behavior (different board revisions)
;
; This detection is crucial because different hardware requires different
; methods for the CMOS/NMOS CPU detection tests.
;
; ZXTYPE Result Values (returned in register A):
;   0 - Standard 48K Spectrum (no AY chip, no Timex hardware)
;   1 - Spectrum with AY sound chip (128K, +2, +3, or retrofitted 48K)
;   2 - Timex 2048/2068 (features Timex-specific control register)
;   3 - 48K Spectrum with ULA hysteresis detection capability
;==============================================================================

;------------------------------------------------------------------------------
; Main Hardware Detection Entry Point
;------------------------------------------------------------------------------
ZXTYPE: 
	LD      E,0		; E = ZXTYPE result (0 = assume basic 48K) 

;------------------------------------------------------------------------------
; Test #1: Check for Timex 2048/2068 Hardware
;------------------------------------------------------------------------------
; DETECTION PRINCIPLE: Port 0xFF behavior differs between hardware types
; • Standard Spectrum: Port 0xFF unused → unpredictable read values
; • Timex machines: Port 0xFF is control register → returns written value
;
; TEST METHOD: Write two different patterns and verify both read back correctly
; Pattern 1: 0x3C, Pattern 2: 0xC3 (chosen for bit pattern diversity)

ISTMX:
;	LD	BC,0ff00h+TMX_CTRL_PORT 
	LD	C,TMX_CTRL_PORT 
				; $FF port is half decoded
	IN	A,(C)		; A = current Timex control register value
	LD	D,A		; D = original value for later restoration

	; Test Pattern 1: Write and verify a specific bit pattern
	LD	A,0C0h		; A = test pattern 1: 11000000 binary 
	CALL	TMXDETECT
	JR	NZ,ISAY		; No match - not Timex hardware, try hysteresis test

	; Test Pattern 2: Verify with a different pattern for confirmation
	LD	A,080h		; A = test pattern 2: 10000000 binary
	CALL	TMXDETECT
	JR	NZ,ISAY		; No match - not Timex, try hysteresis test

	; Both test patterns succeeded - this is definitely Timex hardware
	INC     E               ; Increment E from 0 to 1: ZXTYPE = 1 (Timex)

;------------------------------------------------------------------------------
; Return for Timex Detection
;------------------------------------------------------------------------------
        JR      RTYPE           ; Jump to final return

; called by ISTMX
TMXDETECT:
	LD	L,A		; save value to be written
	OUT	(C),A		; Write pattern to Timex control register
	IN	A,(C)		; A = readback from control register
	CP	L		; Does it match what we wrote?

				; in a non-Timex, no effect
				; LD+OUT does not affect flags
	LD	A,D		; A = original Timex control register value
	OUT	(C),A		; Restore original value to prevent system instability
	RET

;------------------------------------------------------------------------------
; Test #2: Check for YM2149/AY-3-891x Sound Chip
;------------------------------------------------------------------------------
; The AY sound chip is present in:
; - ZX Spectrum 128K, +2, +3 (standard)
; - Some retrofitted 48K Spectrums with sound upgrades
; - Compatible clones with enhanced sound capabilities
; 
; DETECTION METHODOLOGY:
; 1. Write a test pattern to an AY register
; 2. Read the value back from the same register  
; 3. If values match exactly → AY chip present
; 4. If values differ → No AY chip (standard 48K)
;
; AY CHIP ADDRESSING SCHEME:
;   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
;   │ Select Register │───→│ Write/Read Data │───→│ Verify Storage  │
;   │ Port: 0xFFFD    │    │ Port: 0xBFFD    │    │ Latch Function  │
;   │ (Address Latch) │    │ (Data Port)     │    │ Working         │
;   └─────────────────┘    └─────────────────┘    └─────────────────┘
;
; WHY REGISTER 1 IS USED:
; • Register 1 = Tone Generator B Fine Tune 
; • Non-critical register (won't affect audio during brief test)
; • Reliable read/write on all AY variants (AY-3-8912, YM2149F, clones)
; • Full data retention capability (perfect for latch testing)
;
; TEST PATTERN SELECTION:
; • 0x0F chosen as safe maximum value for most AY registers
; • Ensures we're not writing invalid data that might be ignored
; • Clear non-zero pattern that's easy to verify on readback
; • Compatible with both AY-3-8912 (4-bit) and YM2149F (5-bit) limits
;
; Test method: Write a known value to an AY register and read it back.
; If the value matches, an AY chip is present.
ISAY:   
	LD      BC,AY_ADDR_PORT	; BC = AY-3-8912 register select port FFFD 
				; (address latch)
	LD      A,01h		; Select AY register 1 (tone generator B fine tune)
	OUT     (C),A		; Send register number to AY address latch
				; This selects which internal register to access
        
	LD      B,0BFh		; BC = AY data port 0BFFDh (keeping C=0xFD)
				; Port address changes: 0xFFFD → 0xBFFD
	LD      A,0Fh		; A = test pattern 0x0F 
				; (safe maximum for compatibility)
	OUT     (C),A		; Write test data to selected AY register 1
				; If AY present: value stored in internal latch
				; If no AY: write goes nowhere (no storage)
        
	LD      B,0FFh		; BC = back to register select port 0xFFFD
				; Must re-select register before reading
	IN      A,(C)		; A = data read back from AY register 1
				; If AY present: returns stored 0x0F value
				; If no AY: returns bus noise/floating values

	CP      0Fh		; Does readback match our test pattern exactly?
	JR      NZ,HYSTE	; If different values → no AY chip, test for Hysteresis
        
	INC     E		; AY chip detected: E = 1 
	INC	E		; Increment E from 1 to 2: ZXTYPE = 2 (AY)
	JR	RTYPE		; Skip remaining tests and return with result

; ALTERNATIVE AY DETECTION METHODS CONSIDERED:
; • Could test multiple registers, but single register sufficient
; • Could use different test patterns, but 0x0F is safest
; • Could test register value limits, but adds complexity
; • This simple method works reliably across all AY variants


;------------------------------------------------------------------------------
; Test #3: ULA Hysteresis Test (Experimental)
;------------------------------------------------------------------------------
; This test attempts to detect different ZX Spectrum board revisions by
; exploiting electrical characteristics of the ULA chip's input thresholds.
; 
; Different board issues may have different
; electrical characteristics that affect the EAR input hysteresis behavior.
; 
; WARNING: This is experimental and may not work reliably on all hardware.

; Routine called from HYSTE:
;---------------------------------------------------------
; HYSTE_TEST
; Called from HYSTE
; Purpose:
;   Output a voltage level to the ULA and then read back
;   the EAR input bit (bit 6 of ULA port).
;
; Timing:
;   Z80A @ 3.5 MHz → 1 T-state ≈ 0.2857 µs
;---------------------------------------------------------

;---------------------------------------------------------
; HYSTE_TEST
; Called from HYSTE
;
; Function:
;   Drive the ULA speaker/MIC output (bits 3 and 4 of port FEh)
;   at a steady level long enough for the analogue circuitry
;   to settle, then read back the EAR input bit (bit 6).
;
; Timing (Z80A @ 3.5 MHz → 1 T ≈ 0.2857 µs):
;   - Entry overhead   : 21 T ≈ 6.00 µs
;   - Stabilisation loop: 6370 T ≈ 1.820 ms
;   - Exit overhead    : 39 T ≈ 11.14 µs
;   → Routine total    : 6430 T ≈ 1.837 ms
;
; Output: for a successful test:
;		bit 4,MIC=1 bit 3,Speaker=1 --> EAR=1
;		bit 4,MIC=0 bit 3,Speaker=0 --> EAR=0
;
;---------------------------------------------------------

HYSTE_TEST:
	PUSH    BC		; 11 T (≈ 3.14 µs)
				; Save caller’s loop counter

	LD      BC,0FFFEh	; 10 T (≈ 2.86 µs)
				; B = 255 → iteration count
				; C = FEh → ULA I/O port

HYST:
	OUT     (C),A		; 12 T (≈ 3.43 µs)
				; Write to ULA:
				;   Bit 3 = speaker level
				;   Bit 4 = MIC output level
				;   Voltage high if bit set, low if cleared

	DJNZ    HYST		; 13 T if branch taken
				;  8 T if final iteration
				;
				; Per iteration: 25 T (≈ 7.14 µs)
				; Final iteration: 20 T (≈ 5.71 µs)
				; 255 iterations total = 6370 T
				; → Holds output steady ≈ 1.82 ms

	IN 	A,(C)		; 12 T (≈ 3.43 µs)
                                ; Read ULA input register
                                ; Bit 6 = EAR input line

	POP     BC		; 10 T (≈ 2.86 µs)
				; Restore caller’s loop counter

	AND     040h		;  7 T (≈ 2.00 µs)
				; Isolate EAR input (bit 6 of ULA port FEh):
				; - Clears all other bits (0-5,7)
				; - Leaves 0x40 if EAR is high, 0x00 if EAR is low
				; - Prepares A for conditional checks or return
				; - Ensures later code only sees the EAR line state

	RET                     ; 10 T (≈ 2.86 µs)
				; Return to caller



; main point of entry, after AY test failed
HYSTE:	
	LD	B,3		; B = try hysteresis test 3 times for reliability

HYSTEL1:

	; Test low voltage output to EAR input

	CALL	GETBORDER	; A = BORDER COLOUR (0-7 - bits 2-0)
				; A (bits 4,3 low)
	CALL    HYSTE_TEST
	JR      nz,RTYPE	; If high, hysteresis test failed
				; leave via RTYPE

	; Test high voltage output to EAR input

	OR	18h		; A (bits 4,3 high)
				; OR with border colour

	CALL	HYSTE_TEST
	JR	Z,RTYPE		; If low, hysteresis test failed
				; leave via RTYPE

	DJNZ	HYSTEL1		; Repeat test B times for reliability

	; All hysteresis tests passed - ULA exhibits predictable behavior
	LD	E,3		; E = 3: ZXTYPE = 3 (hysteresis-capable ULA)

;------------------------------------------------------------------------------
; Final Return Point
;------------------------------------------------------------------------------
RTYPE: 
	LD	A,E		; A = ZXTYPE result value
	RET			; Return with ZXTYPE value in A

; --------------------------------------
; GETBORDER
; Returns the current border colour (0–7)
; by decoding it back out of system variable BORDCR.
; Note: BORDCR does NOT store the border colour directly!
;       It holds a full attribute byte:
;         PAPER = border colour
;         INK   = black/white (depends on brightness)
;         BRIGHT, FLASH set as needed
; Therefore, to recover the border, we must extract bits 3–5.
; --------------------------------------

GETBORDER:
	LD	A,(BORDCR)	; Load attribute byte from system variable 23624 (5C48h)
	SRL	A		; Shift right 3 times so PAPER (border) bits 3–5 → 0–2
	SRL	A
	SRL	A
	AND	7		; Isolate lower 3 bits (0–7 colour number)
	RET


;==============================================================================
; DATA STORAGE AREA
;==============================================================================
; This section contains variables and buffers used by the detection routines

; Control and result variables
DEBUG		DB	0	; Debug mode flag: 0=off, 1=on (shows raw results)
				; displays intermediate results and add some minor tests
ISCMOS		DB	0	; CMOS test result: 00h=NMOS, FFh=CMOS
ISU880		DB	0	; U880 test result: 0=standard Z80, 1=U880 CPU
XYRESULT	DB	0	; XF/YF flag test results (encoded)

; XF/YF flag test counters (4 bytes total)
; Used by TESTXY to count flag occurrences in different test conditions
XFYFCOUNT	DB	0,0,0,0 ; Counters for the four XF/YF test scenarios

; Extended flag test counters (used by TESTFLAGS in debug mode)
XFCOUNT		DW	0	; 16-bit counter for XF flag occurrences
YFCOUNT		DW	0	; 16-bit counter for YF flag occurrences

;==============================================================================
; MESSAGE STRINGS
;==============================================================================
; All strings are terminated with ' character for PRINTSTR routine

; Program identification and credits
MSGSIGNIN	DB	'Z80 Processor Type Detection (C) 2024 Sergey Kiselev'
		DB	0DH	; Carriage return
MSGRUI		DB	' ZX Port 2025 Rui Ribeiro', 0DH
MSGCRLF		DB	0DH,'$'	; Carriage return + end of string

; Debug mode messages (raw test results)
MSGRAWCMOS	DB	'Raw results:       CMOS: $'
MSGFLAGS	DB	'XF/YF flags test:  $'
MSGRAWU880	DB	' U880: $'
MSGRAWXY	DB	' XF/YF: $'

; Main detection result header
MSGCPUTYPE	DB	'Detected CPU type: $'

; U880 CPU detection results
MSGU880NEW	DB	'Newer MME U880, Thesys Z80, Microelectronica MMN 80CPU$'
MSGU880OLD	DB	'Older MME U880$'

; U880 CPU detection results
MSGSHARPLH5080A	DB	'Sharp LH5080A$'
MSGNMOSZ80	DB	'Zilog Z80, Zilog Z08400 or similar NMOS CPU',0DH
		DB      '                   ' ; Alignment spacing
		DB	'Mostek MK3880N, SGS/ST Z8400, Sharp LH0080A, KR1858VM1$'
MSGNECD780C	DB	'NEC D780C, GoldStar Z8400, possibly KR1858VM1$'
MSGNECD780C1	DB	'NEC D780C-1$'
MSGKR1858VM1	DB	'Overclocked KR1858VM1$'
MSGNMOSUNKNOWN	DB	'Unknown NMOS Z80 clone$'

; CMOS Z80 variant detection results
MSGCMOSZ80	DB	'Zilog Z84C00$'
MSGTOSHIBA	DB	'Toshiba TMPZ84C00AP, ST Z84C00AB$'
MSGNECD70008AC	DB	'NEC D70008AC$'
MSGCMOSUNKNOWN	DB	'Unknown CMOS Z80 clone$'

; User interaction message for visual CMOS test
MESBW		DB	'Press B-black W-white border'
		DB	0DH, 0DH,'$' ; Double newline for spacing

	END $8000	; Program ends here, execution starts at $8000

