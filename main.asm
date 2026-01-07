;===============================================================================
; MSP430G2553 - Simon Says Memory Game
; Requirements implemented:
;  - Idle animation (waiting for start)
;  - Student-designed start mechanism: long-press one button (~1s) to start
;    and select difficulty (Easy/Med/Hard/Nightmare)
;  - 3 levels: lengths 2,3,5 (Level1>=2, increasing by +1/+2)
;  - Correct level: onboard GREEN LED blink + 2s pause
;  - Wrong input: onboard RED LED ON + all 4 LEDs blink for 2s + back to idle
;  - Winning condition: external WIN LED (P2.4) stays ON until next game
;  - Bonus: Random pattern generation (xorshift16 + WDT seeding)
;  - Bonus: Easter egg (hold all 4 buttons in idle)
;
; Pin map:
;   Game LEDs : P2.0..P2.3
;   WIN LED   : P2.4 (external green)
;   RED LED   : P1.0 (on-board)
;   GREEN LED : P1.6 (on-board)
;   Buttons   : P1.1..P1.4 (pull-up, pressed=0)
;===============================================================================

            .cdecls C,LIST,"msp430.h"
            .def    RESET

;----------------------------
; Constants / Equates
;----------------------------
GAME_LEDS       .equ    (BIT0|BIT1|BIT2|BIT3)   ; P2.0..P2.3
WIN_LED         .equ    BIT4                    ; P2.4

RED_LED         .equ    BIT0                    ; P1.0
GRN_LED         .equ    BIT6                    ; P1.6

BTN_MASK        .equ    (BIT1|BIT2|BIT3|BIT4)   ; P1.1..P1.4

; States
S_IDLE          .equ    0
S_PLAYER        .equ    1
S_LEVEL_WIN     .equ    2
S_LEVEL_LOSE    .equ    3

NUM_LEVELS      .equ    3
MAX_STEPS       .equ    16                      ; generate up to 16 random steps

; Timing thresholds (in "ticks" of DELAY_MS)
START_HOLD_T    .equ    20                      ; ~1s hold (tune)
EGG_HOLD_T      .equ    20                      ; ~1s hold (tune)

;-------------------------------------------------------------------------------
            .text
            .retain
            .retainrefs

;===============================================================================
; RESET / INIT
;===============================================================================
RESET:
            mov.w   #0280h, SP                  ; init stack

            mov.w   #WDTPW|WDTHOLD, &WDTCTL     ; stop WDT immediately

; Optional: set DCO to ~1MHz for more stable delays (uses factory calib)
            mov.b   &CALBC1_1MHZ, &BCSCTL1
            mov.b   &CALDCO_1MHZ, &DCOCTL

; Start WDT in interval mode to "stir" the seed while waiting in idle
            mov.w   #WDTPW|WDTTMSEL|WDTCNTCL|WDTIS1|WDTIS0, &WDTCTL
            bis.b   #WDTIE, &IE1

;----------------------------
; Port setup
;----------------------------
; P2: game LEDs + win LED outputs
            bis.b   #(GAME_LEDS|WIN_LED), &P2DIR
            bic.b   #GAME_LEDS, &P2OUT          ; keep WIN LED as-is (do not touch here)

; P1: onboard LEDs outputs
            bis.b   #(RED_LED|GRN_LED), &P1DIR
            bic.b   #(RED_LED|GRN_LED), &P1OUT

; P1: buttons inputs with pull-ups
            bic.b   #BTN_MASK, &P1DIR
            bis.b   #BTN_MASK, &P1REN
            bis.b   #BTN_MASK, &P1OUT           ; pull-up => released=1

; Button interrupts (falling edge)
            bis.b   #BTN_MASK, &P1IES
            bic.b   #BTN_MASK, &P1IFG
            bis.b   #BTN_MASK, &P1IE

; Init variables
            mov.w   #S_IDLE, &STATE
            mov.w   #0, &LEVEL
            mov.w   #0, &PROG
            mov.w   #0, &BTN_EVENT
            mov.w   #0, &START_CNT
            mov.w   #0, &EGG_CNT
            mov.w   #0, &DIFF

            bis.w   #GIE, SR                    ; enable interrupts

;===============================================================================
; MAIN LOOP (state machine)
;===============================================================================
MAIN:
;----------------------------
; IDLE: animation + start/easter-egg detection
;----------------------------
IDLE_STATE:
            mov.w   #S_IDLE, &STATE
            bic.b   #(RED_LED|GRN_LED), &P1OUT  ; onboard LEDs off
            bic.b   #GAME_LEDS, &P2OUT          ; turn off game LEDs (do NOT clear WIN_LED)

            mov.w   #0, &START_CNT
            mov.w   #0, &EGG_CNT

IDLE_LOOP:
; idle animation: LED0 -> LED1 -> LED2 -> LED3 (one by one)
            mov.w   #0, r10                     ; r10 = led index 0..3

.IDLE_NEXT_LED:
            call    #IDLE_CHECK_INPUTS          ; may jump to START_GAME / EASTER_EGG

; turn on selected LED
            mov.w   r10, r11
            call    #IDX_TO_LED_MASK            ; returns mask in r12 (byte in low)
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r12, &P2OUT

            mov.w   #10, r14
            call    #DELAY_MS

; off
            bic.b   #GAME_LEDS, &P2OUT
            mov.w   #10, r14
            call    #DELAY_MS

; next index
            inc.w   r10
            cmp.w   #4, r10
            jne     .IDLE_NEXT_LED

            jmp     IDLE_LOOP

;----------------------------
; START GAME: clear WIN, stop WDT, generate random pattern, go show level
;----------------------------
START_GAME:
            bic.b   #WIN_LED, &P2OUT            ; WIN LED must clear when a new game starts

; stop WDT while playing (avoid jitter)
            mov.w   #WDTPW|WDTHOLD, &WDTCTL
            bic.b   #WDTIE, &IE1

            mov.w   #0, &LEVEL
            mov.w   #0, &PROG
            mov.w   #0, &BTN_EVENT

            call    #GEN_RANDOM_PATTERN         ; fill ORDER[0..MAX_STEPS-1]

            jmp     SHOW_LEVEL

;----------------------------
; SHOW LEVEL PATTERN
;----------------------------
SHOW_LEVEL:
            mov.w   #0, &PROG
            call    #SHOW_PATTERN

; enable input phase
            mov.w   #S_PLAYER, &STATE
            mov.w   #0, &BTN_EVENT
            bic.b   #BTN_MASK, &P1IFG
            bis.b   #BTN_MASK, &P1IE

; wait for player sequence to complete or fail
PLAYER_LOOP:
            cmp.w   #S_PLAYER, &STATE
            jne     PLAYER_DONE

            mov.w   &BTN_EVENT, r12
            cmp.w   #0, r12
            jeq     PLAYER_LOOP                 ; no button event yet

; consume event: r12 = (idx+1), so idx = r12-1
            dec.w   r12                         ; r12 = idx 0..3
            mov.w   r12, r13                    ; pressed idx -> r13

; expected idx = ORDER[PROG]
            mov.w   #ORDER, r10
            add.w   &PROG, r10
            mov.b   0(r10), r14                 ; expected idx in r14 (low byte)
            and.w   #0x00FF, r14

            cmp.w   r14, r13
            jne     SET_LOSE

; correct: light corresponding LED while button held, then advance PROG
            mov.w   r13, r11
            call    #IDX_TO_LED_MASK            ; r12 = LED mask
            bis.b   r12, &P2OUT

; wait until release
            mov.w   r13, r11
            call    #IDX_TO_BTN_MASK            ; r12 = BTN mask
.WAIT_RELEASE:
            bit.b   r12, &P1IN                  ; released => bit=1
            jnz     .RELEASED
            jmp     .WAIT_RELEASE
.RELEASED:
            bic.b   #GAME_LEDS, &P2OUT

; re-enable button interrupts for next press
            bic.b   #BTN_MASK, &P1IFG
            bis.b   #BTN_MASK, &P1IE

; next step
            inc.w   &PROG

; if PROG == level_length => level success
            call    #GET_LEVEL_LENGTH           ; returns length in r12
            cmp.w   r12, &PROG
            jeq     SET_LEVEL_WIN

; clear event and continue
            mov.w   #0, &BTN_EVENT
            jmp     PLAYER_LOOP

SET_LOSE:
            mov.w   #S_LEVEL_LOSE, &STATE
            jmp     PLAYER_DONE

SET_LEVEL_WIN:
            mov.w   #S_LEVEL_WIN, &STATE
            jmp     PLAYER_DONE

PLAYER_DONE:
            cmp.w   #S_LEVEL_WIN, &STATE
            jeq     LEVEL_WIN_HANDLER

            cmp.w   #S_LEVEL_LOSE, &STATE
            jeq     LEVEL_LOSE_HANDLER

            jmp     IDLE_STATE

;----------------------------
; LEVEL WIN HANDLER
;----------------------------
LEVEL_WIN_HANDLER:
; onboard GREEN LED brief blink
            bis.b   #GRN_LED, &P1OUT
            mov.w   #15, r14
            call    #DELAY_MS
            bic.b   #GRN_LED, &P1OUT

; required 2-second pause before next pattern
            call    #DELAY_2S

; next level
            inc.w   &LEVEL
            cmp.w   #NUM_LEVELS, &LEVEL
            jeq     GAME_WON

            jmp     SHOW_LEVEL

;----------------------------
; LEVEL LOSE HANDLER
;----------------------------
LEVEL_LOSE_HANDLER:
            bis.b   #RED_LED, &P1OUT            ; red on

; blink all 4 LEDs simultaneously for ~2 seconds
            mov.w   #8, r15                     ; 8 toggles * 250ms ≈ 2s (tune)
.BLINK_LOOP:
            xor.b   #GAME_LEDS, &P2OUT
            mov.w   #25, r14
            call    #DELAY_MS
            dec.w   r15
            jnz     .BLINK_LOOP

            bic.b   #GAME_LEDS, &P2OUT
            bic.b   #RED_LED, &P1OUT            ; red off

; lose => return to idle, WDT seeding resumes
            call    #RESUME_WDT_SEED
            jmp     IDLE_STATE

;----------------------------
; GAME WON HANDLER
;----------------------------
GAME_WON:
; external WIN LED stays ON until a new game starts
            bis.b   #WIN_LED, &P2OUT

; return to idle, WDT seeding resumes
            call    #RESUME_WDT_SEED
            jmp     IDLE_STATE

;===============================================================================
; SUBROUTINES
;===============================================================================

;----------------------------
; IDLE_CHECK_INPUTS
; - called periodically during idle animation
; - detects:
;   * Start: hold exactly one button ~1s => sets DIFF and jumps START_GAME
;   * Easter egg: hold all 4 buttons ~1s => run EASTER_EGG
;----------------------------
IDLE_CHECK_INPUTS:
            push    r10
            push    r11
            push    r12
            push    r13

; read buttons (pressed=0)
            mov.b   &P1IN, r12
            and.b   #BTN_MASK, r12

; all pressed? (all bits are 0)
            cmp.b   #0, r12
            jne     .NOT_ALL

; all four held -> egg counter++
            inc.w   &EGG_CNT
            cmp.w   #EGG_HOLD_T, &EGG_CNT
            jl      .DONE

; trigger easter egg
            mov.w   #0, &EGG_CNT
            call    #EASTER_EGG
            jmp     .DONE

.NOT_ALL:
            mov.w   #0, &EGG_CNT

; start detection: exactly one button pressed (one bit 0, others 1)
; We check each button; if more than one pressed => reset
            mov.w   #0, r13                     ; pressed_count
            mov.w   #0, r11                     ; selected_idx

; BTN0 (P1.1)
            bit.b   #BIT1, r12
            jnz     .B1_NOT
            inc.w   r13
            mov.w   #0, r11
.B1_NOT:
; BTN1 (P1.2)
            bit.b   #BIT2, r12
            jnz     .B2_NOT
            inc.w   r13
            mov.w   #1, r11
.B2_NOT:
; BTN2 (P1.3)
            bit.b   #BIT3, r12
            jnz     .B3_NOT
            inc.w   r13
            mov.w   #2, r11
.B3_NOT:
; BTN3 (P1.4)
            bit.b   #BIT4, r12
            jnz     .B4_NOT
            inc.w   r13
            mov.w   #3, r11
.B4_NOT:

; if pressed_count != 1 => reset start counter
            cmp.w   #1, r13
            jeq     .ONE_PRESSED

            mov.w   #0, &START_CNT
            jmp     .DONE

.ONE_PRESSED:
            inc.w   &START_CNT
            cmp.w   #START_HOLD_T, &START_CNT
            jl      .DONE

; start condition met: set difficulty and jump to START_GAME
            mov.w   r11, &DIFF
            mov.w   #0, &START_CNT

            pop     r13
            pop     r12
            pop     r11
            pop     r10
            jmp     START_GAME

.DONE:
            pop     r13
            pop     r12
            pop     r11
            pop     r10
            ret

;----------------------------
; RESUME_WDT_SEED
; - restart WDT interval + enable WDT interrupt for seeding in idle
;----------------------------
RESUME_WDT_SEED:
            mov.w   #WDTPW|WDTTMSEL|WDTCNTCL|WDTIS1|WDTIS0, &WDTCTL
            bis.b   #WDTIE, &IE1
            ret

;----------------------------
; GET_LEVEL_LENGTH
; - returns length in r12 for current LEVEL (0..NUM_LEVELS-1)
;----------------------------
GET_LEVEL_LENGTH:
            push    r10
            mov.w   &LEVEL, r10
            rla.w   r10                           ; *2 (word table)
            add.w   #LEVEL_LEN_TBL, r10
            mov.w   0(r10), r12
            pop     r10
            ret

;----------------------------
; SHOW_PATTERN
; - shows ORDER[0..len-1] based on DIFF timing
;----------------------------
SHOW_PATTERN:
            push    r10
            push    r11
            push    r12
            push    r13
            push    r14

            call    #GET_LEVEL_LENGTH
            mov.w   r12, r13                     ; r13 = length

            mov.w   #0, r10                      ; i=0
.SHOW_LOOP:
            cmp.w   r13, r10
            jeq     .DONE

; idx = ORDER[i]
            mov.w   #ORDER, r11
            add.w   r10, r11
            mov.b   0(r11), r12
            and.w   #0x00FF, r12
            mov.w   r12, r11                     ; idx -> r11

; LED ON
            call    #IDX_TO_LED_MASK             ; r12 = LED mask
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r12, &P2OUT

            call    #DELAY_PATTERN_ON

; LED OFF
            bic.b   #GAME_LEDS, &P2OUT
            call    #DELAY_PATTERN_OFF

            inc.w   r10
            jmp     .SHOW_LOOP

.DONE:
            bic.b   #GAME_LEDS, &P2OUT
            pop     r14
            pop     r13
            pop     r12
            pop     r11
            pop     r10
            ret

;----------------------------
; DELAY helpers
;----------------------------
DELAY_PATTERN_ON:
; r14 = ON ticks from table by DIFF
            push    r10
            push    r11
            mov.w   &DIFF, r10
            rla.w   r10
            add.w   #ON_TBL, r10
            mov.w   0(r10), r14
            call    #DELAY_MS
            pop     r11
            pop     r10
            ret

DELAY_PATTERN_OFF:
            push    r10
            push    r11
            mov.w   &DIFF, r10
            rla.w   r10
            add.w   #OFF_TBL, r10
            mov.w   0(r10), r14
            call    #DELAY_MS
            pop     r11
            pop     r10
            ret

DELAY_2S:
; approx 2 seconds (tune r14 if needed)
            mov.w   #200, r14
            call    #DELAY_MS
            ret

;----------------------------
; DELAY_MS
; - crude calibrated delay loop
; - input: r14 = number of outer ticks
;----------------------------
DELAY_MS:
            push    r15
.OUTER:
            mov.w   #400, r15                    ; inner loop count (tune)
.INNER:
            dec.w   r15
            jnz     .INNER
            dec.w   r14
            jnz     .OUTER
            pop     r15
            ret

;----------------------------
; IDX_TO_LED_MASK
; - input:  r11 = idx 0..3
; - output: r12 (low byte) = BIT0..BIT3 for P2
;----------------------------
IDX_TO_LED_MASK:
            push    r10
            mov.w   #LED_LUT, r10
            add.w   r11, r10
            mov.b   0(r10), r12
            pop     r10
            ret

;----------------------------
; IDX_TO_BTN_MASK
; - input:  r11 = idx 0..3
; - output: r12 (low byte) = BIT1..BIT4 for P1
;----------------------------
IDX_TO_BTN_MASK:
            push    r10
            mov.w   #BTN_LUT, r10
            add.w   r11, r10
            mov.b   0(r10), r12
            pop     r10
            ret

;----------------------------
; GEN_RANDOM_PATTERN
; - xorshift16, stores indices 0..3 into ORDER[0..MAX_STEPS-1]
;----------------------------
GEN_RANDOM_PATTERN:
            push    r10
            push    r11
            push    r12
            push    r13
            push    r14
            push    r15

            mov.w   &SEED, r12                   ; seed in r12
            mov.w   #ORDER, r10                  ; dst pointer
            mov.w   #MAX_STEPS, r11              ; count

.RNG_LOOP:
; xorshift16: s ^= s>>7; s ^= s<<9; s ^= s>>8
            mov.w   r12, r13
            mov.w   #7, r14
.SHR7:      rra.w   r13
            dec.w   r14
            jnz     .SHR7
            xor.w   r13, r12

            mov.w   r12, r13
            mov.w   #9, r14
.SHL9:      rla.w   r13
            dec.w   r14
            jnz     .SHL9
            xor.w   r13, r12

            mov.w   r12, r13
            mov.w   #8, r14
.SHR8:      rra.w   r13
            dec.w   r14
            jnz     .SHR8
            xor.w   r13, r12

; idx = seed & 3
            mov.w   r12, r15
            and.w   #3, r15
            mov.b   r15, 0(r10)
            inc.w   r10

            dec.w   r11
            jnz     .RNG_LOOP

            mov.w   r12, &SEED                   ; save updated seed

            pop     r15
            pop     r14
            pop     r13
            pop     r12
            pop     r11
            pop     r10
            ret

;----------------------------
; EASTER_EGG
; - secret animation using only GAME_LEDS, preserves WIN_LED state
;----------------------------
EASTER_EGG:
            push    r12
            push    r13
            push    r14
            mov.b   &P2OUT, r12
            and.b   #WIN_LED, r12                ; preserve win bit in r12 (low)

; simple "ping-pong" animation
            mov.w   #3, r14
.EG1:
            mov.b   #BIT0, r13
            bis.b   r12, r13                     ; keep win
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r13, &P2OUT
            mov.w   #10, r14
            call    #DELAY_MS

            mov.b   #BIT1, r13
            bis.b   r12, r13
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r13, &P2OUT
            mov.w   #10, r14
            call    #DELAY_MS

            mov.b   #BIT2, r13
            bis.b   r12, r13
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r13, &P2OUT
            mov.w   #10, r14
            call    #DELAY_MS

            mov.b   #BIT3, r13
            bis.b   r12, r13
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r13, &P2OUT
            mov.w   #10, r14
            call    #DELAY_MS

            dec.w   r14
            jnz     .EG1

; restore: turn off game leds but keep win led as before
            bic.b   #GAME_LEDS, &P2OUT
            bis.b   r12, &P2OUT

            pop     r14
            pop     r13
            pop     r12
            ret

;===============================================================================
; INTERRUPTS
;===============================================================================

; Watchdog ISR: seed++
wdt_ISR:
            inc.w   &SEED
            reti

; Port 1 ISR: capture which button was pressed during PLAYER state
p1_ISR:
            push    r12
            push    r13

; only accept during player state
            cmp.w   #S_PLAYER, &STATE
            jne     .CLR_EXIT

; ignore if an event is already pending
            mov.w   &BTN_EVENT, r12
            cmp.w   #0, r12
            jne     .CLR_EXIT

; disable further button interrupts until main consumes this event
            bic.b   #BTN_MASK, &P1IE

; determine which IFG bit fired -> store idx+1 in BTN_EVENT (so 0 means none)
            mov.b   &P1IFG, r12
            and.b   #BTN_MASK, r12

            bit.b   #BIT1, r12
            jz      .CHK2
            mov.w   #1, &BTN_EVENT               ; idx0+1
            jmp     .CLR_EXIT
.CHK2:
            bit.b   #BIT2, r12
            jz      .CHK3
            mov.w   #2, &BTN_EVENT               ; idx1+1
            jmp     .CLR_EXIT
.CHK3:
            bit.b   #BIT3, r12
            jz      .CHK4
            mov.w   #3, &BTN_EVENT               ; idx2+1
            jmp     .CLR_EXIT
.CHK4:
            bit.b   #BIT4, r12
            jz      .CLR_EXIT
            mov.w   #4, &BTN_EVENT               ; idx3+1

.CLR_EXIT:
            bic.b   #BTN_MASK, &P1IFG
            pop     r13
            pop     r12
            reti

;===============================================================================
; DATA / TABLES
;===============================================================================
            .data
            .align 2

STATE:      .word   0
LEVEL:      .word   0
PROG:       .word   0
DIFF:       .word   0
SEED:       .word   0xACE1

BTN_EVENT:  .word   0          ; 0 = none, else (idx+1)

START_CNT:  .word   0
EGG_CNT:    .word   0

ORDER:      .space  MAX_STEPS  ; store idx bytes 0..3

            .sect ".const"
            .align 2

; Level lengths (word table)
LEVEL_LEN_TBL:
            .word   2, 3, 5

; Difficulty timing tables (ticks for DELAY_MS)
; index: 0 Easy, 1 Medium, 2 Hard, 3 Nightmare
ON_TBL:      .word  60, 45, 30, 20
OFF_TBL:     .word  30, 25, 18, 10

; LUTs for LED/BTN masks by idx
LED_LUT:     .byte  BIT0, BIT1, BIT2, BIT3
BTN_LUT:     .byte  BIT1, BIT2, BIT3, BIT4

;===============================================================================
; STACK & VECTORS
;===============================================================================
            .global __STACK_END
            .sect   .stack

            .sect   ".int10"            ; WDT vector
            .short  wdt_ISR
            .sect   ".int02"            ; Port1 vector
            .short  p1_ISR
            .sect   ".reset"
            .short  RESET
            .end
