; a2_morse.asm
;
; Student name: Gavriil Maryshev
; Date of completed work: June 27, 2022

; =============================================
; ==== BEGINNING OF "DO NOT TOUCH" SECTION ====
; =============================================

.include "m2560def.inc"

.cseg
.equ S_DDRB=0x24
.equ S_PORTB=0x25
.equ S_DDRL=0x10A
.equ S_PORTL=0x10B

	
.org 0
	; Copy test encoding (of 'sos') into SRAM
	;
	ldi ZH, high(TESTBUFFER)
	ldi ZL, low(TESTBUFFER)
	ldi r16, 0x30
	st Z+, r16
	ldi r16, 0x37
	st Z+, r16
	ldi r16, 0x30
	st Z+, r16
	clr r16
	st Z, r16

	; initialize run-time stack
	ldi r17, high(0x21ff)
	ldi r16, low(0x21ff)
	out SPH, r17
	out SPL, r16

	; initialize LED ports to output
	ldi r17, 0xff
	sts S_DDRB, r17
	sts S_DDRL, r17

; =======================================
; ==== END OF "DO NOT TOUCH" SECTION ====
; =======================================

; ***************************************************
; **** BEGINNING OF FIRST "STUDENT CODE" SECTION **** 
; ***************************************************

	; If you're not yet ready to execute the
	; encoding and flashing, then leave the
	; rjmp in below. Otherwise delete it or
	; comment it out.
	

    ; The following seven lines are only for testing of your
    ; code in part c. When you are confident that your part c
    ; is working, you can then delete these seven lines. 
	ldi r17, high(TESTBUFFER)
	ldi r16, low(TESTBUFFER)
	push r17
	push r16
	rcall flash_message
    pop r16
    pop r17
	rjmp stop

   
; ***************************************************
; **** END OF FIRST "STUDENT CODE" SECTION ********** 
; ***************************************************


; ################################################
; #### BEGINNING OF "TOUCH CAREFULLY" SECTION ####
; ################################################

; The only things you can change in this section is
; the message (i.e., MESSAGE01 or MESSAGE02 or MESSAGE03,
; etc., up to MESSAGE09).
;

	; encode a message
	;
	ldi r17, high(MESSAGE10 << 1)
	ldi r16, low(MESSAGE10 << 1)
	push r17
	push r16
	ldi r17, high(BUFFER01)
	ldi r16, low(BUFFER01)
	push r17
	push r16
	rcall encode_message
	pop r16
	pop r16
	pop r16
	pop r16

; ##########################################
; #### END OF "TOUCH CAREFULLY" SECTION ####
; ##########################################


; =============================================
; ==== BEGINNING OF "DO NOT TOUCH" SECTION ====
; =============================================
	; display the message three times
	;
	ldi r18, 3
main_loop:
	ldi r17, high(BUFFER01)
	ldi r16, low(BUFFER01)
	push r17
	push r16
	rcall flash_message
	dec r18
	tst r18
	brne main_loop


stop:
	rjmp stop
; =======================================
; ==== END OF "DO NOT TOUCH" SECTION ====
; =======================================


; ****************************************************
; **** BEGINNING OF SECOND "STUDENT CODE" SECTION **** 
; ****************************************************


flash_message:
//push registers that I want to use then load the stack pointer and point it to what I need in the stack
//loops to call morse flash until it hits 0x00
		push ZL
		push ZH
		push YL
		push YH
		push r23
		in YH, SPH
		in YL, SPL
		
		ldd ZH, Y + 10
		ldd ZL, Y + 9
	
		//loops to until end of sequence
		loopto0x00:
			ld r23, Z+
			mov r16, r23
			call morse_flash
			cpi r23, 0x00
			brne loopto0x00

		morse_flashend:
			pop r23
			pop YH
			pop YL
			pop ZH
			pop ZL
		
	ret

morse_flash:
	
	push r16
	push r25
	push r27
	push r19
	push r28
	cpi r16, 0x00
	breq quit
	mov r16, r0

	ldi r25, 0x04 //count
	//
	looptogetnibble:
		lsr r16
		ror r27//low nibble of r16
		dec r25
		cpi r25, 0x00
		brne looptogetnibble

	swap r27
		 

	someloop:
		mov r28, r27
		andi r28, 0b00000001 
		cpi r28, 0x01
		breq dash
		cont:	
		cpi r28, 0x00
		breq dot		
		cont2:
		lsr r27
		dec r16
		cpi r16, 0x00
		brne someloop

	quit:
	pop r28
	pop r19
	pop r27
	pop r25
	pop r16
	ret

dot:
	push r16
	ldi r16, 0x01
	call leds_on
	call delay_short
	call leds_off
	call delay_long
	pop r16
	rjmp cont2

dash:
	push r16
	ldi r16, 0x06
	call leds_on
	call delay_long
	call leds_off
	call delay_long
	pop r16
	rjmp cont


leds_on:
	push r16
	push r20
	push r21

	cpi r16, 0x00
	breq zeroleds
	cpi r16, 0x01
	breq oneleds
	cpi r16, 0x02
	breq twoleds
	cpi r16, 0x03
	breq threeleds
	cpi r16, 0x04
	breq fourleds
	cpi r16, 0x05
	breq fiveleds
	cpi r16, 0x06
	breq sixleds

	zeroleds:
		ldi r20, 0x00
		ldi r21, 0x00
		sts S_PORTL, r20
		sts S_PORTB, r21
		rjmp quitleds

	oneleds:
		ldi r20, 0x00
		ldi r21, 0x02
		sts S_PORTL, r20
		sts S_PORTB, r21
		clr r21
		rjmp quitleds
		

	twoleds:
		ldi r20, 0x00
		ldi r21, 0x0a
		sts S_PORTL, r20
		sts S_PORTB, r21
		clr r21
		rjmp quitleds
		

	threeleds:
		ldi r20, 0x02
		ldi r21, 0x0a
		sts S_PORTL, r20
		sts S_PORTB, r21
		rjmp quitleds
		

	fourleds:
		ldi r20, 0x0a
		ldi r21, 0x0a
		sts S_PORTL, r20
		sts S_PORTB, r21
		rjmp quitleds

		

	fiveleds:
		ldi r20, 0x3e
		ldi r21, 0x0a
		sts S_PORTL, r20
		sts S_PORTB, r21
		rjmp quitleds

	sixleds:
		ldi r20, 0xaa
		ldi r21, 0x0a
		sts S_PORTL, r20
		sts S_PORTB, r21
		rjmp quitleds
		

	quitleds:
		pop r21
		pop r20
		pop r16
		ret

leds_off:
	ldi r20, 0x00
	sts S_PORTL, r20
	sts S_PORTB, R20
	ret


encode_message:
		push ZL
		push ZH
		push YL
		push YH
		push r16
		push r17
		push r18

		in YH, SPH
		in YL, SPL
		
		ldd ZH, Y + 14
		ldd ZL, Y + 13

		ldd XH, Y + 12
		ldd XL, Y + 11


		looptopush:
			lpm r16, Z+
			cpi r16, 0x00
			breq end_encodemsg
			push ZH
			push ZL
			push r16
			call alphabet_encode
			
			pop r16
			pop ZL
			POP ZH
			st x+, r0
			clz
			cpi r16, 0x00
			brne looptopush

				
		end_encodemsg:
		pop r18
		pop r17
		pop r16
		pop YH
		POP YL
		POP ZH
		POP ZL
		//ldi r16, 0x00
		//st x, r16

	ret	


alphabet_encode:

/*	Z = ITU_MORSE
	while (mem[Z] != 0)
		if mem[Z] equals letter-to-be-converted:
			Z = Z + 1
			while mem[Z] != 0:
				do something if mem[Z] is a dot or
					do something else if mem[Z] is a dash
				Z = Z + 1
			finished (i.e., break out of outermost loop)
		Z = Z + 8*/

//stack pointer to the letter in stack
//another pointer to the memory that stores the aphabet table
//do +8 to get next letter in table adiw
//compare that to stack pointer


		push ZL
		push ZH
		push YL
		push YH
		push r23
		push r16
		push r17
		push r18
		push r19
		push r20
		in YH, SPH
		in YL, SPL
		
		clr r20
		ldd r23, Y + 14
		ldi ZL, low(ITU_MORSE << 1)
		ldi ZH, high(ITU_MORSE << 1)

		ldi r18, 0xd0
		
		loopforchar:
			lpm r16, Z+
			cp r16, r23
			breq getdotdash
			forcharcont:
			dec r18
			cpi r18, 0x00
			brne loopforchar
			rjmp doned


		getdotdash:
			lpm r16, Z+
			cpi r16, 0x2e
			breq dodot
			cpi r16, 0x2d
			breq dodash
			cpi r16, 0x00
			rjmp forcharcont

		dodot:
			inc r19

			rjmp getdotdash


		dodash:
			inc r19
			lsl r20
			inc r20
			rjmp getdotdash
		doned:
			swap r19
			add r19, r20
			mov r0, r19
			mov r16, r19


			
		endencode:
			pop r20
			pop r19
			pop r18
			pop r17
			pop r16
			pop r23
			pop YH
			pop YL
			pop ZH
			pop ZL
		
	ret	 	

; **********************************************
; **** END OF SECOND "STUDENT CODE" SECTION **** 
; **********************************************


; =============================================
; ==== BEGINNING OF "DO NOT TOUCH" SECTION ====
; =============================================

delay_long:
	rcall delay
	rcall delay
	rcall delay
	ret

delay_short:
	rcall delay
	ret

; When wanting about a 1/5th of second delay, all other
; code must call this function
;
delay:
	rcall delay_busywait
	ret


; This function is ONLY called from "delay", and
; never directly from other code.
;
delay_busywait:
	push r16
	push r17
	push r18

	ldi r16, 0x08
delay_busywait_loop1:
	dec r16
	breq delay_busywait_exit
	
	ldi r17, 0xff
delay_busywait_loop2:
	dec	r17
	breq delay_busywait_loop1

	ldi r18, 0xff
delay_busywait_loop3:
	dec r18
	breq delay_busywait_loop2
	rjmp delay_busywait_loop3

delay_busywait_exit:
	pop r18
	pop r17
	pop r16
	ret

		
.org 0x1000

ITU_MORSE: .db "a", ".-", 0, 0, 0, 0, 0
	.db "b", "-...", 0, 0, 0
	.db "c", "-.-.", 0, 0, 0
	.db "d", "-..", 0, 0, 0, 0
	.db "e", ".", 0, 0, 0, 0, 0, 0
	.db "f", "..-.", 0, 0, 0
	.db "g", "--.", 0, 0, 0, 0
	.db "h", "....", 0, 0, 0
	.db "i", "..", 0, 0, 0, 0, 0
	.db "j", ".---", 0, 0, 0
	.db "k", "-.-", 0, 0, 0, 0
	.db "l", ".-..", 0, 0, 0
	.db "m", "--", 0, 0, 0, 0, 0
	.db "n", "-.", 0, 0, 0, 0, 0
	.db "o", "---", 0, 0, 0, 0
	.db "p", ".--.", 0, 0, 0
	.db "q", "--.-", 0, 0, 0
	.db "r", ".-.", 0, 0, 0, 0
	.db "s", "...", 0, 0, 0, 0
	.db "t", "-", 0, 0, 0, 0, 0, 0
	.db "u", "..-", 0, 0, 0, 0
	.db "v", "...-", 0, 0, 0
	.db "w", ".--", 0, 0, 0, 0
	.db "x", "-..-", 0, 0, 0
	.db "y", "-.--", 0, 0, 0
	.db "z", "--..", 0, 0, 0
	.db 0, 0, 0, 0, 0, 0, 0, 0

MESSAGE01: .db "a a a", 0
MESSAGE02: .db "sos", 0
MESSAGE03: .db "a box", 0
MESSAGE04: .db "dairy queen", 0
MESSAGE05: .db "the shape of water", 0, 0
MESSAGE06: .db "top gun maverick", 0, 0
MESSAGE07: .db "obi wan kenobi", 0, 0
MESSAGE08: .db "oh canada our own and native land", 0
MESSAGE09: .db "is that your final answer", 0

; First message ever sent by Morse code (in 1844)
MESSAGE10: .db "what god hath wrought", 0


.dseg
.org 0x200
BUFFER01: .byte 128
BUFFER02: .byte 128
TESTBUFFER: .byte 4

; =======================================
; ==== END OF "DO NOT TOUCH" SECTION ====
; =======================================
