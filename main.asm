; --COPYRIGHT--,BSD_EX
;  Copyright (c) 2012, Texas Instruments Incorporated
;  All rights reserved.
; 
;  Redistribution and use in source and binary forms, with or without
;  modification, are permitted provided that the following conditions
;  are met:
; 
;  *  Redistributions of source code must retain the above copyright
;     notice, this list of conditions and the following disclaimer.
; 
;  *  Redistributions in binary form must reproduce the above copyright
;     notice, this list of conditions and the following disclaimer in the
;     documentation and/or other materials provided with the distribution.
; 
;  *  Neither the name of Texas Instruments Incorporated nor the names of
;     its contributors may be used to endorse or promote products derived
;     from this software without specific prior written permission.
; 
;  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
;  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
;  PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
;  CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
;  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
;  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
;  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
;  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
;  EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
; 
; ******************************************************************************
;  
;                        MSP430 CODE EXAMPLE DISCLAIMER
; 
;  MSP430 code examples are self-contained low-level programs that typically
;  demonstrate a single peripheral function or device feature in a highly
;  concise manner. For this the code may rely on the device's power-on default
;  register values and settings such as the clock configuration and care must
;  be taken when combining code from several examples to avoid potential side
;  effects. Also see www.ti.com/grace for a GUI- and www.ti.com/msp430ware
;  for an API functional library-approach to peripheral configuration.
; 
; --/COPYRIGHT--
;*******************************************************************************
;   MSP430G2xx3 Demo - Reset on Invalid Address fetch, Toggle P1.0
;
;   Description: Toggle P1.0 by xor'ing P1.0 inside of a software loop that
;   ends with TAR loaded with 3FFFh - op-code for "jmp $" This simulates a code
;   error. The MSP430F2xx will force a reset because it will not allow a fetch
;   from within the address range of the peripheral memory, as is seen by
;   return to the mainloop and LED flash.
;   In contrast, an MSP430F1xx device will "jmp $" stopping code execution with
;   no LED flash.
;   ACLK = n/a, MCLK = SMCLK = default DCO
;
;                MSP430G2xx3
;             -----------------
;         /|\|              XIN|-
;          | |                 |
;          --|RST          XOUT|-
;            |                 |
;            |             P1.0|-->LED
;
;   D. Dang
;   Texas Instruments Inc.
;   December 2010
;   Built with Code Composer Essentials Version: 4.2.0
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
    bis.b #BUTALL, &P1REN ; enable buttons
    bis.b #BUTALL, &P1OUT 
    bis.b #LEDALL, &P2DIR   ; set leds as output
    bic.b #LEDALL, &P2OUT   ; Ensure all are OFF initially

;------------------------------------------------------------------------------
;           MAIN LOOP
;------------------------------------------------------------------------------
wait:
    inc r12 ; seed 
    bit.b #00001000b,&P1IN
    jnz wait

MAINLOOP:
    call #GEN_RANDOM ; create random array

userin:
    jmp userin
    jmp MAINLOOP

GEN_RANDOM:
; --- PRNG Step (Seed in R12) ---
    mov.w &LEVEL, r10
    mov.w #ORDER, r11
    inc.w r11
.GEN_RANDOM_LOOP:
; 1. Standard LFSR Step 
    bit.w   #1, r12
    clrc
    rrc.w   r12
    jnc     .NO_XOR
    xor.w   #0xB400, r12
.NO_XOR:
    mov r12, r13 ; mask bits
    and.w #0x0003,r13
    mov.b  r13, 0(r11)
    ; show the generated lights
    bis.b BITTABLE(r13), &P2OUT
    call #DELAY
    bic.b #LEDALL, &P2OUT  ; turn off

    inc.w   r11
    dec.w   r10
    jnz .GEN_RANDOM_LOOP
.DONE:
    inc.w &LEVEL                ; increnent level
    ret                         ; Return to caller
    
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
;------------------------------------------------------------------------------
;           data
;------------------------------------------------------------------------------
.data
LEVEL:
    .word 5
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

BITTABLE: .word 0x0102,0x0408 ; convert table for leds

;------------------------------------------------------------------------------
;           Interrupt Vectors
;------------------------------------------------------------------------------
            .sect   ".reset"                ; MSP430 RESET Vector
            .short  RESET                   ;        
            .end
