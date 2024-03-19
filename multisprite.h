; Provided under the CC0 license. See the included LICENSE.txt for details.

; multisprite stuff below - 5 bytes each starting with spritex

SpriteIndex = $80

objectx     = $81
player0x    = objectx
player1x    = objectx + 1
player2x    = objectx + 2
player3x    = objectx + 3

missile0x   = objectx + 4
missile1x   = objectx + 5
ballx       = objectx + 6

objecty     = $88

player0y    = objecty
player1y    = objecty + 1
player2y    = objecty + 2
player3y    = objecty + 3

missile0y   = objecty + 4
missile1y   = objecty + 5
bally       = objecty + 6

player0pal  = $90
_COLUP0     = $90
NewCOLUP1   = $91
player1pal  = NewCOLUP1
player2pal  = NewCOLUP1 + 1
player3pal  = NewCOLUP1 + 2


player0pointer = $94
player0pointerlo = player0pointer
player0pointerhi = player0pointer + 1

player1pointerlo = $96
player1pointerhi = $97
player2pointerlo = $98
player2pointerhi = $99
player3pointerlo = $9A
player3pointerhi = $9B

spriteheight = $9C ; heights of multiplexed player sprite
player0height = $9C
player1height = $9D
player2height = $9E
player3height = $9F

statusbarlength = $A0
pfscorecolor    = $A1
pfscore1        = $A2       ;--- use playfield in score area
pfscore2        = $A3
lifecolor       = pfscorecolor
lifepointer     = pfscore1
lives           = pfscore2

score       = $A4  ;+B5,B6
score1      = score
score2      = score + 1
score3      = score + 2
scorecolor  = $A7
rand        = $A8

kernelConfig			= $A9

;---------------------------------
;-- axuiliary variables

aux0 = $B0
aux1 = $B1
aux2 = $B2
aux3 = $B3
aux4 = $B4
aux5 = $B5
aux6 = $B6
aux7 = $B7

;---------------------------------------------------
;--- variables for screen
;
;-- screenData - index into graphics table
;-- screenBgColor - bg color for row
;-- screenKernelType -
;--   bit 0 - is platform?
;--   bit 1 - has blocking wall?
;--   bit 4/5 - block wall size (nusiz1)
;--   bit 6/7 - kernel type:
;--      00 = regular
;--      40 = asymmetric platforms
;--      80 = lanterns using PF0 + PF1
;--      C0 = lanterns using PF1 + PF2
;--      F0 = background patterns (ex: mountains)

screenData           = $F080  ; 80..97
screenBgColor        = $F098  ; 98..AF
screenKernelType     = $F0B0  ; B0..C7
screenLanternsPF     = $F0D0  ; D0..DF
screenWallPF         = $F0E0  ; E0..EF

writeScreenData       = $F000
writeScreenBgColor    = $F018
writeScreenKernelType = $F030
writeScreenLanternsPF = $F050
writeScreenWallPF     = $F060


;--------------------------------------------------------------------
;-- General Variables available to the user program

A = $c0
a = $c0
B = $c1
b = $c1
C = $c2
c = $c2
D = $c3
d = $c3
E = $c4
e = $c4
F = $c5
f = $c5
G = $c6
g = $c6
H = $c7
h = $c7
I = $c8
i = $c8
J = $c9
j = $c9
K = $ca
k = $ca
L = $cb
l = $cb
M = $cc
m = $cc
N = $cd
n = $cd
O = $ce
o = $ce
P = $cf
p = $cf
Q = $d0
q = $d0
R = $d1
r = $d1
S = $d2
s = $d2
T = $d3
t = $d3
U = $d4
u = $d4
V = $d5
v = $d5
W = $d6
w = $d6
X = $d7
x = $d7
Y = $d8
y = $d8
Z = $d9
z = $d9

;-------------------------------------------------------------------
;-- Temporary variables - used by kernel, 
;--       but can be used by user program.
;-
;-- NOTE:  These are obliterated when drawscreen is called

kernelTemps         = $DA ;-- kernel uses a bunch of memory

scorepointers       = $E0 ;-- uses 6

temp8 = $E0
temp9 = $E1

temp1 = $EA
temp2 = $EB
temp3 = $EC
temp4 = $ED
temp5 = $EE
temp6 = $EF


temp7 = $F0 ; This is used to aid in bankswitching


stack1 = $f6
stack2 = $f7
stack3 = $f8
stack4 = $f9
; the stack bytes above may be used in the kernel
; stack = F6-F7, F8-F9, FA-FB, FC-FD, FE-FF

 MAC RETURN	; auto-return from either a regular or bankswitched module
   ifnconst bankswitch
     rts
   else
     jmp BS_return
   endif
 ENDM
