# MSP430 Memory Game

This project is a simple memory game (similar to Simon Says) implemented in MSP430 assembly language.
The microcontroller displays a sequence using LEDs, and the player is expected to repeat the same sequence using push buttons.

The main purpose of this project is to practice low-level programming, interrupt handling, and state-based game logic on the MSP430 microcontroller.

In addition to the main gameplay, the project also contains a hidden easter egg feature that can be discovered through a specific user interaction.

## How the Game Works

- The game starts in an idle state and waits for user input
- A random LED sequence is generated based on the current level
- The sequence is displayed to the player using LEDs
- The player must repeat the same sequence using the buttons
- If the input is correct, the level is increased and a longer sequence is generated
- If the input is wrong, the game resets and waits for a new start

## Implementation Details

- Random values are generated using a bit-shift based pseudo-random method
- Button inputs are handled using Port 1 interrupts
- LEDs are controlled through Port 2
- The overall game flow is controlled using a state variable (player turn, win, lose, etc.)
- A small hidden easter egg is implemented using an alternative control flow and LED animation
- Care was taken to avoid infinite loops and stack-related issues

## Hardware Assumptions

- MSP430 microcontroller
- LEDs connected to Port 2 (P2.0 – P2.3)
- Buttons connected to Port 1 with pull-up resistors enabled
- Button interrupts are triggered on high-to-low transitions
- Pin definitions can be easily changed from the constant section in the source code

## TODO

- Make the game faster as levels increase
- Add a time limit for player input
- Implement a score system

## Notes

This project was developed mainly for learning purposes.
The code is not heavily optimized, but it is written in a clear way to make debugging and understanding easier.

## Build Information

- Developed using Code Composer Studio
- Target platform: MSP430
