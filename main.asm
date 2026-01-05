;*******************************************************************************
 .cdecls C,LIST,  "msp430.h"

;-------------------------------------------------------------------------------
            .def    RESET                   ; Export program entry-point to
                                            ; make it known to linker.
;------------------------------------------------------------------------------
            .text                           ; Program Start
;------------------------------------------------------------------------------
RESET       mov.w   #0280h,SP               ; Initialize stackpointer
StopWDT     mov.w   #WDTPW+WDTHOLD,&WDTCTL  ; Stop WDT

SETUP:
    bic.b #0xFF, &P1IE    ; disable all interrupts during config
    bis.b #0xff, &P1REN ; enable buttons resistors for stop floating
    bis.b #0xff, &P1OUT ; button presses h -> l, pull up all of them
    bis.b #LEDALL, &P2DIR   ; set leds as output
    bic.b #LEDALL, &P2OUT   ; Ensure all are OFF initially

    bis.w #GIE, SR ; enable interrupts
    bis.b #BUTGAME, &P1IES ; buttons interrupts from H to L
    bic.b #0xFF, &P1IFG ; clear interrrupts
    bis.b #BUTGAME, &P1IE  ; enable button interrupts

;------------------------------------------------------------------------------
;           MAIN LOOP
;------------------------------------------------------------------------------
wait:
    mov.w #ORDER, r10
    inc r12 ; seed 
    bit.b #00001000b,&P1IN
    
    jnz wait

MAINLOOP:
    cmp.w #2, &LEVEL
    jnz .lvl_ok
    mov.w #1, &LEVEL
    call #GEN_RANDOM ; create random array
    mov.w #2, &LEVEL
    call #GEN_RANDOM ; create random array
    jmp .after_gen
.lvl_ok:
    call #GEN_RANDOM ; create random array
.after_gen:
    call #SHOW_LEVEL 
    mov.b #PLAYER_TURN, &STATE ; set game state
    mov.w #0, r11 ; set players progression
PLAYER_TURN_STATE:
    cmp #PLAYER_TURN, &STATE
    jz PLAYER_TURN_STATE ; player still playing
    
    cmp #WIN, &STATE 
    jz WIN_STATE ; player passed the level

    cmp #LOSE, &STATE 
    jz LOSE_STATE ; player failed the level
 
EGG_STATE:
    jmp wait

LOSE_STATE:
    ; do smth
    bic.w #GIE, SR ; disable interrupts
    mov.w #PLAYER_TURN, &STATE
    mov.w #2, &LEVEL
    mov.w #0, r11
    jmp wait

WIN_STATE:
    inc.w &LEVEL ; increnent level
    jmp MAINLOOP ; continue 

; functions

SHOW_LEVEL:
    mov.w #ORDER, r11
    mov.w &LEVEL, r5
   
.SHOW_LEVEL_loop:
    mov.b @r11+, r13 ; get current and increment pointer
    ; show the generated lights
    bis.b BITLEDTABLE(r13), &P2OUT
    call #DELAY
    bic.b #LEDALL, &P2OUT  ; turn off

    dec r5
    jnz .SHOW_LEVEL_loop ; return if -1 (flowed) not negative
    ret

GEN_RANDOM:
; --- (Seed in R12) ---
    mov.w &LEVEL,r11
; xorshift798
    mov.w #7, r5
    call #SHR
    mov.w #9, r5
    call #SHL
    mov.w #8, r5
    call #SHR    
; save the value 
    mov r12, r13 ; mask bits
    and.w #0x0003,r13
    dec.w r11
    mov.b r13,ORDER(r11)
    ret                         ; Return to caller
    
SHR: ; r12 >>= r5
    rra.w r12
    dec.w r5
    jnz SHR
    ret 
SHL: ; r12 <<= r5
    rla.w r12
    dec.w r5
    jnz SHL
    ret

DELAY: 
    push r5
    xor.w r5,r5
.DELAY_LOOP:
    nop
    nop
    nop
    dec r5
    jnz .DELAY_LOOP
    pop r5
    ret

; BUTTON ISR
p1_ISR: ; r11 = progression (current led/button/whatever) points to ORDER+index
    mov.b &P1IFG, r5
    and.b #BUTGAME, r5
    bic.b #BUTGAME, &P1IFG ; clear IF for next interrupt

    mov.b ORDER(r11),r6
    mov.b BITBUTTABLE(r6),r6 ; needed button

    cmp.b r6,r5 ; compare
    jnz .isr_false
.isr_correct
    
    mov.w &LEVEL, r7
    dec.w r7
    cmp.w r7, r11
    jnz .isr_done
.isr_correct_win
    mov.w #WIN,&STATE
    jmp .isr_done
.isr_false
    mov.w #LOSE,&STATE
    jmp .isr_done

.isr_egg ; maybe ?
    jmp .isr_done
.isr_done
    inc r11
    reti
;------------------------------------------------------------------------------
;           data
;------------------------------------------------------------------------------
    
.data
STATE:
    .word 0
LEVEL:
    .word 2
ORDER:
    .space 32

; DEFINE LED CONSTANTS 
LED0    .equ    0x0001
LED1    .equ    0x0002
LED2    .equ    0x0004
LED3    .equ    0x0008
LEDALL  .equ    0x000f
; DEFINE BUTTON CONSTANTS
BUT0    .equ    0x0001
BUT1    .equ    0x0002
BUT2    .equ    0x0008
BUT3    .equ    0x0010
BUTONB  .equ    0x0004
BUTALL  .equ    0x001f
BUTGAME .equ    0x001b
; DEFINE GAME STATES
PLAYER_TURN     .equ    0
WIN             .equ    1
LOSE            .equ    2
EGG             .equ    3

BITLEDTABLE: .byte 0x01,0x02,0x04,0x08 ; convert table for led: int to pin
BITBUTTABLE: .byte 0x01,0x02,0x08,0x10 ; convert table for buttons: int to pin

;-------------------------------------------------------------------------------
; Stack Pointer definition
            ;-------------------------------------------------------------------------------
            .global __STACK_END
            .sect .stack


;------------------------------------------------------------------------------
;           Interrupt Vectors
;------------------------------------------------------------------------------
            .sect ".int02" ; Port 1 interrupt vector
            .short p1_ISR
            .sect   ".reset"                ; MSP430 RESET Vector
            .short  RESET                   ;        
            .end
