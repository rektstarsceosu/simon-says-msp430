;*******************************************************************************
 .cdecls C,LIST,  "msp430.h"

;-------------------------------------------------------------------------------
            .def    RESET                   ; Export program entry-point to
                                            ; make it known to linker.

;------------------------------------------------------------------------------
            .text                           ; Assemble into program memory.
            .retain                         ; Override ELF conditional linking
                                            ; and retain current section.
            .retainrefs                     ; And retain any sections that have
                                            ; references to current section.
;------------------------------------------------------------------------------
RESET:    
    mov.w   #0280h,SP               ; Initialize stackpointer

SETUP:
    mov.w   #WDTPW+WDTTMSEL+WDTCNTCL+WDTIS0+WDTIS1, &WDTCTL ; start watchdog
    bis.b   #WDTIE, &IE1

    bic.b #0xff,&P1DIR ; set buttons in 
    bis.b #0xff, &P1REN ; enable buttons resistors for stop floating
    bis.b #0xff, &P1OUT ; button presses h -> l, pull up all of them
    bis.b #BUTGAME, &P1IES ; buttons interrupts from H to L
    bis.b #BUTGAME, &P1IE  ; set button interrupts

    bis.b #LEDALL, &P2DIR   ; set leds as output
    bic.b #LEDALL, &P2OUT   ; Ensure all are OFF initially

    bic.b #0xff, &P1IFG ; clear interrrupts
    bis.w #GIE, SR ; enable interrupts

    mov.w #0,&LEVEL
    mov.w #-1,&STATE
;------------------------------------------------------------------------------
;           MAIN LOOP
;------------------------------------------------------------------------------
wait:
    xor.b #LEDALL,&P2OUT
    call #DELAY

    bit.b #BUT3,&P1IN
    jnz wait

MAINLOOP:
    mov.w   #WDTPW+WDTHOLD,&WDTCTL  ; Stop WDT
    bic.b   #WDTIE, &IE1

    bic.b #LEDALL,&P2OUT ; turn off animation
    call #GEN_RANDOM ; create random
    mov.w #0,&LEVEL

START_LEVEL:
    mov.w #0, &PROG ; set players progression
    
    call #SHOW_LEVEL

    mov.w #PLAYER_TURN, &STATE ; set game state


PLAYER_TURN_STATE:
    cmp #PLAYER_TURN, &STATE
    jz PLAYER_TURN_STATE ; player still playing

    cmp #WIN, &STATE
    jz WIN_STATE ; player passed the level

    cmp #LOSE, &STATE
    jz LOSE_STATE ; player failed the level

EGG_STATE:
    push r12 ; corrupt stack >w<
    ret

LOSE_STATE:
    ; do smth
    ;reset
    mov.w   #0x0000, &WDTCTL

WIN_STATE:
    mov.w #4,r5
    mov.w #00100000b,&P2OUT
    rra.b &P2OUT
.WIN_STATE_loop:
    rra.b &P2OUT
    call #DELAY
    dec.w r5
    jnz .WIN_STATE_loop
    bic.b #LEDALL, &P2OUT ; done
    call #DELAY

    add.w #1, &LEVEL ; increnent level
    jmp START_LEVEL ; continue

; functions

SHOW_LEVEL:
    push r11
    push r5
    push r6 

    mov.w #ORDER, r11
    mov.w &LEVEL,r5
.SHOW_LEVEL_loop:
    mov.w 0(r11),r6
    ;call #INT2PIN
    bis.b r6, &P2OUT    

    add.w #2, r11
    call #DELAY
    bic.b #LEDALL, &P2OUT ; turn of leds
    call #DELAY
    
    add.w #-1, r5
    cmp.w #-1,r5
    jne .SHOW_LEVEL_loop ; return if -1 

    pop r6
    pop r5
    pop r11
    ret

GEN_RANDOM:
    push r6
    push r11
    push r12
    push r5
    push r13
    
; --- (Seed in RAM) ---
    mov.w &SEED, r12       ; Load seed from memory
    mov.w #ORDER,r11
    add.w &LEVEL,r11

.GEN_RANDOM_loop:
; xorshift798
    mov.w r12, r13        ; copy seed to r13
    mov.w #7, r5
    call #SHR            ; r13 = seed >> 7
    xor.w r13, r12        ; seed ^= (seed >> 7)

    mov.w r12, r13        ; copy new seed to r13
    mov.w #9, r5
    call #SHL            ; r13 = seed << 9
    xor.w r13, r12        ; seed ^= (seed << 9)

    mov.w r12, r13        ; copy new seed to r13
    mov.w #8, r5
    call #SHR            ; r13 = seed >> 8
    xor.w r13, r12        ; seed ^= (seed >> 8)
; save the value
    mov.w r12,r6
    and.w #0x03,r6
    call #INT2PIN
    mov.w r6,0(r11)
    add.w #2, r11
    cmp.w #ORDER+64,r11
    jne .GEN_RANDOM_loop

    mov.w r12, &SEED       ; Save evolved seed back to memory
    pop r13
    pop r5
    pop r12
    pop r11
    pop r6
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
INT2PIN: ; r6 => r6
    and.w #0x03,r6
    add.w r6,pc
    jmp .case1
    jmp .case2
    jmp .case3
    jmp .case4
.case1:
    mov.w #BUT0,r6 
    ret
.case2:
    mov.w #BUT1,r6 
    ret
.case3:
    mov.w #BUT2,r6 
    ret
.case4:
    mov.w #BUT3,r6 
    ret


DELAY:
    push r5
    xor.w r5,r5
.DELAY_LOOP:
    nop
    nop
    dec r5
    jnz .DELAY_LOOP
    pop r5   
    ret
; watchdog isr
wdt_ISR:
    inc.w &SEED           
    reti
; BUTTON ISR

p1_ISR: ;
    push r5
    push r6
    push r11

    cmp.w #-1,&STATE
    jeq .isr_done ; game has not started 

    mov.w &PROG,r11
    add.w r11,r11 
    add.w &ORDER,r11
    mov.w 0(r11),r6 ; get choice from order array

    bit.b r6, &P1IN ; check button
    jnz .isr_false

.isr_correct
    bis.b r6, &P2OUT
    bit.b r6, &P1IN
    jz .isr_correct
    bic.b #LEDALL,&P2OUT ; indicate that its correct

    cmp.w &PROG,&LEVEL
    jeq .isr_correct_win
    inc.w &PROG
    jmp .isr_done

.isr_correct_win
    mov.w #WIN,&STATE
    jmp .isr_done
.isr_false
    mov.w #LOSE,&STATE
    jmp .isr_done

.isr_egg ; maybe ?
    mov.w #EGG,&STATE
    jmp .isr_done
.isr_done

    pop r11
    pop r6
    pop r5
    bic.b #0xff, &P1IFG ; clear IF for next interrupt
    reti
;------------------------------------------------------------------------------
;           data
;------------------------------------------------------------------------------

    .sect ".const"
    .align 2

    .data
    .align 2
STATE:
    .word -1
LEVEL:
    .word 0
PROG:
    .word 0
SEED:
    .word 0xba11 ; storage for randomness
ORDER:
    .space 128

; DEFINE LED CONSTANTS
LED0    .equ    00000001b
LED1    .equ    00000010b
LED2    .equ    00000100b
LED3    .equ    00001000b
LEDALL  .equ    00001111b
; DEFINE BUTTON CONSTANTS
BUT0    .equ    00000001b
BUT1    .equ    00000010b
BUT2    .equ    00000100b
BUT3    .equ    00001000b
BUTALL  .equ    00001111b
BUTGAME .equ    00001111b
; DEFINE GAME STATES
PLAYER_TURN     .equ    0
WIN             .equ    1
LOSE            .equ    2
EGG             .equ    3



;-------------------------------------------------------------------------------
; Stack Pointer definition
            ;-------------------------------------------------------------------------------
            .global __STACK_END
            .sect .stack


;------------------------------------------------------------------------------
;           Interrupt Vectors
;------------------------------------------------------------------------------
            .sect ".int10" ; watchdog
            .short wdt_ISR
            .sect ".int02" ; Port 1 interrupt vector
            .short p1_ISR
            .sect   ".reset"                ; MSP430 RESET Vector
            .short  RESET                   ;
            .end