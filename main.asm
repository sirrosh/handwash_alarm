#include P12F675.inc
radix dec
    __CONFIG   _CP_OFF & _CPD_OFF & _WDT_OFF & _PWRTE_ON & _INTRC_OSC_NOCLKOUT & _MCLRE_ON

#define Light       GPIO, GP0

#define	RS_INTCON   B'11000000'
; GIE ----------------+|||||||
; PEIE ----------------+||||||
; T0IE -----------------+|||||
; INTE ------------------+||||
; GPIE -------------------+|||
; T0IF --------------------+||
; INTF ---------------------+|
; GPIF ----------------------+
#define	RS_T1CON    B'00110001'     ; Tc=Fosc/4=1MHz, 1:8 = 125000ticks/s, interrupt every 0.52428 seconds @ TMR1 overflow
; N/I ----------------+|||||||
; TMR1GE --------------+||||||
; T1CKPS1 --------------+|||||
; T1CKPS0 ---------------+||||
; T1OSCEN ----------------+|||
; /T1SYNC -----------------+||
; TMR1CS -------------------+|
; TMR1ON --------------------+
#define MyDelay      59             ; we need ~59 interrupts for ~23 sec

                                    ; Work modes register
#define mCounting   wMode, 0        ; Counting active
#define mLight      wMode, 1        ; The light is lit (GPIO shadow bit)

    CBLOCK 0x20
i_cycle
W_temp
STATUS_temp
TH
wMode
    ENDC

RES_VECT    CODE    0x0000          ; processor reset vector
    NOP                             ; for ICD
    GOTO    START

INT_VECT    CODE    0x0004          ; interrupt vector
    GOTO    INTERRUPT


MAIN_PROG   CODE                    ; let linker place main program

START
    CLRF    INTCON
    CLRF    wMode
    banksel OSCCAL
    CALL    0x3FF                   ; Get the OSCCAL value
    MOVWF   OSCCAL                  ; Calibrate oscillator
    banksel GPIO
    CLRF    GPIO                    ; Clearig port
    MOVLW   0x07                    ; Turning off analog modules
    MOVWF   CMCON
    banksel ANSEL
    CLRF    ANSEL
    BCF     Light                   ; TRISIO configuration while BANK=1
    banksel T1CON                   ; Configure TMR1
    CLRF    TMR1L
    CLRF    TMR1H
    MOVLW   RS_T1CON
    MOVWF   T1CON
    banksel PIE1
    BSF     PIE1, TMR1IE            ; Enable TMR1 interrupt
    banksel T1CON
    MOVLW   MyDelay                 ; Start counting 24h
    MOVWF   TH
    BSF     mCounting               ; Mode select bit
    MOVLW   RS_INTCON
    MOVWF   INTCON                  ; Allow interrupts

RUN_CYCLE
    ; do smth useful
    NOP
    BTFSS   mCounting
    SLEEP                           ; halt forever here
    GOTO    RUN_CYCLE               ; loop

;
; Subroutine toggles the light and saves the current state
; === void TLIGHT(void)
;
TLIGHT
    banksel GPIO
    BTFSC   mLight          ; are we on?
    GOTO    LIGHT_IS_ON     ; yes
    BSF     Light           ; no, turning on
    BSF     mLight
    RETURN
LIGHT_IS_ON
    BCF     Light           ; yes, turning off
    BCF     mLight
    RETURN



INTERRUPT
    MOVWF   W_temp          ; copy W to temp register, could be in either bank
    SWAPF   STATUS, W       ; swap status to be saved into W
    BCF     STATUS, RP0     ; change to bank 0 regardless ofcurrent bank
    MOVWF   STATUS_temp     ; save status to bank 0 register
                            ; why we are here?
    banksel PIR1
    BTFSS   PIR1, TMR1IF    ; is it TMR1?
    GOTO    OTHER_INT       ; no, something else
;--- here starts TMR1 ISR

    BCF     PIR1, TMR1IF    ; yes, it is TMR1
    BTFSS   mLight          ; if the light's not lit
    BSF     TMR1H, 7        ; make "on" cycles halfway shorter by setting TMR1_MSB=1
    CALL    TLIGHT          ; toggle light
    DECFSZ  TH              ; decrement counter
    GOTO    EXIT_INT        ; this is not the end, continuing to exit
    CLRF    INTCON          ; this is the end, my friend...
    CLRF    wMode           ; turning everything off
    BCF     Light
    RETFIE

OTHER_INT
    banksel PIR1
    CLRF    PIR1            ; we souldn't be here, unexpected interrupt
    BCF     INTCON, GPIF    ; clearing all IFs to avoid interrupt loopp
    BCF     INTCON, T0IF
EXIT_INT
    SWAPF   STATUS_temp, W  ; swap STATUS_TEMP register into W, sets bank to original state
    MOVWF   STATUS          ; move W into STATUS register
    SWAPF   W_temp, F       ; swap W_TEMP
    SWAPF   W_temp, W       ; swap W_TEMP into W

    RETFIE

    END