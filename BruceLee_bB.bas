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
    set romsize 16kSC

;=======================
;--  Constants
;-----------------------

    const pfscore = 3
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

    const _Color_Blue_Sky           = _98
    const _Color_Green              = _D8
    const _Color_GardenBG           = _A0


;------------------------------
;--- Player Goals for game:

    const GOAL_COLLECT_VILLAGE_LANTERNS = 1
    const GOAL_GARDEN_GATE_1            = 2     ;-- bottom of garden gate open?


;==============================
;----- Variables
;------------------------------

    dim actionTimers  = a ;b,c
    dim spriteTimers  = d ;e,f
    dim spriteStates  = g ;h,i
    dim spriteFrames  = j ;k,l
    dim spriteStats   = m ;n,o  - health / lives...
    
    dim curSprite     = p       ;--- current sprite being handled (0=player, 1=ninja, 2=yamo)

    dim mainTimer     = q
    dim currentScreen = r       ;-- current game screen
    dim gameState     = s       ;-- current state of the game
    dim currentGoal   = t       ;-- current goal player is pursuing

    dim sndEffect     = u
    dim sndPos        = v

    ;---- Sprite variables

    dim playerTimer = spriteTimers
    dim playerState = spriteStates
    dim playerFrame = spriteFrames
    dim actionTimer = actionTimers

    dim blackNinjaX = player1x
    dim blackNinjaY = player1y
    dim blackNinjaTimer = spriteTimers + 1
    dim blackNinjaState = spriteStates + 1
    dim blackNinjaFrame = spriteFrames + 1
    dim blackNinjaCount = actionTimers + 1

    dim yamoX = player2x
    dim yamoY = player2y
    dim yamoFrame = spriteFrames + 2
    dim yamoState = spriteStates + 2
    dim yamoTimer = spriteTimers + 2
    dim yamoCount = actionTimers + 2

    ;--- need to keep track of lanterns that have been collected
    dim lanternInvBits        = aux0  ;-- aux0..aux3
    dim lanternScreensCleared = aux6

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

    ;--- initialize player to standing frame in middle of screen
    player0x = 76
    player0y = 55
    playerFrame = 0
    gosub SetPlayerFrame

    gameState = GAME_INIT

    blackNinjaFrame = 0
    yamoFrame = 0

    ;--- initialize game to first screen
    currentScreen = 0
    currentGoal = GOAL_COLLECT_VILLAGE_LANTERNS

    ;--- add in initial lantern inventory bits
    lanternInvBits[0] = 0;x3F
    lanternInvBits[1] = 0;x3F
    lanternInvBits[2] = 0;xFF
    lanternInvBits[3] = 0;x03

    ;--- test scoreboard
    pfscore1 = 0         ;21
    statusbarlength = 0  ;255
    goto DoScreenInit


;---------------------------------------------------------
;-- Main Game loop
;---------------------------------------------------------


PrepScreen      ;-- called during vblank
    gosub PlaySound bank2
    if gameState = GAME_RUNNING then gosub CheckLanterns bank2
    gosub MoveElectroFields bank2
    gosub SetBlackNinjaFrame
    gosub SetYamoFrame

    ;--- make sure background screen color is set before screen drawing starts
    COLUBK = _Color_Blue_Sky - 4
    return otherbank


MainLoop
    if switchreset then goto Start
    
    drawscreen

    mainTimer = mainTimer + 1

    gosub HandleBruceLee
    gosub HandlePlayerAnimation
    if gameState = GAME_SCREEN_INIT then goto DoScreenInit

DoGameRunningLogic
    gosub HandleBlackNinja
    gosub HandleYamo
    goto MainLoop

DoScreenInit
    gosub LoadLevel bank2
    gosub InitBlackNinja
    gosub InitYamo
    gosub SpawnEnemy bank2
    gameState = GAME_RUNNING
    goto MainLoop


;-------------------------------------------------------------------------
;--- handle switching screens

    data nxtScrRgt
    1,2,3,3
end
    data nxtScrLft
    0,0,1,3
end
    data nxtScrDwn
    3,3,3,3
end
    data nxtScrUp
    0,0,0,0
end

nextScreenRight
    gosub CheckGoal bank2
    currentScreen = nxtScrRgt[currentScreen]
    player0x = 0
    gameState = GAME_SCREEN_INIT
    return thisbank


nextScreenLeft
    gosub CheckGoal bank2
    currentScreen = nxtScrLft[currentScreen]
    player0x = 149
    gameState = GAME_SCREEN_INIT
    return thisbank

nextScreenDown
    gosub CheckGoal bank2
    if currentGoal < GOAL_GARDEN_GATE_1 then return thisbank
    currentScreen = nxtScrDwn[currentScreen]
    player0y = 160
    gameState = GAME_SCREEN_INIT
    return thisbank

nextScreenUp
    gosub CheckGoal bank2
    currentScreen = nxtScrUp[currentScreen]
    gameState = GAME_SCREEN_INIT
    
    ;-- TODO: figure out a way to prevent player
    ;--       from immediately climbing ladder after screen transition
    playerState = playerState & CLEAR_PLAYER_STATE
    playerTimer = 20
    player0y = 0x20
    return thisbank


;-----------------------------------------------------------------------------------
;-------------- Constants for Player

    ;--- player movement state
    const PLAYER_STATE_MASK  = 0xF0
    const CLEAR_PLAYER_STATE = 0x0F
    const PLAYER_HIT          = 0x10
    const PLAYER_DUCK   	  = 0x30
    const PLAYER_FALL   	  = 0x40
    const PLAYER_JUMP   	  = 0x80
    const PLAYER_CLIMB  	  = 0xC0
    const CLEAR_PLAYER_FALL   = 0xBF
    const CLEAR_PLAYER_CLIMB  = 0x3F

    ;--- player fighting actions
    const PLAYER_ACTION_MASK        = 0x03
    const PLAYER_CLEAR_ACTION_MASK  = 0xFC
    const PLAYER_NORMAL 	        = 0x00
    const PLAYER_PUNCH  	        = 0x01
    const PLAYER_KICK               = 0x02
    const PLAYER_KICK_AND_JUMP      = PLAYER_KICK | PLAYER_JUMP 
    const PLAYER_REST_ACTION        = 0x03  ;//-- when player action is done, will sit here until button released.


    ;--- timer values
    const JUMP_COOLDOWN = 30
    const FALL_COOLDOWN = 6
    const KICK_TIME     = 24
    const DUCK_TIMER    = 12
    const JUMP_TIMER    = 12
    const PLAYER_MAX_KICK_JUMP = 8
    const WAIT_PLAYER_STUNNED = 40

    const PLAYER_FACING = 0x08

    const FACE_RIGHT = 0xF7		;//-- AND mask
    const FACE_LEFT  = 0x08		;//--  OR mask
    const DIR_MASK   = 0xF7
    const DIR_BIT    = 0x08

;-------------------------------------------------------
;-- general enemy constants

    ;-- sprite number consts
    const SN_PLAYER = 0
    const SN_BLACK_NINJA = 1
    const SN_YAMO = 2

    ;------------------------------------
    ;-- enemy states
    const CLEAR_ENEMY_STATE = 0x0F
    const ENEMY_STATE_MASK  = 0xF0
    const ENEMY_WAIT        = 0x00
	const ENEMY_RUN         = 0x10
	const ENEMY_ATTACK      = 0x20
	const ENEMY_FALL        = 0x40  ;-- aligns with player
    const ENEMY_JUMP        = 0x80  ;-- aligns with player
    const ENEMY_KNOCK_BACK  = 0x60
    const ENEMY_CLIMB  	    = 0xC0  ;-- aligns with player

    ;------------------------------------
    ;-- enemy timer values
    
    const ENEMY_FALL_WAIT_TIMER = 60
    const JUMP_CNT = 48
    const HALF_JUMP_CNT = 24


;---------------------------------------
;-- Yamo Timer Constants

    const YAMO_KICK_TIMER = 48
    const YAMO_RUN_TIMER = 40
    const YAMO_WAIT_TIMER = 10
    const YAMO_ATTACK_WAIT_TIME = 60

    const YAMO_JUMP_CNT = 48
    const YAMO_HALF_JUMP_CNT = 24    

;--------------------------------------------------------------------
;--- Yamo animation frames and graphics pointers

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


;---------------------------------------
;-- Black Ninja Constants

    const NINJA_WAIT_TIMER = 60
    const NINJA_RUN_TIMER  = 36
    const NINJA_ATTACK_WAIT_TIME = 72
    const NINJA_ATTACK_TIMER = 36
    const NINJA_ATTACK_ANIM_LEN = 27
    const NINJA_ATTACK_DIST = 10
    const NINJA_ATTACK_DIST_X2 = 20


;--------------------------------------------------------------------
;--- Black Ninja - animation frames and graphics pointers

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



;---------------------------------------------------------------------------------
;--  Handle player input, state & movement
;---------------------------------------------------------------------------------


    const CAN_AND_IS_MOVING = $03

    dim movementFlags      = temp1
    dim canMove_bit0       = temp1
    dim isMoving_bit1      = temp1
    dim isLadder_bit2      = temp1
    dim isFirePressed_bit7 = temp1
    dim isDownPressed_bit6 = temp1
    dim isUpPressed_bit5   = temp1
    dim isMovingRight_bit4 = temp1

HandleYamoPlayer
    curSprite = 2
    movementFlags = 0

;-- load input for player from joystick 0
    if joy1fire then isFirePressed_bit7{7} = 1
    if joy1down then isDownPressed_bit6{6} = 1
    if joy1up   then isUpPressed_bit5{5} = 1
    if joy1left || joy1right then isMoving_bit1{1} = 1
    if joy1right then isMovingRight_bit4{4} = 1
    goto HandlePlayer

HandleBruceLee
    curSprite = 0
    movementFlags = 0

    ;-- load input for player from joystick 0
    if joy0fire then isFirePressed_bit7{7} = 1
    if joy0down then isDownPressed_bit6{6} = 1
    if joy0up   then isUpPressed_bit5{5} = 1
    if joy0left || joy0right then isMoving_bit1{1} = 1
    if joy0right then isMovingRight_bit4{4} = 1

HandlePlayer

    ;-- IF fire button NOT pressed, clear action
    if !isFirePressed_bit7{7} then actionTimer = 0 : playerState = playerState & PLAYER_CLEAR_ACTION_MASK

    ;-- while processing current player state,
    ;--   keep track of whether player can move freely or not    
    canMove_bit0{0} = 1

    ;-- check if player might get hit by enemy
    ;if playerState & PLAYER_STATE_MASK <> PLAYER_HIT then gosub CheckForPlayerHitByEnemy

    if playerState & PLAYER_STATE_MASK = PLAYER_HIT then goto HandlePlayerHit
    if playerState & PLAYER_STATE_MASK = PLAYER_DUCK then goto HandlePlayerDuckState
    if playerState & PLAYER_STATE_MASK = PLAYER_FALL then goto HandlePlayerFallState
    if playerState & PLAYER_STATE_MASK = PLAYER_JUMP then goto HandlePlayerJumpState
    if playerState & PLAYER_STATE_MASK = PLAYER_CLIMB then goto HandlePlayerClimbState

    ;--- when ALL else fails handle the normal state of the player
    goto HandlePlayerNormalState

;----------------------------------------------------------
HandlePlayerHit
    ;gosub HandleSpriteKnockedBack
    ;canMove_bit0{0} = 0     ;-- stop player from moving (stunned)
    ;goto _handle_player_world_interactions

    if (playerTimer <> 0) then goto _cont_player_hit
        playerState = playerState & CLEAR_PLAYER_STATE
        goto HandlePlayerNormalState
_cont_player_hit
    
    canMove_bit0{0} = 0     ;-- stop player from moving (stunned)
    goto _handle_player_world_interactions

;----------------------------------------------------------
HandlePlayerFallState
    if (playerTimer <> 0) then goto _player_handle_action_timer
	playerState = playerState & PLAYER_CLEAR_ACTION_MASK
	canMove_bit0{0} = 0
    goto _player_handle_action_timer

;----------------------------------------------------------
HandlePlayerDuckState
    if !isDownPressed_bit6{6} then goto _stop_ducking
    canMove_bit0{0} = 0

    ;-- check if at exit on bottom
    ;-- TODO: fix transition
    if playerTimer = 0 && currentScreen = 0 && player0y = 0x1F then goto nextScreenDown
    goto _player_handle_action_timer

_stop_ducking
    playerState = playerState & CLEAR_PLAYER_STATE
    playerTimer = 0
    goto _player_handle_action_timer

;----------------------------------------------------------
HandlePlayerClimbState
    if isUpPressed_bit5{5} then player0y = player0y + 1
    if isDownPressed_bit6{6} then player0y = player0y - 1

    if player0y > 0xA8 then goto nextScreenUp

    ;--- handle switching player facing direction
    ;---   to create the two climbing frames from a single graphics frame
    playerState = playerState & DIR_MASK
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
        if !isFirePressed_bit7{7} then _cont_player_jump
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
        if !isUpPressed_bit5{5} then _skip_player_jump_check
        playerTimer = JUMP_TIMER
        playerState = playerState | PLAYER_JUMP

_skip_player_jump_check


    ;-- check for player actions (kicking / punching)
    if !isFirePressed_bit7{7} then goto _player_check_for_duck

        ;--- check if player can do an action
        if playerState & PLAYER_ACTION_MASK <> 0 then _player_already_acting
        
        if !isMoving_bit1{1} then playerState = playerState | PLAYER_PUNCH : sndPos = 0 : sndEffect = 2
        if isMoving_bit1{1} then playerState = playerState | PLAYER_KICK_AND_JUMP : playerTimer = PLAYER_MAX_KICK_JUMP
       
        if (playerState & DIR_BIT) = FACE_LEFT then if player0x > 4 then player0x = player0x - 2
        if (playerState & DIR_BIT) <> FACE_LEFT then if player0x < 150 then player0x = player0x + 2

        actionTimer = KICK_TIME
        
_player_already_acting
        canMove_bit0{0} = 0  
        goto _player_handle_action_timer    ;-- SKIP over ducking code (since player is jumping)

    ;---- check to see if player is attempting to duck
_player_check_for_duck
    if !isDownPressed_bit6{6} then _player_not_ducking
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

    if (movementFlags & CAN_AND_IS_MOVING) <> CAN_AND_IS_MOVING then goto _done_player_lr

        ;-- figure out which row is shoulder-level with player
        ;--   (for checking for a blocking wall)
        temp5 = (player0y - 7) / 8
        temp5 = screenKernelType[temp5] & 0xF0      ;will either be 0x10 or 0x20
	
        if !isMovingRight_bit4{4} then _player_moving_left
            playerState = playerState & FACE_RIGHT
            if player0x >= 152 then _done_player_lr ;-- block at far right
            player0x = player0x + 1

            ;--- IF player at far right AND there's no blocking wall, THEN do screen transition
            if player0x < 152 then goto _done_player_lr
            if temp5 >= 0x10 then goto _done_player_lr 
            goto nextScreenRight
            
_player_moving_left	
            playerState = playerState | FACE_LEFT
            if player0x < 1 then _done_player_lr  ;-- block at far left
            
            player0x = player0x - 1

            ;--- IF player at far left AND there's no blocking wall, THEN do screen transition
            if player0x <> 0 then goto _done_player_lr
            if temp5 = 0x20 then goto _done_player_lr
            goto nextScreenLeft

_done_player_lr


    ;------------------------------------------------------------
_handle_player_world_interactions

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
    gosub CheckForBackground bank4
    
    ;---------------------------------------------------------------------------
    ; apply gravity if player is not standing on ground or jumping / climbing
    ;   or trigger climbing state if player interacts with a ladder

    if playerState >= PLAYER_JUMP then goto _player_already_jumping
    if temp5 = 0 then goto _player_on_ground
			
    if playerState & PLAYER_STATE_MASK <> PLAYER_FALL then playerTimer = FALL_COOLDOWN
	playerState = (playerState & CLEAR_PLAYER_STATE) | PLAYER_FALL

	if mainTimer & 1 = 1 then player0y = player0y - 1
    return thisbank

    ;---------------------------------------------
    ;if player is on ground

_player_on_ground
    playerState = playerState & CLEAR_PLAYER_FALL
	if playerState & PLAYER_STATE_MASK <> PLAYER_DUCK then return thisbank

    if !isLadder_bit2{2} then return thisbank
    playerState = (playerState & CLEAR_PLAYER_STATE) | PLAYER_CLIMB
    return thisbank

    ;---------------------------------------------------
    ;-- WHEN the player is jumping or climbing,
	;--   check if player is interacting with a ladder
	;--   and set CLIMB state appropriately

_player_already_jumping
    if !isLadder_bit2{2} then goto _stop_climbing
    playerState = playerState | PLAYER_CLIMB
    return thisbank
		
_stop_climbing
    if playerState & PLAYER_CLIMB = PLAYER_CLIMB then playerState = playerState & CLEAR_PLAYER_CLIMB
    return thisbank


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
    const COL_BRUCELEE_HURT    = <(ct_red-SpriteColorTables)


;------------------------
;---- animate player

HandlePlayerAnimation
    player0pal = COL_BRUCELEE

    ;if playerState & PLAYER_STATE_MASK = PLAYER_HIT then goto SetPlayerFrame

    playerFrame = FRM_BRUCE_STANDING

    ;-- normal running
    if movementFlags & CAN_AND_IS_MOVING = CAN_AND_IS_MOVING then temp5 = mainTimer & 0x7 : playerFrame = bruceRunningFrames[temp5]

    ;--- action animation (NOTE: order is important!)
    ;---     if player is jumping, that overrides the punch animation
    ;--        since player shouldn't be able to punch when jumping)
    if playerState & PLAYER_ACTION_MASK = PLAYER_PUNCH then playerFrame = FRM_BRUCE_PUNCH
    if playerState & PLAYER_STATE_MASK = PLAYER_JUMP then playerFrame = FRM_BRUCE_RUNNING_2
    if playerState & PLAYER_ACTION_MASK = PLAYER_KICK then playerFrame = FRM_BRUCE_JMP_KICK

    ;--- ducking animation
    if playerState & PLAYER_STATE_MASK <> PLAYER_DUCK then _player_no_ducking_animation		
    if playerTimer < 6 then playerFrame = FRM_BRUCE_DUCKING_2 : player0pal = COL_BRUCELEE_DUCK2
    if playerTimer >= 6 then playerFrame = FRM_BRUCE_DUCKING_1 : player0pal = COL_BRUCELEE_DUCK1
_player_no_ducking_animation

    ;--- falling animation
    if playerState & PLAYER_STATE_MASK = PLAYER_FALL then if playerFrame = 0 then playerFrame = FRM_BRUCE_FALLING

    ;--- climbing animation (mostly handled in the HandlePlayerClimbState)
    if playerFrame < FRM_BRUCE_JMP_KICK then if playerState & PLAYER_STATE_MASK = PLAYER_CLIMB then playerFrame = FRM_BRUCE_CLIMBING

    if playerState & PLAYER_STATE_MASK = PLAYER_HIT then player0pal = ((mainTimer & 2) / 2) + COL_BRUCELEE_HURT

    ;--- setup player frame
SetPlayerFrame
    player0pointerlo = _player_gfx_lo[playerFrame]
    player0pointerhi = _player_gfx_hi[playerFrame]
    player0height = 17
    return thisbank




;=======================================================
;-- general code and data for handling enemies


/*
    dim movementFlags = temp1
    dim canMove_bit0 = temp1
    dim isMoving_bit1 = temp1
    dim isLadder_bit2 = temp1
*/

    ;-------------------------------------------------------
    ;-- shared temp vars used in enemy subroutines

    dim enemyState = temp2
    dim deltaX = temp3
    dim deltaY = temp4

;--- handle moving an enemy (curSprite), requires movementFlags in temp1
MoveEnemy
    enemyState = spriteStates[curSprite]

    if !canMove_bit0{0} then goto _done_move_enemy_lr
	if enemyState & DIR_BIT = FACE_LEFT then goto _move_enemy_left
	    if player0x[curSprite] < 150 then player0x[curSprite] = player0x[curSprite] + 1
	    goto _done_move_enemy_lr
_move_enemy_left
	    if player0x[curSprite] >= 6 then player0x[curSprite] = player0x[curSprite] - 1
_done_move_enemy_lr

    gosub CheckForBackground bank4
    
    ;-- apply gravity
    if temp5 = 0 then goto _enemy_on_ground

        ;-- check if enemy is flying thru the air (knocked back), IF SO, skip gravity
        if enemyState & ENEMY_STATE_MASK = ENEMY_KNOCK_BACK then goto _enemy_on_ground

        if curSprite <> SN_YAMO then _not_yamo_for_gravity
            if enemyState & ENEMY_STATE_MASK = ENEMY_ATTACK then goto _enemy_on_ground    
_not_yamo_for_gravity

        enemyState = (enemyState & DIR_BIT) | ENEMY_FALL
        if mainTimer & 0x1 = 1 then player0y[curSprite] = player0y[curSprite] - 1
        goto _done_enemy_move

_enemy_on_ground    ;-- also YAMO in JUMP ATTACK / KNOCK BACK state
        if enemyState & ENEMY_STATE_MASK <> ENEMY_FALL then goto _done_enemy_move
        enemyState = (enemyState & DIR_BIT) | ENEMY_WAIT
        spriteTimers[curSprite] = #ENEMY_FALL_WAIT_TIMER

_done_enemy_move

    ;-- save enemy state
    spriteStates[curSprite] = enemyState
    return


;=======================================================
;-- Player / Enemy Interactions
;-------------------------------------------------------

CheckForPlayerHitEnemy
    enemyState = spriteStates[curSprite]

    if enemyState & ENEMY_STATE_MASK = ENEMY_KNOCK_BACK then goto _enemy_not_hit
    if ((player0y[curSprite] - player0y) + 6) >= 12 then goto _enemy_not_hit

    deltaX = (player0x[curSprite] - player0x)
    if (deltaX + 4) >= 8 then goto _enemy_not_hit

    ;-- need to use player facing direction to determine if Yamo is hit or not
    if playerState & DIR_BIT <> FACE_LEFT then if deltaX > $F0 then goto _enemy_not_hit
    if playerState & DIR_BIT =  FACE_LEFT then if deltaX < $10 then goto _enemy_not_hit

        ;-- Sound FX: Enemy Hit
        sndPos = 0 : sndEffect = 2
        
        ;-- knock enemy back
        enemyState = ENEMY_KNOCK_BACK
        if deltaX < $10 then enemyState = enemyState | FACE_LEFT

        spriteStates[curSprite] = enemyState
        spriteTimers[curSprite] = #YAMO_ATTACK_WAIT_TIME
        
        ;---- score the move according to the player action
        if playerState & PLAYER_ACTION_MASK = PLAYER_PUNCH then score = score + 100 else score = score + 75

_enemy_not_hit
    return thisbank


;=======================================================
;--- Check if player is hit by enemy
;-------------------------------------------------------


CheckIfEnemyHitPlayer
    enemyState = spriteStates[curSprite]

    ;-- skip out if enemy is not attacking, player already hit, OR player is ducking
    if enemyState & ENEMY_STATE_MASK <> ENEMY_ATTACK then goto _enemy_did_not_hit
    if playerState & PLAYER_STATE_MASK = PLAYER_HIT then goto _enemy_did_not_hit
    if playerState & PLAYER_STATE_MASK = PLAYER_DUCK then goto _enemy_did_not_hit

    ;-- check if within range
    if ((player0y[curSprite] - player0y) + 6) >= 12 then goto _enemy_did_not_hit
    deltaX = (player0x[curSprite] - player0x)
    if (deltaX + 4) >= 8 then goto _enemy_did_not_hit

    ;-- need to use player facing direction to determine if hit or not
    if playerState & DIR_BIT <> FACE_LEFT then if deltaX >= 12 then goto _enemy_did_not_hit
    if playerState & DIR_BIT =  FACE_LEFT then if deltaX < $F4 then goto _enemy_did_not_hit

        ;-- Sound FX: Player Hit
        sndPos = 0 : sndEffect = 2

        playerState = (playerState & CLEAR_PLAYER_STATE) | PLAYER_HIT
        playerTimer = WAIT_PLAYER_STUNNED

_enemy_did_not_hit
    return thisbank



;------------------------------------------------------------------
;--  Handle when sprite is knocked back after attack

    data recoverTimeTbl
    20, 40, 60
end

    data knockedFrames
    FRM_BRUCE_FALLING, FRM_NINJA_ATTACK_2, FRM_YAMO_KICK
end

HandleSpriteKnockedBack
    spriteFrames[curSprite] = knockedFrames[curSprite]

    if mainTimer & 0x1 = 0 then return thisbank      ;-- only 30 fps for being knocked back

    ;-- Handle jump portion of being knocked back
	if spriteTimers[curSprite] < HALF_JUMP_CNT then player0y[curSprite] = player0y[curSprite] - 1 : goto _done_with_enemy_in_air
    if spriteTimers[curSprite] < JUMP_CNT      then player0y[curSprite] = player0y[curSprite] + 1
_done_with_enemy_in_air

    if spriteStates[curSprite] & DIR_BIT <> FACE_LEFT then if player0x[curSprite] > 0 then player0x[curSprite] = player0x[curSprite] - 1
    if spriteStates[curSprite] & DIR_BIT = FACE_LEFT  then if player0x[curSprite] < 150 then player0x[curSprite] = player0x[curSprite] + 1

    if spriteTimers[curSprite] > 0 then return thisbank

    ;-- done, prep for next move
    spriteStates[curSprite] = spriteStates[curSprite] & CLEAR_ENEMY_STATE
    spriteTimers[curSprite] = recoverTimeTbl[curSprite]

    return thisbank


;=======================================================
;-- Black Ninja
;-------------------------------------------------------


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

    ;---- check for Black Ninja being hit
    temp2 = playerState & PLAYER_ACTION_MASK
    if temp2 = PLAYER_PUNCH || temp2 = PLAYER_KICK then gosub CheckForPlayerHitEnemy thisbank

    if blackNinjaState & ENEMY_STATE_MASK = ENEMY_KNOCK_BACK then gosub HandleSpriteKnockedBack : goto MoveEnemy
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

    ;-- check if we've hit player (TODO: add timer condition?)
    gosub CheckIfEnemyHitPlayer

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
	blackNinjaState = blackNinjaState & DIR_MASK
	if blackNinjaX >= player0x then blackNinjaState = blackNinjaState | FACE_LEFT
	blackNinjaState = blackNinjaState | ENEMY_RUN
    blackNinjaTimer = NINJA_RUN_TIMER
    return


;---------------------------------------------------------------
;--  Handle when Black Ninja is running and potentially attacks


HandleBlackNinjaRun
    temp3 = blackNinjaTimer & 0x7
    blackNinjaFrame = blackNinjaRunningFrames[temp3]

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
	blackNinjaState = (blackNinjaState & CLEAR_ENEMY_STATE) | ENEMY_ATTACK
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


InitYamo
    player2pal = COL_YAMO

    yamoX = 140
    yamoY = 30 ;144
    yamoState = 0
    yamoTimer = YAMO_WAIT_TIMER    ;-- initial wait timer
    return


;---------------------------------------

SetYamoFrame
    player2pointerlo = _yamo_gfx_lo[yamoFrame]
    player2pointerhi = _yamo_gfx_hi[yamoFrame]
    player2height = 17
    return


;---------------------------------------

HandleYamo
    curSprite = 2       ;-- make sure to indicate to other subroutines that we're working with Yamo
    movementFlags = 0

    if yamoTimer <> 0 then yamoTimer = yamoTimer - 1

    yamoFrame = FRM_YAMO_STANDING
    canMove_bit0{0} = 0

    ;---- check for Yamo being hit
    temp2 = playerState & PLAYER_ACTION_MASK
    if temp2 = PLAYER_PUNCH || temp2 = PLAYER_KICK then gosub CheckForPlayerHitEnemy thisbank


    ;--- handle yamo state

    if yamoState & ENEMY_STATE_MASK = ENEMY_KNOCK_BACK then gosub HandleSpriteKnockedBack : goto MoveEnemy
    if yamoState & ENEMY_STATE_MASK = ENEMY_WAIT then if yamoTimer = 0 then goto HandleYamoNextMove
    if yamoState & ENEMY_STATE_MASK = ENEMY_RUN then goto HandleYamoRun
    if yamoState & ENEMY_STATE_MASK = ENEMY_ATTACK then goto HandleYamoAttack
    goto MoveEnemy

;---------------------------------------------------------------
;--  Handle when Yamo is ready to make next move

HandleYamoNextMove
	yamoState = yamoState & DIR_MASK;
	if yamoX >= player0x then yamoState = yamoState | FACE_LEFT
	yamoState = yamoState | ENEMY_RUN
    yamoTimer = YAMO_RUN_TIMER
    return


;---------------------------------------------------------------
;--  Handle when Yamo is running and potentially attacks

    const YAMO_ATTACK_DIST = 20
    const YAMO_ATTACK_DIST_X2 = 40

HandleYamoRun


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
	yamoState = (yamoState & CLEAR_ENEMY_STATE) | ENEMY_ATTACK
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

    ;-- check if we've hit player (TODO: add timer condition?)
    gosub CheckIfEnemyHitPlayer

    temp4 = yamoState & DIR_BIT   ; FACE_LEFT

_handle_yamo_jump
    ;-- Handle jump portion of attack
	if yamoTimer < YAMO_HALF_JUMP_CNT then yamoY = yamoY - 1 else if yamoTimer < YAMO_JUMP_CNT then yamoY = yamoY + 1
		
	;-- Move yamo in direction he is facing
	if temp4 = 0 then goto _yamo_attack_right
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







;====================================================================================
;--  Bank 2 - Sound + Levels
;--
    bank 2




;-------------------------------------------------------------------------
;-- Check goal:

CheckGoal
    if currentGoal = GOAL_COLLECT_VILLAGE_LANTERNS then goto CheckCollectedLanterns
    return




;--------------------------------------------------------------------------
;--- Sound effect engine
;--------------------------------------------------------------------------
;-- To play a sound, simply:
;       set sndEffect to desired value
;       set sndPos to 0

PlaySound
    if sndEffect = 0 then return
    if sndPos = 0 then sndPos = sndStartOfs[sndEffect]

    temp1 = sndData[sndPos]
    AUDC0 = temp1 / 16
    if temp1 <> 0 then sndPos = sndPos + 1
    AUDF0 = sndData[sndPos]
    AUDV0 = temp1 & 0xf
    sndPos = sndPos + 1

    ;-- check if done with sound effect
    if temp1 = 0 then sndEffect = 0 : sndPos = 0
    return

    data sndStartOfs
    0, 1, 6, 0xB, 0x10
end

    data sndData
    0
    $49, $18    ;-- collected lantern sound
    $49, $0F
    0
    $89, $1F    ;-- punch
    $89, $1C
    0
    $C5, $15
    $C5, $10
    0
    $49, $18    ;-- screen cleared
    $49, $18
    $49, $16
    $49, $12
    $49, $18
    $49, $0F
    0, 0
end



;-------------------------------------------------------------------------
;---- define screens
;-------------------------------------------------------------------------


    data levelBgData                    ;-- background colors for above ground
    0x05,0x07,0x07,0x07,0x07,0x07
	0x07,0x07,0x07,0x07,0x07,0x07
	0x05,0x05,0x04,0x04,0x04
	_Color_Blue_Sky,_Color_Blue_Sky,_Color_Blue_Sky

    _Color_GardenBG+1,_Color_GardenBG+1,_Color_GardenBG+1,_Color_GardenBG+1  ;-- underground garden
    _Color_GardenBG+1,_Color_GardenBG+1,_Color_GardenBG+1,_Color_GardenBG+1
    _Color_GardenBG+1,_Color_GardenBG+1,_Color_GardenBG+1,_Color_GardenBG+1
    _Color_GardenBG+1,_Color_GardenBG+1,_Color_GardenBG+1,_Color_GardenBG+1
    _Color_GardenBG+1,_Color_GardenBG+1,_Color_GardenBG+1,_Color_GardenBG+1
end

    data textColor
    _00, _00, _00, _0A
end
    
	
    data levelData
    0x08, 0x10,0x10,0x10,0x10,0  ;//-- Screen 1 from original game
    0x08, 0x50,0x50,0x50,0x50,0  ;-- asym
    0x00, 0x00,0x00,0x00,0x00    ;--asym
    0x00, 0x00,0x00

    0x08, 0x10,0x10,0x10,0x10,0  ;//-- Screen 2 from original game
    0x20, 0x00,0x00,0x00,0x00,0
    0x28, 0x00,0x00,0x00,0x00
    0x00, 0x00,0x00

    0x08, 0x10,0x10,0x00,0x00,0  ;//-- Screen 3 from original game
    0x30, 0x00,0x00,0x00,0x00,0 ;--asym
    0x18, 0x00,0x00,0x00,0x00   ;--asym
    0x00, 0x00,0x00

    0x38, 0x18,0x18,0x18,0x18,0
    0x28, 0x18,0x18,0x18,0x18,0
    0x20, 0x18,0x18,0x18,0x18,0
    0x20, 0x10
end

    data levelDataStartOfs  ;-- offset into screen data table
    0, 20, 40, 60
end
    data levelDataAreaTbl   ;-- offset into area data tables
    0, 0, 0, 20
end
    data levelConfigTbl     ;-- kernel configuration byte
    0, 0, 0, 3
end

    ;--- default level row type data for mountain screens
    const KT_BKGROUND      = 0          ;--   0 = background / decoration
    const KT_PLATFORM      = 8         ;--    8 = platform/ground
    const KT_RT_WALL       = 0x12      ;-- 0x12 = wall on right
    const KT_LR_WALL       = 0x22      ;-- 0x22 = wall on left & right
    const KT_WALL          = 0x60
    const KT_ASYM_PLAT_ROW = 0x40      ;-- 0x60 = asymmetric kernel
    const KT_ASYM_PLAT     = 0x48      ;-- 0x68 = asymmetric platform kernel
    const KT_LANTERN       = 0x80      ;-- 0x80 = lantern kernel (PF0, PF1)
    const KT_LANTERN2      = 0xC0      ;-- 0xC0 = lantern kernel (PF1, PF2)
    const KT_MOUNTAINS     = 0xF0      ;-- 0xF0 = mountains / decorative bg

    data screenPlatformKernelTbl
    KT_PLATFORM,  KT_ASYM_PLAT, KT_ASYM_PLAT, KT_MOUNTAINS  ;-- screen1
    KT_PLATFORM,  KT_PLATFORM,  KT_PLATFORM,  KT_MOUNTAINS  ;-- screen2
    KT_PLATFORM,  KT_PLATFORM,  KT_ASYM_PLAT, KT_MOUNTAINS  ;-- screen3
    KT_PLATFORM,  KT_ASYM_PLAT+6, KT_ASYM_PLAT+6, 0             ;-- screen4
end


    data levelRowTypes
    KT_PLATFORM,  KT_LR_WALL,   KT_LR_WALL,   KT_LR_WALL,   KT_LR_WALL,  KT_LANTERN+4
    KT_PLATFORM,  KT_BKGROUND,  KT_BKGROUND,  KT_BKGROUND,  KT_BKGROUND, KT_LANTERN
    KT_PLATFORM,  KT_BKGROUND,  KT_BKGROUND,  KT_BKGROUND,  KT_BKGROUND
    0,            KT_MOUNTAINS, KT_BKGROUND

    KT_PLATFORM,  KT_WALL+12,   KT_WALL+12,   KT_WALL+12,   KT_WALL+12,  KT_LANTERN2+8
    KT_PLATFORM,  KT_WALL+6,    KT_WALL+6,    KT_WALL+6,    KT_WALL+6,   KT_LANTERN+4
    KT_PLATFORM,  KT_WALL,      KT_WALL,      KT_WALL,      KT_WALL,     KT_LANTERN
    KT_BKGROUND,  KT_PLATFORM
end

;---------------------------------------------------
;--- lantern data for screens

    data screen_lanternPos      ;-- high nibble = byte, low nibble = bit position
    0x24, 0x35, 0x46, 0x60, 0x62, 0x75
    0x17, 0x27, 0x56, 0x51, 0x66, 0x61
    0x00, 0x04, 0x22, 0x30, 0x34, 0x40, 0x44, 0x54, 0x64, 0x70

    0x06, 0x15, 0x20, 0x24, 0x35, 0x62, 0xA0, 0xB4      ;-- underground
end

    data screenLanternCount
    6, 6, 10, 8, 0
end
    data screenLanternDataOfs
    0, 6, 12, 22, 0
end
    data lanternBit
    1,2,4,8,16,32,64,128
end

;---------------------------
;-- wall data
;--  FOR EACH WALL SET
;--    size in bytes (rows * 6)
;--    data for each row (6 per row)

    data wallDataTbl
    0
    18
      $10,0,0,0,$08,$10
      $10,0,0,0,$10,$10
      $10,0,0,0,$20,$10
    12
      0,0,0,0,0,$10
      $10,0,0,0,$10,$10
end


    ;--- offset into wall data table for each screen
    data wallOfsTbl
    0,0,20,1
end


LoadLevel
    dim levelDataOfs = temp2
    dim areaTypeOfs = temp3
    dim highWallStyle = temp4

    ;---- clear superchip RAM
    for temp1 = 0 to 127
        writeScreenData[temp1] = 0
    next temp1

    ;-- set level data offset base on level number    
    levelDataOfs = levelDataStartOfs[currentScreen]
    areaTypeOfs = levelDataAreaTbl[currentScreen]
    kernelConfig = levelConfigTbl[currentScreen]
    scorecolor = textColor[currentScreen]

    ;--- store screen data in SuperchipRAM
    for temp1 = 0 to 20
		writeScreenData[temp1]	  = levelData[levelDataOfs] | 0x7
		writeScreenBgColor[temp1] = levelBgData[areaTypeOfs]
        writeScreenKernelType[temp1] = levelRowTypes[areaTypeOfs]
        levelDataOfs = levelDataOfs + 1
        areaTypeOfs = areaTypeOfs + 1
	next

    ;-- asymmetric platform rows
    temp3 = currentScreen * 4
    temp2 = 0
    for temp1 = 0 to 3
        writeScreenKernelType[temp2] = screenPlatformKernelTbl[temp3]
        temp3 = temp3 + 1
        temp2 = temp2 + 6
    next

    gosub LoadLanterns

    ;--- Load Playfield data for Walls
LoadWalls
    dim wallTblIdx = temp2
    wallTblIdx = wallOfsTbl[currentScreen]
    if wallTblIdx = 0 then goto _skip_load_walls

    temp3 = wallDataTbl[wallTblIdx]
    wallTblIdx = wallTblIdx + 1

    for temp1 = 0 to temp3
        writeScreenWallPF[temp1] = wallDataTbl[wallTblIdx]
        wallTblIdx = wallTblIdx + 1
    next
    ;if currentScreen <> 5 then goto _skip_load_walls
    ;for temp1 = 1 to 4
    ;    writeScreenKernelType[temp1] = KT_WALL + 6
    ;    temp2 = temp1 + 6
    ;    writeScreenKernelType[temp2] = KT_WALL + 6
    ;    temp2 = temp2 + 6
    ;    writeScreenKernelType[temp2] = KT_WALL
    ;next
_skip_load_walls

    ;--- missile 1 is used for blocking walls
    missile1x = 159

    ballx = 136 - 10

    ;--- experiment to enable blocking walls on the screen edges
    ;------------------------------------------------------------------------
    ;--- since we have just a few screens, handle the differences here

    ;-- do high wall
    if currentScreen = 3 then goto _skip_screen2_block 

    highWallStyle = 0
    if currentScreen = 1 then highWallStyle = KT_RT_WALL  ;-- screen 1 has higher wall only on right
    if currentScreen = 2 then highWallStyle = KT_LR_WALL

    ;if currentScreen = 2 then goto _skip_this_block_for_Screen2
    writeScreenKernelType[7]  = highWallStyle
    writeScreenKernelType[8]  = highWallStyle
    writeScreenKernelType[9]  = highWallStyle
    writeScreenKernelType[10] = highWallStyle
_skip_this_block_for_Screen2

    if currentScreen <> 2 then _skip_screen2_block
    writeScreenKernelType[13]  = KT_RT_WALL
    writeScreenKernelType[14]  = KT_RT_WALL
    writeScreenKernelType[15]  = KT_RT_WALL
    writeScreenKernelType[16]  = KT_RT_WALL

    writeScreenKernelType[11]  = KT_LANTERN2
    writeScreenKernelType[5]   = KT_LANTERN2+4
_skip_screen2_block

    gosub SpawnEnemy

    return



;-------------------------------------------------------------------------
;-- Handle electro field

    dim electroX = ballx

    ;--- areas where hazard is visible
    ;---   byte 1 = row
    ;---   byte 2 = min x
    ;---   byte 3 = max x
    ;---   byte 4 - padding

    data hazardAreaTbl
    12, 0x03, 0x15, 0
    6,  0x6C, 0x80, 0
    0
end

    data electroMoveTbl
    0, -3, 2, -1
    0, -5, 3, -2
end

MoveElectroFields
    if currentScreen <> 3 then return

    temp1 = (mainTimer & 0x7)
    electroX = electroX + electroMoveTbl[temp1]
    if electroX >= $F8 then electroX = 159

    ;---  now display hazard for appropriate row
    dim hazTblIdx = temp1
    dim hazRow    = temp2
    dim hazData   = temp3

    hazData = 6
    hazTblIdx = 0
_handle_next_hazard_area
    hazRow = hazardAreaTbl[hazTblIdx]
    if hazRow = 0 then goto _done_with_hazards

    ;-- read in current kernel type
    hazData = screenKernelType[hazRow] & 0xF8

    ;-- check if within range
    hazTblIdx = hazTblIdx + 1
    if electroX < hazardAreaTbl[hazTblIdx] then _no_hazard
    hazTblIdx = hazTblIdx + 1
    if electroX >= hazardAreaTbl[hazTblIdx] then _no_hazard

    ;-- turn on hazard (ENAxx) for row
    hazData = hazData | 2

_no_hazard
    writeScreenKernelType[hazRow] = hazData

    ;-- move to next hazard definiton
    hazTblIdx = (hazTblIdx & 0xFC) + 4
    goto _handle_next_hazard_area

_done_with_hazards
    return



;-------------------------------------------------------------------------
;-- Spawn enemy

    data enemySpawnPosTblX
    20, 60, 100, 140,  20, 60, 100, 140,    20,  60, 100, 140
end
    data enemySpawnPosTblY
    30, 30, 30, 30,    90, 90,  90,  90,   144, 144, 144, 144
end

    data ninjaSpawnLocs
    0, 0, 0, 8
end

SpawnEnemy
    dim idx = temp2
    idx = ninjaSpawnLocs[currentScreen]
    blackNinjaX = enemySpawnPosTblX[idx]
    blackNinjaY = enemySpawnPosTblY[idx]    
    return




;-------------------------------------------------------------------------
;--- draw lanterns into SuperchipRAM

    data ltnScrBit      ;screen cleared bits for:
    1,2,4, 0,0,0,0,0    ;--- village
end

    data scrnInvIdx     ;screen inventory index for lanternInvBits array
    0,1,2               ;--- village
    4                   ;--- garden
end

    dim lanternCount = temp2
    dim lanternDataOfs = temp3
    dim lanternData = temp4
    dim lanternBytePos = temp5

    ;---- variables to keep track of lantern inventrory
    dim ltnInvIdx = temp8   ;-- lantern inventory index
    dim ltnInvBit = temp9   ;-- lantern inventory bit

LoadLanterns
    ;-- check if lanterns even need to be loaded (in case player already got them all)
    lanternData = ltnScrBit[currentScreen] & lanternScreensCleared
    if lanternData <> 0 then _skip_loading_lanterns

    lanternDataOfs = screenLanternDataOfs[currentScreen]
    lanternCount = screenLanternCount[currentScreen]
    if lanternCount = 0 then _skip_loading_lanterns

    ;---- set the lantern inventory index/bit position for the current screen
    ltnInvIdx = scrnInvIdx[currentScreen]
    ltnInvBit = 1

    ;-- draw each lantern individually
    for temp1 = 1 to lanternCount

        ;-- check if lantern is still there
        if lanternInvBits[ltnInvIdx] & ltnInvBit <> 0 then goto _next_lantern_byte

        ;-- read lantern position byte
        lanternData = screen_lanternPos[lanternDataOfs]
        
        ;-- decode position
        lanternBytePos = lanternData / 16       ;-- which PF byte
        lanternData = lanternData & 7
        lanternData = lanternBit[lanternData]   ;-- which bit

        ;-- draw lantern into correct PF byte
        writeScreenLanternsPF[lanternBytePos] = screenLanternsPF[lanternBytePos] | lanternData

_next_lantern_byte
        lanternDataOfs = lanternDataOfs + 1

        ltnInvBit = ltnInvBit * 2
        if ltnInvBit = 0 then ltnInvBit = 1 : ltnInvIdx = ltnInvIdx + 1
    next

_skip_loading_lanterns
    return



;-------------------------------------------------------------------------
;-- Check all lanterns player collected

    dim lanternsOnScreen = temp2
    ;dim lanternData = temp4        ;-- already defined above


CheckCollectedLanterns
    ;---make sure screen hasn't already been cleared
    lanternData = ltnScrBit[currentScreen] & lanternScreensCleared
    if lanternData <> 0 then return

    ;----  scan for any lanterns on screen
    lanternsOnScreen = 0
    for temp1 = 1 to 8
        lanternData = screenLanternsPF[temp1]
        lanternsOnScreen = lanternsOnScreen | lanternData
    next

    if lanternsOnScreen <> 0 then goto SaveLanternsCollected

    ;-- play sound for collecting ALL lanterns on screen
    sndPos = 0 : sndEffect = 4
    score = score + 2000

    ;-- mark screen as being cleared
    ;--  then, if player finished village lantern collection, move on to next goal
    lanternScreensCleared = ltnScrBit[currentScreen] | lanternScreensCleared    
    if lanternScreensCleared = 7 then currentGoal = GOAL_GARDEN_GATE_1

    return


    ;-----------------------------------------------------------
    ;-- Save lanterns collected into inventory

SaveLanternsCollected
    lanternDataOfs = screenLanternDataOfs[currentScreen]
    lanternCount = screenLanternCount[currentScreen]

    ;---- set the lantern inventory index/bit position for the current screen
    ltnInvIdx = scrnInvIdx[currentScreen]
    ltnInvBit = 1

    ;--- scan thru initial lantern position table and check to see if still on screen
    for temp1 = 1 to lanternCount
        
        ;-- first check if lantern is already marked in inventory
        if lanternInvBits[ltnInvIdx] & ltnInvBit <> 0 then goto _next_saved_lantern_byte

        ;-- read lantern position byte
        lanternData = screen_lanternPos[lanternDataOfs]
        
        ;-- decode position
        lanternBytePos = lanternData / 16       ;-- which PF byte
        lanternData = lanternData & 7
        lanternData = lanternBit[lanternData]   ;-- which bit

        ;-- if lantern was taken, mark it in the inventory
        if screenLanternsPF[lanternBytePos] & lanternData <> 0 then goto _next_saved_lantern_byte
        lanternInvBits[ltnInvIdx] = lanternInvBits[ltnInvIdx] | ltnInvBit

_next_saved_lantern_byte
        lanternDataOfs = lanternDataOfs + 1

        ltnInvBit = ltnInvBit * 2
        if ltnInvBit = 0 then ltnInvBit = 1 : ltnInvIdx = ltnInvIdx + 1

    next
    return


;--------------------------------------------------------------------
/**
 *    Check Lanterns - Check if player grabbed one of the lanterns
 *
 *  NOTE:  Currently only handles bottom row of lanterns
 */
    data lantBumpPfTbl          ;-- this is which lantern byte to read (middle of screen doesn't have any)
    0,1,1,-1,-1,-1,-1,2,2,3     ;-- PF0/PF1
    -1,0,0,1,1,2,2,3,3,-1       ;-- PF1/PF2
end
    data lpfBitmask             ;-- this is which lantern bit to read
	16,32,64,128,128,64,32,16
	8,4,2,1,1,2,4,8
end

    ;--- Lantern position data (4 bytes)
    ;--    Data Row #,
    ;--    Min Y Bound,
    ;--    Max Y Bound,
    ;--    Screen Row
    data lanternPos
    4, 0x24, 0x28, 5
    0, 0x54, 0x58, 11
    0xFF,0,0,0

    8, 0x24, 0x28, 5
    4, 0x54, 0x58, 11
    0, 0x84, 0x88, 17
    0xFF
end

    
CheckLanterns
    dim lanternIdx = temp1
    dim bumpX = temp1
    dim bumpRow = temp2     ;-- which lantern row to read
    dim bumpRowOfs = temp3  ;-- offset into bump byte table (based on kernel type for row)

    dim bumpPF = temp4      ;-- which PF byte to check
    dim bumpBitX = temp5    ;-- which bit to check
    dim bumpData = temp5
    dim bumpMask = temp6

    ;--- make sure player is hitting lantern row
    ;if player0y < 0x24 || player0y > 0x28 then return

;---> TODO: figure out which lantern row to check
    lanternIdx = 0
    if currentScreen = 3 then lanternIdx = 12

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
    lanternIdx = lanternIdx + 1
    bumpRowOfs = lanternPos[lanternIdx]
    if screenKernelType[bumpRowOfs] >= 0xC0 then bumpRowOfs = 10 else bumpRowOfs = 0

    bumpX = (player0x + 1) / 4

    ;---------------------------------------------
    ;-- check for first bit

_check_lantern_bit          ;-- this should be done twice

    ;-- figure out which PF byte to check
    bumpPF = (bumpX / 4) + bumpRowOfs ;--- +10 if PF1/PF2 type of lantern row
    bumpPF = lantBumpPfTbl[bumpPF]

    if bumpPF >= 0x80 then goto _check_lantern_bit2  ;-- negative number means no byte to check

    bumpPF = bumpPF + bumpRow
    bumpBitX = bumpX & 0x0F
    bumpMask = lpfBitmask[bumpBitX]
    bumpData = screenLanternsPF[bumpPF]

    if bumpData & bumpMask = 0 then goto _check_lantern_bit2

    writeScreenLanternsPF[bumpPF] = (bumpMask ^ 0xFF) & bumpData

    ;-- play sound for collecting lantern
    sndPos = 0 : sndEffect = 1
    score = score + 125

    ;---------------------------------------------
    ;-- check for second bit

_check_lantern_bit2

    bumpX = bumpX + 1
    ;if bumpX >= 39 then return

    ;-- figure out which PF byte to check
    bumpPF = (bumpX / 4) + bumpRowOfs ;--- +10 if PF1/PF2 type of lantern row
    bumpPF = lantBumpPfTbl[bumpPF]

    if bumpPF >= 0x80 then return  ;-- negative number means no byte to check

    bumpPF = bumpPF + bumpRow
    bumpBitX = bumpX & 0x0F
    bumpMask = lpfBitmask[bumpBitX]
    bumpData = screenLanternsPF[bumpPF]

    if bumpData & bumpMask = 0 then return

    writeScreenLanternsPF[bumpPF] = (bumpMask ^ 0xFF) & bumpData

    ;-- play sound for collecting lantern
    sndPos = 0 : sndEffect = 1
    score = score + 125

    return




;--------------------------------------------------------------
;--- Handle Ladder - check if player is on or near a ladder
;--------------------------------------------------------------

    ;--- LADDER structure (4 bytes per ladder):
    ;---     ladder left X,
    ;---     ladder right X,
    ;---     lowest Y point,
    ;---     highest Y point

    data _ladder_screen1
    0x48, 0x4F, 0x28, 0xAE ;-- debug ladder
    0,0,0,0
    0x48, 0x4F, 0x28, 0x7E  ;-- screen 1 ladder
    0,0,0,0
    0x48, 0x4F, 0x28, 0x4E      ;0x3C, 0x60
    0x48, 0x4F, 0x58, 0x7E      ;0x6C, 0x90
    0,0,0,0
end

    data screenLadderOfsTbl
    8, 16, 8, 0
end

;---------------------------------------
    dim playerY   = temp3
    dim ladderX   = temp4
    dim isLadder  = temp5

CheckForLadder
    playerY = player0y
    if isDownPressed_bit6{6} then playerY = playerY - 1

    isLadder = 0

    ;-- current screen determines starting offset
    temp6 = screenLadderOfsTbl[currentScreen]

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




;====================================================================================
;--  Bank 3 - (currently unused)
;--

    bank 3
    temp1 = temp1



;====================================================================================
;--  Bank 4 - bB drawscreen and sprites (and playfield)
;--
;---  NOTE: This should always be the last bank

    bank 4

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
    if (screenKernelType[spriteRow] & 0xF0) = KT_ASYM_PLAT_ROW then goto _bg_asym

    ;----------------------------------------
    ;-- handle symmetric platforms

        ;-- TODO:  currently only handles mirrored playfield (since that is the screen that is implemented)
        if spriteX >= 80 then spriteX = 160 - spriteX

        ;--- now figure out which playfield data chunk we need
        temp5 = screenData[spriteRow] : temp5 = (temp5 & 0xF8) | 5  ;-- always read 5th scanline (avoid)
        if spriteX < 16 then temp5 = bitmapPF0[temp5] : goto _done_with_check_background
        if spriteX < 48 then temp5 = bitmapPF1[temp5] : goto _done_with_check_background
        temp5 = bitmapPF2[temp5] : goto _done_with_check_background

    ;----------------------------------------
    ;-- handle asymmetric platforms
_bg_asym

        ;--- now figure out which playfield data chunk we need
        temp5 = screenData[spriteRow] : temp5 = (temp5 & 0xF8) | 5  ;-- always read 5th scanline (avoid)

        if spriteX < 16 then temp5 = asymPltfrmPF0[temp5] : goto _done_with_check_background
        if spriteX < 48 then temp5 = asymPltfrmPF1[temp5] : goto _done_with_check_background
        if spriteX >= 144 then temp5 = asymPltfrmPF5[temp5] : goto _done_with_check_background
        if spriteX >= 112 then temp5 = asymPltfrmPF4[temp5] : goto _done_with_check_background

        temp5 = asymPltfrmPF2[temp5] : goto _done_with_check_background

    ;--------------------------------------

_done_with_check_background
    spriteX = (spriteX / 4) & 0xF
    temp5 = temp5 & pfBitmask[spriteX]

    ;--- temp5 will not be 0 IF sprite is standing on something
    if temp5 = 0 then temp5 = 1 : return otherbank
    temp5 = 0
    return otherbank



;---
;--- The following macro helps keep sprite graphics contained within a page.
;---
    asm
      MAC PAD_BB_SPRITE_DATA
.SPRITE_HEIGHT  SET {1}
      if	(<*) > (<(*+.SPRITE_HEIGHT))
        align 256
      ;repeat	($100-<*)
      ;.byte	0
      ;repend
      endif
      if (<*) < 80
	   repeat (80-<*)
	   .byte 0
	   repend
	   endif
   ENDM

;-----------------------------------------------------------------------------------
;--  Color tables used for the shared P1 sprite
;
;-- These tables are accessed using the COLUx variable from each sprite as an index
;-- For each row in this table, the first color is the bottom color of the sprite, moving up towards the top

    PAD_BB_SPRITE_DATA 128

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

ct_red:                 .byte _00,_42,_30,_42,_30,_42,_30,_42
                        .byte _30,_42,_30,_42,_30,_42,_30,_42

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

    asm
    PAD_BB_SPRITE_DATA 16
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

    asm
    PAD_BB_SPRITE_DATA 16
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

    asm
    PAD_BB_SPRITE_DATA 16
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
    asm
    PAD_BB_SPRITE_DATA 16
end
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

    asm
    PAD_BB_SPRITE_DATA 16
end
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

    asm
    PAD_BB_SPRITE_DATA 16
end
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
    asm
    PAD_BB_SPRITE_DATA 16
end
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

    asm
    PAD_BB_SPRITE_DATA 16
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

    asm
    PAD_BB_SPRITE_DATA 16
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
    %00100110
    %00110010
    %00010110
    %00011100
    %00001000
    %00011101
    %00111111

    %01111110
    %01011000
    %01011100
    %01010000
    %01001100
    %01000000
    %11111111
    %00100000
    0
end

/*
	// running frame 2 + attack frame 0
	0x88,0x8C,0xC4,0x6C,0x28,0x10,0xB8,0xFC,
	0x7E,0x1A,0x3A,0x0A,0x32,0x02,0xFF,0x04,
*/
    asm
    PAD_BB_SPRITE_DATA 16
end
  data _Ninja_Running2
    0
    %00010001
    %00110001
    %00100011
    %00110110
    %00010100
    %00001000
    %00011101
    %00111111

    %01111110
    %01011000
    %01011100
    %01010000
    %01001100
    %01000000
    %11111111
    %00100000
    0
end


/*
	// running frame 3
	0x30,0x60,0x70,0x38,0x28,0x10,0xB8,0xFC,
	0x7E,0x1A,0x3A,0x0A,0x32,0x02,0xFF,0x04,
*/


    asm
    PAD_BB_SPRITE_DATA 16
end
  data _Ninja_Running3
    0
    %00001100
    %00000110
    %00001110
    %00011100
    %00010100
    %00001000
    %00011101
    %00111111

    %01111110
    %01011000
    %01011100
    %01010000
    %01001100
    %01000000
    %11111111
    %00100000
    0
end

/*
	// running frame 4
	0x30,0x2C,0x38,0x18,0x38,0x10,0xB8,0xFC,
	0x7E,0x1A,0x3A,0x0A,0x32,0x02,0xFF,0x04,
*/
    asm
    PAD_BB_SPRITE_DATA 16
end
  data _Ninja_Running4
    0
    %00001100
    %00110100
    %00011100
    %00011000
    %00011100
    %00001000
    %00011101
    %00111111

    %01111110
    %01011000
    %01011100
    %01010000
    %01001100
    %01000000
    %11111111
    %00100000
    0
end


    asm
    PAD_BB_SPRITE_DATA 17
end
  data _Ninja_Attack1
    0
    %00010001
    %00110001
    %00100011
    %00110110
    %00010100
    %00001000
    %00011101
    %00111111

    %01111110
    %01011000
    %01011100
    %01010000
    %11001100
    %01110000
    %00001111
    0
end

    asm
    PAD_BB_SPRITE_DATA 17
end
  data _Ninja_Attack2
    0
    %00001100
    %00000110
    %00001110
    %00011100
    %00010100
    %00001010
    %00011110
    %00111110

    %01111110
    %01011000
    %01011100
    %11010000
    %11001100
    %00100000
    %00010000
    %00001000
    0
end

    asm
    PAD_BB_SPRITE_DATA 17
end
  data _Ninja_Attack3
    0
    %00110100
    %00011000
    %00111000
    %01110000
    %01010000
    %01100000
    %11110000
    %11111100

    %01101111
    %01100011
    %01110000
    %01000000
    %00110000
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
	
   asm
    PAD_BB_SPRITE_DATA 16
end
  data _Yamo_Running1
    0
    %01000110
    %10001100
    %01111100
    %00111100
    %00111101
    %10111101
    %10111111
    %10111110

    %11111100
    %01111110
    %00011100
    %00011110    
    %00011111
    %00011011
    %00011110
    %01111100    
end

    asm
    PAD_BB_SPRITE_DATA 16
end
  data _Yamo_Running2
    0
    %01101100
    %01001000
    %00111100
    %00111100
    %00111101
    %10111101
    %10111111
    %10111110
    %11111100
    %01111110
    %00011100
    %00011110
    %00011111
    %00011011
    %00011110
    %01111100
end

    asm
    PAD_BB_SPRITE_DATA 16
end
  data _Yamo_Running3
    0
    %00110010
    %00100101
    %00111100
    %00111100
    %00111101
    %10111101
    %10111111
    %10111110
    %11111100
    %01111110
    %00011100
    %00011110
    %00011111
    %00011011
    %00011110
    %01111100
end

  data _Yamo_Kick
    0
    %00111000
    %01100000
    %01111111
    %01111001
    %01111000
    %01111010
    %01111110
    %01111100
    %01111000
    %01111100
    %00111000
    %00111100
    %00111110
    %00110110
    %00111100
    %01111100
    0
end

/*
    data _Bull_Waiting
    0
    %00000001
    %01111000
    %11111101
    %00001110
    %11111110
    %10101111
    %01111111
    %00010011
    %00111111
    %01100110
    %10000001
    0
end
    data _Bull_Shift
    0
    -6
    -1
    0
    0
    1
    1
    2
    4
    0
    0
    0
end
    data _Bull_Size
    0
    0x20
    0x30
    0x30
    0x30
    0x30
    0x30
    0x30
    0x30
    0
    0
    0
end
*/