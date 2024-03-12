;----------------------------------------------------------------------------
;--- bBasic Custom kernel for BruceLee 
;--
;--- Overrides bBasic Multi-sprite kernel
;---
;----------------------------------------------------------------------------

    align 256

__MCMSK_START:

;show_kernel_stats = 1

;--------------------------------------------------
;--- Constants

KERNEL_VBLANK_TIME   = $28  ;--33.6 * 76 / 64
KERNEL_DISPLAY_TIME  = $E4  ;--192 * 76 / 64
KERNEL_OVERSCAN_TIME = $25  ;--31.2 * 76 / 64

SCREEN_HEIGHT           = 80
SPR_OFS                 = 2



;--------------------------------------------------
;--- Temporary Variables

;--- NOTE:  $f6 is used as temporary storage of the Stack Pointer during the kernel, 
;             so it cannot be used here


;==================================================================
;==== CODE
;=============

multisprite_setup

    ;--- make sure display kernel starts relatively quick
    LDA		#KERNEL_OVERSCAN_TIME
    STA		TIM64T
    RTS



;----------------------------------------------------------------------
;--  Horizontal Position Routine
;----------------------------------------------------------------------
; Call this function with 
;       A == horizontal position (0-159)
;   and X == the object to be positioned (0=P0, 1=P1, 2=M0, etc.)
;
; If you do not wish to write to P1 during this function, make
; sure Y==0 before you call it.  This function will change Y, and A
; will be the value put into HMxx when returned.
; Call this function with at least 11 cycles left in the scanline 
; (jsr + sec + sta WSYNC = 11); it will return 9 cycles
; into the second scanline

PositionASpriteSubroutine        
    SEC
    STA		WSYNC               	;begin line 1
    STA.w	HMCLR               	;+4         4
DivideBy15Loop
    SBC 	#15
    BCS 	DivideBy15Loop          ;+4/5        8/13.../58

    TAY                         	;+2        10/15/...60
    LDA 	FineAdjustTableEnd,Y    ;+5        15/20/...65

    STA 	HMP0,X                  ;+4        19/24/...69
    STA 	RESP0,X                 ;+4        23/28/33/38/43/48/53/58/63/68/73
    STA 	WSYNC                   ;+3         0        begin line 2
    STA 	HMOVE                   ;+3
    RTS                         	;+6         9



;=====================================================================
;---------------------------------------------------------------------

drawscreen

WaitForOverscanEnd
    lda TIMINT
    bpl WaitForOverscanEnd

	;------ Vertical Sync
    lda #2
    sta WSYNC
    sta VSYNC
    sta WSYNC
    sta WSYNC
    lsr
    sta VDELBL
    sta VDELP0
    sta WSYNC
    sta VSYNC        ;turn off VSYNC

    lda #KERNEL_OVERSCAN_TIME
    sta TIM64T

; run possible vblank bB code
  ifconst vblank_bB_code
    jsr vblank_bB_code
  endif


	;--- load which enemy to show this frame
	LDA     mainTimer
	AND     #$1
	STA     .enemyNum


    ;-------------
    ;--position P0, P1, M0, M1, BL

    ldx #4
    lda ballx
    jsr PositionASpriteSubroutine
    
    dex
    lda missile1x
    jsr PositionASpriteSubroutine
    
    dex
    lda missile0x
    jsr PositionASpriteSubroutine

    dex
	lda player0x
	jsr PositionASpriteSubroutine

	ldy .enemyNum
    dex
    lda player1x,y
    jsr PositionASpriteSubroutine


;-----------------------------
    ;--some final setup
	;--prep for late-HMOVE

    ldx #4
    lda #$80
cycle74_HMCLR
    sta HMP0,X
    dex
    bpl cycle74_HMCLR


    lda #0
	sta PF0
    sta PF1
    sta PF2
    sta GRP0
    sta GRP1
	jmp drawKernelASM





;-------------------------------------------------------------------------
;----------------------Kernel Routine-------------------------------------
;-------------------------------------------------------------------------
    
START_OF_KERNEL_ROUTINES:

 ;SUBROUTINE
 ;-- Local Variables

.lanternDrawPF      = $DA		;--  4 byte buffer for lantern playfield data

.line               = $DE
.row                = $DF
.enemyNum           = $E0

.p1drawY            = $E2
.p0drawY            = $E3

.curPlayerPtr       = $E4
.curPlayerColPtr    = $E6
.playerMask         = $E8
.curEnemyPtr        = $EA
.curEnemyColorPtr   = $EC
.enemyMask          = $EE

PLAYER_HEIGHT   = 16
PLAYER_SCRN_OFS = 3    ;//--- this offsets the player with a row
ENEMY_SCRN_OFS  = 4

TOP_ROW              = $13  ;--
TOP_ROW_Y            = $9F  ;--TOP_ROW * 8 + 7

SCREEN_BOTTOM		 = SCREEN_HEIGHT + 16  ;-- bottom of screen is (height+16)

PLAYER_FACING        = $08  ;--


drawKernelASM:
    TSX
    STX     stack1

	;---------------------------------------------------------
	;--- prepare player character pointer

	;-- char p0drawY = (playerY >> 1) + PLAYER_SCRN_OFS;		// this is a count
	LDA     player0y
	LSR  
	CLC
	ADC     #PLAYER_SCRN_OFS
	STA     .p0drawY
	
	;-- char *curPlayerPtr	  = playerPtr - p0drawY
	LDA     player0pointerlo
	LDX     player0pointerhi
	
	;--- need to adjust pointer to start at bottom of sprite
	;---     so that sprite is able to go off top of screen
	CLC
	ADC 	#16
	BCC 	*+$3
	INX

	SEC
	SBC     .p0drawY
	BCS     *+$3
	DEX
	STA     .curPlayerPtr
	STX     [.curPlayerPtr+1]
	
	;-- char *curPlayerColPtr = playerColors - 80 + p0drawY
	LDA     #<[SpriteColorTables+15]  ; player0colorPlo
	LDX     #>[SpriteColorTables+15]  ; player0colorPhi
    CLC
    ADC     player0pal
    BCC     *+$3
    INX
	SEC
	SBC     .p0drawY
	BCS     *+$3
	DEX
	STA     .curPlayerColPtr
	STX     [.curPlayerColPtr+1]

	;-- char *playerMask = &maskZone[80] - p0drawY
	LDA     #<[maskZone+SCREEN_BOTTOM]
	LDX     #>[maskZone+SCREEN_BOTTOM]
	SEC
	SBC     .p0drawY
	BCS     *+$3
	DEX
	STA     .playerMask
	STX     [.playerMask+1]

	LDY 	.enemyNum
	LDA     #$10
	STA     NUSIZ1

	LDA     player1y,y          	;-- load from array using index with offset
	LSR  
	CLC
	ADC     #ENEMY_SCRN_OFS
	STA     .p1drawY
	                                	
	;-- char *curEnemyPtr 		= curEnemy.gfxPtr - p1drawY
	LDA 	.enemyNum
	ASL
	TAY
	LDA     player1pointerlo,y          	;-- load from array using index with offset
	LDX     player1pointerhi,y

	;--- need to use adjust pointer to start at bottom of sprite
	;---     to allow for sprite to go off top of screen
	CLC
	ADC 	#16
	BCC 	*+$3
	INX

	SEC
	SBC     .p1drawY
	BCS     *+$3
	DEX
	STA     .curEnemyPtr
	STX     [.curEnemyPtr+1]
	
	LDY	.enemyNum
	;-- char *curEnemyColorPtr = curEnemy.colorPtr - p1drawY
	LDA     #<[SpriteColorTables+16]
	LDX     #>[SpriteColorTables+16]
	CLC
    ADC     player1pal,y
    BCC     *+$3
    INX
	SEC
	SBC     .p1drawY
	BCS     *+$3
	DEX
	STA     .curEnemyColorPtr
	STX     [.curEnemyColorPtr+1]
	
	;-- char *enemyMask = &maskZone[80] - p1drawY
	LDA     #<[maskZone+SCREEN_BOTTOM]
	LDX     #>[maskZone+SCREEN_BOTTOM]
	SEC
	SBC     .p1drawY
	BCS     *+$3
	DEX
	STA     .enemyMask
	STX     [.enemyMask+1]

	;------------------------------------------------------
	                                	;-- Line #166 :		TIA.refp1 = playerState & PLAYER_FACING;
	LDA     playerState
	AND     #PLAYER_FACING
	STA     REFP1
	                                	;-- Line #167 :		TIA.refp0 = curEnemy.state & PLAYER_FACING;
	LDA     blackNinjaState,y  ;_NUSIZ1,y
	AND     #PLAYER_FACING
	STA     REFP0

	;------ load first row of lantern data into a buffer for the kernel
	LDA     [screenLanternsPF+0]
	STA     <[.lanternDrawPF+$0]
	LDA     [screenLanternsPF+1]
	STA     <[.lanternDrawPF+$1]
	LDA     [screenLanternsPF+2]
	STA     <[.lanternDrawPF+$2]
	LDA     [screenLanternsPF+3]
	STA     <[.lanternDrawPF+$3]

WaitForScreenStart:                    	;-- Line #194 :	    while (RIOT.timint >= 0) {}
	LDA     TIMINT
	BPL     WaitForScreenStart


	;----------------------------------------------------------------------
	;--- Start of Display

L001D:

	STA     WSYNC
	LDA     #$0
	STA     VBLANK						;--- Turn on beam
	STA 	CXCLR						;--- clear out collisions
	                                	
	LDA     #<KERNEL_DISPLAY_TIME		;--  start display timer
	STA     TIM64T

	LDA     #<TOP_ROW					;-- set row counter
	STA     .row
	
	;-------------------------------------
	;---- Main Display Loop

	STA     WSYNC                                	
	LDY     #SCREEN_HEIGHT
DrawLoopStart:

	;// Load in info for next row of graphics

		LDX 	.row				;3	[3]

		LDA 	screenBgColor,x		;4	[7]		-- load background color for row
		STA 	COLUBK  			;3	[10]
		AND		#1					;2	[12]	-- bit 0 of background color is used to
		STA 	CTRLPF  			;3	[15]	-- set mirrored vs repeating playfield


		;---- jump to the kernel needed for this row

		LDA 	screenKernelType,X
		BMI  	LanternKernel

		CMP 	#$40
		BCC		RegularKernel

		JMP 	AsymKernel

		;--------------------------------------------------------
		;--- Regular kernel - Symmetric
		;--
		;--  Blocking wall uses missile 1 (shares color with Bruce Lee)

RegularKernel:
		;--- prep work for blocking wall
		AND 	#$32				;2  [48]  --- mask off kernelType bits that don't apply
		STA 	<missile1y 			;3	[51]
		AND 	#$F0				;2	[53]
		STA 	NUSIZ1				;3	[56]

		LDA 	screenData,x		;4	[60]
		TAX							;2	[62]	--- X = bitmapOfs = screenData[row]

;NormalDrawLoopStart:
        ;/* main row loop */
        LDA 	#4					;2	[23]
		STA 	.line				;3	[26]
        ;//do {
LineLoop:
			DEY
            ;/* even lines, sprite 0 */
			
			STA 	WSYNC
			LDA 	bitmapColors,x			;4	[4]
			STA 	COLUPF  				;3	[7]  -- TIA.colupf = bitmapColors[bitmapOfs];
			LDA 	bitmapPF0,x				;4	[11]
			STA 	PF0 					;3	[14] -- TIA.pf0 = bitmapPF0[bitmapOfs];
			LDA 	bitmapPF1,x				;4	[18]
			STA 	PF1 					;3	[21] -- TIA.pf1 = bitmapPF1[bitmapOfs];
			LDA 	bitmapPF2,x				;4	[25]
			STA 	PF2 					;3	[28] -- TIA.pf2 = bitmapPF2[bitmapOfs];
			DEX								;2	[30]
			
			LDA		(.curPlayerPtr),y	    ;5	[35]
			AND 	(.playerMask),y		    ;5	[40]
			STA 	GRP1    			    ;3	[43]
			LDA 	(.curPlayerColPtr),y	;5	[48]
			AND 	(.playerMask),y		    ;5	[40]
			STA		COLUP1  			    ;3	[51]

			;LDA 	#0
			;STA 	ENAM1

            ;/* odd lines, sprite 1 */
			STA 	WSYNC
			LDA 	bitmapColors,x			;4	[4]
			STA 	COLUPF  				;3	[7]  -- TIA.colupf = bitmapColors[bitmapOfs];
			LDA 	bitmapPF0,x				;4	[11]
			STA 	PF0 					;3	[14] -- TIA.pf0 = bitmapPF0[bitmapOfs];
			LDA 	bitmapPF1,x				;4	[18]
			STA 	PF1 					;3	[21] -- TIA.pf1 = bitmapPF1[bitmapOfs];
			LDA 	bitmapPF2,x				;4	[25]
			STA 	PF2 					;3	[28] -- TIA.pf2 = bitmapPF2[bitmapOfs];
			DEX								;2	[30] -- bitmapOfs--
			
			LDA		(.curEnemyPtr),y		;5	[35]
			AND 	(.enemyMask),y 			;5	[40]
			STA 	GRP0    				;3	[43]
			LDA 	(.curEnemyColorPtr),y	;5	[48]
			STA		COLUP0  				;3	[51]

			LDA 	<missile1y
			STA 	ENAM1
			
			DEC 	.line				    ;5	[56]
			BNE 	LineLoop			    ;2/3	[59]
			
        ;//} while (line > 0);
        
		DEC 	.row						;5	[69]
		BMI 	.done
		;BPL		DrawLoopStart
		JMP 	DrawLoopStart
.done:
		JMP 	DoneWithAllRows
		
		
;//===================================================================
;//=== Handle lantern row using asymmetric kernel for PF0,PF1
;//           Only ladder uses PF2
		
LanternKernel:
		CMP 	#$C0
		BCC 	DoLanternKernel
		CMP 	#$F0
		BCC 	DoNewLanternKernel
		JMP  	MountainKernel
DoLanternKernel:

		DEC 	.row
		LDX 	#7
		
LT_LineLoop:
			DEY                         ;2  [73]
            ;/* even lines, sprite 0 */
			
			STA 	WSYNC
			LDA 	lanternColors,x		    ;4	[4]
			STA 	COLUPF  			    ;3	[7]
			LDA 	.lanternDrawPF+0		;3	[10]
			STA 	PF0 				    ;3	[13]
			LDA 	.lanternDrawPF+1		;3	[16]
			STA 	PF1 				    ;3	[19]
			
			LDA 	ladderGfx,x 		    ;4	[23] -- typical center ladder
			STA 	PF2    				    ;3	[26]
						
			LDA		(.curPlayerPtr),y	    ;5	[31]
			AND     (.playerMask),y		    ;5	[36]
			STA 	GRP1    			    ;3	[39]
			LDA 	(.curPlayerColPtr),y	;5	[44]
			STA		COLUP1  			    ;3	[47]

			LDA 	.lanternDrawPF+2		;3	[50]
			STA 	PF1 				    ;3	*53* -- TIA.pf1 = bitmapPF1[bitmapOfs];
			LDA 	.lanternDrawPF+3		;3	[56]
			STA 	PF0 				    ;3	[59] -- TIA.pf0 = bitmapPF0[bitmapOfs];			
			
			DEX
			
            ;/* odd lines, sprite 1 */
			STA 	WSYNC
			
			LDA 	lanternColors,x			;4	[4]
			STA 	COLUPF  				;3	[7]  -- TIA.colupf = bitmapColors[bitmapOfs];
			LDA 	.lanternDrawPF+0		;3	[10]
			STA 	PF0 					;3	[13] -- TIA.pf0 = bitmapPF0[bitmapOfs];
			LDA 	.lanternDrawPF+1		;3	[16]
			STA 	PF1 					;3	[19] -- TIA.pf1 = bitmapPF1[bitmapOfs];

			LDA 	ladderGfx,x				;4	[23]
			STA 	PF2 					;3	[26] -- TIA.pf2 = bitmapPF2[bitmapOfs];
		
			LDA		(.curEnemyPtr),y		;5	[31]
			AND 	(.enemyMask),y			;5	[36]
			STA 	GRP0    				;3	[39]
			LDA 	(.curEnemyColorPtr),y	;5	[44]
			STA		COLUP0  				;3	[47]

			LDA 	.lanternDrawPF+2		;4	[51]
			STA 	PF1 					;3	[54] -- TIA.pf1 = bitmapPF1[bitmapOfs];		
			LDA 	.lanternDrawPF+3		;4	[58]
			STA 	PF0 					;3	[61] -- TIA.pf0 = bitmapPF0[bitmapOfs];

			DEX								;2	[63] -- bitmapOfs--
			BPL 	LT_LineLoop				;3  [66]

		;----- Done with lanterns, load next set of lanterns and prepare for next row
LT_Return:
		LDA 	#0
		STA 	PF0
		STA 	PF1

	;// Load in info for next row of graphics

		LDX 	.row				;3	[3]
		LDA 	screenBgColor,x		;4	[7]
		STA 	COLUBK  			;3	[10]	-- TIA.colubk = screenBgColor[row];
		;AND		#1					;2	[12]
		;STA 	CTRLPF  			;3	[15]	-- TIA.ctrlpf = screenBgColor[row] & 1
		
		LDA 	screenLanternsPF+4	;3	[18]
		STA 	.lanternDrawPF+0	;3	[21]
		LDA 	screenLanternsPF+5	;3	[24]
		STA 	.lanternDrawPF+1	;3	[27]
		LDA 	screenLanternsPF+6	;3	[30]
		STA 	.lanternDrawPF+2	;3	[33]
		LDA 	screenLanternsPF+7	;3	[36]
		STA 	.lanternDrawPF+3	;3	[39]
		
		LDA 	screenKernelType,X	;4	[43]	;-- need to load next kernel type
		JMP 	RegularKernel		;3	[46]


;===========================================================================
;=== Handle lantern + ladder row using asymmetric kernel for PF1,PF2
;
;-- PF0 is unused


DoNewLanternKernel:
		DEC 	.row
		LDX 	#7
		
LT_LineLoop2:
			DEY                         ;2  [73]
            ;/* even lines, sprite 0 */
			
			STA 	WSYNC
			LDA 	#0						;2	[2]
			STA 	PF0						;3	[5]
			LDA 	lanternColors,x		    ;4	[9]
			STA 	COLUPF  			    ;3	[12]
			LDA 	.lanternDrawPF+0		;3	[15]
			STA 	PF1 				    ;3	[18]
			LDA 	.lanternDrawPF+1		;3	[21]
			ORA 	ladderGfx,x				;4	[25]
			STA 	PF2 				    ;3	[28]
									
			LDA		(.curPlayerPtr),y	    ;5	[33]
			AND     (.playerMask),y		    ;5	[38]
			STA 	GRP1    			    ;3	[41]

			LDA 	.lanternDrawPF+2		;3	[44]
			NOP 							;2	[46]
			STA 	PF2 				    ;3	[49]
			LDA 	.lanternDrawPF+3		;3	[52]
			STA 	PF1 				    ;3	*55*

			LDA 	(.curPlayerColPtr),y	;5	[60]
			STA		COLUP1  			    ;3	[63]
			
			
			DEX
			
            ;/* odd lines, sprite 1 */
			STA 	WSYNC
			
			LDA 	#0						;2	[2]
			STA 	PF0						;3	[5]
			LDA 	lanternColors,x		    ;4	[9]
			STA 	COLUPF  			    ;3	[12]
			LDA 	.lanternDrawPF+0		;3	[15]
			STA 	PF1 				    ;3	[18]
			LDA 	.lanternDrawPF+1		;3	[21]
			ORA 	ladderGfx,x				;4	[25]
			STA 	PF2 				    ;3	[28]
		
			LDA		(.curEnemyPtr),y		;5	[33]
			AND 	(.enemyMask),y			;5	[38]
			STA 	GRP0    				;3	[41]

			LDA 	.lanternDrawPF+2		;3	[44]
			NOP 							;2	[46]
			STA 	PF2 				    ;3	[49]
			LDA 	.lanternDrawPF+3		;4	[52]
			STA 	PF1 					;3	*55*
			
			LDA 	(.curEnemyColorPtr),y	;5	[60]
			STA		COLUP0  				;3	[63]

			
			DEX								;2	[65]
			BPL 	LT_LineLoop2			;3  [68]

		;----- Done with lanterns, load next set of lanterns and prepare for next row
LT_Return2:
		LDA 	#0
		STA 	PF1
		STA 	PF2

	;// Load in info for next row of graphics

		LDX 	.row				;3	[3]
		LDA 	screenBgColor,x		;4	[7]
		STA 	COLUBK  			;3	[10]	-- TIA.colubk = screenBgColor[row];
		;AND		#1					;2	[12]
		;STA 	CTRLPF  			;3	[15]	-- TIA.ctrlpf = screenBgColor[row] & 1
		
		LDA 	screenLanternsPF+4	;3	[18]
		STA 	.lanternDrawPF+0	;3	[21]
		LDA 	screenLanternsPF+5	;3	[24]
		STA 	.lanternDrawPF+1	;3	[27]
		LDA 	screenLanternsPF+6	;3	[30]
		STA 	.lanternDrawPF+2	;3	[33]
		LDA 	screenLanternsPF+7	;3	[36]
		STA 	.lanternDrawPF+3	;3	[39]
		
		LDA 	screenKernelType,X	;4	[43]	;-- need to load next kernel type
		JMP 	RegularKernel		;3	[46]


		;-------------------------------------------------------------------------
		;------------------- Asymmetric Kernel... center is symmetric
		;---
		;------  This kernel is typically used for drawing platforms.
		align 256
AsymKernel:
		LDA 	#0
		STA 	ENAM1

		LDA 	screenData,x		;4	[19]
		TAX							;2	[21]	--- X = bitmapOfs = screenData[row]

AsymBitmapDrawLoopStart:
        ;/* main row loop */
        LDA 	#4					;2	[23]
		STA 	.line				;3	[26]
        ;//do {
AsymLineLoop:
			DEY
            ;/* even lines, sprite 0 */
			
			STA 	WSYNC
			LDA 	bitmapColors,x			;4	[4]
			STA 	COLUPF  				;3	[7]  -- TIA.colupf = bitmapColors[bitmapOfs];
			LDA 	bitmapPF0,x				;4	[11]
			STA 	PF0 					;3	[14]
			LDA 	bitmapPF1,x				;4	[18]
			STA 	PF1 					;3	[21]
			LDA 	bitmapPF2,x				;4	[25]
			STA 	PF2 					;3	[28]
			
			LDA		(.curPlayerPtr),y	    ;5	[33]
			AND 	(.playerMask),y		    ;5	[38]
			STA 	GRP1    			    ;3	[41]
			LDA 	(.curPlayerColPtr),y	;5	[46]
			STA		COLUP1  			    ;3	[49]

			LDA 	bitmapPF4,x				;4	[53]
			STA 	PF1 					;3	[56]
			LDA 	bitmapPF5,x				;4	[60]
			STA 	PF0 					;3	[63]
			DEX								;2	[65]
			
			
            ;/* odd lines, sprite 1 */
			LDA 	bitmapColors,x			;4	[4]
			STA 	WSYNC
			STA 	COLUPF  				;3	[7]  -- TIA.colupf = bitmapColors[bitmapOfs];
			LDA 	bitmapPF0,x				;4	[11]
			STA 	PF0 					;3	[14] -- TIA.pf0 = bitmapPF0[bitmapOfs];
			LDA 	bitmapPF1,x				;4	[18]
			STA 	PF1 					;3	[21] -- TIA.pf1 = bitmapPF1[bitmapOfs];
			LDA 	bitmapPF2,x				;4	[25]
			STA 	PF2 					;3	[28] -- TIA.pf2 = bitmapPF2[bitmapOfs];
			
			LDA		(.curEnemyPtr),y		;5	[35]
			AND 	(.enemyMask),y 			;5	[40]
			STA 	GRP0    				;3	[43]
			LDA 	(.curEnemyColorPtr),y	;5	[48]
			STA		COLUP0  				;3	[51]

			LDA 	bitmapPF4,x				;4	[55]
			STA 	PF1 					;3	[58]
			LDA 	bitmapPF5,x				;4	[62]
			STA 	PF0 					;3	[65]
			DEX								;2	[30] -- bitmapOfs--
			
			DEC 	.line				    ;5	[70]
			BNE 	AsymLineLoop		    ;2/3	[59]
			
        ;//} while (line > 0);
        
		DEC 	.row						;5	[69]
		LDA 	#0
		STA 	PF1
		JMP 	DrawLoopStart

	;-------------------------------------------------------------------------
	;//------------------- Mountain Kernel
	;
	;   very basic symmetric kernel for drawing mountains 
	;     (and potentially other decorations) and both sprites

MountainKernel:
		LDX 	#15

MountainDrawLoop:
			DEY
            ;/* even lines, sprite 0 */
			
			STA 	WSYNC
			LDA 	mountainColors,x		;4	[4]
			STA 	COLUPF  				;3	[7]
			LDA 	mountainsPF0,x			;4	[11]
			STA 	PF0 					;3	[14]
			LDA 	mountainsPF1,x			;4	[18]
			STA 	PF1 					;3	[21]
			LDA 	mountainsPF2,x			;4	[25]
			STA 	PF2 					;3	[28]
			
			LDA		(.curPlayerPtr),y	    ;5	[33]
			AND 	(.playerMask),y		    ;5	[38]
			STA 	GRP1    			    ;3	[41]
			LDA 	(.curPlayerColPtr),y	;5	[46]
			STA		COLUP1  			    ;3	[49]

			DEX								;2	[65]
			
			
            ;/* odd lines, sprite 1 */
			STA 	WSYNC
			LDA 	mountainColors,x		;4	[4]
			STA 	COLUPF  				;3	[7]
			LDA 	mountainsPF0,x			;4	[11]
			STA 	PF0 					;3	[14]
			LDA 	mountainsPF1,x			;4	[18]
			STA 	PF1 					;3	[21]
			LDA 	mountainsPF2,x			;4	[25]
			STA 	PF2 					;3	[28]
			
			LDA		(.curEnemyPtr),y		;5	[33]
			AND 	(.enemyMask),y 			;5	[38]
			STA 	GRP0    				;3	[41]
			LDA 	(.curEnemyColorPtr),y	;5	[46]
			STA		COLUP0  				;3	[49]

			DEX								;2	[51]
			BPL 	MountainDrawLoop	    ;2/3	[53/54]
			
        ;---- prep for next row
		LDX 	.row
		DEX
		DEX
		STX 	.row
		JMP 	DrawLoopStart
		
		;//-------------------------------------------------------------------
		
DoneWithAllRows:
	LDA     #$0
	STA     GRP0
	STA     GRP1
	STA     ENAM0
	STA     ENAM1
	JMP     DoneWithKernel

;	LSR 	<zp     ;5
;	BCC 	.label  ;3
;	STA 	PF0		;3  [8/10] cycles per PFx


END_OF_KERNEL_ROUTINES:








;-------------------------------------------------------------------------

DoneWithKernel
    
BottomOfKernelLoop

    sta WSYNC
    ldx stack1		;-- restore stack pointer
    txs
    ldx #0
    STx GRP0
    STx GRP1 ; seems to be needed because of vdel
	sta PF0
    sta PF1
    sta PF2
    sta ENABL
    sta ENAM0
    sta ENAM1
    sta HMCLR
	STA REFP0
	STA REFP1

    jsr setscorepointers


    ; shove 6-digit score routine here

sixdigscore
    lda #0
    

    ;--- set high bytes of score pointers

    lda #>scoretable
    sta scorepointers+1
    sta scorepointers+3
    sta scorepointers+5
    sta scorepointers+7;temp2
    sta scorepointers+9;temp4
    sta scorepointers+11;temp6


    sta WSYNC
    sta HMCLR               ;3  [3]
    lda #$01                ;2  [5]
    sta CTRLPF              ;3  [8]
    ldy #7                  ;2  [10]
    sty VDELP0              ;3  [13]
    sty VDELP1              ;3  [16]
    LDA #$40                ;2  [18]
    STA HMP1                ;3  [21]
	LDA #$30				;2	[23]
	STA HMP0				;3  [26]
    LDA scorecolor          ;3  [29]
    STA COLUP0              ;3  [32]
    STA COLUP1              ;3  [35]
    
    LDA #$03                ;2  [37]
    STA NUSIZ0              ;3  [40]

    STA RESP0               ;3  *43*
    STA RESP1               ;3  *46*

    STA NUSIZ1              ;3  [49]

    lda  (scorepointers),y  ;5  [54]
    sta  GRP0               ;3  [57]
  ifconst pfscore
    lda pfscorecolor        ;3  [60]
    sta COLUPF              ;3  [63]
  else
    sleep 6                 ;6  [63]
  endif

    lda  (scorepointers+8),y;5  [68]

    sleep 2                 ;3  [70]
    STA HMOVE               ;3  [73]  Early HMOVE
	sleep 2					;2	[75]
    jmp beginscore          ;3  [2]

  align 64

loop2
    lda  (scorepointers),y     ;+5  68  204
    sta  GRP0            ;+3  71  213      D1     --      --     --
  ifconst pfscore
  if pfscore = 1 || pfscore = 3
    lda pfscore1
    sta PF1
  else
    lda #0
    sta PF1
    nop
  endif
  else
    sleep 6
  endif
    ; cycle 0
    lda  (scorepointers+$8),y   ;+5   5   15

beginscore						;----- enter at 2
    sta  GRP1                   ;+3   8   24      D1     D1      D2     --
    lda  (scorepointers+$6),y   ;+5  13   39
    sta  GRP0                   ;+3  16   48      D3     D1      D2     D2
    lax  (scorepointers+$2),y   ;+5  29   87
    txs
    lax  (scorepointers+$4),y   ;+5  36  108
    sleep 4
  ifconst pfscore
  if pfscore > 1
    lda statusbarlength
    sta PF1
  else
    lda #0
    sta.w PF1
  endif
  else
    sleep 6
  endif
    lda  (scorepointers+$A),y   ;+5  21   63
    stx  GRP1                   ;+3  44  132      D3     D3      D4     D2!
    tsx
    stx  GRP0                   ;+3  47  141      D5     D3!     D4     D4     ..[42,43,44]
    sta  GRP1                   ;+3  50  150      D5     D5      D6     D4!
    sty  GRP0                   ;+3  53  159      D4*    D5!     D6     D6
    dey
    bpl  loop2           ;+2  60  180


    ;--- Wait for end of display

WaitForDisplayEnd:
    LDA     TIMINT
    BPL     WaitForDisplayEnd

    ;--- Start VBLANK timer

    lda  #KERNEL_VBLANK_TIME
    sta  TIM64T


    ldx stack1
    txs

    LDA #0   
    STA GRP0
    STA GRP1
    sta PF1 
    sta PF0
    STA VDELP0
    STA VDELP1;do we need these
    STA NUSIZ0
    STA NUSIZ1


;-------------------------------------------------------------------------
;------------------------Overscan Routine---------------------------------
;-------------------------------------------------------------------------

OverscanRoutine


skipscore
    lda #2
    sta WSYNC
    sta VBLANK        ;turn on VBLANK

;--------------------------------
;---- KernelCleanupSubroutine
;--------------------------------

    ldx #$FF
    RETURN        ;--- Display kernel is done, return to appropriate address


;-------------------------------------------------------------------------
;----------------------------End Main Routines----------------------------
;-------------------------------------------------------------------------


;-------------------------------------------------------------------------
;------------------------------------------------------------------------
;-- FineAdjustTable - HMove table
;--
;-- NOTE:  This table needs to be here to prevent interference with
;--        the superchip due to the forced page-crossing used when
;--        accessing this table.

FineAdjustTableBegin
    .byte %01100000                ;left 6
    .byte %01010000
    .byte %01000000
    .byte %00110000
    .byte %00100000
    .byte %00010000
    .byte %00000000                ;left 0
    .byte %11110000
    .byte %11100000
    .byte %11010000
    .byte %11000000
    .byte %10110000
    .byte %10100000
    .byte %10010000
    .byte %10000000                ;right 8

    ;-- label used when table is accessed via forced page-crossing
FineAdjustTableEnd        =        (FineAdjustTableBegin - 241)



; room here for score?

setscorepointers
    lax score+2
    jsr scorepointerset
    sty scorepointers+10;5
    stx scorepointers+2
    lax score+1
    jsr scorepointerset
    sty scorepointers+4
    stx scorepointers+6;1
    lax score
    jsr scorepointerset
    sty scorepointers+8;3
    stx scorepointers
    rts

scorepointerset
    and #$0F
    asl
    asl
    asl
    adc #<scoretable
    tay
    txa
    and #$F0
    lsr
    adc #<scoretable
    tax
    rts
;    align 256


;-------------------------------------------------------------------------
;----------------------Begin Kernel Data----------------------------------
;-------------------------------------------------------------------------


mountainsPF0:
	.byte $33,$33,$13,$13,$07,$07,$03,$03
	.byte $01,$01,$01,$01,$01,$01,$01,$01
mountainsPF1:
	.byte $FF,$7F,$7F,$3F,$1F,$1F,$0F,$0F
	.byte $07,$07,$03,$03,$01,$01,$00,$00
mountainsPF2:
	.byte $FF,$FF,$FF,$FF,$FF,$FF,$7F,$7F
	.byte $7F,$7F,$3F,$3F,$3E,$3E,$1C,$1C
mountainColors:
	.byte $08,$08,$0A,$0A,$0C,$0E,$0C,$0E
	.byte $0C,$0F,$0C,$0F,$0E,$0C,$0E,$0F
	

;------------------------------------------------------
;--  118F: bitmapPF0
;--  0050 (bytes)

bitmapPF0:
	.byte $00,$00,$00,$00,$00,$00,$00,$00
	.byte $FF,$FF,$FF,$FF,$FF,$FF,$00,$00  ;-- ground
	
	.byte $1F,$AA,$FF,$AA,$FF,$FF,$55,$55  ;-- screen 2 platforms
	.byte $FF,$AA,$FF,$AA,$FF,$FF,$55,$55

	.byte $A0,$80,$E0,$20,$A0,$A0,$E0,$40	;-- background lattice work

	.byte $FF,$AA,$FF,$AA,$FF,$FF,$55,$55	;-- screen 1 top platform (asym)
	.byte $F0,$A0,$FF,$AA,$FF,$FF,$55,$55

	.byte $00,$00,$00,$00,$00,$00,$00,$00  ;-- middle of the screen ladder

	.byte $1F,$AA,$FF,$AA,$FF,$FF,$55,$55  ;-- screen 3 platforms
	.byte $1F,$AA,$FF,$AA,$FF,$FF,$55,$55


;------------------------------------------------------
;--  11DF: bitmapPF1
;--  0058 (bytes)

bitmapPF1:
	.byte $00,$00,$00,$00,$00,$00,$00,$00
	.byte $FF,$FF,$FF,$FF,$FF,$FF,$00,$00  ;-- ground
	
	.byte $E3,$55,$FF,$55,$FF,$FF,$55,$55  ;-- screen 2 platforms
	.byte $A0,$50,$F0,$50,$F0,$F0,$80,$80

	.byte $14,$10,$1C,$04,$14,$14,$1C,$08	;-- lattice

	.byte $FF,$55,$FF,$55,$FF,$FF,$AA,$AA  ;-- screen 1 platforms
	.byte $00,$00,$C0,$40,$C0,$C0,$80,$80

	.byte $00,$00,$00,$00,$00,$00,$00,$00	;-- screen 1 ladder

	.byte $FF,$55,$FF,$55,$FF,$FF,$AA,$AA  ;-- screen 3 platforms
	.byte $F1,$51,$F1,$51,$F1,$F1,$A0,$A0


;------------------------------------------------------

lanternColors:
	.byte $38,$66,$DA,$44,$28,$3E,$3A,$00
	;.byte $00,$66,$DA,$00,$36,$3E,$00,$02	;-- lanterns allowing black walls

pfBitmask:
	.byte 16,32,64,128,128,64,32,16
	.byte 8,4,2,1,1,2,4,8
	
ladderGfx:
	.byte 128,0,0,128,0,0,128,0
	.byte 128,0,0,128,0,0,128,0


;------------------------------------------------------
;--  1237: bitmapPF2
;--  0048 (bytes)
	align 256
bitmapPF2:
	.byte $00,$00,$00,$00,$00,$00,$00,$00
	.byte $FF,$FF,$FF,$FF,$FF,$FF,$00,$00  ;-- ground

	.byte $80,$00,$00,$80,$00,$80,$80,$00  ;-- screen 2 platforms
	.byte $98,$28,$B8,$28,$F8,$F8,$A8,$A8

	.byte $00,$00,$00,$00,$00,$00,$00,$00	;-- lattice

	.byte $BE,$55,$FF,$55,$FF,$FF,$55,$55  ;-- screen 1 platforms
	.byte $80,$00,$00,$80,$00,$00,$80,$00  ;-- screen 1 platform + ladder
	.byte $80,$00,$00,$80,$00,$00,$80,$00  ;-- screen 1 ladder

	.byte $82,$05,$07,$85,$87,$87,$80,$00  ;-- screen 3 platform + ladder
	.byte $9E,$15,$1F,$95,$1F,$1F,$95,$15  ;-- screen 3 platforms
	


;----------------------------------------------------
;--- asymmetric bitmaps

bitmapPF0_1:
	.byte $F0,$A0,$F0,$A0,$F0,$F0,$A0,$A0
	.byte $F0,$A0,$F0,$A0,$F0,$F0,$50,$50
	.byte $F0,$50,$F0,$50,$F0,$F0,$50,$00	;-- also used by PF0_1
	.byte $00,$00,$FF,$AA,$FF,$FF,$55,$55

bitmapPF1_1:
	.byte $F0,$50,$F0,$50,$F0,$F0,$50,$00	;-- also used by PF0_1
	.byte $FF,$55,$FF,$55,$FF,$FF,$AA,$AA
	.byte $80,$00,$00,$80,$00,$00,$80,$00  ;-- screen 1 ladder
	.byte $00,$00,$F1,$51,$F1,$F1,$A0,$A0  ;-- screen 3 platforms


bitmapPF4 = bitmapPF1_1 - 0x28
bitmapPF5 = bitmapPF0_1 - 0x28




;------------------------------------------------------
;--  128F: bitmapColors
;--  0050 (bytes)

bitmapColors:
	.byte $00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$0E,$0E,$34,$44,$00,$00   ;-- ground

	.byte $00,$00,$00,$00,$40,$44,$34,$44   ;-- screen 2 platforms
	.byte $00,$00,$00,$00,$40,$44,$34,$44

	.byte $0A,$0C,$0A,$0E,$0A,$0A,$0C,$0E   ;-- lattice

	.byte $00,$00,$00,$00,$40,$44,$34,$44   ;-- screen 1 platforms
	.byte $00,$00,$00,$00,$40,$44,$34,$44
	.byte $38,$66,$DA,$44,$28,$3E,$3A,$00	;-- screen 1 ladder

	.byte $00,$00,$00,$00,$40,$44,$34,$44	;-- screen 3 platforms
	.byte $00,$00,$00,$00,$40,$44,$34,$44




;------------------------------------------------------
;--  14FD: maskZone
;--  00A0 (bytes)
		align 256
maskZone:
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 255,255,255,255,255,255,255,255
	.byte 255,255,255,255,255,255,255,255
	.byte 255,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0
	.byte 0,0,0,0,0,0,0,0


  ifconst show_kernel_stats
    echo "Multi-sprite kernel starts at ", __MCMSK_START
    echo "Multi-Sprite Kernel at ", START_OF_KERNEL_ROUTINES, "..", END_OF_KERNEL_ROUTINES
    echo "Size of Multi-Sprite kernel(s): ", (END_OF_KERNEL_ROUTINES - START_OF_KERNEL_ROUTINES)
    echo " Find Adjust table at: ", FineAdjustTableBegin
    echo " Find Adjust accessed at: ", FineAdjustTableEnd
    echo "Multi-sprite kernel ends at ", *
  endif