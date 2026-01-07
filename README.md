# MSP430 Memory Game

This project is a simple memory game (similar to Simon Says) written in MSP430
assembly language. The microcontroller shows a sequence using LEDs and the player
is expected to repeat the same sequence using buttons.

The main goal of the project was to practice low-level programming, interrupt
handling, and state-based game logic on the MSP430.

---

## How the Game Works

- The game starts in an idle state and waits for user input
- A random LED pattern is generated depending on the current level
- The pattern is shown to the player using LEDs
- The player must repeat the pattern using buttons
- If the input is correct, the level increases
- If the input is wrong, the game resets and waits for a new start

---

## Implementation Details

- Random values are generated using a simple bit-shift based method
- Button inputs are handled using Port 1 interrupts
- LEDs are controlled through Port 2
- Game flow is controlled using a state variable (player turn, win, lose, etc.)
- Care was taken to avoid infinite loops and stack-related issues

---

## Hardware Assumptions

- MSP430 microcontroller
- LEDs connected to Port 2 (P2.0 – P2.3)
- Buttons connected to Port 1 with pull-up resistors enabled
- Button interrupts are triggered on high-to-low transitions

Pin definitions can be changed easily from the constant section in the source code.

---

## TODO

- If there is enough time, try to implement the 3rd extra point:  
  - make the game faster as levels increase  
  - add a time limit for player input

---

## Notes

This project was developed mainly for learning purposes. The code is not heavily
optimized, but it is written in a clear way to make debugging and understanding
easier.

---

## Build

- Developed using Code Composer Studio
- Target platform: MSP430
