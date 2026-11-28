; ============================================================================
; SUPER MARIO ENGINE - MEMBER B COMPLETE GAME LOGIC & INTERRUPTS
; Modules Covered:
;   Module 7  : Keyboard Hardware Interrupt Handler (INT 09h)
;   Module 8  : Timer Hardware Interrupt Handler & Game Clock (INT 1Ch)
;   Module 9  : Player Movement & 8.8 Fixed-Point Physics
;   Module 10 : Axis-Separated Tile & Entity Collision Detection
;   Module 11 : Enemy & Koopa Shell AI State Machine
;   Module 12 : Interactive Blocks, Coins & Mushroom Power-Up Logic
;   Module 13 : 32-Bit Score, Health, Lives & Top-Bar HUD Renderer
;   Module 15 : Death/Win Sequences, Level Reset & Clean Vector Restoration
;
; Coding Conventions:
;   - 16-bit Real Mode x86 Assembly (NASM)
;   - Stack-based parameter passing for parameterized routines
;   - Full register preservation on all procedures
; ============================================================================

; ----------------------------------------------------------------------------
; Constants & Hardware Definitions (Appendix A)
; ----------------------------------------------------------------------------
KEY_LEFT        EQU 4Bh
KEY_RIGHT       EQU 4Dh
KEY_UP          EQU 48h
KEY_DOWN        EQU 50h
KEY_SPACE       EQU 39h
KEY_LSHIFT      EQU 2Ah
KEY_P           EQU 19h
KEY_W           EQU 11h
KEY_A           EQU 1Eh
KEY_D           EQU 20h
KEY_ENTER       EQU 1Ch
KEY_ESC         EQU 01h

; 8.8 Fixed-Point Physics Constants (Appendix A.5)
ACCEL_WALK      EQU 00C0h               ; Fast instant acceleration
FRICTION_DECEL  EQU 0080h               ; Quick crisp stop
MAX_WALK_SPD    EQU 0380h               ; 3.5 px/frame (2.3x faster)
MAX_RUN_SPD     EQU 0500h               ; 5.0 px/frame sprint
GRAVITY_ACCEL   EQU 00A0h               ; Snappy gravity
JUMP_START_VEL  EQU 0F600h              ; -10.0 px/frame instant jump
JUMP_CUTOFF_VEL EQU 0FC00h              ; -4.0 px/frame short hop
MAX_FALL_SPD    EQU 0600h               ; 6.0 px/frame max fall
STOMP_BOUNCE    EQU 0FA00h              ; -6.0 px/frame bounce              ; -3.0 px/frame

GOOMBA_SPD      EQU 0080h               ; 0.5 px/frame
KOOPA_SPD       EQU 00C0h               ; 0.75 px/frame
SHELL_SPD       EQU 0300h               ; 3.0 px/frame
MUSHROOM_SPD    EQU 0100h               ; 1.0 px/frame

; Tile Codes (Appendix A.2)
TILE_SKY        EQU 0
TILE_GROUND     EQU 1
TILE_BRICK      EQU 2
TILE_Q_COIN     EQU 3
TILE_Q_MUSH     EQU 4
TILE_EMPTY      EQU 5
TILE_PIPE_TL    EQU 6
TILE_PIPE_TR    EQU 7
TILE_PIPE_BL    EQU 8
TILE_PIPE_BR    EQU 9
TILE_STAIR      EQU 10
TILE_COIN       EQU 11
TILE_FLAG       EQU 12

; Game Limits & Map Dimensions
MAP_SIZE_BYTES  EQU (MAP_COLS * MAP_ROWS) ; 60 * 12 = 720 bytes
MAX_ENEMIES     EQU 8
ENEMY_REC_SIZE  EQU 12                  ; Bytes per enemy record
TICKS_PER_SEC   EQU 18                  ; Standard DOS 18.2 Hz timer tick

; Enemy Types & States
ETYPE_NONE      EQU 0
ETYPE_GOOMBA    EQU 1
ETYPE_KOOPA     EQU 2

ESTATE_SLEEP    EQU 0
ESTATE_WALK     EQU 1
ESTATE_FLAT     EQU 2
ESTATE_SHELL_ST EQU 3
ESTATE_SHELL_MV EQU 4

; Game State IDs (Section 5.12)
STATE_PLAYING   EQU 0
STATE_PAUSED    EQU 1
STATE_DYING     EQU 2
STATE_LIFELOST  EQU 3
STATE_WINSEQ    EQU 4
STATE_COMPLETE  EQU 5
STATE_GAMEOVER  EQU 6
STATE_EXIT_MENU EQU 7

; ============================================================================
; MODULE 7 & MODULE 8: HARDWARE INTERRUPT INSTALLATION & HANDLERS
; ============================================================================

; ----------------------------------------------------------------------------
; Procedure: InitSystemInterrupts
; Purpose  : Saves original INT 09h (keyboard) and INT 1Ch (timer) vectors,
;            clears the 128-byte key state table, and installs custom ISRs.
; Inputs   : None
; Outputs  : Custom keyboard & timer handlers active
; Registers: None changed (all preserved)
; ----------------------------------------------------------------------------
InitSystemInterrupts:
    push    ax
    push    bx
    push    cx
    push    dx
    push    di
    push    es

    ; Clear 128-byte key_state buffer
    push    cs
    pop     es
    mov     di, key_state
    mov     cx, 64
    xor     ax, ax
    rep     stosw
    mov     byte [e0_prefix], 0

    ; Save old INT 09h vector (Keyboard)
    mov     ax, 3509h
    int     21h
    mov     [old_int09_off], bx
    mov     [old_int09_seg], es

    ; Save old INT 1Ch vector (User Timer Tick)
    mov     ax, 351Ch
    int     21h
    mov     [old_int1c_off], bx
    mov     [old_int1c_seg], es

    ; Install new INT 09h and INT 1Ch vectors
    cli
    mov     ax, 2509h
    mov     dx, KeyboardISR
    int     21h

    mov     ax, 251Ch
    mov     dx, TimerISR
    int     21h
    sti

    pop     es
    pop     di
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

; ----------------------------------------------------------------------------
; Procedure: RestoreSystemInterrupts
; Purpose  : Restores original DOS INT 09h and INT 1Ch interrupt vectors so
;            the keyboard and clock work normally after exiting the game.
; Inputs   : None
; Outputs  : Original IVT entries restored
; Registers: None changed
; ----------------------------------------------------------------------------
RestoreSystemInterrupts:
    push    ax
    push    dx
    push    ds

    cli
    mov     dx, [cs:old_int09_off]
    mov     ds, [cs:old_int09_seg]
    mov     ax, 2509h
    int     21h

    mov     dx, [cs:old_int1c_off]
    mov     ds, [cs:old_int1c_seg]
    mov     ax, 251Ch
    int     21h
    sti

    pop     ds
    pop     dx
    pop     ax
    ret

; ----------------------------------------------------------------------------
; Procedure: KeyboardISR (INT 09h Hardware Handler)
; Purpose  : Reads scan codes from port 60h, handles E0h extended prefixes,
;            updates the 128-byte key_state table (1=pressed, 0=released),
;            and sends End-Of-Interrupt (EOI) to PIC port 20h.
; Inputs   : Hardware IRQ1 via Port 60h
; Outputs  : Updates key_state[scan_code]
; Registers: None changed (ISR safe)
; ----------------------------------------------------------------------------
KeyboardISR:
    push    ax
    push    bx
    push    ds

    push    cs
    pop     ds

    in      al, 60h                     ; Read scan code from keyboard controller

    cmp     al, 0E0h                    ; Extended key prefix (arrow keys)?
    jne     .process_code
    mov     byte [e0_prefix], 1
    jmp     .send_eoi

.process_code:
    mov     byte [e0_prefix], 0
    mov     bl, al
    and     bx, 007Fh                   ; Mask bit 7 to get base scan code (0..127)

    test    al, 80h                     ; Bit 7 = 1 means key release
    jnz     .key_released
    mov     byte [key_state + bx], 1    ; Key pressed
    jmp     .send_eoi

.key_released:
    mov     byte [key_state + bx], 0    ; Key released

.send_eoi:
    mov     al, 20h                     ; Send EOI to Master PIC
    out     20h, al

    pop     ds
    pop     bx
    pop     ax
    iret

; ----------------------------------------------------------------------------
; Procedure: TimerISR (INT 1Ch Hardware Handler)
; Purpose  : Increments frame tick counter every ~55ms and decrements the
;            300-second game clock once per real second when playing.
; Inputs   : Hardware IRQ0 via BIOS INT 1Ch chain
; Outputs  : Increments sys_ticks; updates game_time
; Registers: None changed (chains to original INT 1Ch)
; ----------------------------------------------------------------------------
TimerISR:
    push    ax
    push    ds

    push    cs
    pop     ds

    inc     word [sys_ticks]

    ; Only count down game clock during active PLAYING state
    cmp     byte [game_state], STATE_PLAYING
    jne     .chain_old

    inc     byte [sec_subticks]
    cmp     byte [sec_subticks], TICKS_PER_SEC
    jb      .chain_old

    mov     byte [sec_subticks], 0
    cmp     word [game_time], 0
    je      .chain_old
    dec     word [game_time]

 .chain_old:
    pop     ds
    pop     ax
    jmp     far [cs:old_int1c_off] ; Chain to original BIOS timer handler

; ============================================================================
; MODULE 15: LEVEL RESET, NEW GAME, DEATH & WIN SEQUENCES
; ============================================================================

; ----------------------------------------------------------------------------
; Procedure: NewGame
; Purpose  : Resets all session variables (score=0, coins=0, lives=3) and
;            initializes the level for a brand new playthrough.
; Inputs   : None
; Outputs  : Fresh game session ready in STATE_PLAYING
; Registers: None changed
; ----------------------------------------------------------------------------
NewGame:
    push    ax

    mov     word [score_low], 0
    mov     word [score_high], 0
    mov     word [coins_count], 0
    mov     byte [lives_count], 3

    call    ResetLevel

    pop     ax
    ret

; ----------------------------------------------------------------------------
; Procedure: ResetLevel
; Purpose  : Restores working_map from original_map using REP MOVSB, resets
;            Mario to Small form (HP=1) at start coordinates, resets camera,
;            clock (300s), mushroom, and reloads initial enemy table.
; Inputs   : None
; Outputs  : Level state restored for current life
; Registers: None changed
; ----------------------------------------------------------------------------
ResetLevel:
    push    ax
    push    cx
    push    si
    push    di
    push    ds
    push    es

    push    cs
    pop     ds
    push    cs
    pop     es

    ; Copy original_map -> working_map (720 bytes)
    mov     si, original_map
    mov     di, working_map
    mov     cx, MAP_SIZE_BYTES
    rep     movsb

    ; Copy initial_enemies -> active_enemies
    mov     si, initial_enemies
    mov     di, active_enemies
    mov     cx, (MAX_ENEMIES * ENEMY_REC_SIZE)
    rep     movsb

    ; Reset Mario state (8.8 fixed point: x=32 -> 2000h, y=144 -> 9000h)
    mov     word [hero_x_fp], 32
    mov byte[hero_x_sub],0
    mov     word [hero_y_fp], 8000h
    mov     word [hero_vx_fp], 0
    mov     word [hero_vy_fp], 0
    mov     byte [hero_hp], 1           ; Small Mario
    mov     byte [hero_on_ground], 1
    mov     byte [hero_dir], 1          ; Facing right
    mov     byte [hero_invuln], 0
    mov     byte [hero_stomp_chain], 0
    mov     word [hero_anim_ctr], 0

    ; Reset mushroom & camera
    mov     byte [mush_active], 0
    mov     word [cam_x], 0

    ; Reset clock & state
    mov     word [game_time], 300
    mov     byte [sec_subticks], 0
    mov     byte [game_state], STATE_PLAYING

    pop     es
    pop     ds
    pop     di
    pop     si
    pop     cx
    pop     ax
    ret

; ============================================================================
; MAIN PLAYABLE GAME LOOP (Integrates Modules 9-15 with Member A's Renderer)
; ============================================================================

; ----------------------------------------------------------------------------
; Procedure: PlayFullGameStage
; Purpose  : Executes the complete frame-by-frame gameplay loop (Section 5.13)
;            from NewGame until the player returns to the Title screen.
; Inputs   : None
; Outputs  : Returns to caller when Esc/GameOver/LevelComplete exits to title
; Registers: None changed
; ----------------------------------------------------------------------------
PlayFullGameStage:
    push    ax
    push    bx
    push    cx
    push    dx

    sti                                 ; Ensure hardware interrupts are enabled
    call    NewGame

    mov     ah, 00h
    int     1Ah
    mov     [prev_frame_tick], dx

.frame_loop:
    ; Step 1: Wait for next BIOS 18.2 Hz timer tick (guaranteed not to hang)
    mov     ah, 00h
    int     1Ah
    cmp     dx, [prev_frame_tick]
    je      .frame_loop
    mov     [prev_frame_tick], dx


    ; Dispatch based on current game_state
   ; Dispatch based on current game_state via indexed jump table (Section 5.12)
    xor     bx, bx
    mov     bl, [game_state]
    cmp     bl, STATE_EXIT_MENU
    jae     .exit_to_title
    shl     bx, 1                       ; Word offset = state * 2
    jmp     word [state_jump_table + bx]

; --- STATE: PLAYING (Section 5.13 Order of Work) ---
.do_playing:
    ; Check Escape -> Title or P -> Pause
    cmp     byte [key_state + KEY_ESC], 1
    je      .exit_to_title

    cmp     byte [key_state + KEY_P], 1
    jne     .no_pause_key


    mov     byte [key_state + KEY_P], 0 ; Consume press
    mov     byte [game_state], STATE_PAUSED
    jmp     .frame_loop

.no_pause_key:
    ; Step 3: Update Mario physics & tile collisions
    call    UpdatePlayerPhysics

    ; Step 4: Update enemies, shells, and active mushroom
    call    UpdateEnemies
    call    UpdateMushroom

    ; Step 5: Resolve entity collisions (enemies, shells, mushroom)
    call    CheckEntityCollisions

    ; Step 6: Decrement invulnerability blink timer
    cmp     byte [hero_invuln], 0
    je      .chk_death_rules
    dec     byte [hero_invuln]

    ; Step 7: Check pit fall (y >= 192) or time == 0
.chk_death_rules:
    mov     ax, [hero_y_fp]
    shr     ax, 8                       ; Whole pixel Y
    cmp     ax, 192
    jae     .trigger_pit_death

    cmp     word [game_time], 0
    je      .trigger_normal_death

    ; Step 8: Update scrolling camera (Section 5.3)
    call    UpdateCamera

    ; Step 9 & 10: Render complete frame + HUD and flip buffer
    call    RenderGameplayFrame
    call    PresentFrameBuffer
    jmp     .frame_loop

.trigger_pit_death:
    mov     byte [death_is_pit], 1
    call    BeginDeathSequence
    jmp     .frame_loop

.trigger_normal_death:
    mov     byte [death_is_pit], 0
    call    BeginDeathSequence
    jmp     .frame_loop

; --- STATE: PAUSED ---
.do_paused:
    cmp     byte [key_state + KEY_ESC], 1
    je      .exit_to_title
    cmp     byte [key_state + KEY_P], 1
    jne     .draw_pause
    mov     byte [key_state + KEY_P], 0
    mov     byte [game_state], STATE_PLAYING
    jmp     .frame_loop
.draw_pause:

    call    RenderGameplayFrame
call    DimFrameBuffer
    ; Black PAUSED banner box
    push    word 84
    push    word 74
    push    word 152
    push    word 46
    push    word C_BLACK
    call    FillRect

    ; White border around PAUSED box (Top, Bottom, Left, Right)
    push    word 84
    push    word 74
    push    word 152
    push    word 2
    push    word C_WHITE
    call    FillRect

    push    word 84
    push    word 118
    push    word 152
    push    word 2
    push    word C_WHITE
    call    FillRect

    push    word 84
    push    word 74
    push    word 2
    push    word 46
    push    word C_WHITE
    call    FillRect

    push    word 234
    push    word 74
    push    word 2
    push    word 46
    push    word C_WHITE
    call    FillRect

    ; "P A U S E D" in Yellow (11 chars * 8px = 88px -> centered at x=116)
    push    word 116
    push    word 84
    push    word C_YELLOW
    push    word str_paused
    call    DrawString

    ; "Press P to resume" in White (17 chars * 8px = 136px -> centered at x=92)
    push    word 92
    push    word 102
    push    word C_WHITE
    push    word str_resume
    call    DrawString

    call    PresentFrameBuffer
    jmp     .frame_loop
; --- STATE: DYING (1.5s hop & fall off-screen) ---
.do_dying:
    inc     byte [state_timer]
    mov     ax, [hero_y_fp]
    add     ax, [hero_vy_fp]
    mov     [hero_y_fp], ax
    add     word [hero_vy_fp], GRAVITY_ACCEL

    call    RenderGameplayFrame
    call    PresentFrameBuffer

    cmp     byte [state_timer], 28      ; ~1.5 seconds at 18.2 Hz
    jb      .frame_loop

    dec     byte [lives_count]
    cmp     byte [lives_count], 0
    je      .to_gameover
    mov     byte [state_timer], 0
    mov     byte [game_state], STATE_LIFELOST
    jmp     .frame_loop

.to_gameover:
    mov     byte [game_state], STATE_GAMEOVER
    jmp     .frame_loop

; --- STATE: LIFE LOST (2s black screen showing remaining lives) ---
.do_lifelost:
    inc     byte [state_timer]
    push    word 0
    push    word 0
    push    word SCREEN_W
    push    word SCREEN_H
    push    word C_BLACK
    call    FillRect

    push    word 124
    push    word 70
    push    word C_WHITE
    push    word str_world_1_1
    call    DrawString

    push    word 132
    push    word 96
    push    word 0
    call    DrawMarioSprite

    push    word 156
    push    word 100
    push    word C_WHITE
    push    word str_x_prefix
    call    DrawString

    xor     ax, ax
    mov     al, [lives_count]
    push    ax
    push    word 1
    push    word 168
    push    word 100
    call    DrawDecimalNumber

    call    PresentFrameBuffer

    cmp     byte [state_timer], 36      ; ~2 seconds
    jb      .frame_loop
    call    ResetLevel
    jmp     .frame_loop

; --- STATE: WIN SEQUENCE (Slide down flagpole) ---

      ; --- STATE: WIN SEQUENCE (Slide down flagpole) ---
.do_winseq:
    inc     byte [state_timer]
    mov     ax, [hero_y_fp]
    shr     ax, 8
    cmp     ax, 144
    jae     .win_slide_done
    add     word [hero_y_fp], 0200h     ; Slide down 2 px/frame
.win_slide_done:
    call    RenderGameplayFrame
    call    PresentFrameBuffer

    cmp     byte [state_timer], 36
    jb      .frame_loop

    mov     byte [game_state], STATE_COMPLETE
    jmp     .frame_loop

; --- STATE: LEVEL COMPLETE (Figure 10 Breakdown) ---
.do_complete:
    call    RenderLevelCompleteScreen
    call    PresentFrameBuffer

    cmp     byte [key_state + KEY_ENTER], 1
    je      .exit_to_title
    jmp     .frame_loop 
; --- STATE: GAME OVER ---
; --- STATE: GAME OVER (Figure 11 Layout) ---
.do_gameover:
 ; --- STATE: GAME OVER (Figure 11 Layout) ---

    ; Black Background
    push    word 0
    push    word 0
    push    word SCREEN_W
    push    word SCREEN_H
    push    word C_BLACK
    call    FillRect

    ; Red Outer Border (Top, Bottom, Left, Right)
    push    word 28
    push    word 24
    push    word 264
    push    word 3
    push    word C_RED_LIGHT
    call    FillRect

    push    word 28
    push    word 173
    push    word 264
    push    word 3
    push    word C_RED_LIGHT
    call    FillRect

    push    word 28
    push    word 24
    push    word 3
    push    word 152
    push    word C_RED_LIGHT
    call    FillRect

    push    word 289
    push    word 24
    push    word 3
    push    word 152
    push    word C_RED_LIGHT
    call    FillRect

    ; Header: G A M E  O V E R
    push    word 96
    push    word 54
    push    word C_RED_LIGHT
    push    word str_game_over
    call    DrawString

    ; FINAL SCORE: XXXXXX
    push    word 84
    push    word 90
    push    word C_WHITE
    push    word str_final_score
    call    DrawString

    push    word 188
    push    word 90
    call    DrawScore6Digits

    ; Coins: XX (Yellow)
    push    word 80
    push    word 112
    push    word C_YELLOW
    push    word str_go_coins
    call    DrawString

    push    word [coins_count]
    push    word 2
    push    word 136
    push    word 112
    call    DrawDecimalNumber

    ; Time: XXX (Yellow)
    push    word 168
    push    word 112
    push    word C_YELLOW
    push    word str_go_time
    call    DrawString

    push    word [game_time]
    push    word 3
    push    word 216
    push    word 112
    call    DrawDecimalNumber

    ; Footer Prompt: Press ENTER for the title
    push    word 60
    push    word 148
    push    word C_GREEN_LIGHT
    push    word str_press_enter
    call    DrawString

    call    PresentFrameBuffer

    cmp     byte [key_state + KEY_ENTER], 1
    je      .exit_to_title
    jmp     .frame_loop
.exit_to_title:
    mov     byte [key_state + KEY_ESC], 0
    mov     byte [key_state + KEY_ENTER], 0
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret
state_jump_table:
    dw PlayFullGameStage.do_playing     ; 0 = STATE_PLAYING
    dw PlayFullGameStage.do_paused      ; 1 = STATE_PAUSED
    dw PlayFullGameStage.do_dying       ; 2 = STATE_DYING
    dw PlayFullGameStage.do_lifelost    ; 3 = STATE_LIFELOST
    dw PlayFullGameStage.do_winseq      ; 4 = STATE_WINSEQ
    dw PlayFullGameStage.do_complete    ; 5 = STATE_COMPLETE
    dw PlayFullGameStage.do_gameover    ; 6 = STATE_GAMEOVER
    dw PlayFullGameStage.exit_to_title  ; 7 = STATE_EXIT_MENU
; ----------------------------------------------------------------------------
; Procedure: BeginDeathSequence
; Purpose  : Freezes gameplay and initializes Mario's death hop animation.
; Inputs   : [death_is_pit] (1 = skip upward hop, 0 = hop upward)
; Outputs  : Sets game_state = STATE_DYING, state_timer = 0
; Registers: None changed
; ----------------------------------------------------------------------------
BeginDeathSequence:
    mov     byte [game_state], STATE_DYING
    mov     byte [state_timer], 0
    mov     word [hero_vx_fp], 0
    cmp     byte [death_is_pit], 1
    je      .pit_fall
    mov     word [hero_vy_fp], 0FC00h   ; Upward death hop (-4.0 px/frame)
    ret
.pit_fall:
    mov     word [hero_vy_fp], 0080h
    ret

; ----------------------------------------------------------------------------
; Procedure: DimFrameBuffer
; Purpose  : Dims the back buffer with a 50% black checkerboard pattern so the
;            paused gameplay stays visible underneath a darkened tint.
; ----------------------------------------------------------------------------
DimFrameBuffer:
    push    ax
    push    bx
    push    cx
    push    dx

    xor     dx, dx                      ; y = 0 .. 199
.row_loop:
    mov     cx, dx
    and     cx, 1                       ; x starts at 0 on even rows, 1 on odd rows
.col_loop:
    push    cx                          ; x
    push    dx                          ; y
    push    word C_BLACK                ; color = black
    call    PutPixel

    add     cx, 2
    cmp     cx, 320
    jb      .col_loop

    inc     dx
    cmp     dx, 200
    jb      .row_loop

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret
; ============================================================================
; MODULE 9 & MODULE 10: PLAYER PHYSICS & AXIS-SEPARATED TILE COLLISION
; ============================================================================

; ----------------------------------------------------------------------------
; Procedure: UpdatePlayerPhysics
; Purpose  : Applies horizontal acceleration/friction, run speed limits,
;            variable jump height, gravity, and axis-separated tile collision.
; Inputs   : key_state array, hero_* variables
; Outputs  : Updated hero_x_fp, hero_y_fp, hero_vx_fp, hero_vy_fp
; Registers: None changed
; ----------------------------------------------------------------------------
UpdatePlayerPhysics:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Determine max horizontal speed (Walk vs Run with Left Shift)
    mov     cx, MAX_WALK_SPD
    cmp     byte [key_state + KEY_LSHIFT], 1
    jne     .chk_horiz_input
    mov     cx, MAX_RUN_SPD

.chk_horiz_input:
    mov     ax, [hero_vx_fp]
    mov     bl, [key_state + KEY_LEFT]
    or      bl, [key_state + KEY_A]
    mov     bh, [key_state + KEY_RIGHT]
    or      bh, [key_state + KEY_D]

    cmp     bh, 1
    je      .accel_right
    cmp     bl, 1
    je      .accel_left

    ; No direction key held: apply friction toward 0
    cmp     ax, 0
    jg      .fric_pos
    jl      .fric_neg
    jmp     .apply_x_move

.fric_pos:
    sub     ax, FRICTION_DECEL
    jge     .save_vx
    xor     ax, ax
    jmp     .save_vx

.fric_neg:
    add     ax, FRICTION_DECEL
    jle     .save_vx
    xor     ax, ax
    jmp     .save_vx

.accel_right:
    mov     byte [hero_dir], 1
    add     ax, ACCEL_WALK
    cmp     ax, cx
    jle     .save_vx
    mov     ax, cx
    jmp     .save_vx

.accel_left:
    mov     byte [hero_dir], -1
    sub     ax, ACCEL_WALK
    neg     cx
    cmp     ax, cx
    jge     .save_vx
    mov     ax, cx

.save_vx:
    mov     [hero_vx_fp], ax
    test    ax, ax
    jz      .apply_x_move
    inc     word [hero_anim_ctr]

.apply_x_move:
    ; Move X (signed 8.8 vx_fp -> 16-bit whole pixel hero_x_fp + hero_x_sub)
    mov     ax, [hero_vx_fp]
    add     [hero_x_sub], al
    mov     al, ah
    cbw
    adc     [hero_x_fp], ax
    call    ResolveHorizontalCollision

    ; --- Vertical Jump & Gravity ---
    mov     al, [key_state + KEY_SPACE]
    or      al, [key_state + KEY_W]
    or      al, [key_state + KEY_UP]
    cmp     al, 1
    jne     .chk_var_jump

    ; Start jump only if standing on solid ground
    cmp     byte [hero_on_ground], 1
    jne     .apply_gravity
    mov     word [hero_vy_fp], JUMP_START_VEL
    mov     byte [hero_on_ground], 0
    jmp     .apply_gravity

.chk_var_jump:
    ; Variable jump height: if rising faster than cut-off and Space released
    mov     ax, [hero_vy_fp]
    cmp     ax, JUMP_CUTOFF_VEL
    jge     .apply_gravity
    mov     word [hero_vy_fp], JUMP_CUTOFF_VEL

.apply_gravity:
    mov     ax, [hero_vy_fp]
    add     ax, GRAVITY_ACCEL
    cmp     ax, MAX_FALL_SPD
    jle     .save_vy
    mov     ax, MAX_FALL_SPD
.save_vy:
    mov     [hero_vy_fp], ax

    ; Move Y and resolve floor/ceiling/head-block collisions
    mov     ax, [hero_y_fp]
    add     ax, [hero_vy_fp]
    mov     [hero_y_fp], ax
    call    ResolveVerticalCollision

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

; ----------------------------------------------------------------------------
; Procedure: GetTileAtPixel
; Purpose  : Returns the working_map tile code at world pixel coordinate (px, py).
; Inputs   : Stack: [BP+6] = world_x (pixels), [BP+4] = world_y (pixels)
; Outputs  : AL = tile code (0 if out of vertical bounds)
; Registers: AX (return value); all other registers preserved
; ----------------------------------------------------------------------------
GetTileAtPixel:
    push    bp
    mov     bp, sp
    push    bx
    push    dx
    push    si

    mov     bx, [bp+6]                  ; world_x
    mov     dx, [bp+4]                  ; world_y

    cmp     dx, 0
    jl      .out_sky
    cmp     dx, 192
    jae     .out_sky

    shr     bx, 4                       ; col = world_x / 16
    cmp     bx, MAP_COLS
    jae     .out_solid

    shr     dx, 4                       ; row = world_y / 16
    ; index = row * 60 + col = (row * 64) - (row * 4) + col
    mov     si, dx
    shl     si, 6
    mov     ax, dx
    shl     ax, 2
    sub     si, ax
    add     si, bx

    xor     ax, ax
    mov     al, [working_map + si]
    jmp     .done

.out_sky:
    xor     ax, ax
    jmp     .done

.out_solid:
    mov     al, TILE_GROUND

.done:
    pop     si
    pop     dx
    pop     bx
    pop     bp
    ret     4

; ----------------------------------------------------------------------------
; Procedure: IsTileSolid
; Purpose  : Checks if tile code in AL is solid (codes 1..10).
; Inputs   : AL = tile code
; Outputs  : CF = 1 if solid, CF = 0 if passable (sky, coin, flag)
; Registers: Flags only
; ----------------------------------------------------------------------------
IsTileSolid:
    cmp     al, TILE_GROUND
    jb      .not_solid
    cmp     al, TILE_STAIR
    ja      .not_solid
    stc
    ret
.not_solid:
    clc
    ret

; ----------------------------------------------------------------------------
; Procedure: ResolveHorizontalCollision
; Purpose  : Clamps Mario to camera left edge and right world edge, collects
;            overlapping coins, checks flagpole touch, and stops at solid walls.
; Inputs   : hero_x_fp, hero_y_fp, hero_hp
; Outputs  : Adjusted hero_x_fp & hero_vx_fp
; Registers: None changed
; ----------------------------------------------------------------------------
ResolveHorizontalCollision:
    push    ax
    push    bx
    push    cx
    push    dx

    mov     bx, [hero_x_fp]
  
    ; Left camera wall check (Section 5.3)
    cmp     bx, [cam_x]
    jge     .chk_right_edge
    mov     bx, [cam_x]
   
    mov     [hero_x_fp], bx
    mov     word [hero_vx_fp], 0
    jmp     .done

.chk_right_edge:
    cmp     bx, 888                     ; Flagpole at col 56 (world_x = 896 - 8)
    jb      .sample_sides
    mov     bx, 888
    mov     [hero_x_fp], bx
    mov     byte [hero_x_sub], 0
    mov     word [hero_vx_fp], 0
    call    TriggerFlagpoleWin
.sample_sides:
    mov     bx, [hero_x_fp]
   
    add     bx, 2                       ; Hitbox left (inset 2px)
    mov     cx, bx
    add     cx, 11                      ; Hitbox right (12px wide)

    mov     dx, [hero_y_fp]
    shr     dx, 8                       ; Hitbox top
    add     dx, 4                       ; Sample mid-upper body

    ; Test right hitbox edge
    push    cx
    push    dx
    call    GetTileAtPixel
    cmp     al, TILE_FLAG
    je      .hit_flag
    cmp     al, TILE_COIN
    jne     .chk_r_solid
    push    cx
    push    dx
    call    CollectMapCoin
    jmp     .chk_left_side

.chk_r_solid:
    call    IsTileSolid
    jnc     .chk_left_side
    ; Snap left of solid column: col * 16 - 14
    and     cx, 0FFF0h
    sub     cx, 14
   
    mov     [hero_x_fp], cx
    mov     byte [hero_x_sub], 0
    mov     word [hero_vx_fp], 0
    jmp     .done

.chk_left_side:
    push    bx
    push    dx
    call    GetTileAtPixel
    cmp     al, TILE_COIN
    jne     .chk_l_solid
    push    bx
    push    dx
    call    CollectMapCoin
    jmp     .done

.chk_l_solid:
    call    IsTileSolid
    jnc     .done
    and     bx, 0FFF0h
    add     bx, 14
   
    mov     [hero_x_fp], bx
    mov     byte [hero_x_sub], 0
    mov     word [hero_vx_fp], 0
    jmp     .done

.hit_flag:
    call    TriggerFlagpoleWin

.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

; ----------------------------------------------------------------------------
; Procedure: ResolveVerticalCollision
; Purpose  : Checks floor landing (sets on_ground=1, resets stomp chain) and
;            ceiling head-bumps (triggers bricks and '?' blocks).
; Inputs   : hero_x_fp, hero_y_fp, hero_vy_fp, hero_hp
; Outputs  : Adjusted hero_y_fp, hero_vy_fp, hero_on_ground
; Registers: None changed
; ----------------------------------------------------------------------------
ResolveVerticalCollision:
    push    ax
    push    bx
    push    cx
    push    dx

    mov     byte [hero_on_ground], 0

    ; Center X of Mario in whole pixels (hero_x_fp + 8)
    mov     bx, [hero_x_fp]
    add     bx, 8

    ; Check if jumping upward (hero_vy_fp < 0) or falling (hero_vy_fp >= 0)
    cmp     word [hero_vy_fp], 0
    jl      .check_ceiling

    ; --- Falling / Landing Check (Feet Y) ---
    mov     dx, [hero_y_fp]
    shr     dx, 8
    add     dx, 16                      ; Small Mario height = 16px
    cmp     byte [hero_hp], 2
    jne     .feet_y_ok
    add     dx, 16                      ; Super Mario height = 32px
.feet_y_ok:
    cmp     dx, SCREEN_H
    jae     .done                       ; Pit death handled by pit check

    ; Sample left-foot (bx - 4) and right-foot (bx + 4)
    mov     ax, bx
    sub     ax, 4
    push    ax
    push    dx
    call    GetTileAtPixel
    cmp     al, TILE_COIN
    jne     .chk_lfoot_solid
    push    ax
    push    dx
    call    CollectMapCoin
    jmp     .chk_rfoot

.chk_lfoot_solid:
    call    IsTileSolid
    jc      .landed

.chk_rfoot:
    mov     ax, bx
    add     ax, 4
    push    ax
    push    dx
    call    GetTileAtPixel
    cmp     al, TILE_COIN
    jne     .chk_rfoot_solid
    push    ax
    push    dx
    call    CollectMapCoin
    jmp     .done

.chk_rfoot_solid:
    call    IsTileSolid
    jnc     .done

.landed:
    ; Snap feet cleanly to top of ground tile (dx & 0FFF0h)
    and     dx, 0FFF0h
    sub     dx, 16
    cmp     byte [hero_hp], 2
    jne     .snap_y
    sub     dx, 16
.snap_y:
    shl     dx, 8
    mov     [hero_y_fp], dx
    mov     word [hero_vy_fp], 0
    mov     byte [hero_on_ground], 1
    mov     byte [hero_stomp_chain], 0
    jmp     .done

    ; --- Jumping Upward / Head Bump Check ---
.check_ceiling:
    mov     dx, [hero_y_fp]
    shr     dx, 8                       ; Top of Mario's head
    cmp     dx, 16
    jbe     .hit_ceiling_only

    push    bx                          ; Center X of head (whole pixels)
    push    dx                          ; Top Y of head
    call    GetTileAtPixel
    cmp     al, TILE_COIN
    jne     .chk_head_solid
    push    bx
    push    dx
    call    CollectMapCoin
    jmp     .done

.chk_head_solid:
    call    IsTileSolid
    jnc     .done

    ; Trigger ? block / brick at (bx, dx)
    push    bx
    push    dx
    call    HitBlockFromBelow

.hit_ceiling_only:
    and     dx, 0FFF0h
    add     dx, 16                      ; Place head right below the hit block
    shl     dx, 8
    mov     [hero_y_fp], dx
    mov     word [hero_vy_fp], 0

.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret
; ============================================================================
; MODULE 12: BLOCKS, COINS & MUSHROOM POWER-UP LOGIC
; ============================================================================

; ----------------------------------------------------------------------------
; Procedure: CollectMapCoin
; Purpose  : Replaces a coin tile with sky, adds +200 points, and increments
;            coins_count (granting +1 life at 100 coins).
; Inputs   : Stack: [BP+6] = world_x, [BP+4] = world_y
; Outputs  : Working map updated, score & coins incremented
; Registers: None changed
; ----------------------------------------------------------------------------
; ----------------------------------------------------------------------------
; Procedure: HitBlockFromBelow
; Purpose  : Handles head-bumping a ? block or brick at pixel (X, Y) (Sec 5.9).
; Inputs   : Stack: [BP+6]=pixel_x, [BP+4]=pixel_y
; Outputs  : Updates working_map, score, coins, or spawns mushroom
; Registers: None changed
; ----------------------------------------------------------------------------
HitBlockFromBelow:

    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    dx
    push    si

    mov     bx, [bp+6]
    shr     bx, 4                       ; col = pixel_x / 16
    mov     dx, [bp+4]
    shr     dx, 4                       ; row = pixel_y / 16

    cmp     bx, MAP_COLS
    jae     .done
    cmp     dx, MAP_ROWS
    jae     .done

    ; SI = row * 60 + col
    mov     si, dx
    shl     si, 6
    mov     ax, dx
    shl     ax, 2
    sub     si, ax
    add     si, bx

    mov     al, [working_map + si]

    cmp     al, TILE_Q_COIN
    je      .q_coin
    cmp     al, TILE_Q_MUSH
    je      .q_mush
    cmp     al, TILE_BRICK
    je      .brick
    jmp     .done

.q_coin:
    mov     byte [working_map + si], TILE_EMPTY
    inc     word [coins_count]
    cmp     word [coins_count], 100
    jb      .add_coin_pts
    mov     word [coins_count], 0
    inc     byte [lives_count]
.add_coin_pts:
    push    word 0
    push    word 200
    call    AddScore32
    jmp     .done

.q_mush:
    mov     byte [working_map + si], TILE_EMPTY
    mov     byte [mush_active], 1
    mov     ax, bx
    shl     ax, 4                       ; col * 16 (whole pixels)
    mov     [mush_x_fp], ax
    mov     ax, dx
    dec     ax                          ; Spawn one tile above the block
    shl     ax, 12                      ; Y in 8.8 fixed point
    mov     [mush_y_fp], ax
    mov     word [mush_vx_fp], 1        ; +1 pixel per frame right (FIXED from MUSHROOM_SPD)
    mov     word [mush_vy_fp], 0
    jmp     .done

.brick:
    cmp     byte [hero_hp], 2
    jne     .done                       ; Small Mario cannot break bricks
    mov     byte [working_map + si], TILE_SKY
    push    word 0
    push    word 50
    call    AddScore32

.done:
    pop     si
    pop     dx
    pop     bx
    pop     ax
    pop     bp
    ret     4

CollectMapCoin:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    dx
    push    si

    mov     bx, [bp+6]
    mov     dx, [bp+4]
    shr     bx, 4
    shr     dx, 4

    mov     si, dx
    shl     si, 6
    mov     ax, dx
    shl     ax, 2
    sub     si, ax
    add     si, bx

    mov     byte [working_map + si], TILE_SKY

    ; +200 points
    push    word 0
    push    word 200
    call    AddScore32

    ; Increment coins (100 coins -> 1-UP)
    inc     word [coins_count]
    cmp     word [coins_count], 100
    jb      .done
    mov     word [coins_count], 0
    cmp     byte [lives_count], 99
    jae     .done
    inc     byte [lives_count]

.done:
    pop     si
    pop     dx
    pop     bx
    pop     ax
    pop     bp
    ret     4
; ----------------------------------------------------------------------------
; Procedure: TriggerBlockHit
; Purpose  : Handles head-bump interactions on Brick, '?' Coin, and '?' Mushroom
;            blocks in working_map (Section 5.9).
; Inputs   : Stack: [BP+6] = world_x, [BP+4] = world_y
; Outputs  : Modifies working_map, spawns coins/mushrooms, awards points
; Registers: None changed
; ----------------------------------------------------------------------------
TriggerBlockHit:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    dx
    push    si

    mov     bx, [bp+6]
    mov     dx, [bp+4]
    shr     bx, 4                       ; tile col
    shr     dx, 4                       ; tile row

    mov     si, dx
    shl     si, 6
    mov     ax, dx
    shl     ax, 2
    sub     si, ax
    add     si, bx

    mov     al, [working_map + si]

    cmp     al, TILE_BRICK
    je      .hit_brick
    cmp     al, TILE_Q_COIN
    je      .hit_q_coin
    cmp     al, TILE_Q_MUSH
    je      .hit_q_mush
    jmp     .done

.hit_brick:
    ; Only Super Mario (HP == 2) breaks bricks (+50 pts)
    cmp     byte [hero_hp], 2
    jne     .done
    mov     byte [working_map + si], TILE_SKY
    push    word 0
    push    word 50
    call    AddScore32
    jmp     .done

.hit_q_coin:
    mov     byte [working_map + si], TILE_EMPTY
    push    word 0
    push    word 200
    call    AddScore32
    inc     word [coins_count]
    cmp     word [coins_count], 100
    jb      .done
    mov     word [coins_count], 0
    inc     byte [lives_count]
    jmp     .done

.hit_q_mush:
    mov     byte [working_map + si], TILE_EMPTY
    ; Spawn mushroom directly above this block
    mov     byte [mush_active], 1
    shl     bx, 12                      ; col * 16 * 256 (8.8 fixed point)
    mov     [mush_x_fp], bx
    dec     dx                          ; Row above block
    shl     dx, 12
    mov     [mush_y_fp], dx
    mov     word [mush_vx_fp], MUSHROOM_SPD
    mov     word [mush_vy_fp], 0

.done:
    pop     si
    pop     dx
    pop     bx
    pop     ax
    pop     bp
    ret     4

; ----------------------------------------------------------------------------
; Procedure: UpdateMushroom
; Purpose  : Moves active mushroom horizontally (1 px/frame), turns at walls,
;            applies gravity, and deactivates if it falls into a pit.
; Inputs   : mush_* variables
; Outputs  : Updated mush_x_fp, mush_y_fp, mush_active
; Registers: None changed
; ----------------------------------------------------------------------------
UpdateMushroom:
    push    ax
    push    bx
    push    cx
    push    dx

    cmp     byte [mush_active], 1
    jne     .done

    ; --- 1. Horizontal move & leading-edge wall bounce ---
    mov     ax, [mush_x_fp]
    add     ax, [mush_vx_fp]
    mov     [mush_x_fp], ax

    mov     bx, ax
               ; Mushroom left X (whole pixels)

    ; Disappear if it leaves the screen on the left (mush_x + 16 <= cam_x)
    mov     cx, [cam_x]
    sub     cx, 16
    cmp     bx, cx
    jge     .chk_mush_wall
    mov     byte [mush_active], 0
    jmp     .done

.chk_mush_wall:
    cmp     word [mush_vx_fp], 0
    jl      .mush_check_left
    add     bx, 15                      ; Check right edge when moving right
.mush_check_left:
    mov     dx, [mush_y_fp]
    shr     dx, 8
    add     dx, 8

    push    bx
    push    dx
    call    GetTileAtPixel
    call    IsTileSolid
    jnc     .mush_grav
    neg     word [mush_vx_fp]           ; Turn around cleanly at walls

    ; --- 2. Gravity & floor landing ---
.mush_grav:
    mov     ax, [mush_y_fp]
    add     ax, [mush_vy_fp]
    mov     [mush_y_fp], ax
    add     word [mush_vy_fp], GRAVITY_ACCEL

    mov     bx, [mush_x_fp]
    
    add     bx, 8
    mov     dx, [mush_y_fp]
    shr     dx, 8
    add     dx, 16

    cmp     dx, 192
    jb      .chk_mush_floor
    mov     byte [mush_active], 0       ; Falls into pit and disappears
    jmp     .done

.chk_mush_floor:
    push    bx
    push    dx
    call    GetTileAtPixel
    call    IsTileSolid
    jnc     .chk_mario_overlap
    and     dx, 0FFF0h
    sub     dx, 16
    shl     dx, 8
    mov     [mush_y_fp], dx
    mov     word [mush_vy_fp], 0

    ; --- 3. Mario Overlap Check (+1000 pts, Small -> Super Mario HP=2) ---
.chk_mario_overlap:
    mov     ax, [mush_x_fp]
                         ; AX = mush_x
    mov     bx, [hero_x_fp]             ; BX = hero_x

    ; Horizontal overlap: mush_x < hero_x + 14 && mush_x + 14 > hero_x
    mov     cx, bx
    add     cx, 14
    cmp     ax, cx
    jge     .done
    add     ax, 14
    cmp     ax, bx
    jle     .done

    ; Vertical overlap: mush_y < hero_y + hero_h && mush_y + 14 > hero_y
    mov     ax, [mush_y_fp]
                   ; AX = mush_y
    mov     dx, [hero_y_fp]
    shr     dx, 8                       ; DX = hero_y

    mov     cx, dx
    add     cx, 16
    cmp     byte [hero_hp], 2
    jne     .mush_h_ok
    add     cx, 16
.mush_h_ok:
    cmp     ax, cx
    jge     .done
    add     ax, 14
    cmp     ax, dx
    jle     .done

    ; Collected! Remove mushroom, add +1000 points, grow to Super Mario
    mov     byte [mush_active], 0
    push    word 0
    push    word 1000
    call    AddScore32

    cmp     byte [hero_hp], 2
    je      .done
    mov     byte [hero_hp], 2
    sub     word [hero_y_fp], (16 << 8) ; Lift Y by 16px so 32px Mario stands on ground

.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret
; ============================================================================
; MODULE 11: ENEMIES & KOOPA SHELL AI
; ============================================================================
; Enemy Record Layout (12 bytes each):
;   +0 (db): type (0=none, 1=Goomba, 2=Koopa)
;   +1 (db): state (0=sleep, 1=walk, 2=flat, 3=shell_idle, 4=shell_slide)
;   +2 (dw): x_fp (8.8 fixed point)
;   +4 (dw): y_fp (8.8 fixed point)
;   +6 (dw): vx_fp (signed 8.8)
;   +8 (dw): vy_fp (signed 8.8)
;  +10 (db): timer (flat Goomba countdown or 8-frame shell kick grace)
;  +11 (db): reserved padding

; ----------------------------------------------------------------------------
; Procedure: UpdateEnemies
; Purpose  : Iterates over active_enemies table, wakes enemies within 1 tile
;            of screen, updates flat timers, moves enemies/shells, and handles
;            shell-vs-enemy kills (+500 points).
; Inputs   : active_enemies table, cam_x
; Outputs  : Updated enemy positions and states
; Registers: None changed
; ----------------------------------------------------------------------------
UpdateEnemies:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    mov     si, active_enemies
    mov     cx, MAX_ENEMIES

.enemy_loop:
    mov     al, [si]                    ; type
    cmp     al, ETYPE_NONE
    je      .next_enemy

    mov     ah, [si+1]                  ; state
    mov     bx, [si+2]
    shr     bx, 8                       ; world_x

    ; Check activation if sleeping (within camera_x + 336)
    cmp     ah, ESTATE_SLEEP
    jne     .chk_despawn
    mov     dx, [cam_x]
    add     dx, 336
    cmp     bx, dx
    jg      .next_enemy
    mov     byte [si+1], ESTATE_WALK    ; Wake up!
    jmp     .next_enemy

.chk_despawn:
    ; Remove if fallen below pit or far left of camera
    mov     dx, [si+4]
    shr     dx, 8
    cmp     dx, 192
    jae     .kill_enemy

    mov     dx, [cam_x]
    sub     dx, 32
    cmp     bx, dx
    jl      .kill_enemy

    ; Decrement grace / flat timer if > 0
    cmp     byte [si+10], 0
    je      .chk_flat
    dec     byte [si+10]

.chk_flat:
    cmp     ah, ESTATE_FLAT
    jne     .chk_move
    cmp     byte [si+10], 0
    jne     .next_enemy                 ; Still showing flattened Goomba
.kill_enemy:
    mov     byte [si], ETYPE_NONE
    jmp     .next_enemy

.chk_move:
    cmp     ah, ESTATE_SHELL_ST
    je      .next_enemy                 ; Stationary shell does not move

    ; Move horizontally
    mov     ax, [si+2]
    add     ax, [si+6]
    mov     [si+2], ax

    ; Check wall collision at front edge
    mov     bx, ax
    shr     bx, 8
    add     bx, 8
    mov     dx, [si+4]
    shr     dx, 8
    add     dx, 8
    push    bx
    push    dx
    call    GetTileAtPixel
    call    IsTileSolid
    jnc     .enemy_grav
    neg     word [si+6]                 ; Bounce/turn at wall

.enemy_grav:
    mov     ax, [si+4]
    add     ax, [si+8]
    mov     [si+4], ax
    add     word [si+8], GRAVITY_ACCEL

    mov     bx, [si+2]
    shr     bx, 8
    add     bx, 8
    mov     dx, [si+4]
    shr     dx, 8
    add     dx, 16
    push    bx
    push    dx
    call    GetTileAtPixel
    call    IsTileSolid
    jnc     .chk_shell_kills
    and     dx, 0FFF0h
    sub     dx, 16
    shl     dx, 8
    mov     [si+4], dx
    mov     word [si+8], 0

.chk_shell_kills:
    ; If sliding shell, check overlap with other enemies (+500 each)
    cmp     byte [si+1], ESTATE_SHELL_MV
    jne     .next_enemy
    call    CheckSlidingShellHits

.next_enemy:
    add     si, ENEMY_REC_SIZE
    dec     cx
    jnz     .enemy_loop

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

; ----------------------------------------------------------------------------
; Procedure: CheckSlidingShellHits
; Purpose  : Checks if sliding shell at [SI] hits any other walking enemy,
;            defeating it for +500 points (Section 5.5).
; Inputs   : SI = pointer to sliding shell record
; Outputs  : Defeated enemies set to ETYPE_NONE, +500 score awarded
; Registers: None changed
; ----------------------------------------------------------------------------
CheckSlidingShellHits:
    push    ax
    push    bx
    push    cx
    push    di

    mov     di, active_enemies
    mov     cx, MAX_ENEMIES

.scan:
    cmp     di, si
    je      .next
    cmp     byte [di], ETYPE_NONE
    je      .next
    cmp     byte [di+1], ESTATE_FLAT
    je      .next

    ; Compare X distance < 14 and Y distance < 14
    mov     ax, [si+2]
    sub     ax, [di+2]
    jns     .abs_x
    neg     ax
.abs_x:
    cmp     ax, 0E00h                   ; 14 pixels in 8.8
    jae     .next

    mov     ax, [si+4]
    sub     ax, [di+4]
    jns     .abs_y
    neg     ax
.abs_y:
    cmp     ax, 0E00h
    jae     .next

    ; Hit! Remove enemy and add +500 points
    mov     byte [di], ETYPE_NONE
    push    word 0
    push    word 500
    call    AddScore32

.next:
    add     di, ENEMY_REC_SIZE
    loop    .scan

    pop     di
    pop     cx
    pop     bx
    pop     ax
    ret

; ----------------------------------------------------------------------------
; Procedure: CheckEntityCollisions
; Purpose  : Checks Mario against active mushroom and active enemies (stomp,
;            shell kick, or taking damage per Section 5.6 & 5.7).
; Inputs   : hero_* variables, mush_* variables, active_enemies
; Outputs  : Updates HP, score, enemy states, or triggers player death
; Registers: None changed
; ----------------------------------------------------------------------------
CheckEntityCollisions:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; 1. Check Mushroom Overlap
 
    cmp     byte [mush_active], 1
    jne     .check_enemies

    mov     dx, [mush_x_fp]
    shr     dx, 8                       ; Convert mushroom X from 8.8 to whole pixels
    mov     ax, [hero_x_fp]             ; Mario X is already in whole pixels
    sub     ax, dx
    jns     .m_dx
    neg     ax
.m_dx:
    cmp     ax, 14                      ; 14-pixel horizontal overlap threshold
    jae     .check_enemies

    mov     ax, [hero_y_fp]
    sub     ax, [mush_y_fp]
    jns     .m_dy
    neg     ax
.m_dy:
    cmp     ax, 1400h
    jae     .check_enemies

    ; Collect Mushroom (+1000 pts, grow Small -> Super with feet fixed)
    mov     byte [mush_active], 0
    push    word 0
    push    word 1000
    call    AddScore32

    cmp     byte [hero_hp], 1
    jne     .check_enemies
    mov     byte [hero_hp], 2
    sub     word [hero_y_fp], 1000h     ; Keep feet fixed (top -= 16px)

    ; 2. Check Enemy Overlaps
.check_enemies:
  
    mov     si, active_enemies
    mov     cx, MAX_ENEMIES
.e_loop:
    cmp     byte [si], ETYPE_NONE
    je      .e_next
    cmp     byte [si+1], ESTATE_SLEEP
    je      .e_next
    cmp     byte [si+1], ESTATE_FLAT
    je      .e_next

    ; Enemy X check (convert enemy [si+2] from 8.8 fixed point to whole pixels)
    mov     dx, [si+2]
    shr     dx, 8
    mov     ax, [hero_x_fp]
    sub     ax, dx
    jns     .e_dx
    neg     ax
.e_dx:
    cmp     ax, 12
    jae     .e_next

    ; Vertical overlap check (account for Super Mario 32px height)
    mov     bx, [hero_y_fp]
    mov     dx, 1000h                   ; 16px height
    cmp     byte [hero_hp], 2
    jne     .calc_feet
    mov     dx, 2000h                   ; 32px height
.calc_feet:
    add     bx, dx                      ; bx = Mario feet Y (8.8)

    mov     ax, [si+4]                  ; Enemy top Y
    cmp     bx, ax
    jle     .e_next                     ; Mario completely above enemy
    add     ax, 1000h                   ; Enemy bottom Y
    cmp     [hero_y_fp], ax
    jge     .e_next                     ; Mario completely below enemy

    ; Stationary shell check: touching kicks it (+400 pts)
    cmp     byte [si+1], ESTATE_SHELL_ST
    jne     .chk_stomp
    mov     byte [si+1], ESTATE_SHELL_MV
    mov     byte [si+10], 8             ; 8-frame grace period
    mov     word [si+6], SHELL_SPD
    mov     ax, [hero_x_fp]
    cmp     ax, [si+2]
    jl      .kick_done
    neg     word [si+6]                 ; Kick left if Mario is on right
.kick_done:
    push    word 0
    push    word 400
    call    AddScore32
    jmp     .e_next

.chk_stomp:
    ; Stomp if Mario is falling (vy > 0) and feet are in upper half of enemy
    cmp     word [hero_vy_fp], 0
    jle     .hurt_mario
    mov     ax, [si+4]
    add     ax, 0A00h                   ; Enemy top + 10px
    cmp     bx, ax
    jg      .hurt_mario

    ; Valid Stomp! Bounce Mario & award stomp chain points
    mov     word [hero_vy_fp], STOMP_BOUNCE
    call    AwardStompChainPoints

    cmp     byte [si], ETYPE_GOOMBA
    je      .stomp_goomba
    ; Koopa becomes stationary shell
    mov     byte [si+1], ESTATE_SHELL_ST
    mov     word [si+6], 0
    jmp     .e_next

.stomp_goomba:
    mov     byte [si+1], ESTATE_FLAT
    mov     byte [si+10], 18            ; ~1 second flattened display
    jmp     .e_next

.hurt_mario:
    ; Ignore if invulnerable or shell grace timer active
    cmp     byte [hero_invuln], 0
    jne     .e_next
    cmp     byte [si+10], 0
    jne     .e_next

    cmp     byte [hero_hp], 2
    je      .shrink_mario

    ; Small Mario hit -> Die!
    mov     byte [death_is_pit], 0
    call    BeginDeathSequence
    jmp     .done

.shrink_mario:
    mov     byte [hero_hp], 1
    add     word [hero_y_fp], 1000h     ; Keep feet fixed (top += 16px)
    mov     byte [hero_invuln], 36      ; ~2 seconds invulnerability blink

.e_next:
    add     si, ENEMY_REC_SIZE
    dec     cx
    jnz     .e_loop

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

; ----------------------------------------------------------------------------
; Procedure: TriggerFlagpoleWin
; Purpose  : Awards flagpole height points (5000..100 based on row) and enters
;            STATE_WINSEQ (Section 5.11).
; Inputs   : hero_y_fp
; Outputs  : Score updated, game_state = STATE_WINSEQ
; Registers: None changed
; ----------------------------------------------------------------------------
TriggerFlagpoleWin:
    push    ax
    push    bx
    push    dx
mov     word [hero_x_fp], 896       ; Snap Mario onto flagpole center (col 56)
    mov     byte [hero_x_sub], 0
    mov     ax, [hero_y_fp]
    shr     ax, 12                      ; Map row (0..11)
    mov     bx, 5000
    cmp     ax, 3
    jle     .add_flag_pts
    mov     bx, 2000
    cmp     ax, 4
    je      .add_flag_pts
    mov     bx, 800
    cmp     ax, 5
    je      .add_flag_pts
    mov     bx, 400
    cmp     ax, 7
    jle     .add_flag_pts
    mov     bx, 100

.add_flag_pts:
    push    word 0
    push    bx
    call    AddScore32

    ; --- Save SCORE before time bonus (Figure 10) ---
    mov     ax, [score_low]
    mov     [lvl_base_score_low], ax
    mov     ax, [score_high]
    mov     [lvl_base_score_high], ax

    ; --- Compute TIME BONUS = game_time * 50 ---
    mov     ax, [game_time]
    mov     [lvl_time_left], ax
    mov     bx, 50
    mul     bx                          ; DX:AX = game_time * 50
    mov     [lvl_time_bonus], ax

    ; --- Add Time Bonus to FINAL SCORE ---
    push    dx
    push    ax
    call    AddScore32

    mov     byte [game_state], STATE_WINSEQ
    mov     byte [state_timer], 0

    pop     dx
    pop     bx
    pop     ax
    ret

; ============================================================================
; CAMERA UPDATE (Section 5.3)
; ============================================================================

; ----------------------------------------------------------------------------
; Procedure: UpdateCamera
; Purpose  : Advances cam_x smoothly when Mario passes screen x = 160, never
;            scrolls left, and clamps at (MAP_COLS * 16 - 320 = 640).
; Inputs   : hero_x_fp, cam_x
; Outputs  : Updated cam_x
; Registers: None changed
; ----------------------------------------------------------------------------
UpdateCamera:
    push    ax
    push    bx

    mov     ax, [hero_x_fp]
                     ; Whole pixel world_x
    mov     bx, ax
    sub     bx, [cam_x]                 ; screen_x = world_x - cam_x

    cmp     bx, 160
    jle     .done

    sub     ax, 160                     ; new_cam = world_x - 160
    cmp     ax, (MAP_COLS * 16) - SCREEN_W
    jle     .chk_monotone
    mov     ax, (MAP_COLS * 16) - SCREEN_W

.chk_monotone:
    cmp     ax, [cam_x]
    jle     .done
    mov     [cam_x], ax

.done:
    pop     bx
    pop     ax
    ret

; ============================================================================
; MODULE 13: 32-BIT SCORE, DECIMAL CONVERSION & HUD RENDERER
; ============================================================================

; ----------------------------------------------------------------------------
; Procedure: AddScore32
; Purpose  : Adds a 32-bit unsigned point value to score_high:score_low using
;            ADD/ADC and clamps maximum score to 999,999 (000F423Fh).
; Inputs   : Stack: [BP+6] = high word, [BP+4] = low word
; Outputs  : Updated score_high:score_low
; Registers: None changed
; ----------------------------------------------------------------------------
AddScore32:
    push    bp
    mov     bp, sp
    push    ax
    push    dx

    mov     ax, [bp+4]
    mov     dx, [bp+6]
    add     [score_low], ax
    adc     [score_high], dx

    ; Clamp to 999,999 (000F423Fh)
    cmp     word [score_high], 000Fh
    jb      .done
    ja      .clamp
    cmp     word [score_low], 423Fh
    jbe     .done

.clamp:
    mov     word [score_high], 000Fh
    mov     word [score_low], 423Fh

.done:
    pop     dx
    pop     ax
    pop     bp
    ret     4

; ----------------------------------------------------------------------------
; Procedure: AwardStompChainPoints
; Purpose  : Looks up consecutive stomp points from stomp_table (100..8000, or
;            1-UP at 11+) and increments hero_stomp_chain (Section 5.4).
; Inputs   : hero_stomp_chain
; Outputs  : Score or lives incremented
; Registers: None changed
; ----------------------------------------------------------------------------
AwardStompChainPoints:
    push    ax
    push    bx

    xor     bx, bx
    mov     bl, [hero_stomp_chain]
    cmp     bl, 10
    jae     .give_1up

    shl     bx, 1
    mov     ax, [stomp_table + bx]
    push    word 0
    push    ax
    call    AddScore32
    inc     byte [hero_stomp_chain]
    jmp     .done

.give_1up:
    cmp     byte [lives_count], 99
    jae     .done
    inc     byte [lives_count]

.done:
    pop     bx
    pop     ax
    ret

; ----------------------------------------------------------------------------
; Procedure: DrawDecimalNumber
; Purpose  : Converts a 16-bit unsigned integer into zero-padded ASCII digits
;            by repeated division by 10 and draws them on screen.
; Inputs   : Stack: [BP+10]=value, [BP+8]=num_digits, [BP+6]=x, [BP+4]=y
; Outputs  : Draws digits into off-screen frame buffer
; Registers: None changed
; ----------------------------------------------------------------------------
DrawDecimalNumber:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    cx
    push    dx

    mov     ax, [bp+10]                 ; value
    mov     cx, [bp+8]                  ; digit count
    mov     bx, 10

.div_loop:
    xor     dx, dx
    div     bx                          ; AX = AX / 10, DX = remainder
    add     dl, '0'
    push    dx                          ; Push ASCII digit onto stack
    loop    .div_loop

    mov     cx, [bp+8]
    mov     bx, [bp+6]                  ; screen X

.draw_loop:
    pop     ax                          ; Pop digit in reverse order
    push    bx
    push    word [bp+4]                 ; screen Y
    push    word C_WHITE
    push    ax
    call    DrawChar8x8
    add     bx, 8
    loop    .draw_loop

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    pop     bp
    ret     8

; ----------------------------------------------------------------------------
; Procedure: DrawScore6Digits
; Purpose  : Divides 32-bit score_high:score_low repeatedly by 10 to draw a
;            6-digit zero-padded score on the HUD and end screens.
; Inputs   : Stack: [BP+6]=x, [BP+4]=y
; Outputs  : Draws 6 digits at (x, y)
; Registers: None changed
; ----------------------------------------------------------------------------
DrawScore6Digits:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    mov     ax, [score_low]
    mov     dx, [score_high]
    mov     cx, 6
    mov     bx, 10

.extract:
    ; 32-bit division by 10: (DX:AX) / 10
    mov     si, ax                      ; Save low word
    mov     ax, dx
    xor     dx, dx
    div     bx                          ; AX = high / 10, DX = high % 10
    push    ax                          ; Save new high word
    mov     ax, si
    div     bx                          ; AX = new low word, DX = remainder!
    add     dl, '0'
    pop     si                          ; SI = new high word
    push    dx                          ; Push ASCII digit
    mov     dx, si
    loop    .extract

    mov     cx, 6
    mov     bx, [bp+6]

.render:
    pop     ax
    push    bx
    push    word [bp+4]
    push    word C_WHITE
    push    ax
    call    DrawChar8x8
    add     bx, 8
    loop    .render

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    pop     bp
    ret     4

; ----------------------------------------------------------------------------
; Procedure: RenderGameplayFrame
; Purpose  : Draws sky, scrolling working_map tiles, active mushroom, active
;            enemies, Mario (with invulnerability blink & Super height), and
;            the full top-bar HUD (Section 5.14).
; Inputs   : All game state variables
; Outputs  : Complete frame written into [fb_seg]
; Registers: None changed
; ----------------------------------------------------------------------------
; ============================================================================
; Procedure: DrawGoalCastleAndBadges
; Purpose  : Draws the flagpole score zone badges (5000..100) and end castle
;            relative to [cam_x] when near the end of World 1-1 (col 54 = 864px).
; ============================================================================
; ============================================================================
; Procedure: DrawBackgroundScenery
; Purpose  : Renders scrolling white clouds and green bushes behind map tiles.
; ============================================================================
DrawBackgroundScenery:
    push    ax
    push    bx
    push    cx
    push    dx

    xor     bx, bx                      ; World X anchor (0, 256, 512, 768)
.scenery_loop:
    cmp     bx, (MAP_COLS * TILE_SZ)
    jae     .done

    ; --- 1. White Cloud (at bx + 32, y = 32..52) ---
    mov     ax, bx
    add     ax, 32
    sub     ax, [cam_x]
    cmp     ax, -48
    jl      .draw_bush
    cmp     ax, SCREEN_W
    jge     .draw_bush

    push    ax
    push    word 40
    push    word 16
    push    word 12
    push    word C_WHITE
    call    FillRect

    mov     cx, ax
    add     cx, 10
    push    cx
    push    word 32
    push    word 20
    push    word 20
    push    word C_WHITE
    call    FillRect

    mov     cx, ax
    add     cx, 26
    push    cx
    push    word 40
    push    word 16
    push    word 12
    push    word C_WHITE
    call    FillRect

    ; --- 2. Green Bush (at bx + 128, sitting on ground y = 160) ---
.draw_bush:
    mov     ax, bx
    add     ax, 128
    sub     ax, [cam_x]
    cmp     ax, -48
    jl      .next_anchor
    cmp     ax, SCREEN_W
    jge     .next_anchor

    push    ax
    push    word 148
    push    word 14
    push    word 12
    push    word C_GREEN_LIGHT
    call    FillRect

    mov     cx, ax
    add     cx, 10
    push    cx
    push    word 142
    push    word 18
    push    word 18
    push    word C_GREEN_LIGHT
    call    FillRect

    mov     cx, ax
    add     cx, 24
    push    cx
    push    word 148
    push    word 14
    push    word 12
    push    word C_GREEN_LIGHT
    call    FillRect

    push    ax
    push    word 158
    push    word 38
    push    word 2
    push    word C_GREEN_DARK
    call    FillRect

.next_anchor:
    add     bx, 256
    jmp     .scenery_loop

.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

DrawGoalCastleAndBadges:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Flagpole is at col 54 -> world_x = 864 (pole center at 871)
    mov     bx, 896
    sub     bx, [cam_x]                 ; BX = flagpole tile screen_x

    ; Skip entirely if flagpole + castle are off-screen
    cmp     bx, -80
    jl      .done
    cmp     bx, SCREEN_W + 48
    jg      .done

    ; --- 1. Draw 6 White Horizontal Zone Divider Lines (left of pole) ---
    mov     ax, bx
    sub     ax, 38                      ; Line start X (pole_x - 38)
    mov     dx, 24                      ; Starting Y = 24
    mov     cx, 6
.line_loop:
    push    ax
    push    dx
    push    word 45                     ; Width = 45px (reaches pole at bx+7)
    push    word 1
    push    word C_WHITE
    call    FillRect
    add     dx, 24
    loop    .line_loop

    ; --- 2. Draw Colored Score Badges & Numbers ---
    mov     ax, bx
    sub     ax, 36                      ; Badge X = pole_x - 36

    ; Badge 5000 (Red, y = 30)
    push    ax
    push    word 30
    push    word 36
    push    word 12
    push    word C_RED_LIGHT
    call    FillRect
    mov     cx, ax
    add     cx, 2
    push    cx
    push    word 32
    push    word C_WHITE
    push    word str_badge_5000
    call    DrawString

    ; Badge 2000 (Brown/Orange, y = 54)
    push    ax
    push    word 54
    push    word 36
    push    word 12
    push    word C_BROWN
    call    FillRect
    mov     cx, ax
    add     cx, 2
    push    cx
    push    word 56
    push    word C_WHITE
    push    word str_badge_2000
    call    DrawString

    ; Badge 800 (Yellow/Gold, y = 78)
    push    ax
    push    word 78
    push    word 36
    push    word 12
    push    word C_BROWN
    call    FillRect
    mov     cx, ax
    add     cx, 6
    push    cx
    push    word 80
    push    word C_WHITE
    push    word str_badge_800
    call    DrawString

    ; Badge 400 (Green, y = 102)
    push    ax
    push    word 102
    push    word 36
    push    word 12
    push    word C_GREEN_DARK
    call    FillRect
    mov     cx, ax
    add     cx, 6
    push    cx
    push    word 104
    push    word C_WHITE
    push    word str_badge_400
    call    DrawString

    ; Badge 100 (Blue, y = 126)
    push    ax
    push    word 126
    push    word 36
    push    word 12
    push    word C_BLUE_DARK
    call    FillRect
    mov     cx, ax
    add     cx, 6
    push    cx
    push    word 128
    push    word C_WHITE
    push    word str_badge_100
    call    DrawString

    ; --- 3. Draw End-of-Level Cast (at bx + 20, y = 104..160) ---
    mov     ax, bx
    add     ax, 16              ; Castle left X

    ; Main brown castle wall (44x56 px)
    push    ax
    push    word 104
    push    word 44
    push    word 56
    push    word C_BROWN
    call    FillRect

    ; Black outline border around castle wall
    push    ax
    push    word 104
    push    word 1
    push    word 56
    push    word C_BLACK
    call    FillRect

    mov     cx, ax
    add     cx, 43
    push    cx
    push    word 104
    push    word 1
    push    word 56
    push    word C_BLACK
    call    FillRect

    ; 4 Battlements / Crenellations along top (y = 94..104)
    mov     cx, ax
    push    cx
    push    word 94
    push    word 8
    push    word 10
    push    word C_BROWN
    call    FillRect

    add     cx, 12
    push    cx
    push    word 94
    push    word 8
    push    word 10
    push    word C_BROWN
    call    FillRect

    add     cx, 12
    push    cx
    push    word 94
    push    word 8
    push    word 10
    push    word C_BROWN
    call    FillRect

    add     cx, 12
    push    cx
    push    word 94
    push    word 8
    push    word 10
    push    word C_BROWN
    call    FillRect

    ; Black Arched Doorway (centered at ax + 15, y = 126..160)
    mov     cx, ax
    add     cx, 17
    push    cx
    push    word 126
    push    word 10
    push    word 4
    push    word C_BLACK
    call    FillRect

    mov     cx, ax
    add     cx, 15
    push    cx
    push    word 130
    push    word 14
    push    word 30
    push    word C_BLACK
    call    FillRect

.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret
    ; ============================================================================
; Procedure: DrawBlockEffectsAndMushroom
; Purpose  : Draws Figure 8a (coin + 200), 8b (16x16 mushroom sprite), and
;            8c (4 brick shatter debris + 50).
; ============================================================================
DrawBlockEffectsAndMushroom:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; --- 1. Draw Active Mushroom Sprite (Figure 8b) ---
    cmp     byte [mush_active], 1
    jne     .check_popup

    mov     ax, [mush_x_fp]
    shr     ax, 8
    sub     ax, [cam_x]
    cmp     ax, -16
    jl      .check_popup
    cmp     ax, SCREEN_W
    jge     .check_popup

    mov     dx, [mush_y_fp]
    shr     dx, 8

    ; Red mushroom cap (top 10px)
    mov     cx, ax
    add     cx, 3
    push    cx
    push    dx
    push    word 10
    push    word 3
    push    word C_RED_LIGHT
    call    FillRect

    mov     cx, ax
    add     cx, 1
    mov     bx, dx
    add     bx, 3
    push    cx
    push    bx
    push    word 14
    push    word 7
    push    word C_RED_LIGHT
    call    FillRect

    ; White spots on red cap
    mov     cx, ax
    add     cx, 3
    mov     bx, dx
    add     bx, 4
    push    cx
    push    bx
    push    word 3
    push    word 3
    push    word C_WHITE
    call    FillRect

    mov     cx, ax
    add     cx, 10
    push    cx
    push    bx
    push    word 3
    push    word 3
    push    word C_WHITE
    call    FillRect

    ; White / light stem (bottom 6px)
    mov     cx, ax
    add     cx, 4
    mov     bx, dx
    add     bx, 10
    push    cx
    push    bx
    push    word 8
    push    word 6
    push    word C_WHITE
    call    FillRect

    ; --- 2. Draw Coin Pop-up (8a) or Brick Debris (8c) ---
.check_popup:
    cmp     byte [popup_timer], 0
    je      .done
    dec     byte [popup_timer]

    mov     ax, [popup_x]
    sub     ax, [cam_x]
    mov     dx, [popup_y]

    ; Offset based on elapsed frames (18 - popup_timer)
    xor     bx, bx
    mov     bl, 18
    sub     bl, [popup_timer]           ; BX = 0..17

    cmp     byte [popup_type], 1
    jne     .draw_brick_debris

    ; Figure 8a: Yellow oval coin + "200" rising above block
    sub     dx, bx
    mov     cx, ax
    add     cx, 5
    push    cx
    push    dx
    push    word 6
    push    word 12
    push    word C_YELLOW
    call    FillRect

    mov     cx, ax
    add     cx, 2
    mov     bx, dx
    sub     bx, 9
    push    cx
    push    bx
    push    word C_WHITE
    push    word str_pop_200
    call    DrawString
    jmp     .done

.draw_brick_debris:
    ; Figure 8c: 4 brown brick pieces spreading outward + "50"
    mov     cx, ax
    sub     cx, bx
    mov     si, dx
    sub     si, bx
    push    cx
    push    si
    push    word 4
    push    word 4
    push    word C_BROWN
    call    FillRect

    mov     cx, ax
    add     cx, 12
    add     cx, bx
    push    cx
    push    si
    push    word 4
    push    word 4
    push    word C_BROWN
    call    FillRect

    mov     cx, ax
    sub     cx, bx
    mov     si, dx
    add     si, 8
    push    cx
    push    si
    push    word 4
    push    word 4
    push    word C_BROWN
    call    FillRect

    mov     cx, ax
    add     cx, 12
    add     cx, bx
    push    cx
    push    si
    push    word 4
    push    word 4
    push    word C_BROWN
    call    FillRect

    mov     cx, ax
    add     cx, 16
    mov     si, dx
    sub     si, bx
    push    cx
    push    si
    push    word C_WHITE
    push    word str_pop_50
    call    DrawString

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret
   
RenderGameplayFrame:
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    ; 1. Clear background to sky blue
    push    word 0
    push    word 0
    push    word SCREEN_W
    push    word SCREEN_H
    push    word C_SKY
    call    FillRect
call    DrawBackgroundScenery
call    DrawGoalCastleAndBadges



    ; 3. Draw Active Mushroom Sprite & Block Hit Effects (MUST be AFTER RenderVisibleMap!)
 
    ; 2. Draw visible tile grid (rows 1..11, cols around cam_x)
    mov     bx, [cam_x]
    shr     bx, 4                       ; First visible column
    mov     cx, 21                      ; 20 visible + 1 partial column

.map_col_loop:
    cmp     bx, MAP_COLS
    jae     .draw_entities

    mov     dx, 1                       ; Row 0 is reserved for HUD
.map_row_loop:
    cmp     dx, MAP_ROWS
    jae     .next_map_col

    ; Lookup working_map[dx * 60 + bx]
    mov     si, dx
    shl     si, 6
    mov     ax, dx
    shl     ax, 2
    sub     si, ax
    add     si, bx
    mov     al, [working_map + si]
    cmp     al, TILE_SKY
    je      .next_map_row

    ; Preserve row DX, put tile code in DL, screen_x in AX, screen_y in SI
    push    dx
    mov     si, dx
    shl     si, 4                       ; screen_y = row * 16
    mov     dl, al                      ; DL = tile code for DrawSingleTileByCode
    mov     ax, bx
    shl     ax, 4
    sub     ax, [cam_x]                 ; screen_x = col * 16 - cam_x
    call    DrawSingleTileByCode
    pop     dx

.next_map_row:
    inc     dx
    jmp     .map_row_loop

.next_map_col:
    inc     bx
    dec     cx
    jnz     .map_col_loop

    ; 3. Draw Active Mushroom
.draw_entities:
   call    DrawBlockEffectsAndMushroom

    ; 4. Draw Active Enemies
.draw_enemies:
    mov     si, active_enemies
    mov     cx, MAX_ENEMIES
.en_draw_loop:
    cmp     byte [si], ETYPE_NONE
    je      .en_next
    mov     ax, [si+2]
    shr     ax, 8
    sub     ax, [cam_x]
    cmp     ax, -16
    jl      .en_next
    cmp     ax, SCREEN_W
    jge     .en_next

    mov     dx, [si+4]
    shr     dx, 8

    cmp     byte [si], ETYPE_GOOMBA
    jne     .draw_koopa
    xor     bx, bx
    cmp     byte [si+1], ESTATE_FLAT
    jne     .goomba_go
    mov     bx, 1
.goomba_go:
    push    ax
    push    dx
    push    bx
    call    DrawGoombaSprite
    jmp     .en_next

.draw_koopa:
    ; Draw Koopa or Shell in green
    push    ax
    push    dx
    push    word 16
    push    word 16
    push    word C_GREEN_LIGHT
    call    FillRect

.en_next:
    add     si, ENEMY_REC_SIZE
    loop    .en_draw_loop

    ; 5. Draw Mario (skip alternate frames during invulnerability blink)
    test    byte [hero_invuln], 01h
    jnz     .draw_hud

    mov     ax, [hero_x_fp]
    sub     ax, [cam_x]
    mov     dx, [hero_y_fp]
    shr     dx, 8

    mov     bx, [hero_anim_ctr]
    shr     bx, 2
    and     bx, 01h
    cmp     byte [hero_dir], 0
    jge     .m_face_ok
    or      bx, 02h
.m_face_ok:
    cmp     byte [hero_hp], 2
    jne     .draw_small_m
    ; Super Mario (draw upper torso + lower sprite)
    push    ax
    push    dx
    push    bx
    call    DrawMarioSprite
    add     dx, 16
.draw_small_m:
    push    ax
    push    dx
    push    bx
    call    DrawMarioSprite

    ; 6. Top-Bar HUD (Row 0: 320x16 black bar)
.draw_hud:
    push    word 0
    push    word 0
    push    word SCREEN_W
    push    word 16
    push    word C_BLACK
    call    FillRect

    ; SCORE (6 digits)
    push    word 4
    push    word 1
    push    word C_YELLOW
    push    word str_hud_score
    call    DrawString
    push    word 4
    push    word 9
    call    DrawScore6Digits

    ; COINS (x00)
    push    word 68
    push    word 1
    push    word C_YELLOW
    push    word str_hud_coins
    call    DrawString
    push    word 68
    push    word 9
    push    word C_YELLOW
    push    word 'x'
    call    DrawChar8x8
    push    word [coins_count]
    push    word 2
    push    word 76
    push    word 9
    call    DrawDecimalNumber

    ; WORLD 1-1
    push    word 124
    push    word 1
    push    word C_YELLOW
    push    word str_hud_world
    call    DrawString
    push    word 128
    push    word 9
    push    word C_YELLOW
    push    word str_1_1
    call    DrawString

    ; TIME (3 digits)
    push    word 176
    push    word 1
    push    word C_YELLOW
    push    word str_hud_time
    call    DrawString
    push    word [game_time]
    push    word 3
    push    word 180
    push    word 9
    call    DrawDecimalNumber

    ; LIVES (x3)
    push    word 224
    push    word 1
    push    word C_YELLOW
    push    word str_hud_lives
    call    DrawString
    push    word 228
    push    word 9
    push    word C_YELLOW
    push    word 'x'
    call    DrawChar8x8
    xor     ax, ax
    mov     al, [lives_count]
    push    ax
    push    word 1
    push    word 236
    push    word 9
    call    DrawDecimalNumber

    ; HEALTH Hearts (1 or 2 filled)
    push    word 268
    push    word 1
    push    word C_YELLOW
    push    word str_hud_hp
    call    DrawString

    push    word 276
    push    word 9
    push    word 8
    push    word 6
    push    word C_RED_LIGHT
    call    FillRect

    mov     bx, C_BROWN                 ; Empty heart color
    cmp     byte [hero_hp], 2
    jne     .heart2
    mov     bx, C_RED_LIGHT             ; Filled second heart
.heart2:
    push    word 288
    push    word 9
    push    word 8
    push    word 6
    push    bx
    call    FillRect

    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret
; ----------------------------------------------------------------------------
; Procedure: DrawSingleTileByCode
; Purpose  : Helper that dispatches tile drawing at screen (AX, SI) based on
;            tile code in DL.
; Inputs   : AX = screen_x, SI = screen_y, DL = tile code
; Outputs  : Tile rendered into frame buffer
; Registers: None changed
; ----------------------------------------------------------------------------
DrawSingleTileByCode:
    push    ax
    push    bx
    push    dx

    cmp     dl, TILE_GROUND
    je      .tile_ground
    cmp     dl, TILE_BRICK
    je      .tile_brick
    cmp     dl, TILE_Q_COIN
    je      .tile_q
    cmp     dl, TILE_Q_MUSH
    je      .tile_q
    cmp     dl, TILE_EMPTY
    je      .tile_empty
    cmp     dl, TILE_COIN
    je      .tile_coin
    cmp     dl, TILE_FLAG
    je      .tile_flag
    ; Pipes & Stairs
    mov     bx, C_GREEN_LIGHT
    cmp     dl, TILE_STAIR
    jne     .draw_box
    mov     bx, C_BROWN
.draw_box:
    push    ax
    push    si
    push    word 16
    push    word 16
    push    bx
    call    FillRect
    jmp     .done

.tile_ground:
    push    ax
    push    si
    push    word 16
    push    word 16
    push    word C_BROWN
    call    FillRect
    push    ax
    push    si
    push    word 16
    push    word 4
    push    word C_GREEN_LIGHT
    call    FillRect
    jmp     .done

.tile_brick:
    push    ax
    push    si
    call    DrawBrickTile
    jmp     .done

.tile_q:
    push    ax
    push    si
    push    word 16
    push    word 16
    push    word C_YELLOW
    call    FillRect
    add     ax, 4
    add     si, 4
    push    ax
    push    si
    push    word C_RED_DARK
    push    word '?'
    call    DrawChar8x8
    jmp     .done

.tile_empty:
    push    ax
    push    si
    push    word 16
    push    word 16
    push    word C_BROWN
    call    FillRect
    jmp     .done

.tile_coin:
    add     ax, 5
    add     si, 3
    push    ax
    push    si
    push    word 6
    push    word 10
    push    word C_YELLOW
    call    FillRect
    jmp     .done

.tile_flag:
    add     ax, 7
    push    ax
    push    si
    push    word 2
    push    word 16
    push    word C_GREEN_LIGHT
    call    FillRect

.done:
    pop     dx
    pop     bx
    pop     ax
    ret

; ============================================================================
; MEMBER B DATA SECTION (Interrupts, Physics, Entities, Map & HUD Strings)
; ============================================================================
old_int09_off   dw 0
old_int09_seg   dw 0
old_int1c_off   dw 0
old_int1c_seg   dw 0

key_state       times 128 db 0
e0_prefix       db 0

sys_ticks       dw 0
prev_frame_tick dw 0
sec_subticks    db 0
game_time       dw 300

game_state      db STATE_PLAYING
state_timer     db 0

death_is_pit    db 0

; Hero 8.8 Fixed-Point & Status Variables
hero_x_fp       dw 32
hero_x_sub      db 0
hero_y_fp       dw 9000h
hero_vx_fp      dw 0
hero_vy_fp      dw 0
hero_hp         db 1
hero_on_ground  db 1
hero_dir        db 1
hero_invuln     db 0
hero_stomp_chain db 0
hero_anim_ctr   dw 0

; Mushroom Power-Up Entity
mush_active     db 0
popup_timer     db 0
popup_type      db 0
popup_x         dw 0
popup_y         dw 0
str_pop_200     db "200", 0
str_pop_50      db "50", 0
mush_x_fp       dw 0
mush_y_fp       dw 0
mush_vx_fp      dw 0
mush_vy_fp      dw 0

; 32-Bit Score & Session Counters
score_low       dw 0
score_high      dw 0
coins_count     dw 0
lives_count     db 3

stomp_table     dw 100, 200, 400, 500, 800, 1000, 2000, 4000, 5000, 8000

; Level Complete Screen Data (Figure 10)
lvl_base_score_low   dw 0
lvl_base_score_high   dw 0
lvl_time_left       dw 0
lvl_time_bonus      dw 0

; HUD & State Screen Strings
str_hud_score   db "SCORE", 0
str_hud_coins   db "COINS", 0
str_hud_world   db "WORLD", 0
str_1_1         db "1-1", 0
str_hud_time    db "TIME", 0
str_hud_lives   db "LIVES", 0
str_hud_hp      db "HEALTH", 0
str_badge_5000  db "5000", 0
str_badge_2000  db "2000", 0
str_badge_800   db "800", 0
str_badge_400   db "400", 0
str_badge_100   db "100", 0
str_paused      db "P A U S E D", 0
str_resume      db "Press P to resume", 0
str_world_1_1   db "WORLD 1-1", 0
str_x_prefix    db "x", 0
str_lvl_complete db "LEVEL COMPLETE!", 0
str_lc_score    db "SCORE", 0
str_lc_coins    db "COINS", 0
str_lc_time_left db "TIME LEFT", 0
str_lc_time_bonus db "TIME BONUS", 0
str_lc_final_score db "FINAL SCORE", 0
str_lc_x_50     db "x 50 =", 0
str_game_over   db "G A M E  O V E R", 0
str_final_score db "FINAL SCORE:", 0
str_go_coins     db "Coins:"  ,0
str_go_time     db  "Time:",0
str_press_enter db "Press ENTER for the title", 0
str_go_title        db "G A M E   O V E R", 0
str_go_final        db "Final Score:", 0
str_go_enter        db "Press ENTER for the title", 0
; Initial Enemy Table (4 Goombas, 2 Koopas - Section 5.15)
initial_enemies:
    ; Goomba 1 at x=160 (A000h)
    db ETYPE_GOOMBA, ESTATE_SLEEP
    dw 0A000h, 9000h, -GOOMBA_SPD, 0
    db 0, 0
    ; Goomba 2 at x=240 (F000h)
    db ETYPE_GOOMBA, ESTATE_SLEEP
    dw 0F000h, 9000h, -GOOMBA_SPD, 0
    db 0, 0
    ; Unused slots 3..8
    times (6 * ENEMY_REC_SIZE) db 0

active_enemies  times (MAX_ENEMIES * ENEMY_REC_SIZE) db 0

; ============================================================================
; LEVEL MAP DATA (60 Columns x 12 Rows = 720 Bytes - Meets Section 5.15)
; ============================================================================
original_map:
    ; Row 0 (HUD strip)
    times 60 db 0
    ; Row 1
    times 60 db 0
    ; Row 2 (Top of flagpole at col 56)
    times 56 db 0
    db 12, 0, 0, 0
    ; Row 3 (High ? coin block at col 15, flagpole at col 56)
    times 15 db 0
    db 3
    times 40 db 0
    db 12, 0, 0, 0
    ; Row 4 (Coins above first pit at cols 20-23, flagpole at col 56)
    times 20 db 0
    db 11, 11, 11, 11
    times 32 db 0
    db 12, 0, 0, 0
    ; Row 5 (Flagpole at col 56)
    times 56 db 0
    db 12, 0, 0, 0
    ; Row 6 (Mushroom ? at 8, Brick+? at 13-17, End Coins 40-42, Brick-?-Brick 45-47, Stair top 52, Flag 56)
    times 8 db 0
    db 4, 0, 0, 0, 0, 2, 3, 2, 3, 2
    times 22 db 0
    db 11, 11, 11, 0, 0, 2, 3, 2, 0, 0, 0, 0, 10, 0, 0, 0, 12, 0, 0, 0
    ; Row 7 (2nd Brick+Mushroom? at 30-32, pipe at 35-36, Stairs 51-52, Flag 56)
    times 30 db 0
    db 2, 4, 2, 0, 0, 6, 7
    times 14 db 0
    db 10, 10, 0, 0, 0, 12, 0, 0, 0
    ; Row 8 (2-tile pipe at 27-28, pipe body at 35-36, Stairs 50-52, Flag 56)
    times 27 db 0
    db 6, 7
    times 6 db 0
    db 8, 9
    times 13 db 0
    db 10, 10, 10, 0, 0, 0, 12, 0, 0, 0
    ; Row 9 (Pipes, coins at 30-32, Stairs 49-52, Flag base at 56)
    times 27 db 0
    db 8, 9, 0, 11, 11, 11, 0, 0, 8, 9
    times 12 db 0
    db 10, 10, 10, 10, 0, 0, 0, 10, 0, 0, 0
    ; Row 10 (Ground with 2-tile pit at cols 21-22 and 2-tile pit at cols 40-41)
    times 21 db 1
    db 0, 0
    times 17 db 1
    db 0, 0
    times 18 db 1
    ; Row 11 (Sub-ground with matching pits)
    times 21 db 1
    db 0, 0
    times 17 db 1
    db 0, 0
    times 18 db 1

working_map     times MAP_SIZE_BYTES db 0

; ============================================================================
; WIN SEQUENCE & LEVEL COMPLETE SCREEN ROUTINES
; ============================================================================
UpdateWinSequence:
    inc     byte [state_timer]
    cmp     byte [state_timer], 60          ; ~3 seconds wait
    jb      .done
    mov     byte [game_state], STATE_COMPLETE
    mov     byte [state_timer], 0
.done:
    ret

UpdateLevelComplete:
    cmp     byte [key_state + 1Ch], 1       ; 1Ch = ENTER key (uses key_state)
    jne     .wait
    call    NewGame                         ; Reset all & return to STATE_PLAYING
.wait:
    ret

RenderLevelCompleteScreen:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Background
    push    word 0
    push    word 0
    push    word SCREEN_W
    push    word SCREEN_H
    push    word C_BLACK
    call    FillRect

    ; Yellow Border
    push    word 16
    push    word 14
    push    word 288
    push    word 3
    push    word C_YELLOW
    call    FillRect

    push    word 16
    push    word 183
    push    word 288
    push    word 3
    push    word C_YELLOW
    call    FillRect

    push    word 16
    push    word 14
    push    word 3
    push    word 172
    push    word C_YELLOW
    call    FillRect

    push    word 301
    push    word 14
    push    word 3
    push    word 172
    push    word C_YELLOW
    call    FillRect

    ; Header
    push    word 100
    push    word 34
    push    word C_YELLOW
    push    word str_lvl_complete
    call    DrawString

    ; Labels
    push    word 56
    push    word 64
    push    word C_WHITE
    push    word str_lc_score
    call    DrawString

    push    word 56
    push    word 82
    push    word C_WHITE
    push    word str_lc_coins
    call    DrawString

    push    word 56
    push    word 100
    push    word C_WHITE
    push    word str_lc_time_left
    call    DrawString

    push    word 56
    push    word 118
    push    word C_WHITE
    push    word str_lc_time_bonus
    call    DrawString

    push    word 56
    push    word 136
    push    word C_WHITE
    push    word str_lc_final_score
    call    DrawString

    ; Values: SCORE (Base score before bonus)
    mov     ax, [score_low]
    push    ax
    mov     ax, [score_high]
    push    ax
    mov     ax, [lvl_base_score_low]
    mov     [score_low], ax
    mov     ax, [lvl_base_score_high]
    mov     [score_high], ax

    push    word 160
    push    word 64
    call    DrawScore6Digits

    pop     ax
    mov     [score_high], ax
    pop     ax
    mov     [score_low], ax

    ; Values: COINS
    push    word 160
    push    word 82
    push    word C_WHITE
    push    word 'x'
    call    DrawChar8x8

    push    word [coins_count]
    push    word 2
    push    word 176
    push    word 82
    call    DrawDecimalNumber

    ; Values: TIME LEFT
    push    word [lvl_time_left]
    push    word 3
    push    word 160
    push    word 100
    call    DrawDecimalNumber

    push    word 192
    push    word 100
    push    word C_WHITE
    push    word str_lc_x_50
    call    DrawString

    push    word [lvl_time_bonus]
    push    word 4
    push    word 248
    push    word 100
    call    DrawDecimalNumber

    ; Values: TIME BONUS
    push    word 160
    push    word 118
    push    word C_WHITE
    push    word '+'
    call    DrawChar8x8

    push    word [lvl_time_bonus]
    push    word 4
    push    word 176
    push    word 118
    call    DrawDecimalNumber

    ; Values: FINAL SCORE
    push    word 160
    push    word 136
    call    DrawScore6Digits

    ; Footer Prompt
    push    word 68
    push    word 164
    push    word C_GREEN_LIGHT
    push    word str_press_enter
    call    DrawString

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret