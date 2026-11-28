; ============================================================================
; Super Mario Engine - Animated Title Screen & Playable Demo (Mode 13h)
; Assemble: nasm title.asm -f bin -o MARIO.COM
; ============================================================================

ORG 100h
BITS 16

SCREEN_W        EQU 320
SCREEN_H        EQU 200
FB_WORDS        EQU 32000
MAP_COLS        EQU 60
MAP_ROWS        EQU 12
TILE_SZ         EQU 16
GROUND_Y        EQU 154                 ; Mario/Goomba feet sit at y=170 (154+16)

C_BLACK         EQU 0
C_BLUE_DARK     EQU 1
C_GREEN_DARK    EQU 2
C_RED_DARK      EQU 4
C_BROWN         EQU 6
C_SKY           EQU 9
C_GREEN_LIGHT   EQU 10
C_RED_LIGHT     EQU 12
C_YELLOW        EQU 14
C_WHITE         EQU 15

; ============================================================================
; Entry Point
; ============================================================================
start:
    cld
    call    InitFrameBuffer
    jc      near .fatal

    mov     ax, 0013h
    int     10h

.main_menu:
    call    RunTitleScreen
    cmp     ax, 1
    je      near .exit_dos

    call    InitSystemInterrupts
    call    PlayFullGameStage
    call    RestoreSystemInterrupts
    jmp     .main_menu
.exit_dos:
    call    CleanExitToDOS

.fatal:
    mov     ax, 4C01h
    int     21h

; ============================================================================
; RunTitleScreen: Returns AX = 0 (START GAME), AX = 1 (EXIT)
; ============================================================================
RunTitleScreen:
    push    bx
    push    cx
    push    dx

    mov     byte [menu_sel], 0
    mov     word [mario_x], 28
    mov     word [mario_dir], 1
    mov     word [mario_anim], 0
    mov     word [goomba_x], 260
    mov     word [goomba_dir], -1
    mov     word [goomba_anim], 0
    mov     word [arrow_bob], 0

    ; Initialize tick tracker
    mov     ah, 00h
    int     1Ah
    mov     [last_tick], dx

    ; Draw initial frame immediately
    call    DrawTitleFrame
    call    PresentFrameBuffer

.loop:
    mov     ah, 00h
    int     1Ah
    cmp     dx, [last_tick]
    je      .check_key
    mov     [last_tick], dx
    call    StepTitleMotion
    call    DrawTitleFrame
    call    PresentFrameBuffer

.check_key:
    mov     ah, 01h
    int     16h
    jz      .loop

    mov     ah, 00h
    int     16h

    cmp     al, 13                          ; Enter
    je      .confirm
    cmp     al, ' '                         ; Space also confirms
    je      .confirm
    cmp     al, 27                          ; Esc selects EXIT immediately
    je      .esc_exit

    cmp     ah, 48h                         ; Up arrow
    je      .move_up
    cmp     al, 'w'
    je      .move_up
    cmp     al, 'W'
    je      .move_up

    cmp     ah, 50h                         ; Down arrow
    je      .move_down
    cmp     al, 's'
    je      .move_down
    cmp     al, 'S'
    je      .move_down

    jmp     .loop

.move_up:
    mov     byte [menu_sel], 0
    call    DrawTitleFrame
    call    PresentFrameBuffer
    jmp     .loop

.move_down:
    mov     byte [menu_sel], 1
    call    DrawTitleFrame
    call    PresentFrameBuffer
    jmp     .loop

.esc_exit:
    mov     ax, 1
    pop     dx
    pop     cx
    pop     bx
    ret

.confirm:
    xor     ah, ah
    mov     al, [menu_sel]
    pop     dx
    pop     cx
    pop     bx
    ret

; ============================================================================
; StepTitleMotion
; ============================================================================
StepTitleMotion:
    push    ax
    push    bx

    inc     word [frame_ctr]
    mov     ax, [frame_ctr]
    and     ax, 03h
    jnz     .move_sprites
    xor     word [mario_anim], 1
    xor     word [goomba_anim], 1
    inc     word [arrow_bob]

.move_sprites:
    mov     ax, [mario_dir]
    imul    ax, 6
    add     ax, [mario_x]
    cmp     ax, 24
    jg      .chk_m_right
    mov     ax, 24
    mov     word [mario_dir], 1
    jmp     .save_m
.chk_m_right:
    cmp     ax, 276
    jl      .save_m
    mov     ax, 276
    mov     word [mario_dir], -1
.save_m:
    mov     [mario_x], ax

    mov     bx, [goomba_dir]
    imul    bx, 4
    add     bx, [goomba_x]
    cmp     bx, 36
    jg      .chk_g_right
    mov     bx, 36
    mov     word [goomba_dir], 1
    jmp     .save_g
.chk_g_right:
    cmp     bx, 280
    jl      .save_g
    mov     bx, 280
    mov     word [goomba_dir], -1
.save_g:
    mov     [goomba_x], bx
   

    pop     bx
    pop     ax
    ret

; ============================================================================
; DrawTitleFrame
; ============================================================================
DrawTitleFrame:
    push    ax
    push    bx
    push    cx
    push    dx

    ; Sky background
    push    word 0
    push    word 0
    push    word SCREEN_W
    push    word SCREEN_H
    push    word C_SKY
    call    FillRect

    ; Top & bottom brick borders (20 tiles x 16px = 320px)
    xor     bx, bx
.top_bot_loop:
    cmp     bx, 20
    jae     .side_borders
    mov     ax, bx
    shl     ax, 4
    push    ax
    push    word 0
    call    DrawBrickTile
    push    ax
    push    word 184
    call    DrawBrickTile
    inc     bx
    jmp     .top_bot_loop

.side_borders:
    mov     cx, 1
.side_loop:
    cmp     cx, 11
    jae     .ground_strip
    mov     dx, cx
    shl     dx, 4
    push    word 0
    push    dx
    call    DrawBrickTile
    push    word 304
    push    dx
    call    DrawBrickTile
    inc     cx
    jmp     .side_loop

.ground_strip:
    push    word 16
    push    word 170
    push    word 288
    push    word 5
    push    word C_GREEN_LIGHT
    call    FillRect

    push    word 16
    push    word 175
    push    word 288
    push    word 9
    push    word C_BROWN
    call    FillRect

    mov     bx, 22
.dot_loop:
    cmp     bx, 296
    jae     .title_text
    push    bx
    push    word 181
    push    word C_BLACK
    call    PutPixel
    add     bx, 12
    jmp     .dot_loop

.title_text:
    push    word 116
    push    word 34
    push    word C_RED_LIGHT
    push    word str_super_mario
    call    DrawStringShadow

    push    word 132
    push    word 52
    push    word C_WHITE
    push    word str_engine
    call    DrawString

    ; Menu Box
    push    word 98
    push    word 86
    push    word 124
    push    word 48
    push    word C_BLACK
    call    FillRect

    push    word 98
    push    word 86
    push    word 124
    push    word 2
    push    word C_WHITE
    call    FillRect

    push    word 98
    push    word 132
    push    word 124
    push    word 2
    push    word C_WHITE
    call    FillRect

    push    word 98
    push    word 86
    push    word 2
    push    word 48
    push    word C_WHITE
    call    FillRect

    push    word 220
    push    word 86
    push    word 2
    push    word 48
    push    word C_WHITE
    call    FillRect

    mov     ax, [arrow_bob]
    and     ax, 01h
    shl     ax, 1
    add     ax, 108

    cmp     byte [menu_sel], 0
    jne     .sel_exit

    push    ax
    push    word 98
    push    word C_YELLOW
    push    word str_arrow
    call    DrawString

    push    word 122
    push    word 98
    push    word C_YELLOW
    push    word str_start_game
    call    DrawString

    push    word 122
    push    word 116
    push    word C_WHITE
    push    word str_exit
    call    DrawString
    jmp     .credit_and_sprites

.sel_exit:
    push    word 122
    push    word 98
    push    word C_WHITE
    push    word str_start_game
    call    DrawString

    push    ax
    push    word 116
    push    word C_YELLOW
    push    word str_arrow
    call    DrawString

    push    word 122
    push    word 116
    push    word C_YELLOW
    push    word str_exit
    call    DrawString

.credit_and_sprites:
    push    word 56
    push    word 176
    push    word C_WHITE
    push    word str_group
    call    DrawString

    mov     ax, [mario_anim]
    and     ax, 01h
    cmp     word [mario_dir], 0
    jge     .m_right
    or      ax, 02h
.m_right:
    push    word [mario_x]
    push    word GROUND_Y
    push    ax
    call    DrawMarioSprite

    mov     ax, [goomba_anim]
    and     ax, 01h
    push    word [goomba_x]
    push    word GROUND_Y
    push    ax
    call    DrawGoombaSprite

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

; ============================================================================
; RunPlayableStage: Basic scrolling stage so START GAME is interactive
; Controls: A/D or Left/Right = move, W/Up = jump, Esc = back to title
; ============================================================================
RunPlayableStage:
    push    ax
    push    bx
    push    cx
    push    dx

    mov     word [ply_x], 40
    mov     word [ply_y], 144
    mov     word [ply_vy], 0
    mov     word [ply_dir], 0
    mov     word [ply_walk], 0
    mov     word [cam_x], 0

    mov     ah, 00h
    int     1Ah
    mov     [last_tick], dx

    call    DrawStageFrame
    call    PresentFrameBuffer

.stage_loop:
    ; Poll keyboard
    mov     ah, 01h
    int     16h
    jnz     .key_ready
    jmp     .tick_check
.key_ready:

    mov     ah, 00h
    int     16h

    cmp     al, 27                          ; ESC -> return to title menu
    jne     .not_esc
    jmp     .done
.not_esc:

    cmp     ah, 4Bh                         ; Left arrow
    je      .go_left
    cmp     al, 'a'
    je      .go_left
    cmp     al, 'A'
    je      .go_left

    cmp     ah, 4Dh                         ; Right arrow
    je      .go_right
    cmp     al, 'd'
    je      .go_right
    cmp     al, 'D'
    je      .go_right

    cmp     ah, 48h                         ; Up arrow -> jump
    je      .try_jump
    cmp     al, 'w'
    je      .try_jump
    cmp     al, 'W'
    je      .try_jump
    cmp     al, ' '
    je      .try_jump

    jmp     .tick_check

.go_left:
    mov     word [ply_dir], -1
    sub     word [ply_x], 12
    cmp     word [ply_x], 0
    jge     .step_walk_l
    mov     word [ply_x], 0
.step_walk_l:
    inc     word [ply_walk]
    jmp     .update_cam

.go_right:
    mov     word [ply_dir], 1
    add     word [ply_x], 12
    cmp     word [ply_x], (MAP_COLS * TILE_SZ) - 16
    jle     .step_walk_r
    mov     word [ply_x], (MAP_COLS * TILE_SZ) - 16
.step_walk_r:
    inc     word [ply_walk]
    jmp     .update_cam

.try_jump:
 
    cmp     word [ply_y], 144
    jl      .tick_check
    mov     word [ply_vy], -11          ; Stronger instant jump velocity
    add     word [ply_y], -11           ; Move Mario upward IMMEDIATELY on key press
    jmp     .update_cam
.update_cam:
    mov     ax, [ply_x]
    cmp     ax, 120
    jle     .cam_zero
    sub     ax, 120
    cmp     ax, (MAP_COLS * TILE_SZ) - SCREEN_W
    jle     .set_cam
    mov     ax, (MAP_COLS * TILE_SZ) - SCREEN_W
    jmp     .set_cam
.cam_zero:
    xor     ax, ax
.set_cam:
    mov     [cam_x], ax
    call    DrawStageFrame
    call    PresentFrameBuffer
    jmp     .stage_loop

.tick_check:
 
    mov     ah, 00h
    int     1Ah
    cmp     dx, [last_tick]
    je      .stage_loop
    mov     [last_tick], dx

    ; Apply faster gravity
    mov     ax, [ply_y]
    add     ax, [ply_vy]
    add     word [ply_vy], 2            ; Faster fall/arc (was inc = 1)
    cmp     ax, 144
    jl      .store_y
    mov     ax, 144
    mov     word [ply_vy], 0
.store_y:
    mov     [ply_y], ax

    call    DrawStageFrame
    call    PresentFrameBuffer
    jmp     .stage_loop


.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

DrawStageFrame:
    push    ax
    push    bx
    push    cx
    push    dx

    push    word 0
    push    word 0
    push    word SCREEN_W
    push    word SCREEN_H
    push    word C_SKY
    call    FillRect

    ; Top HUD bar
    push    word 0
    push    word 0
    push    word SCREEN_W
    push    word 14
    push    word C_BLACK
    call    FillRect

    push    word 12
    push    word 3
    push    word C_WHITE
    push    word str_hud_help
    call    DrawString

    ; Draw visible ground & blocks with camera scroll
    xor     bx, bx                          ; tile column 0..59
.col_loop:
    cmp     bx, MAP_COLS
    jae     .draw_player

    mov     ax, bx
    shl     ax, 4                           ; world_x = col * 16
    sub     ax, [cam_x]                     ; screen_x = world_x - cam_x
    cmp     ax, -16
    jl      .next_col
    cmp     ax, SCREEN_W
    jge     .next_col

    ; Ground rows (y = 160 and y = 176)
    push    ax
    push    word 160
    call    DrawBrickTile

    push    ax
    push    word 176
    call    DrawBrickTile

    ; Decorative blocks at columns 6, 8, 10, 18, 26
    cmp     bx, 6
    je      .q_block
    cmp     bx, 8
    je      .q_block
    cmp     bx, 10
    je      .q_block
    cmp     bx, 18
    je      .q_block
    cmp     bx, 26
    je      .q_block
    jmp     .next_col

.q_block:
    push    ax
    push    word 112
    push    word 16
    push    word 16
    push    word C_YELLOW
    call    FillRect

.next_col:
    inc     bx
    jmp     .col_loop

.draw_player:
    mov     ax, [ply_x]
    sub     ax, [cam_x]
    mov     bx, [ply_walk]
    and     bx, 01h
    cmp     word [ply_dir], 0
    jge     .p_dir_ok
    or      bx, 02h
.p_dir_ok:
    push    ax
    push    word [ply_y]
    push    bx
    call    DrawMarioSprite

    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

; ============================================================================
; DrawBrickTile: [BP+6]=x, [BP+4]=y
; ============================================================================
; ============================================================================
; DrawBackgroundScenery: Renders scrolling white clouds and green bushes
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
    sub     ax, [cam_x]                 ; screen_x = world_x - cam_x
    cmp     ax, -48
    jl      .draw_bush
    cmp     ax, SCREEN_W
    jge     .draw_bush

    ; Left lobe
    push    ax
    push    word 40
    push    word 16
    push    word 12
    push    word C_WHITE
    call    FillRect

    ; Center taller lobe
    mov     cx, ax
    add     cx, 10
    push    cx
    push    word 32
    push    word 20
    push    word 20
    push    word C_WHITE
    call    FillRect

    ; Right lobe
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

    ; Left bush mound
    push    ax
    push    word 148
    push    word 14
    push    word 12
    push    word C_GREEN_LIGHT
    call    FillRect

    ; Center taller bush mound
    mov     cx, ax
    add     cx, 10
    push    cx
    push    word 142
    push    word 18
    push    word 18
    push    word C_GREEN_LIGHT
    call    FillRect

    ; Right bush mound
    mov     cx, ax
    add     cx, 24
    push    cx
    push    word 148
    push    word 14
    push    word 12
    push    word C_GREEN_LIGHT
    call    FillRect

    ; Dark green base shadow strip along ground line (y = 158..160)
    push    ax
    push    word 158
    push    word 38
    push    word 2
    push    word C_GREEN_DARK
    call    FillRect

.next_anchor:
    add     bx, 256                     ; Repeat every 256 world pixels
    jmp     .scenery_loop

.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    ret

DrawBrickTile:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    dx

    mov     bx, [bp+6]
    mov     dx, [bp+4]

    push    bx
    push    dx
    push    word 16
    push    word 16
    push    word C_RED_DARK
    call    FillRect

    push    bx
    push    dx
    push    word 16
    push    word 1
    push    word C_BLACK
    call    FillRect

    mov     ax, dx
    add     ax, 15
    push    bx
    push    ax
    push    word 16
    push    word 1
    push    word C_BLACK
    call    FillRect

    push    bx
    push    dx
    push    word 1
    push    word 16
    push    word C_BLACK
    call    FillRect

    mov     ax, bx
    add     ax, 15
    push    ax
    push    dx
    push    word 1
    push    word 16
    push    word C_BLACK
    call    FillRect

    mov     ax, dx
    add     ax, 8
    push    bx
    push    ax
    push    word 16
    push    word 1
    push    word C_BLACK
    call    FillRect

    mov     ax, bx
    add     ax, 1
    mov     dx, [bp+4]
    add     dx, 1
    push    ax
    push    dx
    push    word 14
    push    word 2
    push    word C_RED_LIGHT
    call    FillRect

    pop     dx
    pop     bx
    pop     ax
    pop     bp
    ret     4

; ============================================================================
; DrawMarioSprite: [BP+8]=x, [BP+6]=y, [BP+4]=flags (bit0=frame, bit1=flip)
; ============================================================================
DrawMarioSprite:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    cx
    push    dx
    push    si
    push    di

    xor     dx, dx
.row_loop:
    cmp     dx, 16
    jae     .done

    xor     cx, cx
.col_loop:
    cmp     cx, 16
    jae     .next_row

    mov     si, cx
    test    word [bp+4], 02h
    jz      .no_flip
    mov     si, 15
    sub     si, cx
.no_flip:

    mov     ax, dx
    shl     ax, 4
    add     ax, si
    mov     di, ax
    xor     ax, ax
    mov     al, [mario_spr_0 + di]

    test    word [bp+4], 01h
    jz      .draw_px
    cmp     dx, 14
    jb      .draw_px
    cmp     al, 0
    je      .draw_px
    mov     al, C_BROWN

.draw_px:
    test    al, al
    jz      .next_col

    mov     bx, [bp+8]
    add     bx, cx
    push    bx
    mov     bx, [bp+6]
    add     bx, dx
    push    bx
    push    ax
    call    PutPixel

.next_col:
    inc     cx
    jmp     .col_loop

.next_row:
    inc     dx
    jmp     .row_loop

.done:
    pop     di
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    pop     bp
    ret     6

; ============================================================================
; DrawGoombaSprite: [BP+8]=x, [BP+6]=y, [BP+4]=frame
; ============================================================================
DrawGoombaSprite:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    cx
    push    dx
    push    di

    xor     dx, dx
.row_loop:
    cmp     dx, 16
    jae     .done

    xor     cx, cx
.col_loop:
    cmp     cx, 16
    jae     .next_row

    mov     ax, dx
    shl     ax, 4
    add     ax, cx
    mov     di, ax
    xor     ax, ax
    mov     al, [goomba_spr + di]

    cmp     dx, 14
    jb      .px_ok
    test    word [bp+4], 01h
    jz      .px_ok
    cmp     cx, 2
    jb      .px_ok
    cmp     cx, 13
    ja      .px_ok
    xor     al, al

.px_ok:
    test    al, al
    jz      .next_col

    mov     bx, [bp+8]
    add     bx, cx
    push    bx
    mov     bx, [bp+6]
    add     bx, dx
    push    bx
    push    ax
    call    PutPixel

.next_col:
    inc     cx
    jmp     .col_loop

.next_row:
    inc     dx
    jmp     .row_loop

.done:
    pop     di
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    pop     bp
    ret     6

; ============================================================================
; DrawString, DrawStringShadow, DrawChar8x8 (Stack-balanced!)
; ============================================================================
DrawStringShadow:
    push    bp
    mov     bp, sp
    push    ax
    push    bx

    mov     ax, [bp+10]
    add     ax, 2
    mov     bx, [bp+8]
    add     bx, 2
    push    ax
    push    bx
    push    word C_BLACK
    push    word [bp+4]
    call    DrawString

    push    word [bp+10]
    push    word [bp+8]
    push    word [bp+6]
    push    word [bp+4]
    call    DrawString

    pop     bx
    pop     ax
    pop     bp
    ret     8

DrawString:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    si

    mov     bx, [bp+10]
    mov     si, [bp+4]

.next_ch:
    lodsb
    test    al, al
    jz      .done

    xor     ah, ah
    push    bx
    push    word [bp+8]
    push    word [bp+6]
    push    ax
    call    DrawChar8x8

    add     bx, 8
    jmp     .next_ch

.done:
    pop     si
    pop     bx
    pop     ax
    pop     bp
    ret     8

; Stack: [BP+10]=x, [BP+8]=y, [BP+6]=color, [BP+4]=ascii
DrawChar8x8:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    cx
    push    dx
    push    si

    mov     ax, [bp+4]
    and     ax, 007Fh
    shl     ax, 3
    mov     si, font8x8
    add     si, ax

    xor     dx, dx                          ; dy = 0..7 (vertical row)
.row_loop:
    cmp     dx, 8
    jae     .done

    mov     bl, [cs:si]                     ; fetch row bitmap from CS
    inc     si
    xor     cx, cx                          ; dx_col = 0..7 (horizontal bit)

.bit_loop:
    cmp     cx, 8
    jae     .next_row

    shl     bl, 1
    jnc     .skip_bit

    mov     ax, [bp+10]                     ; base x
    add     ax, cx                          ; x + col
    push    ax

    mov     ax, [bp+8]                      ; base y
    add     ax, dx                          ; y + row
    push    ax

    push    word [bp+6]                     ; color
    call    PutPixel

.skip_bit:
    inc     cx
    jmp     .bit_loop

.next_row:
    inc     dx
    jmp     .row_loop

.done:
    pop     si
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    pop     bp
    ret     8

; ============================================================================
; Frame Buffer & Pixel Primitives
; ============================================================================
InitFrameBuffer:
    push    ax
    push    bx
    push    es

    mov     ax, cs
    mov     es, ax
    mov     bx, 1000h
    mov     ah, 4Ah
    int     21h
    jc      .fail

    mov     bx, 0FA0h
    mov     ah, 48h
    int     21h
    jc      .fail

    mov     [fb_seg], ax
    clc
    jmp     .end

.fail:
    stc
.end:
    pop     es
    pop     bx
    pop     ax
    ret

PresentFrameBuffer:
    push    cx
    push    si
    push    di
    push    ds
    push    es

    mov     ax, [fb_seg]
    mov     ds, ax
    xor     si, si
    mov     ax, 0A000h
    mov     es, ax
    xor     di, di
    mov     cx, FB_WORDS
    rep     movsw

    pop     es
    pop     ds
    pop     di
    pop     si
    pop     cx
    ret

PutPixel:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    dx
    push    di
    push    es

    mov     bx, [bp+8]
    mov     dx, [bp+6]
    cmp     bx, SCREEN_W
    jae     .done
    cmp     dx, SCREEN_H
    jae     .done

    mov     di, dx
    shl     di, 8
    mov     ax, dx
    shl     ax, 6
    add     di, ax
    add     di, bx

    mov     es, [fb_seg]
    mov     al, [bp+4]
    mov     [es:di], al

.done:
    pop     es
    pop     di
    pop     dx
    pop     bx
    pop     ax
    pop     bp
    ret     6

FillRect:
    push    bp
    mov     bp, sp
    push    ax
    push    bx
    push    cx
    push    dx

    mov     dx, [bp+10]
    mov     cx, [bp+6]
    test    cx, cx
    jz      .done

.r_loop:
    push    cx
    mov     bx, [bp+12]
    mov     cx, [bp+8]
    test    cx, cx
    jz      .r_next

.c_loop:
    push    bx
    push    dx
    push    word [bp+4]
    call    PutPixel
    inc     bx
    loop    .c_loop

.r_next:
    pop     cx
    inc     dx
    loop    .r_loop

.done:
    pop     dx
    pop     cx
    pop     bx
    pop     ax
    pop     bp
    ret     10


CleanExitToDOS:
    
   
    mov     ax, 0003h
    int     10h

    mov     ax, [fb_seg]
    test    ax, ax
    jz      .no_free
    mov     es, ax
    mov     ah, 49h
    int     21h

.no_free:
    mov     ax, 4C00h
    int     21h

; ============================================================================
; Data
; ============================================================================
fb_seg          dw 0
last_tick       dw 0
frame_ctr       dw 0
menu_sel        db 0
arrow_bob       dw 0

mario_x         dw 28
mario_dir       dw 1
mario_anim      dw 0

goomba_x        dw 260
goomba_dir      dw -1
goomba_anim     dw 0

ply_x           dw 40
ply_y           dw 144
ply_vy          dw 0
ply_dir         dw 0
ply_walk        dw 0
cam_x           dw 0

str_super_mario db "SUPER MARIO", 0
str_engine      db "E N G I N E", 0
str_arrow       db ">", 0
str_start_game  db "START GAME", 0
str_exit        db "EXIT", 0
str_group       db "Group: Fatima, Urwa ", 0
str_hud_help    db "A/D:MOVE  W/SPACE:JUMP  ESC:MENU", 0

mario_spr_0:
    db 0,0,0,0,0,12,12,12,12,12,0,0,0,0,0,0
    db 0,0,0,0,12,12,12,12,12,12,12,12,0,0,0,0
    db 0,0,0,0,6,6,6,14,14,0,14,0,0,0,0,0
    db 0,0,0,6,14,6,14,14,14,0,14,14,14,0,0,0
    db 0,0,0,6,14,6,6,14,14,14,14,14,14,0,0,0
    db 0,0,0,6,6,14,14,14,14,6,6,6,0,0,0,0
    db 0,0,0,0,0,14,14,14,14,14,14,0,0,0,0,0
    db 0,0,0,0,12,12,1,12,12,12,0,0,0,0,0,0
    db 0,0,0,12,12,12,1,12,12,1,12,12,12,0,0,0
    db 0,0,12,12,12,12,1,1,1,1,12,12,12,12,0,0
    db 0,0,14,14,12,1,1,14,14,1,1,12,14,14,0,0
    db 0,0,14,14,14,1,1,1,1,1,1,14,14,14,0,0
    db 0,0,0,0,1,1,1,0,0,1,1,1,0,0,0,0
    db 0,0,0,6,6,6,0,0,0,0,6,6,6,0,0,0
    db 0,0,6,6,6,6,0,0,0,0,6,6,6,6,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

goomba_spr:
    db 0,0,0,0,0,0,6,6,6,6,0,0,0,0,0,0
    db 0,0,0,0,0,6,6,6,6,6,6,0,0,0,0,0
    db 0,0,0,0,6,6,6,6,6,6,6,6,0,0,0,0
    db 0,0,0,6,6,6,6,6,6,6,6,6,6,0,0,0
    db 0,0,6,6,15,15,6,6,6,6,15,15,6,6,0,0
    db 0,6,6,6,15,0,6,6,6,6,0,15,6,6,6,0
    db 0,6,6,6,15,15,6,6,6,6,15,15,6,6,6,0
    db 0,6,6,6,6,6,6,6,6,6,6,6,6,6,6,0
    db 0,0,6,6,6,6,14,14,14,14,6,6,6,6,0,0
    db 0,0,0,0,6,14,14,14,14,14,14,6,0,0,0,0
    db 0,0,0,0,0,14,14,14,14,14,14,0,0,0,0,0
    db 0,0,0,0,0,14,14,14,14,14,14,0,0,0,0,0
    db 0,0,0,0,6,6,14,14,14,14,6,6,0,0,0,0
    db 0,0,0,6,6,6,6,0,0,6,6,6,6,0,0,0
    db 0,0,6,6,6,6,0,0,0,0,6,6,6,6,0,0
    db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

; Exact 128-character 8x8 ASCII table (chars 0..127 -> 1024 bytes)
font8x8:
    times (33 * 8) db 0
    db 018h,018h,018h,018h,018h,000h,018h,000h ; 32:' '->33:'!'
    db 06Ch,06Ch,024h,000h,000h,000h,000h,000h ; 34:'"'
    db 06Ch,06Ch,0FEh,06Ch,0FEh,06Ch,06Ch,000h ; 35:'#'
    db 018h,03Eh,060h,03Ch,006h,07Ch,018h,000h ; 36:'$'
    db 000h,0C6h,0CCh,018h,030h,066h,0C6h,000h ; 37:'%'
    db 038h,06Ch,038h,076h,0DCh,0CCh,076h,000h ; 38:'&'
    db 018h,018h,030h,000h,000h,000h,000h,000h ; 39:'''
    db 00Ch,018h,030h,030h,030h,018h,00Ch,000h ; 40:'('
    db 030h,018h,00Ch,00Ch,00Ch,018h,030h,000h ; 41:')'
    db 000h,066h,03Ch,0FFh,03Ch,066h,000h,000h ; 42:'*'
    db 000h,018h,018h,07Eh,018h,018h,000h,000h ; 43:'+'
    db 000h,000h,000h,000h,000h,018h,018h,030h ; 44:','
    db 000h,000h,000h,07Eh,000h,000h,000h,000h ; 45:'-'
    db 000h,000h,000h,000h,000h,018h,018h,000h ; 46:'.'
    db 006h,00Ch,018h,030h,060h,0C0h,080h,000h ; 47:'/'
    db 07Ch,0C6h,0CEh,0D6h,0E6h,0C6h,07Ch,000h ; 48:'0'
    db 018h,038h,018h,018h,018h,018h,07Eh,000h ; 49:'1'
    db 07Ch,0C6h,006h,01Ch,070h,0C0h,0FEh,000h ; 50:'2'
    db 07Ch,0C6h,006h,03Ch,006h,0C6h,07Ch,000h ; 51:'3'
    db 01Ch,03Ch,06Ch,0CCh,0FEh,00Ch,00Ch,000h ; 52:'4'
    db 0FEh,0C0h,0FCh,006h,006h,0C6h,07Ch,000h ; 53:'5'
    db 038h,060h,0C0h,0FCh,0C6h,0C6h,07Ch,000h ; 54:'6'
    db 0FEh,0C6h,00Ch,018h,030h,030h,030h,000h ; 55:'7'
    db 07Ch,0C6h,0C6h,07Ch,0C6h,0C6h,07Ch,000h ; 56:'8'
    db 07Ch,0C6h,0C6h,07Eh,006h,00Ch,078h,000h ; 57:'9'
    db 000h,018h,018h,000h,018h,018h,000h,000h ; 58:':'
    db 000h,018h,018h,000h,018h,018h,030h,000h ; 59:';'
    db 00Ch,018h,030h,060h,030h,018h,00Ch,000h ; 60:'<'
    db 000h,000h,07Eh,000h,07Eh,000h,000h,000h ; 61:'='
    db 060h,030h,018h,00Ch,018h,030h,060h,000h ; 62:'>'
    db 07Ch,0C6h,00Ch,018h,018h,000h,018h,000h ; 63:'?'
    db 07Ch,0C6h,0DEh,0DEh,0DEh,0C0h,078h,000h ; 64:'@'
    db 038h,06Ch,0C6h,0C6h,0FEh,0C6h,0C6h,000h ; 65:'A'
    db 0FCh,066h,066h,07Ch,066h,066h,0FCh,000h ; 66:'B'
    db 03Ch,066h,0C0h,0C0h,0C0h,066h,03Ch,000h ; 67:'C'
    db 0F8h,06Ch,066h,066h,066h,06Ch,0F8h,000h ; 68:'D'
    db 0FEh,062h,068h,078h,068h,062h,0FEh,000h ; 69:'E'
    db 0FEh,062h,068h,078h,068h,060h,0F0h,000h ; 70:'F'
    db 03Ch,066h,0C0h,0CEh,0C6h,066h,03Eh,000h ; 71:'G'
    db 0C6h,0C6h,0C6h,0FEh,0C6h,0C6h,0C6h,000h ; 72:'H'
    db 078h,030h,030h,030h,030h,030h,078h,000h ; 73:'I'
    db 01Eh,00Ch,00Ch,00Ch,0CCh,0CCh,078h,000h ; 74:'J'
    db 0E6h,066h,06Ch,078h,06Ch,066h,0E6h,000h ; 75:'K'
    db 0F0h,060h,060h,060h,062h,066h,0FEh,000h ; 76:'L'
    db 0C6h,0EEh,0FEh,0D6h,0C6h,0C6h,0C6h,000h ; 77:'M'
    db 0C6h,0E6h,0F6h,0DEh,0CEh,0C6h,0C6h,000h ; 78:'N'
    db 07Ch,0C6h,0C6h,0C6h,0C6h,0C6h,07Ch,000h ; 79:'O'
    db 0FCh,066h,066h,07Ch,060h,060h,0F0h,000h ; 80:'P'
    db 07Ch,0C6h,0C6h,0C6h,0D6h,07Ch,00Eh,000h ; 81:'Q'
    db 0FCh,066h,066h,07Ch,06Ch,066h,0E6h,000h ; 82:'R'
    db 07Ch,0C6h,060h,038h,00Ch,0C6h,07Ch,000h ; 83:'S'
    db 0FFh,05Ah,018h,018h,018h,018h,03Ch,000h ; 84:'T'
    db 0C6h,0C6h,0C6h,0C6h,0C6h,0C6h,07Ch,000h ; 85:'U'
    db 0C6h,0C6h,0C6h,0C6h,0C6h,06Ch,038h,000h ; 86:'V'
    db 0C6h,0C6h,0C6h,0D6h,0FEh,0EEh,0C6h,000h ; 87:'W'
    db 0C6h,0C6h,06Ch,038h,06Ch,0C6h,0C6h,000h ; 88:'X'
    db 066h,066h,066h,03Ch,018h,018h,03Ch,000h ; 89:'Y'
    db 0FEh,0C6h,08Ch,018h,032h,066h,0FEh,000h ; 90:'Z'
    times (6 * 8) db 0
    db 000h,000h,078h,00Ch,07Ch,0CCh,076h,000h ; 97:'a'
    db 0E0h,060h,07Ch,066h,066h,066h,0DCh,000h ; 98:'b'
    db 000h,000h,07Ch,0C6h,0C0h,0C6h,07Ch,000h ; 99:'c'
    db 01Ch,00Ch,07Ch,0CCh,0CCh,0CCh,076h,000h ; 100:'d'
    db 000h,000h,07Ch,0C6h,0FEh,0C0h,07Ch,000h ; 101:'e'
    db 038h,06Ch,060h,0F0h,060h,060h,0F0h,000h ; 102:'f'
    db 000h,000h,076h,0CCh,0CCh,07Ch,00Ch,0F8h ; 103:'g'
    db 0E0h,060h,06Ch,076h,066h,066h,0E6h,000h ; 104:'h'
    db 018h,000h,038h,018h,018h,018h,07Eh,000h ; 105:'i'
    db 00Ch,000h,01Ch,00Ch,00Ch,0CCh,0CCh,078h ; 106:'j'
    db 0E0h,060h,066h,06Ch,078h,06Ch,0E6h,000h ; 107:'k'
    db 078h,018h,018h,018h,018h,018h,07Eh,000h ; 108:'l'
    db 000h,000h,0FCh,0D6h,0D6h,0D6h,0D6h,000h ; 109:'m'
    db 000h,000h,0DCh,066h,066h,066h,066h,000h ; 110:'n'
    db 000h,000h,07Ch,0C6h,0C6h,0C6h,07Ch,000h ; 111:'o'
    db 000h,000h,0DCh,066h,066h,07Ch,060h,0F0h ; 112:'p'
    db 000h,000h,076h,0CCh,0CCh,07Ch,00Ch,01Eh ; 113:'q'
    db 000h,000h,0DCh,076h,060h,060h,0F0h,000h ; 114:'r'
    db 000h,000h,07Ch,0C0h,07Ch,006h,0FCh,000h ; 115:'s'
    db 030h,030h,0FCh,030h,030h,036h,01Ch,000h ; 116:'t'
    db 000h,000h,0CCh,0CCh,0CCh,0CCh,076h,000h ; 117:'u'
    db 000h,000h,0C6h,0C6h,0C6h,06Ch,038h,000h ; 118:'v'
    db 000h,000h,0C6h,0D6h,0D6h,0FEh,06Ch,000h ; 119:'w'
    db 000h,000h,0C6h,06Ch,038h,06Ch,0C6h,000h ; 120:'x'
    db 000h,000h,0C6h,0C6h,0C6h,07Eh,006h,0FCh ; 121:'y'
    db 000h,000h,0FEh,08Ch,018h,062h,0FEh,000h ; 122:'z'
    times (5 * 8) db 0
    %include "logic.asm"