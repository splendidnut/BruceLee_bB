/*****************************************************************************
 *                                                                           *
 * Bruce Lee for Atari VCS 2600     - KERNEL DEV                             *
 *                                                                           *
 * by: Philip Blackman                                                       *
 *                                                                           *
 *****************************************************************************/
 
    includesfile multisprite_superchip.inc
    set smartbranching on
    set optimization inlinerand
    set optimization noinlinedata
    set kernel multisprite
    set romsize 8kSC

;=======================
;--  Constants
;-----------------------

    ;--------------------------------------------------------------
    ;--- create a flag and include a color definition table
    ;--- to allow easy handling of NTSC & PAL color differences

    const IS_NTSC = 1                ; TV mode. IS_NTSC = 0 for PAL colors

    inline NTSC_PAL_colors.asm       ; Color constants are defined in external ASM file

;-----------------------------------------------------------------------------------------
;  Color Definitions
;---------------------
; To use the ASM defined colors in bB assignments they have to be redefined,
; otherwise bB is using the ZP memory instead!

    const _Color_Blue_Sky            = _98
    const _Color_Green               = _D8



;==============================
;----- Variables
;------------------------------

    dim actionTimer = a
    dim mainTimer = b
    dim spriteTimers = c ;d,e
    dim spriteStates = f ;g,h
    dim spriteFrames = i ;j,k
    
    dim curSprite = p       ;--- current sprite being handled (0=player, 1=ninja, 2=yamo)

    dim currentScreen = q       ;-- current game screen
    dim gameState = s           ;-- current state of the game


    ;---- Sprite variables

    dim playerTimer = spriteTimers
    dim playerState = spriteStates
    dim playerFrame = spriteFrames

    dim blackNinjaX = player1x
    dim blackNinjaY = player1y
    dim blackNinjaTimer = spriteTimers + 1
    dim blackNinjaState = spriteStates + 1
    dim blackNinjaFrame = spriteFrames + 1

    dim yamoX = player2x
    dim yamoY = player2y
    dim yamoFrame = spriteFrames + 2
    dim yamoState = spriteStates + 2
    dim yamoTimer = spriteTimers + 2

    ;---------------------------------
    ;--- Game State constants
    
    const GAME_INIT         = $00
    const GAME_SCREEN_INIT  = $F0
    const GAME_RUNNING      = $80

;===================================================================================
;--  Bank 1 - Game Code!

    bank 1

Start
    score = 0
    currentScreen = 0

    ;--- initialize player to standing frame in middle of screen
    player0x = 76
    player0y = 55
    playerFrame = 0
    gosub SetPlayerFrame

    gameState = GAME_INIT

    blackNinjaFrame = 0
    yamoFrame = 0

    ;---------------------------------------------------------

DoScreenInit
    gosub LoadLevel
    gosub InitBlackNinja
    gosub InitYamo
    gameState = GAME_RUNNING
    goto MainLoop

;----------------------------------
;-- Main Game loop
;----------------------------------
;

PrepScreen      ;-- called during vblank
    gosub SetBlackNinjaFrame
    gosub SetYamoFrame
    COLUBK = _Color_Blue_Sky - 4
    return otherbank


MainLoop
    if switchreset then goto Start
    
    drawscreen

    mainTimer = mainTimer + 1

    gosub HandlePlayer
    if gameState = GAME_SCREEN_INIT then goto DoScreenInit

DoGameRunningLogic
    gosub HandleBlackNinja
    gosub HandleYamo
    gosub CheckLanterns
    goto MainLoop


;-------------------------------------------------------------------------
;---- define screens

    data levelBgData                    ;-- background colors for above ground
    0x05,0x07,0x07,0x07,0x07,0x07
	0x07,0x07,0x07,0x07,0x07,0x07
	0x05,0x05,0x04,0x04,0x04
	_Color_Blue_Sky,_Color_Blue_Sky,_Color_Blue_Sky
end

    
	
    data levelData
    0x08,0x20,0x20,0x20,0x20,0  ;//-- Screen 1 from original game
    0x30,0x38,0x38,0x38,0x38,0
    0x28,0x00,0x00,0x00,0x00
    0x00,0x00,0x00

    0x08,0x20,0x20,0x20,0x20,0  ;//-- Screen 2 from original game
    0x10,0x00,0x00,0x00,0x00,0
    0x18,0x00,0x00,0x00,0x00
    0x00,0x00,0x00

    0x08,0x20,0x20,0x00,0x00,0  ;//-- Screen 3 from original game
    0x48,0x00,0x00,0x00,0x00,0
    0x40,0x00,0x00,0x00,0x00
    0x00,0x00,0x00
end

    ;--- default level row type data for mountain screens
    const _KT_PLATFORM  = 8         ;--    8 = platform/ground
    const _KT_RT_WALL   = 0x12      ;-- 0x12 = wall on right
    const _KT_LR_WALL   = 0x22      ;-- 0x22 = wall on left & right
    const _KT_LANTERN   = 0x80
    const _KT_MOUNTAINS = 0xF0      ;-- 0xF0 = mountains / decorative bg

    data levelRowTypes
    8,_KT_LR_WALL,_KT_LR_WALL,_KT_LR_WALL,_KT_LR_WALL,_KT_LANTERN
    8,0,0,0,0,_KT_LANTERN
    8,0,0,0,0
    0,_KT_MOUNTAINS,0                    
end

    data screen_lanterns
    0,    0, 0x10, 0x20     ;-- screen 1 lanterns
    0x40, 0, 0x05, 0x20

    0, 0x80, 0x80, 0        ;-- screen 2 lanterns
    0, 0x41, 0x41, 0    

    0,0x11,0x11,0             ;-- screen 3 lanterns
    0,0x11,0x10,0
end

LoadLevel
    dim levelDataOfs = temp2
    dim lanternDataOfs = temp3
    dim highWallStyle = temp4

    ;---- clear superchip RAM
    for i = 0 to 127
        writeScreenData[i] = 0
    next i

    ;-- set data offsets base on level number
    
    levelDataOfs = 0
    lanternDataOfs = 0
    if currentScreen = 1 then levelDataOfs = 20 : lanternDataOfs = 8
    if currentScreen = 2 then levelDataOfs = 40 : lanternDataOfs = 16

    for temp1 = 0 to 20
		writeScreenData[temp1]	  = levelData[levelDataOfs] | 0x7
		writeScreenBgColor[temp1] = levelBgData[temp1]
        writeScreenKernelType[temp1] = levelRowTypes[temp1]
        levelDataOfs = levelDataOfs + 1
	next
    for temp1 = 0 to 8
        writeScreenLanternsPF[temp1] = screen_lanterns[lanternDataOfs]
        lanternDataOfs = lanternDataOfs + 1
    next

    ;--- missile 1 is used for blocking walls
    missile1x = 159

    ;--- experiment to enable blocking walls on the screen edges
    ;------------------------------------------------------------------------
    ;--- since we have just a few screens, handle the differences here

    ;-- do high wall    
    highWallStyle = 0
    if currentScreen = 1 then highWallStyle = _KT_RT_WALL  ;-- screen 1 has higher wall only on right
    if currentScreen = 2 then highWallStyle = _KT_LR_WALL

    writeScreenKernelType[7]  = highWallStyle
    writeScreenKernelType[8]  = highWallStyle
    writeScreenKernelType[9]  = highWallStyle
    writeScreenKernelType[10] = highWallStyle

    ;-- asymmetric platform rows
    if currentScreen = 1 then _skip_asym_rows
        writeScreenKernelType[12] = 0x48    ;-- 8 signifies platform
        if currentScreen = 2 then _skip_asym_rows
            writeScreenKernelType[6]  = 0x48
        
_skip_asym_rows

    if currentScreen <> 2 then _skip_screen2_block
    writeScreenKernelType[13]  = _KT_RT_WALL
    writeScreenKernelType[14]  = _KT_RT_WALL
    writeScreenKernelType[15]  = _KT_RT_WALL
    writeScreenKernelType[16]  = _KT_RT_WALL
_skip_screen2_block

    return


nextScreenRight
    if currentScreen = 2 then return
    currentScreen = currentScreen + 1
    player0x = 0
    gameState = GAME_SCREEN_INIT
    return


nextScreenLeft
    if currentScreen = 0 then return
    currentScreen = currentScreen - 1
    player0x = 149
    gameState = GAME_SCREEN_INIT
    return



;-----------------------------------------------------------------------------------
;-------------- Constants for Player

    ;--- player fighting actions
    const PLAYER_ACTION_MASK        = 0x03
    const PLAYER_CLEAR_ACTION_MASK  = 0xFC
    const PLAYER_NORMAL 	        = 0x00
    const PLAYER_PUNCH  	        = 0x01
    const PLAYER_KICK   	        = 0x02
    const PLAYER_KICK_AND_JUMP      = 0x03
    const PLAYER_REST_ACTION        = 0x03  ;//-- when player action is done, will sit here until button released.

    ;--- player movement state
    const PLAYER_STATE_MASK  = 0xF0
    const CLEAR_PLAYER_STATE = 0x0F
    const PLAYER_DUCK   	  = 0x30
    const PLAYER_FALL   	  = 0x40
    const PLAYER_JUMP   	  = 0x80
    const PLAYER_CLIMB  	  = 0xC0
    const CLEAR_PLAYER_FALL   = 0xBF
    const CLEAR_PLAYER_CLIMB  = 0x3F

    ;--- timer values
    const JUMP_COOLDOWN = 30
    const FALL_COOLDOWN = 6
    const KICK_TIME     = 24
    const DUCK_TIMER    = 12
    const JUMP_TIMER    = 12
    const PLAYER_MAX_KICK_JUMP = 8

    const PLAYER_FACING = 0x08

    const FACE_RIGHT = 0xF7		;//-- AND mask
    const FACE_LEFT  = 0x08		;//--  OR mask
    const FACE_MASK  = 0xF7
    const FACE_DIR   = 0x08

;---------------------------------------------------------------------------------
;--  Handle player input, state & movement


HandlePlayer
    dim movementFlags = temp1
    dim canMove_bit0 = temp1
    dim isMoving_bit1 = temp1
    dim isLadder_bit2 = temp1

    movementFlags = 0

    ;-- IF fire button NOT pressed, clear action
    if !joy0fire then actionTimer = 0 : playerState = playerState & PLAYER_CLEAR_ACTION_MASK

    isMoving_bit1{1} = 0
    if joy0left || joy0right then isMoving_bit1{1} = 1

    ;-- while processing current player state,
    ;--   keep track of whether player can move freely or not    
    canMove_bit0{0} = 1

    if playerState & PLAYER_STATE_MASK = PLAYER_DUCK then goto HandlePlayerDuckState
    if playerState & PLAYER_STATE_MASK = PLAYER_FALL then goto HandlePlayerFallState
    if playerState & PLAYER_STATE_MASK = PLAYER_JUMP then goto HandlePlayerJumpState
    if playerState & PLAYER_STATE_MASK = PLAYER_CLIMB then goto HandlePlayerClimbState

    ;--- when ALL else fails handle the normal state of the player
    goto HandlePlayerNormalState

;----------------------------------------------------------
HandlePlayerFallState
    if (playerTimer <> 0) then goto _player_handle_action_timer
	playerState = playerState & PLAYER_CLEAR_ACTION_MASK
	canMove_bit0{0} = 0
    goto _player_handle_action_timer

;----------------------------------------------------------
HandlePlayerDuckState
    if !joy0down then playerState = playerState & CLEAR_PLAYER_STATE : playerTimer = 0
    if joy0down then canMove_bit0{0} = 0
    goto _player_handle_action_timer

;----------------------------------------------------------
HandlePlayerClimbState
    if joy0up then player0y = player0y + 1
    if joy0down then player0y = player0y - 1

    ;--- handle switching player facing direction
    ;---   to create the two climbing frames from a single graphics frame
    playerState = playerState & FACE_MASK
    if player0y & 0x8 = 0 then playerState = playerState | FACE_LEFT
    goto _player_handle_action_timer


;----------------------------------------------------------
HandlePlayerJumpState

    ; check Jump timer to see if done jumping
    if playerTimer > 0 then _check_for_kick_while_jumping
        playerState = (playerState & CLEAR_PLAYER_STATE) | PLAYER_FALL
        playerTimer = JUMP_COOLDOWN

_check_for_kick_while_jumping
    if actionTimer > 0 then _cont_player_jump
        if !joy0fire then _cont_player_jump
        playerState = playerState | PLAYER_KICK
        actionTimer = KICK_TIME
        
_cont_player_jump
	player0y = player0y + 1
    goto _player_handle_action_timer
    

;----------------------------------------------------------
HandlePlayerNormalState

    ;--- Handle Player wanting to jump

    ; can only start jump if timer has expired
    if playerTimer <> 0 then _skip_player_jump_check
    
        ;-- check if player is trying to jump
        if !joy0up then _skip_player_jump_check
        playerTimer = JUMP_TIMER
        playerState = playerState | PLAYER_JUMP

_skip_player_jump_check


    ;-- check for player actions (kicking / punching)
    if !joy0fire then goto _player_check_for_duck

        ;--- check if player can do an action
        if playerState & PLAYER_ACTION_MASK <> 0 then _player_already_acting
        
        if !isMoving_bit1{1} then playerState = playerState | PLAYER_PUNCH
        if isMoving_bit1{1} then playerState = playerState | PLAYER_KICK_AND_JUMP : playerTimer = PLAYER_MAX_KICK_JUMP
       
        if (playerState & FACE_DIR) = FACE_LEFT then player0x = player0x - 2
        if (playerState & FACE_DIR) <> FACE_LEFT then player0x = player0x + 2

        actionTimer = KICK_TIME
        
_player_already_acting
        canMove_bit0{0} = 0  
        goto _player_handle_action_timer    ;-- SKIP over ducking code (since player is jumping)

    ;---- check to see if player is attempting to duck
_player_check_for_duck
    if !joy0down then _player_not_ducking
    playerState = playerState | PLAYER_DUCK
    playerTimer = DUCK_TIMER
    canMove_bit0{0} = 0

_player_not_ducking


;------------------------------------------------------------------
_player_handle_action_timer

    ;--- handle action timer
    if actionTimer > 0 then actionTimer = actionTimer - 1
    if actionTimer = 0 then if playerState & PLAYER_ACTION_MASK <> 0 then playerState = playerState | PLAYER_REST_ACTION

	;--------------------------------------------------------------
	;--- Player Movement - Horizontal + Facing direction

    if !canMove_bit0{0} then _done_player_lr
	
        if !joy0right then _player_check_left
            playerState = playerState & FACE_RIGHT
            if player0x >= 152 then _done_player_lr ;-- block at far right
            player0x = player0x + 1

            if player0y < 127 || player0x < 152 then _done_player_lr
            goto nextScreenRight
            
	
_player_check_left
        if !joy0left then _done_player_lr		
            playerState = playerState | FACE_LEFT
            if player0x < 1 then _done_player_lr  ;-- block at far left
            
            player0x = player0x - 1

            if player0y < 127 || player0x >= 1 then _done_player_lr
            goto nextScreenLeft

_done_player_lr


    ;------------------------------------------------------------

    if playerTimer > 0 then playerTimer = playerTimer - 1

    
    ;--------------------------------------------------------------
	;--- Handle Ladder - check if player is on or near a ladder

    isLadder_bit2{2} = 0
    curSprite = 0
    gosub CheckForLadder bank2
    if temp5 <> 0 then isLadder_bit2{2} = 1

    ;======================================================
	;--- Track what terrain player is walking on
    curSprite = 0
    gosub CheckForBackground bank2
    
    ;---------------------------------------------------------------------------
    ; apply gravity if player is not standing on ground or jumping / climbing
    ;   or trigger climbing state if player interacts with a ladder

    if playerState >= PLAYER_JUMP then goto _player_already_jumping
    if temp5 = 0 then goto _player_on_ground
			
    if playerState & PLAYER_STATE_MASK <> PLAYER_FALL then playerTimer = FALL_COOLDOWN
	playerState = (playerState & CLEAR_PLAYER_STATE) | PLAYER_FALL

	if mainTimer & 1 = 1 then player0y = player0y - 1
    goto HandlePlayerAnimation

    ;---------------------------------------------
    ;if player is on ground

_player_on_ground
    playerState = playerState & CLEAR_PLAYER_FALL
	if playerState & PLAYER_STATE_MASK <> PLAYER_DUCK then goto HandlePlayerAnimation

    if !isLadder_bit2{2} then goto HandlePlayerAnimation
    playerState = (playerState & CLEAR_PLAYER_STATE) | PLAYER_CLIMB
    goto HandlePlayerAnimation

    ;---------------------------------------------------
    ;-- WHEN the player is jumping or climbing,
	;--   check if player is interacting with a ladder
	;--   and set CLIMB state appropriately

_player_already_jumping
    if !isLadder_bit2{2} then goto _stop_climbing
    playerState = playerState | PLAYER_CLIMB
    goto HandlePlayerAnimation
		
_stop_climbing
    if playerState & PLAYER_CLIMB = PLAYER_CLIMB then playerState = playerState & CLEAR_PLAYER_CLIMB
    goto HandlePlayerAnimation


;--------------------------------------------------------------------
;--- All animation frames and graphics pointers for Bruce Lee

    const FRM_BRUCE_STANDING  = 0
    const FRM_BRUCE_RUNNING_1 = 1
    const FRM_BRUCE_RUNNING_2 = 2
    const FRM_BRUCE_RUNNING_3 = 3

    const FRM_BRUCE_CLIMBING  = 4
    const FRM_BRUCE_JMP_KICK  = 5
    const FRM_BRUCE_PUNCH     = 6

    const FRM_BRUCE_DUCKING_1 = 7
    const FRM_BRUCE_DUCKING_2 = 8

    const FRM_BRUCE_FALLING   = 9


    data _player_gfx_lo
    <_Bruce_Standing
    <_Bruce_Running1, <_Bruce_Running2, <_Bruce_Running3
    <_Bruce_Climbing
    <_Bruce_Jump_Kick
    <_Bruce_Punching
    <_Bruce_Ducking1, <_Bruce_Ducking2
    <_Bruce_Falling
end

    data _player_gfx_hi
    >_Bruce_Standing
    >_Bruce_Running1, >_Bruce_Running2, >_Bruce_Running3
    >_Bruce_Climbing
    >_Bruce_Jump_Kick
    >_Bruce_Punching
    >_Bruce_Ducking1, >_Bruce_Ducking2
    >_Bruce_Falling
end

    data bruceRunningFrames
    3,3,2,2,1,1,2,2
end

    const COL_BRUCELEE         = <(ct_BruceLee-SpriteColorTables)
    const COL_BRUCELEE_DUCK1   = <(ct_BruceLeeDuck1-SpriteColorTables)
    const COL_BRUCELEE_DUCK2   = <(ct_BruceLeeDuck2-SpriteColorTables)


;------------------------
;---- animate player

HandlePlayerAnimation

    playerFrame = FRM_BRUCE_STANDING
    player0pal = COL_BRUCELEE

    ;-- normal running
    if isMoving_bit1{1} && canMove_bit0{0} then temp5 = mainTimer & 0x7 : playerFrame = bruceRunningFrames[temp5]

    ;--- jump or jump_kick animation (still frame)
    if playerState & PLAYER_STATE_MASK <> PLAYER_JUMP then _player_no_jump_animation
        playerFrame = FRM_BRUCE_RUNNING_2
	    if playerState & PLAYER_ACTION_MASK = PLAYER_KICK then playerFrame = FRM_BRUCE_JMP_KICK
    goto _player_no_action_animation
_player_no_jump_animation
        if playerState & PLAYER_ACTION_MASK = PLAYER_KICK then playerFrame = FRM_BRUCE_JMP_KICK
        if playerState & PLAYER_ACTION_MASK = PLAYER_PUNCH then playerFrame = FRM_BRUCE_PUNCH
_player_no_action_animation

    ;--- ducking animation
    if playerState & PLAYER_STATE_MASK <> PLAYER_DUCK then _player_no_ducking_animation		
    if playerTimer < 6 then playerFrame = FRM_BRUCE_DUCKING_2 : player0pal = COL_BRUCELEE_DUCK2
    if playerTimer >= 6 then playerFrame = FRM_BRUCE_DUCKING_1 : player0pal = COL_BRUCELEE_DUCK1
_player_no_ducking_animation

    ;--- falling animation
    if playerState & PLAYER_STATE_MASK = PLAYER_FALL then if playerFrame = 0 then playerFrame = FRM_BRUCE_FALLING

    ;--- climbing animation (mostly handled in the HandlePlayerClimbState)
    if playerFrame < FRM_BRUCE_JMP_KICK then if playerState & PLAYER_STATE_MASK = PLAYER_CLIMB then playerFrame = FRM_BRUCE_CLIMBING

    ;--- setup player frame
SetPlayerFrame
    player0pointerlo = _player_gfx_lo[playerFrame]
    player0pointerhi = _player_gfx_hi[playerFrame]
    player0height = 17
    return




;=======================================================
;-- general code and data for handling enemies

    const ENEMY_FALL_WAIT_TIMER = 60

    const CLEAR_ENEMY_STATE = 0xF8
    const ENEMY_STATE_MASK  = 0x07
    const ENEMY_WAIT        = 0x00
	const ENEMY_RUN         = 0x01
	const ENEMY_ATTACK      = 0x02
	const ENEMY_FALL        = 0x03

;//--- TODO: need to INVERT facing direction 
;//          until Enemy Graphics has been fixed to match player
;//
    const ENEMY_DIR_MASK   = $F7
    const ENEMY_DIR_BIT    = $08
    const ENEMY_FACE_RIGHT = $08		;//-- OR mask
    const ENEMY_FACE_LEFT  = $F7		;//-- AND mask

    const SN_BLACK_NINJA = 1
    const SN_YAMO = 2

/*
    dim movementFlags = temp1
    dim canMove_bit0 = temp1
    dim isMoving_bit1 = temp1
    dim isLadder_bit2 = temp1
*/

;--- handle moving an enemy (curSprite), requires movementFlags in temp1
MoveEnemy
    dim enemyState = temp2
    if curSprite = SN_BLACK_NINJA then enemyState = blackNinjaState else enemyState = yamoState

    if !canMove_bit0{0} then goto _done_move_enemy_lr
	if enemyState & ENEMY_DIR_BIT <> ENEMY_FACE_RIGHT then goto _move_enemy_left
	    if player0x[curSprite] < 150 then player0x[curSprite] = player0x[curSprite] + 1
	    goto _done_move_enemy_lr
_move_enemy_left
	    if player0x[curSprite] >= 6 then player0x[curSprite] = player0x[curSprite] - 1
_done_move_enemy_lr

    gosub CheckForBackground bank2
    
    ;-- apply gravity
    if temp5 = 0 then goto _enemy_on_ground
        if curSprite = SN_YAMO then if enemyState & ENEMY_STATE_MASK = ENEMY_ATTACK then goto _enemy_on_ground

        enemyState = enemyState & ENEMY_DIR_MASK : enemyState = enemyState | ENEMY_FALL
        if mainTimer & 0x1 = 1 then player0y[curSprite] = player0y[curSprite] - 1
        goto _done_enemy_move

_enemy_on_ground    ;-- also YAMO in JUMP ATTACK state
        if enemyState & ENEMY_STATE_MASK <> ENEMY_FALL then goto _done_enemy_move
        enemyState = enemyState & ENEMY_DIR_BIT : enemyState = enemyState | ENEMY_WAIT
        if curSprite = SN_BLACK_NINJA then blackNinjaTimer = ENEMY_FALL_WAIT_TIMER else yamoTimer = ENEMY_FALL_WAIT_TIMER

_done_enemy_move

    ;-- save enemy state
    if curSprite = SN_BLACK_NINJA then blackNinjaState = enemyState else yamoState = enemyState
    return



;=======================================================
;-- Black Ninja
;-------------------------------------------------------

;---------------------------------------
;-- Constants

    const NINJA_WAIT_TIMER = 60
    const NINJA_RUN_TIMER  = 36
    const NINJA_ATTACK_WAIT_TIME = 72
    const NINJA_ATTACK_TIMER = 36
    const NINJA_ATTACK_ANIM_LEN = 27
    const NINJA_ATTACK_DIST = 10
    const NINJA_ATTACK_DIST_X2 = 20


;--------------------------------------------------------------------
;--- All animation frames and graphics pointers for Black Ninja

    const FRM_NINJA_STANDING  = 0
    const FRM_NINJA_RUNNING_1 = 1
    const FRM_NINJA_RUNNING_2 = 2
    const FRM_NINJA_RUNNING_3 = 3

    const FRM_NINJA_ATTACK_1 = 1
    const FRM_NINJA_ATTACK_2 = 4
    const FRM_NINJA_ATTACK_3 = 5
    const FRM_NINJA_ATTACK_4 = 6

    data _ninja_gfx_lo
    <_Ninja_Running1, <_Ninja_Running2, <_Ninja_Running3, <_Ninja_Running4
    <_Ninja_Attack1, <_Ninja_Attack2, <_Ninja_Attack3, <_Ninja_Attack1
end

    data _ninja_gfx_hi
    >_Ninja_Running1, >_Ninja_Running2, >_Ninja_Running3, >_Ninja_Running4
    >_Ninja_Attack1, >_Ninja_Attack2, >_Ninja_Attack3, >_Ninja_Attack1
end

    data blackNinjaRunningFrames
    FRM_NINJA_RUNNING_3, FRM_NINJA_RUNNING_3
    FRM_NINJA_RUNNING_2, FRM_NINJA_RUNNING_2
    FRM_NINJA_RUNNING_1, FRM_NINJA_RUNNING_1
    FRM_NINJA_RUNNING_2, FRM_NINJA_RUNNING_2
end

    data blackNinjaAttackFrames
    FRM_NINJA_ATTACK_4, FRM_NINJA_ATTACK_4
    FRM_NINJA_ATTACK_3, FRM_NINJA_ATTACK_2
    FRM_NINJA_ATTACK_1, FRM_NINJA_ATTACK_1
    FRM_NINJA_ATTACK_1, FRM_NINJA_ATTACK_1
end

    ;--- setup player frame
SetBlackNinjaFrame
    player1pointerlo = _ninja_gfx_lo[blackNinjaFrame]
    player1pointerhi = _ninja_gfx_hi[blackNinjaFrame]
    player1height = 17
    return

;---------------------------------------


InitBlackNinja
    player1pal = 0

    blackNinjaX = 20 ; 140
    blackNinjaY = 144  ;bottom=30 ;top=144
    blackNinjaState = 0
    blackNinjaTimer = NINJA_WAIT_TIMER    ;-- initial wait timer
    return


;---------------------------------------

HandleBlackNinja
    curSprite = 1       ;-- make sure to indicate to other subroutines that we're working with the Black Ninja
    movementFlags = 0

    if blackNinjaTimer <> 0 then blackNinjaTimer = blackNinjaTimer - 1

    blackNinjaFrame = FRM_NINJA_STANDING
    canMove_bit0{0} = 0

    if blackNinjaState & ENEMY_STATE_MASK = ENEMY_WAIT then if blackNinjaTimer = 0 then goto HandleBlackNinjaNextMove
    if blackNinjaState & ENEMY_STATE_MASK = ENEMY_RUN then goto HandleBlackNinjaRun
    if blackNinjaState & ENEMY_STATE_MASK = ENEMY_ATTACK then goto HandleBlackNinjaAttack
    goto MoveEnemy

;--------------------------------    
HandleBlackNinjaAttack

    ;-- Is ninja done with his attack?
    if blackNinjaTimer <> 0 then _do_black_ninja_attack
        blackNinjaState = blackNinjaState & CLEAR_ENEMY_STATE
        blackNinjaTimer = NINJA_WAIT_TIMER
        goto MoveEnemy

_do_black_ninja_attack
    ;-- Is it time to attack?
    if blackNinjaTimer >= NINJA_ATTACK_TIMER then goto MoveEnemy

    ;-- Figure out which attack frame to show
    temp2 = FRM_NINJA_STANDING
    if blackNinjaTimer > NINJA_ATTACK_ANIM_LEN then goto _do_ninja_attack_frame
    temp2 = (blackNinjaTimer / 4) & 0x7

    ;-- Do attack animation and move ninja towards target
_do_ninja_attack_frame
    blackNinjaFrame = blackNinjaAttackFrames[temp2]
    if blackNinjaTimer & 0x1C = 0x8 then canMove_bit0{0} = 1
    goto MoveEnemy

    ;return--- no need as we jumped to MoveEnemy


;---------------------------------------------------------------
;--  Handle when Black Ninja is ready to make next move

HandleBlackNinjaNextMove
	blackNinjaState = blackNinjaState & ENEMY_DIR_MASK;
	if blackNinjaX < player0x then blackNinjaState = blackNinjaState | ENEMY_FACE_RIGHT
	blackNinjaState = blackNinjaState | ENEMY_RUN
    blackNinjaTimer = NINJA_RUN_TIMER
    return


;---------------------------------------------------------------
;--  Handle when Black Ninja is running and potentially attacks


HandleBlackNinjaRun
    dim deltaX = temp2
    dim deltaY = temp3

    temp2 = blackNinjaTimer & 0x7
    blackNinjaFrame = blackNinjaRunningFrames[temp2]

    deltaX = blackNinjaX - player0x : deltaX = deltaX + NINJA_ATTACK_DIST
    deltaY = blackNinjaY - player0y

    canMove_bit0{0} = 0     ;-- start by assuming the enemy is not moving

    ;//----------------------------------------------------------------
	;// Determine whether enemy should keep running, or switch states
	;//
	;//  The enemy should keep running IF
	;//     - enemy is above player
	;//     - enemy is not near player
	;//  IF the enemy is close to the player, THEN ATTACK
	;//  IF none of those conditions are met, 
	;//    THEN enemy should switch back to WAIT, and determine next move
	
    ;-- if enemy above player, move towards player
	if blackNinjaY > player0y then canMove_bit0{0} = 1 : goto _ninja_handle_timer

    ;-- if we're not near player, run towards him
    if deltaX >= NINJA_ATTACK_DIST_X2 then canMove_bit0{0} = 1 : goto _ninja_handle_timer

    ;-- IF enemy is too far away, THEN force into wait state to determine next move
    if deltaY + 10 > 20 then blackNinjaTimer = 0 : goto _ninja_handle_timer

    ;-- if we're close to player AND on same level, initiate attack	
	blackNinjaState = blackNinjaState & CLEAR_ENEMY_STATE : blackNinjaState = blackNinjaState | ENEMY_ATTACK
	blackNinjaTimer = NINJA_ATTACK_WAIT_TIME

_ninja_handle_timer
	
	;-- When timer runs out, enemy will stop and think for a bit before making the next move
	if blackNinjaTimer <> 0 then goto _ninja_done_with_run_state
	blackNinjaState = blackNinjaState & CLEAR_ENEMY_STATE
	blackNinjaTimer = NINJA_WAIT_TIMER

_ninja_done_with_run_state	
	;//--------------
	;// Slow down enemy: 30 pixs per second movement speed

	if (blackNinjaTimer & 0x1) then canMove_bit0{0} = 0
	goto MoveEnemy




;=======================================================
;-- Yamo
;-------------------------------------------------------

;---------------------------------------
;-- Constants

    const YAMO_KICK_TIMER = 48
    const YAMO_RUN_TIMER = 40
    const YAMO_WAIT_TIMER = 10
    const YAMO_ATTACK_WAIT_TIME = 60

    const YAMO_JUMP_CNT = 48
    const YAMO_HALF_JUMP_CNT = 24    

;--------------------------------------------------------------------
;--- All animation frames and graphics pointers for Yamo


    const FRM_YAMO_STANDING  = 0
    const FRM_YAMO_RUNNING_1 = 0
    const FRM_YAMO_RUNNING_2 = 1
    const FRM_YAMO_RUNNING_3 = 2
    const FRM_YAMO_KICK      = 3

    data _yamo_gfx_lo
    <_Yamo_Running1, <_Yamo_Running2, <_Yamo_Running3
    <_Yamo_Kick
end

    data _yamo_gfx_hi
    >_Yamo_Running1, >_Yamo_Running2, >_Yamo_Running3
    >_Yamo_Kick
end

    data yamoRunningFrames
    FRM_YAMO_RUNNING_1, FRM_YAMO_RUNNING_1
    FRM_YAMO_RUNNING_3, FRM_YAMO_RUNNING_3
    FRM_YAMO_RUNNING_2, FRM_YAMO_RUNNING_2
    FRM_YAMO_RUNNING_3, FRM_YAMO_RUNNING_3
end


    const COL_YAMO         = <(ct_yamo-SpriteColorTables)


    ;--- setup player frame
SetYamoFrame
    player2pointerlo = _yamo_gfx_lo[yamoFrame]
    player2pointerhi = _yamo_gfx_hi[yamoFrame]
    player2height = 17
    return

;---------------------------------------


InitYamo
    player2pal = COL_YAMO

    yamoX = 140
    yamoY = 144
    yamoState = 0
    yamoTimer = YAMO_WAIT_TIMER    ;-- initial wait timer
    return


;---------------------------------------

HandleYamo
    curSprite = 2       ;-- make sure to indicate to other subroutines that we're working with Yamo
    movementFlags = 0

    if yamoTimer <> 0 then yamoTimer = yamoTimer - 1

    yamoFrame = FRM_YAMO_STANDING
    canMove_bit0{0} = 0

    if yamoState & ENEMY_STATE_MASK = ENEMY_WAIT then if yamoTimer = 0 then goto HandleYamoNextMove
    if yamoState & ENEMY_STATE_MASK = ENEMY_RUN then goto HandleYamoRun
    if yamoState & ENEMY_STATE_MASK = ENEMY_ATTACK then goto HandleYamoAttack
    goto MoveEnemy

;---------------------------------------------------------------
;--  Handle when Yamo is ready to make next move

HandleYamoNextMove
	yamoState = yamoState & ENEMY_DIR_MASK;
	if yamoX < player0x then yamoState = yamoState | ENEMY_FACE_RIGHT
	yamoState = yamoState | ENEMY_RUN
    yamoTimer = YAMO_RUN_TIMER
    return


;---------------------------------------------------------------
;--  Handle when Yamo is running and potentially attacks

    const YAMO_ATTACK_DIST = 20
    const YAMO_ATTACK_DIST_X2 = 40

HandleYamoRun
    dim deltaX = temp2
    dim deltaY = temp3

    temp2 = yamoTimer & 0x7
    yamoFrame = yamoRunningFrames[temp2]

    deltaX = yamoX - player0x : deltaX = deltaX + YAMO_ATTACK_DIST
    deltaY = yamoY - player0y

    canMove_bit0{0} = 0     ;-- start by assuming the enemy is not moving

    ;//----------------------------------------------------------------
	;// Determine whether enemy should keep running, or switch states
	;//
	;//  The enemy should keep running IF
	;//     - enemy is above player
	;//     - enemy is not near player
	;//  IF the enemy is close to the player, THEN ATTACK
	;//  IF none of those conditions are met, 
	;//    THEN enemy should switch back to WAIT, and determine next move
	
    ;-- if enemy above player, move towards player
	if yamoY > player0y then canMove_bit0{0} = 1 : goto _yamo_handle_timer

    ;-- if we're not near player, run towards him
    if deltaX >= YAMO_ATTACK_DIST_X2 then canMove_bit0{0} = 1 : goto _yamo_handle_timer

    ;-- IF enemy is too far away, THEN force into wait state to determine next move
    if deltaY + 10 > 20 then yamoTimer = 0 : goto _yamo_handle_timer

    ;-- if we're close to player AND on same level, initiate attack	
	yamoState = yamoState & CLEAR_ENEMY_STATE : yamoState = yamoState | ENEMY_ATTACK
	yamoTimer = YAMO_ATTACK_WAIT_TIME

_yamo_handle_timer
	
	;-- When timer runs out, enemy will stop and think for a bit before making the next move
	if yamoTimer <> 0 then goto _yamo_done_with_run_state
	yamoState = yamoState & CLEAR_ENEMY_STATE
	yamoTimer = YAMO_WAIT_TIMER

_yamo_done_with_run_state	
	;//--------------
	;// Slow down enemy: 30 pixs per second movement speed

	if (yamoTimer & 0x1) then canMove_bit0{0} = 0
	goto MoveEnemy


;--------------------------------------------------------------------
HandleYamoAttack
    yamoFrame = FRM_YAMO_KICK
    if mainTimer & 0x1 = 0 then goto _done_yamo_attack

    ;-- Handle jump portion of attack
	if yamoTimer < YAMO_HALF_JUMP_CNT then yamoY = yamoY - 1 else if yamoTimer < YAMO_JUMP_CNT then yamoY = yamoY + 1
		
	;-- Move yamo in direction he is facing
	if yamoState & FACE_LEFT <> 0 then goto _yamo_attack_right
	    if yamoX > 0 then yamoX = yamoX - 1
        goto _done_yamo_attack
_yamo_attack_right
	    if yamoX < 150 then yamoX = yamoX + 1
_done_yamo_attack

    if yamoTimer > 0 then goto MoveEnemy

    ;-- done with attack, prep for next move
    yamoState = yamoState & CLEAR_ENEMY_STATE
    yamoTimer = YAMO_WAIT_TIMER

    goto MoveEnemy





;--------------------------------------------------------------------
/**
 *    Check Lanterns - Check if player grabbed one of the lanterns
 *
 *  NOTE:  Currently only handles bottom row of lanterns
 */
    data lantBumpPfTbl          ;-- this is which lantern byte to read (middle of screen doesn't have any)
    0,1,1,-1,-1,-1,-1,2,2,3
end
    data lpfBitmask             ;-- this is which lantern bit to read
	16,32,64,128,128,64,32,16
	8,4,2,1,1,2,4,8
end

    ;--- Lantern position data (4 bytes)
    ;--    Data Row #,
    ;--    Min Y Bound,
    ;--    Max Y Bound,
    ;--    .padding
    data lanternPos
    4, 0x24, 0x28, 0
    0, 0x54, 0x58, 0
    0xFF
end

    
CheckLanterns
    dim lanternIdx = temp1
    dim bumpX = temp1
    dim bumpRow = temp2     ;-- which lantern row to read
    dim bumpBitX = temp3    ;-- which bit to check
    dim bumpPF = temp4      ;-- which PF byte to check
    dim bumpData = temp5
    dim bumpMask = temp6

    ;--- make sure player is hitting lantern row
    ;if player0y < 0x24 || player0y > 0x28 then return

;---> TODO: figure out which lantern row to check
    lanternIdx = 0

_lantern_row_loop
    bumpRow = lanternPos[lanternIdx]
    if bumpRow > 0x10 then return
    lanternIdx = lanternIdx + 1
    if lanternPos[lanternIdx] > player0y then goto _next_lantern_row
    lanternIdx = lanternIdx + 1
    if lanternPos[lanternIdx] < player0y then goto _next_lantern_row
    goto _found_lantern_row

_next_lantern_row
    lanternIdx = lanternIdx & 0xFC : lanternIdx = lanternIdx + 4
    goto _lantern_row_loop


    ;-- found which lantern row the player is hitting
    ;--- now we need to figure out if a lantern
    ;--- in that row is being hit

_found_lantern_row
    bumpX = player0x + 1
    if playerState & FACE_LEFT = FACE_LEFT then bumpX = bumpX - 3

_check_lantern_bit          ;-- this should be done twice
    bumpX = bumpX + 4
    bumpBitX = bumpX / 4

    ;-- figure out which PF byte to check
    bumpPF = bumpBitX / 4
    bumpPF = lantBumpPfTbl[bumpPF]

    if bumpPF >= 0x80 then return  ;-- negative number means no byte to check

    bumpPF = bumpPF + bumpRow
    bumpBitX = bumpBitX & 0x0F
    bumpMask = lpfBitmask[bumpBitX]
    bumpData = screenLanternsPF[bumpPF]

    if bumpData & bumpMask <> 0 then writeScreenLanternsPF[bumpPF] = (bumpMask ^ 0xFF) & bumpData

    return






;--------------------------------------------------------------------------
;--- routine for doing generic sprite movement --- (for TESTING SPRITES) ---
;--------------------------------------------------------------------------
;-- check joystick direction, and move player accordingly
;--

    const BELOW_SCREEN = 188

HandleGenericMovement

    if !joy0up then goto _skip_move_up
    if player0y = BELOW_SCREEN then _skip_move_up
    player0y = player0y + 1
_skip_move_up

    if !joy0down then goto _skip_move_down
    if player0y = 0 then _skip_move_down
    player0y = player0y - 1
_skip_move_down

    ;-----
    ;-- horizontal movement

    if !joy0right then goto _skip_move_right
    if player0x > 150 then _skip_move_right
    player0x = player0x + 1
_skip_move_right

    if !joy0left then goto _skip_move_left
    if player0x = 0 then _skip_move_left
    player0x = player0x - 1
_skip_move_left

    return






;====================================================================================
;--  Bank 2 - bB drawscreen and sprites (and playfield)
;--
;---  NOTE: This should always be the last bank

    bank 2

    vblank
    gosub PrepScreen bank1
    return

;----------------------------------------------------------------------------------
;--- CheckForBackground - 
;---     read playfield data and return 1 if sprite is not standing on anything
;---
;--- params: curSprite
;--- returns: temp5 - isOnBackground

    const PLAYER_GROUND_OFS = 24
    
    dim spriteX = temp3
    dim spriteRow = temp4

CheckForBackground
    spriteX = player0x[curSprite] + 4
    spriteRow = player0y[curSprite] - PLAYER_GROUND_OFS : spriteRow = spriteRow / 8

    ;-- return IF this is a background row (determined by low nibble of kernel type)
    if (screenKernelType[spriteRow] & 0x8) = 0 then temp5 = 1 : return otherbank

    ;-- check if asymmetric.
    if (screenKernelType[spriteRow] & 0xF0) = 0x40 then goto _bg_asym

    ;-- TODO:  currently only handles mirrored playfield (since that is the screen that is implemented)
    if spriteX >= 80 then spriteX = 160 - spriteX

_bg_asym

    ;--- now figure out which playfield data chunk we need
    temp5 = screenData[spriteRow] : temp5 = (temp5 & 0xF8) | 5  ;-- always read 5th scanline (avoid)

    if spriteX < 16 then temp5 = bitmapPF0[temp5] : goto _done_with_check_background
    if spriteX < 48 then temp5 = bitmapPF1[temp5] : goto _done_with_check_background
    if spriteX >= 144 then temp5 = bitmapPF5[temp5] : goto _done_with_check_background
    if spriteX >= 112 then temp5 = bitmapPF4[temp5] : goto _done_with_check_background

    temp5 = bitmapPF2[temp5] : goto _done_with_check_background

_done_with_check_background
    spriteX = (spriteX / 4) & 0xF
    temp5 = temp5 & pfBitmask[spriteX]

    ;--- temp5 will not be 0 IF sprite is standing on something
    if temp5 = 0 then temp5 = 1 : return otherbank
    temp5 = 0
    return otherbank



;--------------------------------------------------------------
;--- Handle Ladder - check if player is on or near a ladder

    dim playerY   = temp3
    dim ladderX   = temp4
    dim isLadder  = temp5

CheckForLadder
    playerY = player0y
    if joy0down then playerY = playerY - 1

    isLadder = 0

    ;-- current screen determines starting offset
    if currentScreen = 0 then temp6 = 0
    if currentScreen = 1 then temp6 = 8
    if currentScreen = 2 then temp6 = 0

_check_ladder_loop
    ;-- first byte of ladder array indicates if we reached the end of the array or not
    ladderX = _ladder_screen1[temp6]
    if ladderX = 0 then _ladder_not_found

    ;-- check if player is within X range of ladder
    if player0x < ladderX then _check_next_ladder
    temp6 = temp6 + 1
    ladderX = _ladder_screen1[temp6]
    if player0x >= ladderX then _check_next_ladder

    ;-- check if player is within Y range of ladder
    temp6 = temp6 + 1
    if _ladder_screen1[temp6] >= playerY then _check_next_ladder
    temp6 = temp6 + 1
    if _ladder_screen1[temp6] < playerY then _check_next_ladder

    ;--- player is on ladder
    isLadder = 1
    return otherbank

_check_next_ladder
    temp6 = temp6 & 0xFC
    temp6 = temp6 + 4
    goto _check_ladder_loop

_ladder_not_found
    isLadder = 0
    return otherbank


    ;--- LADDER structure (4 bytes per ladder):
    ;---     ladder left X,
    ;---     ladder right X,
    ;---     lowest Y point,
    ;---     highest Y point

    data _ladder_screen1
    0x48, 0x4F, 0x28, 0x7E  ;-- screen 1 ladder
    0,0,0,0
    0x48, 0x4F, 0x28, 0x4E      ;0x3C, 0x60
    0x48, 0x4F, 0x58, 0x7E      ;0x6C, 0x90
    0
end

;---
;--- The following macro helps keep sprite graphics contained within a page.
;---
    asm
      MAC PAD_BB_SPRITE_DATA
.SPRITE_HEIGHT  SET {1}
      if	(<*) > (<(*+.SPRITE_HEIGHT))
      repeat	($100-<*)
      .byte	0
      repend
      endif
      if (<*) < 90
	   repeat (90-<*)
	   .byte 0
	   repend
	   endif
   ENDM

;-----------------------------------------------------------------------------------
;--  Color tables used for the shared P1 sprite
;
;-- These tables are accessed using the COLUx variable from each sprite as an index
;-- For each row in this table, the first color is the bottom color of the sprite, moving up towards the top

    PAD_BB_SPRITE_DATA 1

    ;echo "Sprite Color tables start at ", *

SpriteColorTables:

;--- Sprite palettes
ct_ninja:
ct_black:               .byte _00,_00,_00,_00,_00,_00,_00,_00
                        .byte _00,_00
ct_BruceLee:            .byte _00,_00,_00,_00,_00,_00,_00,_2A
                        .byte _2A,_2A,_2A,_2A,_2A,_2A,_00,_00
ct_BruceLeeDuck1:       .byte _00,_00,_00,_00,_00,_00,_2A,_2A
                        .byte _2A,_2A,_2A,_2A,_00,_00
ct_BruceLeeDuck2:       .byte _00,_00,_00,_00,_00,_2A,_2A,_2A
                        .byte _2A,_00,_00,_00,_00,_00,_00,_00

ct_white:               .byte _0A,_0A,_0C,_0E,_0A,_0C,_0C,_0E
                        .byte _0A,_0A,_0C,_0E,_0A,_0C,_0C,_0E

ct_yamo:                .byte _D6,_D6,_D6,_D6,_00,_00,_D6,_D6
                        .byte _D6,_D6,_D6,_D6,_D6,_D6,_D6,_00

   ;echo "Color tables end at ", *

end

;=======================================================
;--  Sprite Graphics Data

    asm
    PAD_BB_SPRITE_DATA 16
end
  data _Bruce_Standing
    0
    %11100111
    %01100110
    %00100100
    %00100100
    %00101000
    %00111000
    %00111000
    %00111000

    %01001111
    %01101101
    %01111000
    %01110000
    %00110000
    %00111000
    %01111000
    0
end

    data _Bruce_Running1
    0
    %10001000
    %10001100
    %11000100
    %01101100
    %00101000
    %00111000
    %00111000
    %00111100

    %00100110
    %00110100
    %00111100
    %00111000
    %00011000
    %00011100
    %00111100
    0
end


    data _Bruce_Running2
    0
    %00110000
    %01100000
    %01110000
    %00111000
    %00101000
    %00111000
    %00111000
    %00111100

    %00100110
    %00110100
    %00111100
    %00111000
    %00011000
    %00011100
    %00111100
    0
end


    data _Bruce_Running3
    0
    %00110000
    %00101100
    %00111000
    %00011000
    %00111000
    %00111000
    %00111000
    %00111100

    %00100110
    %00110100
    %00111100
    %00111000
    %00011000
    %00011100
    %00111100
    0
end

/*
const char bruceGfx[] = {
	0,
	0xE7,0x66,0x24,0x24,0x28,0x38,0x38,0x38,	// standing still
	0x4F,0x6D,0x78,0x70,0x30,0x38,0x78,0,
	
	0x88,0x8C,0xC4,0x6C,0x28,0x38,0x38,0x3C,	// 3 running frames
	0x26,0x34,0x3C,0x38,0x18,0x1C,0x3C,0,
	
	0x30,0x60,0x70,0x38,0x28,0x38,0x38,0x3C,
	0x26,0x34,0x3C,0x38,0x18,0x1C,0x3C,0,

	0x30,0x2C,0x38,0x18,0x38,0x38,0x38,0x3C,
	0x26,0x34,0x3C,0x38,0x18,0x1C,0x3C,0,
	*/

    data _Bruce_Climbing
    0
    %01000000
    %01000010
    %01000110
    %01100100
    %00111100
    %00111100
    %00111100
    %00111100

    %01100100
    %11110110
    %10111111
    %10101101
    %00011010
    %00011010
    %00111100
    0
end



/*  0x40,0x42,0x46,0x64,0x3C,0x3C,0x3C,0x3C,	// climbing frame (flip to animate)
	0x64,0xF6,0xBF,0x9D,0x19,0x19,0x3C,0,
*/

    data _Bruce_Jump_Kick
    0
    %00000000
    %00000000
    %00000000
    %00111100
    %01100000
    %11111111
    %11111010
    %11110000

    %10101100
    %11010100
    %11110000
    %11100000
    %01100000
    %01110000
    %11110000
    0
end


/*	
	0x00,0x00,0x00,0x3C,0x60,0xFF,0xF9,0xF0,	// jump kick frame
	0x9C,0xD4,0xF0,0xE0,0x60,0x70,0xF0,0,
	
	0x60,0xC0,0xE0,0x70,0x50,0x70,0x70,0x78,	// punch frame
	0x68,0x49,0x7F,0x70,0x30,0x38,0x78,0,
	*/


    data _Bruce_Punching
    0
    %01100000
    %11000000
    %11100000
    %01110000
    %01010000
    %01110000
    %01110000
    %01111000

    %01101000
    %01001001
    %01111111
    %01110000
    %00110000
    %00111000
    %01111000
    0
end


    ;--- bruce lee ducking frames

    data _Bruce_Ducking1
    0
    %11000110
    %01000100
    %01100110
    %00100010
    %00111110
    %00111100
    %00111110
    %01111101

    %10111000
    %00011000
    %00011100
    %00011100
    %00111100
    0
    0
    0
end

    data _Bruce_Ducking2
    0

    %11000100
    %01100111
    %01100011
    %01111110
    %01111110
    %01111101
    %01111000
    %00110000

    %00111000
    %01111000
    0
    0

    0
    0
    0
    0
end

    data _Bruce_Falling
    0
    %01100000
    %01000011
    %01000110
    %01100100
    %00111100
    %00111100
    %00111100
    %00111100

    %01100100
    %11110110
    %10111111
    %10101101
    %00011001
    %00011100
    %00111100
    0
end



/*
const char ninjaGfx[] = {
	// running frame 1
	0x24,0x64,0x4C,0x68,0x38,0x10,0xB8,0xFC,
	0x7E,0x1A,0x3A,0x0A,0x32,0x02,0xFF,0x04,
*/

    asm
    PAD_BB_SPRITE_DATA 16
end
  data _Ninja_Running1
    0
    %00100100
    %01100100
    %01001100
    %01101000
    %00111000
    %00010000
    %10111000
    %11111100

    %01111110
    %00011010
    %00111010
    %00001010
    %00110010
    %00000010
    %11111111
    %00000100
    0
end

/*
	// running frame 2 + attack frame 0
	0x88,0x8C,0xC4,0x6C,0x28,0x10,0xB8,0xFC,
	0x7E,0x1A,0x3A,0x0A,0x32,0x02,0xFF,0x04,
*/

  data _Ninja_Running2
    0
    %10001000
    %10001100
    %11000100
    %01101100
    %00101000
    %00010000
    %10111000
    %11111100

    %01111110
    %00011010
    %00111010
    %00001010
    %00110010
    %00000010
    %11111111
    %00000100
    0
end


/*
	// running frame 3
	0x30,0x60,0x70,0x38,0x28,0x10,0xB8,0xFC,
	0x7E,0x1A,0x3A,0x0A,0x32,0x02,0xFF,0x04,
*/



  data _Ninja_Running3
    0
    %00110000
    %01100000
    %01110000
    %00111000
    %00101000
    %00010000
    %10111000
    %11111100

    %01111110
    %00011010
    %00111010
    %00001010
    %00110010
    %00000010
    %11111111
    %00000100
    0
end

/*
	// running frame 4
	0x30,0x2C,0x38,0x18,0x38,0x10,0xB8,0xFC,
	0x7E,0x1A,0x3A,0x0A,0x32,0x02,0xFF,0x04,
*/

  data _Ninja_Running4
    0
    %00110000
    %00101100
    %00111000
    %00011000
    %00111000
    %00010000
    %10111000
    %11111100

    %01111110
    %00011010
    %00111010
    %00001010
    %00110010
    %00000010
    %11111111
    %00000100
    0
end

  data _Ninja_Attack1
    0
    %10001000
    %10001100
    %11000100
    %01101100
    %00101000
    %00010000
    %10111000
    %11111100

    %01111110
    %00011010
    %00111010
    %00001010
    %00110011
    %00001110
    %11110000
    0
end

  data _Ninja_Attack2
    0
    %00110000
    %01100000
    %01110000
    %00111000
    %00101000
    %01010000
    %01111000
    %01111100
    %01111110
    %00011010
    %00111010
    %00001011
    %00110011
    %00000100
    %00001000
    %00010000
    0
end

  data _Ninja_Attack3
    0
    %00101100
    %00011000
    %00011100
    %00001110
    %00001010
    %00000110
    %00001111
    %00111111
    %11110110
    %11000110
    %00001110
    %00000010
    %00001100
    0
    0
    0
end



/*	0,
	0x46,0x8C,0x7C,0x3C,0x3D,0xBD,0xBF,0xBE,	// running frame 1
	0xFC,0x7E,0x1C,0x1E,0x1F,0x1B,0x1E,0x7C,
	0,
	0x6C,0x48,0x3C,0x3C,0x3D,0xBD,0xBF,0xBE,	// running frame 2
	0xFC,0x7E,0x1C,0x1E,0x1F,0x1B,0x1E,0x7C,
	0,
	0x32,0x25,0x3C,0x3C,0x3D,0xBD,0xBF,0xBE,	// running frame 3
	0xFC,0x7E,0x1C,0x1E,0x1F,0x1B,0x1E,0x7C,
	0,
	0x38,0x60,0x7F,0x79,0x78,0x7A,0x7E,0x7C,	// jump kick frame
	0x78,0x7C,0x38,0x3C,0x3E,0x36,0x3C,0x7C,
	0,*/
	
  data _Yamo_Running1
    0
    %01100010
    %00110001
    %00111110
    %00111100
    %10111100
    %10111101
    %11111101
    %01111101
    %00111111
    %01111110
    %00111000
    %01111000
    %11111000
    %11011000
    %01111000
    %00111110
end

  data _Yamo_Running2
    0
    %00110110
    %00010010
    %00111100
    %00111100
    %10111100
    %10111101
    %11111101
    %01111101
    %00111111
    %01111110
    %00111000
    %01111000
    %11111000
    %11011000
    %01111000
    %00111110
end

  data _Yamo_Running3
    0
    %01001100
    %10100100
    %00111100
    %00111100
    %10111100
    %10111101
    %11111101
    %01111101
    %00111111
    %01111110
    %00111000
    %01111000
    %11111000
    %11011000
    %01111000
    %00111110
end

  data _Yamo_Kick
    0
    %00011100
    %00000110
    %11111110
    %10011110
    %00011110
    %01011110
    %01111110
    %00111110
    %00011110
    %00111110
    %00011100
    %00111100
    %01111100
    %01101100
    %00111100
    %00111110
end

