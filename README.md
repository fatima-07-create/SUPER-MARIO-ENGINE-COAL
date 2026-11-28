# Super Mario Engine – Game State Machine

## Game State Management

The game is controlled by a **state variable (state machine)** that determines which part of the game is currently running. A jump table is used to handle different states based on the current state number.

Each state has its own behavior and transition conditions. The game changes from one state to another depending on player input and game events.

## Game States

The following table describes all game states, when each state is entered, and the conditions under which it is left.

| State | Entered When | Left When |
|---|---|---|
| **TITLE** | At program start, after Game Over, or after Level Complete. | Up/Down move the menu highlight. Enter on START → PLAYING. Enter on EXIT or Esc → EXIT. |
| **PLAYING** | When starting a new game or after the Life Lost screen. | P → PAUSED. Mario dies (Section 5.8) → DYING. Flag touched (Section 5.11) → WIN SEQUENCE. Esc → TITLE. |
| **PAUSED** | When P is pressed while playing. | P → PLAYING. Esc → TITLE. Game updates and the clock are frozen, and the current picture remains visible with "PAUSED" displayed. |
| **DYING** | When Mario dies (Section 5.8). | When the death animation finishes → LIFE LOST (if lives remain) or GAME OVER (if no lives remain). |
| **LIFE LOST** | After the death animation when Mario still has lives remaining. | After about 2 seconds → level reset → PLAYING. |
| **WIN SEQUENCE** | When Mario touches the flag pole (Section 5.11). | When the sliding and walking animations finish → LEVEL COMPLETE. |
| **LEVEL COMPLETE** | After the win sequence. | Enter → TITLE (a new game starts from scratch). |
| **GAME OVER** | When the last life is lost. | Enter → TITLE. |
| **EXIT** | When EXIT is selected from the title screen or Esc is pressed at the title screen. | Restore interrupt vectors, switch back to text mode, and return to DOS. |

## State Transition Handling

The game uses a state variable to keep track of the current state. A jump table indexed by the state number is used to execute the appropriate game-state handler.

The state machine ensures that:

- Only the current state's logic is executed.
- Player input controls the appropriate state transitions.
- Game updates and the game clock remain frozen while paused.
- Death and victory animations complete before transitioning to the next state.
- The game can return to the title screen after Game Over or Level Complete.
- The EXIT state safely restores system settings and returns control to DOS.
