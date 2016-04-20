;bootable zpage seek/read
;copyright (c) Peter Ferrie 2015-16
;thanks to 4am for inspiration and testing
;assemble using ACME
!cpu 6502
!to "0boot",plain
*=$800
        tracks    = $d1         ;user-defined
        address   = $d1         ;user-defined
        entry     = $d1d1       ;user-defined
        sectors   = $00         ;user-defined, sectors to load from partial track (increase tracks first)
        version   = 2

        ;memory usage:
        ;256 bytes ($200-2FF) static table
        grouped   = $200
        ;106 bytes ($300-369) static table
        preshift  = $300
        ;86 bytes ($36A-3BF) dynamic table (2-bit array)
        bit2tbl   = $36a

        !byte   1               ;we'll read the other one ourselves
        lsr                     ;check sector number
        bne     +               ;branch if not 1
        inc     $3d             ;increment sector (faster to find)
        txa
        lsr
        lsr
        lsr
        lsr
        ora     #$c0            ;slot to PROM base
        pha
        lda     #$5b            ;read-1
        pha
        rts

        ;the following TAY is a workaround for a CFFA bug
        ;the bug is that Y isn't zero on entry
        ;the workaround sets it to one instead
        ;it's not zero, but it's better than #$10

+       tay
        txa
        ora     #$8c            ;slot to Q6L
-       ldx     $900, y
        stx     $0, y           ;copy RTS to zpage
        iny
        bne     -
-       iny
        ldx     <(patchtbl-1), y
        sta     $0, x           ;replace placeholders with Q6L
        bne     -
        and     #$f0            ;PHASEOFF
        sta     <(slotpatch6+1)
        ora     #8              ;MOTOROFF
        sta     <(slotpatch8+1)
        ldx     #(stackend-addrtbl)
-       lda     <(addrtbl-1), x
        pha                     ;copy stack frame
        dex
        bne     -
        ldy     #<(tracks*2)
        bne     +               ;branch always
*=$839
        jsr     preread
        lda     #>(entry-1)
        pha
        lda     #<(entry-1)
        pha
        ldx     #<((tracks*16)+sectors)
        lda     #address
        jmp     $bf00           ;DOS 3.3 launcher entrypoint

        ;build read/seek call-sequence per track
+
!if sectors>0 {
        txa
        pha
        lda     #<initsec
        pha
        txa
        clc
        bcc     ++
}

-       txa
        bcc     +               ;set initially by LSR above
        pha
        pha
        !byte   $c9             ;CMP masks SEC, clears carry on even rounds
+       sec                     ;SEC is reached on odd rounds
!if sectors>0 {
++
}
        pha
        lda     #<(seek-1)
        pha                     ;push seek twice for two phases
        dey
        bne     -

        ;construct denibbilisation table
        ;pre-shifted for interleave read

        ldx     #$40
--      ldy     <(tmpval+1)
        tya
        asl
        bit     <(tmpval+1)
        beq     +
        ora     <(tmpval+1)
        eor     #$ff
        and     #$7e
-       bcs     +
        lsr
        bne     -
        dex
        txa
        asl
        asl
        sta     preshift-$16, y
+       dec     <(tmpval+1)
        bne     --

        ;construct 2-bit group table

--      lsr     <(curtrk+1)
        lsr     <(curtrk+1)
-       lda     <indextbl, x
        sta     grouped-1, y
        inc     <(sector+1)
        lda     <(sector+1)
        and     <(curtrk+1)
        bne     +
        inx
        txa
        and     #3
        tax
+       iny
        iny
        iny
        iny
        cpy     #4
        bcs     -
        iny
        cpy     #4
        bcc     --

preread         ;must exit with carry set!
        rts

*=$8fe
        !byte   $be, 1

;the following lives on sector $0E
!pseudopc 0 {
        wait    = $fca8

count
        !byte   version         ;not copied!

        ;fill address array for one track

inittrk
        ldx     #$f0
initsec
!if sectors>0 {
        !byte   $2c
        ldx     #<(-sectors)
}
        stx     <count
rdpage
        lda     #address
        sta     <(addrtbl-$f0), x
        inc     <(rdpage+1)
        inx
        bne     rdpage

read
--	jsr	readnib
-       cmp     #$d5
        bne     --
	jsr	readnib
        cmp     #$aa
        bne     -
        tay                     ;we need Y=#$AA later
	jsr	readnib
        eor     #$ad            ;zero A if match
        beq     check_mode

        ;if not #$AD, then #$96 is assumed

        ldy     #2              ;volume, track, sector
-	jsr	readnib
        rol                     ;set carry
        sta     <(sector+1)
	jsr	readnib
        and     <(sector+1)
        dey
        bpl     -
        sta     <(sector+1)     ;store index for later
        tay
        ldx     <addrtbl, y     ;fetch corresponding address
        stx     <(adrpatch6+2)
        dex
        stx     <(adrpatch3+2)
        stx     <(adrpatch5+2)
        inx                     ;restore value in case it was zero
branch_read
        bcs     read            ;branch always
check_mode
        cpx     #0
        beq     read            ;loop if not expecting #$AD

--      sta     <(tmpval+1)     ;zero rolling checksum
slotpatch1
-       ldx     $c0d1
        bpl     -
        lda     preshift-$96, x
        sta     bit2tbl-$aa, y  ;store 2-bit array
tmpval
        eor     #$7f            ;constant used in table init, self-mod later
        iny
        bne     --
        ldy     #$aa
slotpatch2
-       ldx     $c0d1
        bpl     -
        eor     preshift-$96, x
        ldx     bit2tbl-$aa, y
        eor     grouped+2, x    ;first 86 nibbles use group bits 0-1
adrpatch3
        sta     $d156, y
        iny
        bne     -
        and     #$fc
        ldy     #$aa
slotpatch3
-       ldx     $c0d1
        bpl     -
        eor     preshift-$96, x
        ldx     bit2tbl-$aa, y
        eor     grouped+1, x    ;second 86 nibbles use group bits 2-3
adrpatch5
        sta     $d1ac, y
        iny
        bne     -
        and     #$fc
        ldx     #$ac
slotpatch4
-       ldy     $c0d1
        bpl     -
        eor     preshift-$96, y
        ldy     bit2tbl-$ac, x
        eor     grouped, y      ;last 84 nibbles use group bits 4-5
adrpatch6
        sta     $d100, x
        inx
        bne     -
        and     #$fc
slotpatch5
-       ldy     $c0d1
        bpl     -
        eor     preshift-$96, y
        bne     branch_read     ;branch if checksum failure
sector
        ldy     #0              ;constant used in table init, self-mod later
        stx     addrtbl, y      ;zero corresponding address
        inc     <count          ;adjust remaining count (faster than looping over array)
        bne     branch_read     ;read all requested sectors in one track
        rts

seek            ;requires carry set on entry
        inc     <(curtrk+1)     ;phase on
curtrk
        ldy     #$3f            ;constant used in table init, self-mod later
        lda     #4
        jsr     delay
        dey                     ;phase off
        adc     #$41            ;clear carry while setting #$42
delay
        sta     <(setdelay+1)
        tya
        and     #3
        rol
        tax
slotpatch6
        lda     $c0d1, x
setdelay
        lda     #$d1
        jmp     wait

readnib
slotpatch7
-       lda     $c0d1
        bpl     -
        rts

driveoff
slotpatch8
        lda     $c0d1

        ;place post-read routine here
        ;must end before $ed

seekret         ;shhhh
        jmp     entry

addrtbl
        !word   $fe89-1, $fe93-1, driveoff-1
stackend
patchtbl
        !byte   <(slotpatch1+1), <(slotpatch2+1), <(slotpatch3+1), <(slotpatch4+1), <(slotpatch5+1), <(slotpatch7+1)
indextbl        ;the 0 also terminates the patchtbl list!
        !byte   0, 2, 1, 3
}
