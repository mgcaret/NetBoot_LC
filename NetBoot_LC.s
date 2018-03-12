; Apple //e Workstation Card
; replacement for "hard-coded" boot blocks (in ca65 format).
; By Michael Guidero
;
; The Apple //e Card for Macintosh LC is quite capable.  It
; emulates all of the functions of the Apple //e Workstation Card
; except for one:  When you boot "over the network", instead of getting
; the boot blocks over the network, it loads them from the "IIe Startup"
; resource fork, from BBLK#5120.  Because the boot blocks contain both
; ProDOS and the Logon program, as shipped by Apple the LC //e Card is
; "stuck" at ProDOS 1.9 and Logon 1.3 as shipped by Apple.  Updating them
; requires using ResEdit to hack the IIe Startup program.
;
; The real Workstation Card finds a boot server on the network and loads
; the boot blocks over the network via ATP.  Updating the boot blocks
; is as simple as replacing them on the boot server.
;
; While I figured out how to update the boot blocks in IIe Startup, having
; to hack it with ResEdit just to make it work the same as my regular //es
; with Workstation Cards every time a new ProDOS comes out was an annoying
; prospect.
;
; So as a solution, here's a replacement for BBLK#5120 that makes the LC
; //e Card work like a standard Apple //e with a Workstation Card.
;
; Other features:
; * Puts a letter in the lower left corner indicating what part of the
;   boot process is happening, in case something goes wrong.
; * On-screen spinner, spins as each block is received.
; * Displays the current AppleTalk zone.
; * Displays the boot server network, node, and socket.
;
; Revisions since I gave out the Gist link:
;   07/10/2017 - Fix NBPBuf to be at $xx00 instead of $00xx
;              - Display boot server address/socket & object name
;              - convert output to use monitor routines rather than direct write
;                for messages only, spinners and status still direct write
;              - If in the boot scan loop, try next slot if we fail.
;   07/11/2017 - Convert all AT calls to macro
;              - Adjust retry interval/tries in GetMyZone call.
;              - Display zone if possible, when ca/option held.
;              - Added missing init type flags byte to AT Init call.  No harm no foul.
;

.pc02

.macro    ATcall    PList
          jsr   GoCard
          .byte $42
          .addr PList
.endmacro

NBPBufSz  = $0100               ; NBP buffer size

DispTmp   = $02                 ; temp var for display routines
ch        = $24                 ; cursor horizontal pos
CardPtr   = $fe                 ; ZP loc of card pointer
IRQvect   = $03fe               ; ROM calls here on IRQ
BootStart = $0800               ; where we load boot blocks
NotifyLoc = $07d0               ; process notify screen loc
SpinLoc   = $428+19             ; spinner screen loc
DeathLoc  = $4A8+19

mli       = $bf00               ; ProDOS entry pt
init      = $fb2f               ; init text screen
tabv      = $fb5b               ; vtab to a-reg
title     = $fb60               ; clear screen, display "Apple //e"
bell1     = $fbdd               ; beep
wait      = $fca8               ; waste time
cout      = $fded               ; character out
setkbd    = $fe89               ; set keyboard as input
setvid    = $fe93               ; set text screen as output

clraltchar = $c00e

          .org  BootStart       ; code gets loaded here

; Main routine
.proc     NetBootLC
          jsr   init            ; init text screen
          jsr   setkbd
          jsr   setvid
          jsr   HelloMsg        ; Greeting message
          lda   #'F'+$80
          sta   NotifyLoc       ; tell user we are finding the card
          jsr   FindCard
          bcc   :+
errend:   jsr   ErrorMsg        ; whoopsie doodles
die:      jmp   Death           ; Try next slot or hang.
:         lda   #'R'+$80
          sta   NotifyLoc       ; tell user we are moving boot code
          jsr   ReloBoot        ; move $0300 code
          lda   #'I'+$80
          sta   NotifyLoc       ; tell user we are initing the card
          jsr   InitCard
          bcs   errend          ; Init failed... sorry
          jsr   GetInfo
          bcs   errend
          ; local zone lookup doesn't always work when we don't have a bridge
          ; so if we don't have a bridge yet, don't do zone lookup unless ca/option is
          ; pressed
          lda   ATbridge
          bne   :+              ; if we have a bridge
          sec                   ; flag no zone info
          lda	  $c062			      ; check closed-apple/option
		      bpl   :++			        ; skip if not pressed
:         lda   #'Z'+$80
          sta   NotifyLoc       ; tell user we are getting our zone
          jsr   GetZone
:         jsr   DispInfo        ; carry set = do not try to display zone from NBPBuf
          lda   #'L'+$80
          sta   NotifyLoc       ; tell user we are looking for server
          jsr   FindSrv
          bcc   :+              ; found it
          jsr   NoServer        ; didn't find one... sorry
          bra   die
:         jsr   DispServ        ; give user boot network location
          lda   #'B'+$80
          sta   NotifyLoc       ; tell user we are gonna boot
          ldx   #3              ; copy boot server addr to ATP req
:         lda   NBPBuf,x
          sta   ATPaddr,x
          stz   mli,x           ; and zero out ProDOS MLI entry point, too,
                                ; because the Logon program might check this and
                                ; avoid initializing the card.
          dex
          bpl   :-
          ; brk                   ; DEBUG
          jmp   ATPBoot         ; go to $300 code
.endproc
         
; Find workstation card, since the //e Card is flexible about its
; placement.  Also we can run on a regular //e with a Workstation Card
; for no particular reason.
.proc     FindCard
          lda   #$f9            ; offset to ID bytes
          sta   CardPtr
          lda   #$c7            ; start at slot 7
          sta   CardPtr+1
nextslot: ldy   #3              ; check ID bytes
:         lda   (CardPtr),y
          cmp   idtbl,y
          bne   nomatch
          dey
          bpl   :-
          ldy   #4              ; This is card type byte offset
                                ; 0 = IIgs
                                ; 1 = Workstation Card
                                ; 2 = unseen Server(!) Card
                                ; $F0 = card diags in progress
:         lda   (CardPtr),y
          sta   NotifyLoc       ; a little visual info
          cmp   #$f0            ; Shouldn't happen on LC Card, but...
          beq   :-              ; wait for it all the same
          cmp   #1              ; Because it's proper to make sure it's a working WS Card
          beq   gotcard         ; found it!
nomatch:  dec   CardPtr+1       ; next slot
          lda   CardPtr+1       ; get it
          cmp   #$c0            ; hit slot 0?
          bne   nextslot        ; nope
          sec                   ; no card found
          rts
gotcard:  clc                   ; card found
          rts
idtbl:    .byte "ATLK"
.endproc

; Initialize the WorkStation Card
.proc     InitCard
          sei                   ; disable interrupts for now
          lda   #<CardInt       ; set up IRQ vector
          sta   IRQvect         ; for card
          lda   #>CardInt
          sta   IRQvect+1
          lda   CardPtr+1
          sta   GoCard+2        ; init card MLI call addr
          sta   CardInt+2       ; init card interrupt addr
          ATcall iniparms
done:     cli                   ; re-enable interrupts
          rts
; AppleTalk init call parms.  Undocumented for the most part.
iniparms: .byte 0,1             ; synchronous init
          .word $0000           ; result code, most likely
          .byte $00             ; init type.  Known types & users:
                                ;   $00 - partial init, no MLI global page update
                                ;         used by: ETalk (ethernet NetBoot)
                                ;   $80 - full init, no MLI global page update
                                ;         used by: ETalk (no NetBoot), Fizzy
                                ;         Possibly not usable on WS Card.
                                ;   $40 - full init, MLI global page update
                                ;         used by: ATInit, Logon (boot block version)
          .dword $00000000      ; "ProDOS" entry point - zero seems to work
                                ; if not using global page update
          .byte $00             ; node num preference, 0 = any node number
          .word $0000           ; unknown or reserved
.endproc

; do GetInfo call
.proc     GetInfo
          ATcall inforeq
          bcs   done
          lda   abridge
          sta   ATbridge
          lda   thisnet
          sta   ATnet
          lda   thisnet+1
          sta   ATnet+1
          lda   nodenum
          sta   ATnode
done:     rts
inforeq:  .byte 0,2             ; sync GetInfo
          .word $0000           ; result code
          .dword $00000000      ; completion address
thisnet:  .word $0000           ; this network #
abridge:  .byte $00             ; local bridge
          .byte $00             ; hardware ID
          .word $00             ; ROM version
nodenum:  .byte $00             ; node number
.endproc

; Display our info.  If carry is clear, try to display zone name
; from results of GetMyZone in NBPBuf
; i.e. call GetInfo, then call GetMyZone, then call this.
.proc     DispInfo
          php
          lda   #17             ; line 18
          jsr   tabv
          stz   ch              ; col 0
          ; display our address
          lda   ATnet           ; network is 16-bit
          ldx   ATnet+1
          jsr   PrintU16
          lda   #'.'+$80        ; standard separator
          jsr   cout
          lda   #$00
          ldx   ATnode          ; node number
          jsr   PrintU16
          ; display bridge node if present
          lda   ATbridge
          beq   :+              ; skip if 0
          ldx   #msg4-msg1      ; " bridge ."
          jsr   Disp
          lda   #$00
          ldx   ATbridge
          jsr   PrintU16
:         plp                   ; see if we should display zone
          bcs   done            ; nope
          ; display zone
          ldx   #msg5-msg1      ; " zone "
          jsr   Disp
          jsr   DispZone        ; display it
done:     rts
.endproc

; Get our zone - for information
.proc     GetZone
          ATcall zonereq
          bcs   done            ; error, bail
          lda   NBPBuf          ; check pascal str count
          bne   done            ; if nonzero, done
          sec                   ; otherwise signal error
done:     rts
zonereq:  .byte 0,$1a           ; sync GetMyZone
          .word $0000           ; result
          .dword $00000000      ; completion
          .dword NBPBuf         ; we'll use the NBP buffer since zone is just FYI
          .byte  4,4            ; 4 times every 1 sec
          .word $0000           ; reserved
.endproc

.proc     DispZone
          ; below commented out because we assume we are called from DispInfo
          ;lda   #17             ; line 19
          ;jsr   tabv
          ;stz   ch              ; col 0
          ldx   #$00
:         cpx   NBPBuf          ; did we display all of them?
          beq   done            ; yes, done
          lda   NBPBuf+1,x      ; get char
          ora   #$80
          jsr   cout            ; display
          inx                   ; next
          bra   :-
done:     rts
.endproc

; Find a boot server in our zone
.proc     FindSrv
          ATcall lookup
          bcs   done            ; error, bail
          lda   matches         ; check # matches
          bne   done            ; OK if not zero
          sec
done:     rts
; parameter list for NBPLookup
lookup:   .byte 0,16            ; sync NBPLookup
          .word $0000           ; result
          .dword $00000000      ; completion
          .dword srvname        ; pointer to name to find
          .byte 8,16            ; 16 times, every 2 secs
          .word $0000           ; reserved
          .word NBPBufSz        ; buffer size
          .dword NBPBuf         ; buffer loc
          .byte 1               ; matches wanted
matches:  .byte $00             ; matches found
srvname:  .byte 1,"="           ; object
          .byte 14,"Apple //e Boot" ; type
          .byte 1,"*"           ; zone
.endproc

; Display found boot server address and object name
.proc     DispServ
          lda   #18             ; line 19
          jsr   tabv
          stz   ch              ; col 0
          ; display the server address
          lda   NBPBuf          ; network is 16-bit
          ldx   NBPBuf+1
          jsr   PrintU16
          lda   #'.'+$80        ; standard separator
          jsr   cout
          lda   #$00
          ldx   NBPBuf+2        ; node number
          jsr   PrintU16
          lda   #'/'+$80        ; standard separator
          jsr   cout
          lda   #$00
          ldx   NBPBuf+3        ; socket number
          jsr   PrintU16
          lda   #' '+$80
          ; now display server object name
          jsr   cout
          ldx   #$00
:         cpx   NBPBuf+5        ; did we display all of them?
          beq   done            ; yes, done
          lda   NBPBuf+6,x      ; get char
          ora   #$80
          jsr   cout            ; display
          inx                   ; next
          bra   :-
done:     rts
.endproc
          
; Print unsigned 16-bit integer
; adapted from
; https://groups.google.com/forum/#!topic/comp.sys.apple2/_y27d_TxDHA
.proc     PrintU16
          stx   DispTmp
          sta   DispTmp+1
          lda   #$00
:         pha
          lda   #$00
          clv
          ldy   #$10
:         cmp   #$05
          bcc   :+
          sbc   #$85
          sec
:         rol   DispTmp
          rol   DispTmp+1
          rol   a
          dey
          bne   :--
          ora   #$b0
          bvs   :---
:         jsr   cout
          pla
          bne   :-
          rts
.endproc

; we are dead and can't even start downloading boot blocks
; so go to next slot if we are booting, or hang otherwise
; can't be used after we go to $300 code
.proc     Death
          lda   $00           ; $00 must be 0
          bne   :+            ; or we are not booting
          lda   $01
          and   #$f0          
          cmp   #$c0          ; $01 must be $Cx
          bne   :+
          lda   #$ff
          jsr   wait          ; wait a bit so user can see message
          jmp   $faba
:         sta   clraltchar    ; make sure alt char set is off
          lda   #$58          ; flashing (red) X
          sta   DeathLoc      ; on screen
hang:     bra   hang          ; hang
.endproc

; display the "no boot server" message
.proc     NoServer
          ldx   #msg3-msg1
          bra   Disp
.endproc

; display the "something went wrong" message
.proc     ErrorMsg
          ldx   #msg2-msg1
          bra   Disp
.endproc

; display the greeting
.proc     HelloMsg
          jsr   title           ; apple ii title screen (card boot clears screen)
          ldx   #msg1-msg1      ; better be zero!
          ; fall-through
.endproc

; Display one of the messages, can't be used after we go to $300 code
.proc     Disp
          lda   msg1,x
          bne   :+
          rts
:         inx                   ; set up for next message byte
          cmp   #$18            ; last line + 1
          bcc   repos
          eor   #$80
          jsr   cout            ; not supposed to change anything
          bra   Disp
repos:    jsr   tabv            ; destroys a and y, but not x
          lda   msg1,x          ; get horizontal
          sta   ch              ; and write
          inx                   ; next message byte
          bra   Disp
.endproc

msg1:     .byte 05,08,"NetBoot LC v1.0 by M.G."
          .byte 06,05,"Starting up over the network...",$00
msg2:     .byte 08,09,"Something went wrong!",$00
msg3:     .byte 08,12,"No boot server!",$00
msg4:     .byte ", bridge .",$00
msg5:     .byte ", zone ", $00

; move $300 code into position
.proc     ReloBoot
          ldx   #BootOSize+1
:         lda   BootRStrt-1,x
          sta   $0300-1,x
          dex
          bne   :-
          rts
.endproc

; Code to be moved to $300 follows
BootRStrt = *
          .org  $0300
BootOBgn  = *
; Call the card's MLI
.proc     GoCard
          jmp   $C714           ; For slot 7, modify in InitCard
.endproc

; Provide an interrupt handler for the card
.proc     CardInt
          jsr   $C719           ; For slot 7, modify in InitCard
          rti
.endproc

; Boot using ATP requests to retrieve boot blocks.
.proc     ATPBoot
fetch:    lda   #1
          sta   ATPbmap         ; want only block 0 (ATP-wise)
          ATcall ATPparms
          bcs   error           ; oops
          lda   Status          ; is EOF?
          beq   :+              ; keep reading if not EOF
          sei                   ; otherwise, no more interrupts
          jmp   BootStart       ; and execute next boot stage
:         inc   BlkNum          ; implicitly limited, below
          lda   BlkNum          ; get it for spinner
          and   #$03            ; mask in low bits
          tay
          lda   spinner,y       ; get spinner char
          sta   SpinLoc         ; put on middle of screen
          lda   BlkPtr+1        ; block pointer (load addr)
          clc
          adc   #$02            ; $200 bytes
          sta   BlkPtr+1        ; inc address
          cmp   #$c0            ; Reading too far?
          bcc   fetch           ; read next block if not          
error:    jsr   bell1           ; beep speaker
          lda   #$58            ; flashing (red) X
          sta   SpinLoc         ; on screen
hang:     bra   hang
spinner:  .byte '|'+$80
          .byte '/'+$80
          .byte '-'+$80
          .byte '\'+$80
.endproc
ATbridge: .byte $00             ; local bridge
ATnet:    .word $0000           ; local net
ATnode:   .byte $00             ; our node number
ATPparms: .byte 0,18            ; sync SendATPReq
          .word $0000           ; result
          .dword $00000000      ; compl. addr
          .byte $00             ; socket #
ATPaddr:  .dword $00000000      ; destination address
          .word $0000           ; TID
          .word $0000           ; req buffer size
          .dword $00000000      ; req buffer addr
          .byte $02             ; boot type
                                ; $01 = IIgs stage 1
                                ; $02 = //e
                                ; $03 = IIgs boot image
BlkNum:   .word $0000           ; block number to req
          .byte $00             ; unused
          .byte $01             ; one response buffer
          .dword BDS            ; pointer to response BDS
          .byte $00             ; ATP flags
          .byte 8,32            ; try 32 times every 2 seconds
ATPbmap:  .byte $00             ; bitmap of blocks to recieve
          .byte $00             ; number of responses
          .res  6               ; 6 bytes reserved
BDS:      .word $0200           ; length of buffer
BlkPtr:   .dword BootStart      ; block pointer
Status:   .dword $00000000      ; returned user bytes, first byte = 1 if EOF
          .word $0000           ; actual length
BootOEnd  = * 
.assert   BootOEnd < $3d0, warning, "Page 3 code too big"
BootOSize = BootOEnd - BootOBgn
; end of $300 code, fix up origin
          .org  BootRStrt + BootOSize

NBPBuf    = (* >> 8 + 1)*$100   ; put this on next page boundary
.out      .sprintf("NBP Buffer at $%x", NBPBuf)
