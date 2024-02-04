; Good to Know
	; See https://cc65.github.io/doc/ca65.html for list of Directives
	; See https://www.masswerk.at/6502/6502_instruction_set.html for list of Instructions 
	;
	; $ inidicates we are writing a hex number
	;
	; When working with instructions:
		; # indicates we are giving an immediate value, so #$00 is 0,
		; and without # it is probably a Memory Address instead
	;
	; When working with Directives (such as .byte) the # is not used
		; so it is still an immediate value (though that value can be referencing an address)


.segment "HEADER"
										; See https://www.nesdev.org/wiki/INES for these INES bits and Magic Number
	.byte	"NES", $1A	; iNES header identifier, ACII for NES followed by EOF character
	.byte	2						; 2x 16KB PRG code
	.byte	1						; 1x  8KB CHR data
	.byte	$01					; Bit 0 is 1 so Horizontally Arrange Nametable with Vertical Mirroring
	.byte $00					; Byte 7 (Flags 7) has more setup, all 0 for current usage

;;;;;;;;;;;;;;;

;;; "nes" linker config requires a STARTUP section, even if it's empty
.segment "STARTUP"

.segment "CODE"

reset:				; Start of every NES Program, always has the following similar setup instructions
							; See https://www.nesdev.org/wiki/Status_flags for status flag bits
	sei					; disable IRQs via Status Register Flag
	cld					; disable Decimal values via Status Register flag

							; See https://www.nesdev.org/wiki/APU for APU Control Bytes and Bits
	ldx	#$40		; 0100 0000 is the Inhibit IRQ bit
	stx	$4017		; $4017 is the byte for this APU Frame Counter settings

	ldx	#$ff		; Set Stack Pointer to be the top of the 256 bytes addressable
	txs

							; See https://www.nesdev.org/wiki/PPU_registers for PPU Control Bytes and Bits
	inx					; now X = 0 since $ff + $01 wraps around
	stx	$2000		; disable NMI since bit 7 is currently 0 in X Register
	stx	$2001		; disable Rendering since bits 1-4 are currently 0 in X Register

							; While X Register is 0, set another APU Control Byte
	stx	$4010		; disable DMC IRQs since bit 7 is currently 0 in X Register

	;; first wait for vblank to make sure PPU is ready
vblankwait1:
	bit	$2002				; Set Negative and Overflow status flag Bits to be the corresponding bits
									; of this Byte so we can loop to wait by branching with the next instruction.
	bpl	vblankwait1	; Branches if Negative status flag is 0, so loop until PPU changes
									; that PPU VBlank Ready Status bit 7 via the Byte $2002
	; I think the reason for doing this initial vblankwait is because before we start clearing the
	; screen in the next block we want to time it so that we don't clear the screen while the PPU is
	; in the middle of pulling those memory addresses.
	; Ideally, the CRT will have already rendered $0000 to $0100 by the time we overwrite the memory
	; at those bytes with a blank background so that those bytes were already rendered from before.
	; This way it is less likely that it will look like it is broken because if we didn't time this
	; background clearing then half of whatever image was getting rendered will become blanked out in
	; the bottom scanlines.

clear_memory:
	lda	#$00
	sta	$0000, x
	sta	$0100, x
	sta	$0200, x
	sta	$0300, x
	sta	$0400, x
	sta	$0500, x
	sta	$0600, x
	sta	$0700, x
	inx
	bne	clear_memory

	;; second wait for vblank, PPU is ready after this
vblankwait2:
	bit	$2002
	bpl	vblankwait2

clear_palette:	
	;; Need clear both palettes to $00. Needed for Nestopia. Not
	;; needed for FCEU* as they're already $00 on powerup.
	lda	$2002		; Read PPU status to reset PPU address
	lda	#$3f		; Set PPU address to BG palette RAM ($3F00)
	sta	$2006
	lda	#$00
	sta 	$2006

	ldx	#$20		; Loop $20 times (up to $3F20)
	lda	#$00		; Set each entry to $00
@loop:
	sta	$2007
	dex
	bne	@loop

	lda	#%10000000	; intensify blues
	sta	$2001

forever:
	jmp	forever

nmi:
	rti
 
;;;;;;;;;;;;;;  
  
.segment "VECTORS"

	;; When an NMI happens (once per frame if enabled) the label nmi:
	.word	nmi
	;; When the processor first turns on or is reset, it will jump to the
	;; label reset:
	.word	reset
	;; External interrupt IRQ is not used in this tutorial 
	.word	0
  
;;;;;;;;;;;;;;  
  
.segment "CHARS"

;;; No CHR-ROM needed for this app