; Z80TYPE.ASM - DETERMINE AND PRINT Z80 CPU TYPE
; WRITTEN BY SERGEY KISELEV <SKISELEV@GMAIL.COM>
; PORTED TO Z80 Zilog format/Timex Rui Ribeiro/2025 <ruyrybeyro@gmail.com>
;
; RUNS ON TIMEX 2048/2068 SYSTEMS WITH ZILOG Z80 AND COMPATIBLE PROCESSORS
; USES TIMEX CONTROL REGISTER FOR TESTS
;
; "BDOS" call
WRCHR	EQU	2 		; print char
WRSTR	EQU	9		; print string

; TIMEX CONTROL REGISTER
SIOBC	EQU	0FFH

	ORG	8000H
	ld de,MSGSIGNIN
	call PRINTSTR
	
ARGDEBUG:
	ld a,0			; change to 1 if needed
	ld hl,DEBUG
	ld (hl),a
	
NOARGS:
	call TESTCMOS
	ld hl,ISCMOS
	ld (hl),a		; store result to ISCMOS
		
	call TESTU880
	ld hl,ISU880
	ld (hl),a		; store result to ISU880
	
	call TESTXY
	ld hl,XYRESULT
	ld (hl),a
;-------------------------------------------------------------------------
; Debug
	ld hl,DEBUG
	ld a,(hl)
	cp 0
	jp z,DETECTCPU
	
	ld hl,ISCMOS
	ld a,(hl)
	ld de,MSGRAWCMOS	; display CMOS test result
	call PRINTSTR
	call PRINTHEX
	
	ld hl,ISU880
	ld a,(hl)		; store result to ISU880	
	ld de,MSGRAWU880	; display U880 test result
	call PRINTSTR
	call PRINTHEX
	ld hl,XYRESULT
	ld a,(hl)
	ld de,MSGRAWXY	; display XF/YF flags test result
	call PRINTSTR
	call PRINTHEX
	ld de,MSGCRLF
	call PRINTSTR
	
	call TESTFLAGS	; TEST HOW FLAGS SCF AFFECTS FLAGS
;-------------------------------------------------------------------------
; CPU detection logic
DETECTCPU:
	ld de,MSGCPUTYPE
	call PRINTSTR
; check for U880 CPU
	ld hl,ISU880
	ld a,(hl)
	cp 0		; Is it a U880?
	jp z,CHECKZ80	; check Z80 flavor
	
	ld hl,XYRESULT
	ld a,(hl)
	cp 0FFH		; does it always set XF/YF?
	ld de,MSGU880NEW
	jp z,DONE		; jump if a new U880/Thesys Z80
	ld de,MSGU880OLD
	 jp DONE
; check for Z80 type
CHECKZ80:
	ld hl,ISCMOS
	ld a,(hl)
	cp 0		; Is it a NMOS CPU?
	jp nz,CHECKCMOS	; check CMOS Z80 flavor
; check for Sharp LH5080A
	ld hl,XYRESULT
	ld a,(hl)
	cp 30H
	jp z,SHARPLH5080A
	cp 0FFH		; does it always set XF/YF?
	jp z,NMOSZ80
	cp 0FDH		; does it sometimes not set XF when FLAGS.3=1?
	jp z,NECU780C
	cp 0F4H
	jp z,KR1858VM1
	ld de,MSGNMOSUNKNOWN
	 jp DONE
SHARPLH5080A:
	ld de,MSGSHARPLH5080A
	 jp DONE
	
NMOSZ80:
	ld de,MSGNMOSZ80
	 jp DONE
	
NECU780C:
	ld de,MSGNECD780C
	 jp DONE
KR1858VM1:
	ld de,MSGKR1858VM1
	 jp DONE
CHECKCMOS:
	ld hl,XYRESULT
	ld a,(hl)
	cp 0FFH		; does it always set XF/YF?
	jp z,CMOSZ80
	cp 3FH		; does it never set YF when A.5=1?
	jp z,TOSHIBA
; test for NEC D70008AC. These CPUs seem to behave as following:
; A.5=1 & F.5=0 => YF=1
; A.3=1 & F.3=0 => XF is not set at all, or only sometimes is set
; A.5=0 & F.5=1 => YF is sometimes set
; A.3=0 & F.3=1 => XF is sometimes set
; Note: All of 3 D70008AC that I have behave a bit differently here
;       this might need to be updated when more tests are done
	cp 20H		; YF is often set when A.5=1?
	jp nc,CMOSUNKNOWN	; XYRESULT > 1Fh, not a NEC...
	and 0FH		; F.5=1 & A.5=0 and F.3=1 & A.3=0 results
	cp 03H		; F.5=1 & A.5=0 never result in YF set?
	jp c,CMOSUNKNOWN
	and 03H		; F.3=1 & A.3=0 results
	jp nz,NEC
CMOSUNKNOWN:	
	ld de,MSGCMOSUNKNOWN
	 jp DONE
	
CMOSZ80:
	ld de,MSGCMOSZ80
	 jp DONE
TOSHIBA:
	ld de,MSGTOSHIBA
	 jp DONE
NEC:
	ld de,MSGNECD70008AC
	 jp DONE
DONE:
	call PRINTSTR
	ld de,MSGCRLF
	call PRINTSTR
	ret			; RETURN TO CP/M
	
;-------------------------------------------------------------------------
; TESTCMOS - Test if the CPU is a CMOS variety according to OUT (C),0 test
; Note: CMOS Sharp LH5080A is reported as NMOS
; Input:
;	None
; Output:
;	A = 00 - NMOS
;	A = FF - CMOS
;------------------------------------------------------------------------- 
TESTCMOS:
; NMOS/CMOS CPU DETECTION ALGORITHM:
; 1. DISABLE INTERRUPTS
; 2. READ AND SAVE TIMEX CONTROL REGISTER
; 3. MODIFY TIMEX CONTROL REGISTER USING OUT (C),<0|0FFH>
;    (DB 0EDH, 071H) UNDOCUMENTED INSTRUCTION:
;      ON AN NMOS CPU: OUT (C),0
;      ON A CMOS CPU: OUT (C),0FFH
; 4. READ AND SAVE TIMEX CONTROL REGISTER
; 5. RESTORE TIMEX CONTROL REGISTER
; 6. ENABLE INTERRUPTS
; 7. CHECK THE VALUE READ BACK IN STEP 4
;      0 - NMOS CPU
;      0FFH - CMOS CPU

	di
	in a,(SIOBC)		; READ THE CURRENT INTERRUPT VECTOR
	ld b,a			; SAVE THE ORIGINAL VECTOR TO REGISTER B
	ld c,SIOBC
	DB	0EDH, 071H	; UNDOCUMENTED OUT (C),<0|0FFH> INSTRUCTION
				; WRITE 0 OR FF TO TIMEX CONTROL REGISTER
	in a,(SIOBC)		; READ TIMEX CONTROL REGISTER
	ld c,a			; SAVE TO REGISTER C
	ld a,b			; RESTORE TIMEX CONTROL REGISTER
	out (SIOBC),a		; WRITE IT TO TIMEX CONTROL REGISTER
	ei
	ld a,c			; VALUE WRITTEN BY OUT (C),<0|0FFH> INSTRUCTION
	ret
;-------------------------------------------------------------------------
; TESTU880 - Check if the CPU is MME U880 or Thesys Z80
; Input:
;	None
; Output:
;	A = 0 - Non-U880
;	A = 1 - U880
;-------------------------------------------------------------------------
TESTU880:
	ld hl,0FFFFH
	ld bc,00100H+SIOBC	; USE TIMEX CONTROL REGISTER FOR TESTS
	di

	in a,(SIOBC)		; READ TIMEX CONTROL REGISTER
	scf
	DB	0EDH,0A3H	; Z80 OUTI INSTRUCTION
	push af		; SAVE THE ORIGINAL TIMEX CONTROL REGISTER ON THE STACK
	pop af		; RESTORE THE TIMEX CONTROL REGISTER
	out (SIOBC),a		; WRITE IT TO TIMEX CONTROL REGISTER
	ei
	ld a,1		; Assume it is a U880, set A = 1
	jp c,TESTU880DONE	; It is a U880, exit
	xor a		; Not a U880, set A = 00
TESTU880DONE:
	ret
;-------------------------------------------------------------------------
; TESTXY - Tests how SCF (STC) instruction affects FLAGS.5 (YF) and FLAGS.3 (XF)
; Input:
;	None
; Output:
;	A[7:6] - YF result of F = 0, A = C | 0x20 & 0xF7
;	A[5:4] - XF result of F = 0, A = C | 0x08 & 0xDF
;	A[3:2] - YF result of F = C | 0x20 & 0xF7, A = 0
;	A[1:0] - XF result of F = C | 0x08 & 0xDF, A = 0
;	Where the result bits set as follows:
;	00 - YF/XF always set as 0
;	11 - YF/XF always set as 1
;	01 - YF/XF most of the time set as 0
;	10 - YF/XF most of the time set as 1
;-------------------------------------------------------------------------
TESTXY:
	ld c,0FFH		; loop counter
	
TESTXY1:
	ld hl,XFYFCOUNT	; results stored here
; check F = 0, A = C | 0x20 & 0xF7
	ld e,00H		; FLAGS = 0
	ld a,c
	or 020H		; A.5 = 1
	and 0F7H		; A.3 = 0
	ld d,a		; A = C | 0x20 & 0xF7
	push de		; PUSH DE TO THE STACK
	pop af		; POP A AND FLAGS FROM THE STACK (DE)
	scf			; SET CF FLAG, DEPENDING ON THE CPU TYPE THIS
				; ALSO MIGHT CHANGE YF AND XF FLAGS
	call STOREYCOUNT
; check F = 0, A = C | 0x08 & 0xDF
	ld e,00H		; FLAGS = 0
	ld a,c
	or 08H		; A.3 = 1
	and 0DFH		; A.5 = 0
	ld d,a		; A = C | 0x08 & 0xDF
	push de		; PUSH DE TO THE STACK
	pop af		; POP A AND FLAGS FROM THE STACK (DE)
	scf			; SET CF FLAG, DEPENDING ON THE CPU TYPE THIS
				; ALSO MIGHT CHANGE YF AND XF FLAGS
	call STOREXCOUNT
; check F = C | 0x20 & 0xF7, A = 0
	ld a,c
	or 020H		; FLAGS.5 = 1
	and 0F7H		; FLAGS.3 = 0
	ld e,a		; FLAGS = C | 0x20 & 0xF7
	ld d,00H		; A = 0
	push de		; PUSH DE TO THE STACK
	pop af		; POP A AND FLAGS FROM THE STACK (DE)
	scf			; SET CF FLAG, DEPENDING ON THE CPU TYPE THIS
				; ALSO MIGHT CHANGE YF AND XF FLAGS
	call STOREYCOUNT
; check F = C | 0x08 & 0xDF, A = 0
	ld a,c
	or 08H		; FLAGS.3 = 1
	and 0DFH		; FLAGS.5 = 0
	ld e,a		; FLAGS = C | 0x08 & 0xDF
	ld d,00H		; A = 0
	push de		; PUSH DE TO THE STACK
	pop af		; POP A AND FLAGS FROM THE STACK (DE)
	scf			; SET CF FLAG, DEPENDING ON THE CPU TYPE THIS
				; ALSO MIGHT CHANGE YF AND XF FLAGS
	call STOREXCOUNT
	dec c
	jp nz,TESTXY1
	
	ld c,4		; iteration count - number of bytes
	ld hl,XFYFCOUNT	; counters
TESTXY2:
	rla
	rla
	and 0FCH		; zero two least significant bits
	ld b,a		; store A to B
	ld a,(hl)
	cp 7FH
	jp nc,TESTXY3		; jump if the count is 0x80 or more
	cp 0
	jp z,TESTXY5		; the count is 0 leave bits at 0
	ld a,1		; the count is between 1 and 0x7F, set result bits to 01
	 jp TESTXY5
TESTXY3:
	cp 0FFH
	ld a,2		; the count is between 0x80 and 0xFE, set result bits to 10
	jp nz,TESTXY4
	ld a,3		; the count is 0xFF, set result bits to 11
	 jp TESTXY5
TESTXY4:
	ld a,1		; the count is 0x7F or less, set result bits to 01
TESTXY5:
	or b
	inc hl
	dec c
	jp nz,TESTXY2
	ret
;-------------------------------------------------------------------------
; STOREXCOUNT - Isolates and stores XF to the byte counter at (HL)
; Input:
;	FLAGS	- flags
;	HL	- pointer to the counters
; Output:
;	HL	- incremented by 1 (points to the next counter)
; Trashes A and DE
;-------------------------------------------------------------------------
STOREXCOUNT:
	push af		; transfer flags
	pop de		; to E register
	ld a,e
	and 08H		; isolate XF
	jp z,STOREXDONE
	inc (hl)		; increment the XF counter (HL)
STOREXDONE:
	inc hl		; point to the next entry
	ret
;-------------------------------------------------------------------------
; STOREYCOUNT - Isolates and stores YF to the byte counter at (HL)
; Input:
;	FLAGS	- flags
;	HL	- pointer to the counters
; Output:
;	HL	- incremented by 1 (points to the next counter)
; Trashes A and DE
;-------------------------------------------------------------------------
STOREYCOUNT:
	push af		; transfer flags
	pop de		; to E register
	ld a,e
	and 20H		; isolate YF
	jp z,STOREYDONE
	inc (hl)		; increment the YF counter (HL)
STOREYDONE:
	inc hl		; point to the next entry
	ret
	
;-------------------------------------------------------------------------
; TESTFLAGS - TEST HOW SCF INSTRUCTION AFFECTS YF AND XF FLAGS
; NOTE: YF IS FLAGS.5 AND XF IS FLAGS.3
; INPUT:
;	NONE
; OUTPUT:
;	PRINTED ON CONSOLE
;-------------------------------------------------------------------------	
TESTFLAGS:
	ld de,MSGFLAGS
	ld c,WRSTR
	call BDOS
	ld d,00H
TFLOOP1:
	ld e,00H
TFLOOP2:
	push de
	di
	push de		; PUSH DE TO THE STACK
	pop af		; POP A AND FLAGS FROM THE STACK (DE)
	ccf			; SET CF FLAG, DEPENDING ON THE CPU TYPE THIS
				; ALSO MIGHT CHANGE YF AND XF FLAGS
	push af		; STORE A AND F
	pop de		; NEW FLAGS IN E
	ei
	ld a,e		; FLAGS TO ACCUMULATOR
	pop de
	 jp CONT
PRINTFLAGS:
	call PRINTHEX	; PRINT ACCUMULATOR
	ld a,e		; FLAGS TO ACCUMULATOR
	pop de
	push af
	ld a,d		; PRINT ORIGINAL ACCUMULATOR(FLAGS)
	call PRINTHEX
	pop af
	call PRINTHEX	; PRINT NEW FLAGS
	push de
	ld de,MSGCRLF
	call PRINTSTR
	pop de
CONT:
	ld hl,XFCOUNT	; POINT TO XF COUNTER
	rrca			; BIT 3 TO CF
	rrca
	rrca
	rrca
	jp nc,TFLOOP4
	inc (hl)		; INCREMENT COUNTER IF FLAG IS SET
	jp nz,TFLOOP4		; NO OVERFLOW
	inc hl		; MOVE TO THE HIGH BIT
	inc (hl)		; INCREMENT HIGHER BIT
TFLOOP4:
	ld hl,YFCOUNT	; POINT TO YF COUNTER
	rrca			; BIT 5 TO CF
	rrca
	jp nc,TFLOOP5
	inc (hl)		; INCREMENT COUNTER IF FLAG IS SET
	jp nz,TFLOOP5		; NO OVERFLOW
	inc hl		; MOVE TO THE HIGH BIT
	inc (hl)		; INCREMENT HIGHER BIT
TFLOOP5:
	inc e
	jp nz,TFLOOP2
	inc d		; INCREMENT D
	jp nz,TFLOOP1
; PRINT VALUES
	ld c,4		; 4 BYTES
	ld hl,YFCOUNT+1	; POINT AT THE MSB
TFLOOP6:
	ld a,(hl)
	call PRINTHEX
	dec hl
	dec c
	jp nz,TFLOOP6		; PRINT NEXT DIGIT
	ld de,MSGCRLF
	ld c,WRSTR
	call BDOS
	ret
; PRINT VALUES
	ld hl,YFCOUNT+1	; MSB OF YF COUNT
	ld a,(hl)
	call PRINTHEX
	dec hl		; LSB OF YF COUNT
	ld a,(hl)
	call PRINTHEX
	ld hl,XFCOUNT+1	; MSB OF XF COUNT
	ld a,(hl)
	call PRINTHEX
	dec hl		; LSB OF XF COUNT
	ld a,(hl)
	call PRINTHEX
	ld de,MSGCRLF
	ld c,WRSTR
	call BDOS
	ret
;-------------------------------------------------------------------------
; PRINTHEX - PRINT BYTE IN HEXADECIMAL FORMAT
; INPUT:
;	A - BYTE TO PRINT
; OUTPUT:
;	NONE
;-------------------------------------------------------------------------
PRINTHEX:
	push bc
	push de
	push hl
	push af		; SAVE PRINTED VALUE ON THE STACK
	rrca			; ROTATE HIGHER 4 BITS TO LOWER 4 BITS
	rrca
	rrca
	rrca
	call PRINTDIGIT	; PRINT HIGHER 4 BITS
	pop af		; RESTORE PRINTED VALUE
	push af		; PUSH IT TO THE STACK AGAIN
	call PRINTDIGIT	; PRINT LOWER 4 BITS
	pop af	
	pop hl
	pop de
	pop bc
	ret
;-------------------------------------------------------------------------	
; PRINTDIGIT - PRINT DIGIT IN HEXADECIMAL FORMAT
; INPUT:
;	A - DIGIT TO PRINT, LOWER 4 BITS 
; OUTPUT:
;	NONE
; TRASHES REGISTERS A, FLAGS, BC, DE, HL
;-------------------------------------------------------------------------	
PRINTDIGIT:
	and 0FH		; ISOLATE LOWER 4 BITS
	add a,'0'		; CONVERT TO ASCII
	cp '9'+1		; GREATER THAN '9'?
	jp c,PRINTIT
	add a,'A'-'9'-1	; CONVERT A-F TO ASCII
	
PRINTIT:
	ld e,a
	ld c,WRCHR
	call BDOS
	ret
;-------------------------------------------------------------------------
; PRINTSTR - Print string
; INPUT:
;	D - address of the string to print
; OUTPUT:
;	None
; Note: String must be terminated with a dollar sign
;-------------------------------------------------------------------------
PRINTSTR:
	push af
	push bc
	push de
	push hl
	ld c,WRSTR
	call BDOS
	pop hl
	pop de
	pop bc
	pop af
	ret

BDOS    PUSH    AF
        LD      A,C
        CP      2
        JR      NZ,PRSTR
        LD      A,E
        CALL    PRCHAR
        JR      BEND
PRSTR   LD      A,(DE)
        CP      '$'
        JR      Z,BEND
        CALL    PRCHAR
        INC     DE
        JR      PRSTR
BEND    POP     AF
        RET

PRCHAR  PUSH    DE
        PUSH    HL
        PUSH    BC
        CP      10
        JR      Z,NOTPRINT
        RST     $10
NOTPRINT:
        POP     BC
        POP     HL
        POP     DE
        RET


DEBUG		DB	0
ISCMOS		DB	0
ISU880		DB	0
XYRESULT	DB	0
XFYFCOUNT	DB	0,0,0,0
XFCOUNT		DW	0
YFCOUNT		DW	0
MSGSIGNIN	DB	'Z80 Processor Type Detection (C) 2024 Sergey Kiselev'
		DB	0DH
MSGRUI		DB	' 2025 Ported Timex Rui Ribeiro', 0DH
MSGCRLF		DB	0DH,'$'
MSGUSAGE	DB	'Invalid argument. Usage: z80type [/D]',0DH,'$'
MSGRAWCMOS	DB	'Raw results:       CMOS: $'
MSGFLAGS	DB	'XF/YF flags test:  $'
MSGRAWU880	DB	' U880: $'
MSGRAWXY	DB	' XF/YF: $'
MSGCPUTYPE	DB	'Detected CPU type: $'
MSGU880NEW	DB	'Newer MME U880, Thesys Z80, Microelectronica MMN 80CPU$'
MSGU880OLD	DB	'Older MME U880$'
MSGSHARPLH5080A	DB	'Sharp LH5080A$'
MSGNMOSZ80	DB	'Zilog Z80, Zilog Z08400 or similar NMOS CPU',0DH
		DB      '                   '
		DB	'Mostek MK3880N, SGS/ST Z8400, Sharp LH0080A, KR1858VM1$'
MSGNECD780C	DB	'NEC D780C, GoldStar Z8400, possibly KR1858VM1$'
MSGKR1858VM1	DB	'Overclocked KR1858VM1$'
MSGNMOSUNKNOWN	DB	'Unknown NMOS Z80 clone$'
MSGCMOSZ80	DB	'Zilog Z84C00$'
MSGTOSHIBA	DB	'Toshiba TMPZ84C00AP, ST Z84C00AB$'
MSGNECD70008AC	DB	'NEC D70008AC$'
MSGCMOSUNKNOWN	DB	'Unknown CMOS Z80 clone$'
	END $8000
