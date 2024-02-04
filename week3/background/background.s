; Good to Know
	; See https://cc65.github.io/doc/ca65.html for list of Directives
	; See https://www.masswerk.at/6502/6502_instruction_set.html for list of Instructions 
	;
	; $ inidicates we are writing a hex number
	; % indiciates we are writing a binary number
	; No prefix indicates we are writing a decimal number (never write decimal because it is disabled)
	;
	; When working with instructions:
		; # indicates we are giving an immediate value, so #$00 is 0,
		; and without # it is probably a Memory Address instead
	;
	; When working with Directives (such as .byte) the # is not used
		; so it is still an immediate value (though that value can be referencing an address)
	;
	; Acronyms and Some Definitions:
		; PPU is Picture Processing Unit, a processor separate from CPU that passes data to CRT or
		; whatever display you are using.
		; APU is Audio Processing Unit, another separate processor on the Motherboard, and it handles sound.
		; Note: You write code that runs in the CPU, but through certain Memory Addresses you can
		; control the PPU and APU and through other address ranges you can pass data to them.
		;
		; NMI is Non Maskable Interrupt https://en.wikipedia.org/wiki/Non-maskable_interrupt
		;
		; IRQ is Interrupt Request https://en.wikipedia.org/wiki/Interrupt_request
		;
		; CRT is Cathode Ray Tube, the TV that renders things in Scanlines (to the program it pretends
		; that everything is done in scanlines regardless of display, I just say CRT for simplicity)
		;
		; BG is background
		;
		; FCEUX and Nestopia are programs that run your iNES (.nes extended) file after you Assemble 
		; and Link it.
	;
	; Unexpected / Sneaky things:
		; You have to set the PPU Read/Write Address by consecutively writing to the byte at
		; address $2006 twice.
		; It's unexpected because you have to specify a 2 byte address by writing to 1 byte and then
		; writing to it again, rather than writing to 2 separate bytes.
		; The first write specifies the High byte of the address and the second write specifies
		; the Low byte of the address.
			; FIGURED OUT WHY: As I got further along I realized that PPU Memory is separate from the RAM
			; and that the PPU accesses RAM that the CPU has access to in order to get instructions, and
			; data. So when I want to access PPU Memory I have to do so via a combination of writes 
			; to control memory addresses and writes to data memory addresses.
			; My flawed expectation was that I would write a whole block of bytes and then tell the PPU
			; what the start and end of those bytes was, but that would take up space on the RAM to fill
			; up all those bytes I want to write to the PPU, and RAM is already pretty limited, and if I
			; were to read data from the PPU it would probably take up all the CPU RAM.
			; Instead you write 1 byte at a time to a single byte, over and over.
			; Now I can Write to the PPU Memory without taking up space in the CPU RAM.
			; Also, the reason for writing to $2006 in CPU RAM is to set what address in PPU Memory
			; you want to do the reading and writing from, so the $2006 byte and the $2007 byte are the
			; only 2 bytes needed to Reader/Write all the data you could ever want From/To the PPU Memory.
	;


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

; Note that the CPU has dedicated bytes $0000 to $0800 to Internal RAM use, so this is what we
; are clearing out in this next block
clear_memory:
	lda	#$00					; Overwriting to 0 will be used to clear the Bytes

										; X at this point is still 0 on the first Branching Iteration since we
										; haven't modified it since the Reset Block
	sta	$0000, x		
	sta	$0100, x
	sta	$0200, x
	sta	$0300, x			; Each of these is storing the A register which is currently 0 in a Byte at
	sta	$0400, x			; at the given address which is offset by X.
	sta	$0500, x			; Note that X will loop from 0 to 255 then the branch will end back at 0.
	sta	$0600, x			; Only need to offset by every 256 bytes or $0100 since we offset the X
	sta	$0700, x			; to write to all the bytes in between.

										; The first Increment of X makes it 1 before checking Zero flag with BNE
	inx								; Keep incrementing the X register, eventually it will wrap back around to 0 
										; after the 256th increment
	bne	clear_memory	; When INX wraps X back to 0 on the 256th iteration the Zero flag will be set
										; and we will no longer loop

	;; second wait for vblank, PPU is ready after this
	; Later on the vblank wait block should be moved to a stored procedure because that would
	; be useful since there are situations that we want to do this
vblankwait2:
	bit	$2002
	bpl	vblankwait2

;; Need clear both palettes to $00. Needed for Nestopia. Not
;; needed for FCEU* as they're already $00 on powerup.
clear_palette:
	; The CPU Cannot directly access the Color Palette memory, this is accessed by the PPU.
	; So I must through memory tell the PPU that I am going to write to the Color
	; Palette addresses, then tell it what data to write. 
	
	; First reset the PPU Read/Write Address
	lda	$2002		; Read PPU status to reset PPU address
	
	; Set PPU address to BG (background) palette RAM Address ($3F00)
	; Note that you write the 2 Byte Address for the PPU to Read/Write from by writing
	; the High Byte to $2006 and then immediately following that with a write of the Low
	; Byte to $2006.
	; So 1 byte gets used to set that 2 Byte address by writing to it twice, rather than using
	; 2 separate bytes to specify that 2 Byte address.
	lda	#$3f		
	sta	$2006
	lda	#$00
	sta 	$2006

	ldx	#$20		; Loop $20 times (up to $3F20)
	lda	#$00		; Set each entry to $00
@loop:
	sta	$2007		; $2007 is that 1 byte that I Write to over and over again to pass data to PPU
							; memory 1 byte at a time
	dex
	bne	@loop

	lda	#%01000000	; PPUMask, the first 3 bits (RGB) set color emphasis for what Blank (no color) is 
	sta	$2001				; $2001 is the PPUMask CPU RAM Address

; After the code above has ran (starting from the reset block) this program is now done so just loop
; forever so that we don't execute the stuff below this, like the data section or the NMI handler, etc.
forever:					
	jmp	forever

; This is where you write the block of code to handle the Non Maskable Interrupt, so when we
; press a button on a controller for example, that triggers an interrupt in the program, and then
; this nmi block will run and we will then trigger a subroutine to update character position data,
; etc. 
; Currently we aren't handling input so this is just blank and that RTI instruction is the
; Return From Interrupt
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