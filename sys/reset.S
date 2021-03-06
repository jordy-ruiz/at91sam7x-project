@ reset.s : Code d'initialisation de la carte avancée
@ Basé en partie sur le crt0.s de la libc et de la page suivante
@ https://www.sparkfun.com/datasheets/DevTools/SAM7/at91sam7%20serial%20communications.pdf
    
    .include "sys/carte.inc"

    .equ JS_U, 1<<9
    .equ JS_D, 1<<8
    .equ JS_L, 1<<7
    .equ JS_R, 1<<14
    .equ JS_P, 1<<15
    .equ BT1, 1<<24
    .equ BT2, 1<<25

    .global _start
    .global _vec_reset
    .global _vec_undef
    .global _vec_swi
    .global _vec_pabt
    .global _vec_dabt
    .global _vec_rsv
    .global _vec_irq
    .global _vec_fiq

    .global undefHandler
    .global swiHandler
    .global prefAbrtHandler
    .global dataAbortHandler
    .global irqHandler

    .global undefExceptionMsg

    /* Standard definitions of Mode bits and Interrupt (I & F) flags in PSRs (program status registers) */
    .equ ARM_MODE_USR, 0x10 /* Normal User Mode */
    .equ ARM_MODE_FIQ, 0x11 /* FIQ Processing Fast Interrupts Mode */
    .equ ARM_MODE_IRQ, 0x12 /* IRQ Processing Standard Interrupts Mode */
    .equ ARM_MODE_SVC, 0x13 /* Supervisor Processing Software Interrupts Mode */
    .equ ARM_MODE_ABT, 0x17 /* Abort Processing memory Faults Mode */
    .equ ARM_MODE_UND, 0x1B /* Undefined Processing Undefined Instructions Mode */
    .equ ARM_MODE_SYS, 0x1F /* System Running Priviledged Operating System Tasks Mode */
    .equ I_BIT, 0x80 /* when I bit is set, IRQ is disabled (program status registers) */
    .equ F_BIT, 0x40 /* when F bit is set, FIQ is disabled (program status registers) */

    /* Stack Sizes */
    .equ _stack_end,     0x0020ff00     /* Adresse de la fin de stack */
    .equ UND_STACK_SIZE, 0x00000040     /* stack for "undefined instruction" interrupts is 64 bytes */
    .equ ABT_STACK_SIZE, 0x00000040     /* stack for "abort" interrupts is 64 bytes */
    .equ FIQ_STACK_SIZE, 0x00000080     /* stack for "FIQ" interrupts is 128 bytes */
    .equ IRQ_STACK_SIZE, 0x00000C00     /* stack for "IRQ" normal interrupts is 3072 bytes */
    .equ SVC_STACK_SIZE, 0x00000100     /* stack for "SVC" supervisor mode is 256 bytes */

    .text
    .arm
    .align

_start:
    @ Vecteurs d'exception ARM
    @ http://infocenter.arm.com/help/index.jsp?topic=/com.arm.doc.ddi0210c/CIHEHHJJ.html
__vec_reset:    ldr pc, =reset              @ 0x0  Reset
__vec_undef:    ldr pc, =__vec_undef        @ 0x4  Undefined Instruction (dummy for gdb)
__vec_swi:      ldr pc, =__vec_swi          @ 0x8  Software Interrupt (endless loop)
__vec_prefabrt: ldr pc, =__vec_prefabrt     @ 0xc  Prefetch Abort
__vec_dataabrt: ldr pc, =dataAbortHandler   @ 0x10
__vec_reserved: nop                         @ Reserved
__vec_irq:      ldr pc, =irqHandler         @ 0x18 IRQ Handler
__vec_fiq:      ldr pc, =__vec_fiq          @ 0x2c FIQ Handler (endless loop)


reset:
    @ tester s'il est necessaire de changer le mapping de la SRAM
    mov r0, #0
    ldr r1, [r0]
    mov r0, #0x200000
    ldr r2, [r0]
    cmp r1, r2
    beq cont
    @ changer le mapping
    mvn r0, #0xff @ addresse du registre de controle de l'operation REMAP
    mov r1, #1
    str r1, [r0]
cont:
    /* Initialisation de *toutes* les stacks */
    ldr     r0, =_stack_end

    @ Pour info, CPSR_c -> permet d'éditer directement les champs de controle du CPSR
    msr     CPSR_c, #(ARM_MODE_UND|I_BIT|F_BIT) @ Passage en contexte Undefined Instruction
    mov     sp, r0                                                          @ Mise en place de la stack (0x210000)
    sub     r0, r0, #UND_STACK_SIZE                         @ Soustraction de la stack au total

    msr     CPSR_c, #(ARM_MODE_ABT|I_BIT|F_BIT) @ Passage en contexte Data Abort
    mov     sp, r0                                                          @ Mise en place stack
    sub     r0, r0, #ABT_STACK_SIZE                         @ Soustraction

    msr     CPSR_c, #(ARM_MODE_FIQ|I_BIT|F_BIT) @ Passage en mode Fast Interrupt
    mov     sp, r0                                                          @ Idem plus haut
    sub     r0, r0, #FIQ_STACK_SIZE

    msr     CPSR_c, #(ARM_MODE_IRQ|I_BIT|F_BIT) @ Mode IRQ..
    mov     sp, r0
    sub     r0, r0, #IRQ_STACK_SIZE

    msr     CPSR_c, #(ARM_MODE_SVC|I_BIT|F_BIT) @ Idem mode superviseur
    mov     sp, r0
    sub     r0, r0, #SVC_STACK_SIZE

    msr     CPSR_c, #(ARM_MODE_SYS|I_BIT|F_BIT) @ Et passage en mode système
    mov     sp, r0

    //msr   CPSR_c, #(ARM_MODE_SVC|I_BIT|F_BIT) @ Idem mode superviseur

    @ Le reste de l'execution se fera en mode système ?
/*
    Ancien code d'initialisation de la stack (sans gestion des autres modes)
    @ se mettre en mode irq
    mrs r1, CPSR
    bic r1, #0b1101
    msr CPSR, r1
    @ initialiser sp_irq
    mov sp, #0x210000
    @ revenir en mode supervisor
    orr r1, r1, #0b1
    msr CPSR, r1
    @ initialiser sp
    ldr sp, =0x20f000
*/

/*
    Nécessaire pour le code en C: Zero-Initialisation du segment BSS.
    En C, les variables sont toujours initialisées à zéro par l'OS
    au chargement du programme.
*/
    mov     r0, #0
    ldr     r1, =__bss_start__
    ldr     r2, =__bss_end__
rstloop:
    cmp     r1, r2
    strlo   r0, [r1], #4
    blo     rstloop

    @ Activation des pins joystick/boutons sur le PIO 
    ldr r12, =PIOA_BASE
    ldr r0, =JS_U|JS_D|JS_L|JS_R|JS_P
    str r0, [r12, #PIO_IDR]
    ldr r0, [r12, #PIO_ISR]

    ldr r12, =PIOB_BASE
    ldr r0, =BT1|BT2
    str r0, [r12, #PIO_IDR]
    ldr r0, [r12, #PIO_ISR]

    ldr r12, =AIC_BASE
    ldr r0, =0x704c
    str r0, [r12, #AIC_IDCR]
    str r0, [r12, #AIC_ICCR]
    str r0, [r12, #AIC_EOICR]

    @demasquer les interruptions
    mrs r1, CPSR
    bic r1,r1,#0x80
    msr CPSR,r1

    b main @ mov pc, lr


/* =======================================================================  */
/* Function: AT91F_Irq_Handler                                              */
/*                                                                          */
/* This IRQ_Handler supports nested interrupts (an IRQ interrupt can itself */
/* be interrupted).                                                         */
/*                                                                          */
/* This handler re-enables interrupts and switches to "Supervisor" mode to  */
/* prevent any corruption to the link and IP registers.                     */
/*                                                                          */
/* The Interrupt Vector Register (AIC_IVR) is read to determine the address */
/* of the required interrupt service routine. The ISR routine can be a      */
/* standard C function since this handler minds all the save/restore        */
/* protocols.                                                               */
/*                                                                          */
/*                                                                          */
/* Programmers:                                                             */
/*--------------------------------------------------------------------------*/
/* ATMEL Microcontroller Software Support - ROUSSET -                       */
/*--------------------------------------------------------------------------*/
/* DISCLAIMER: THIS SOFTWARE IS PROVIDED BY ATMEL "AS IS" AND ANY EXPRESS   */
/* OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED        */
/* WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND      */
/* NON-INFRINGEMENT ARE DISCLAIMED. IN NO EVENT SHALL ATMEL BE LIABLE FOR   */
/* ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR                 */
/* CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT        */
/* OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR       */
/* BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,    */
/* WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE     */
/* OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,        */
/* EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.                       */
/* File source : Cstartup.s79                                               */
/* Object : Generic CStartup to AT91SAM7S256                                */
/* 1.0 09/May/06 JPP : Creation                                             */
/*                                                                          */
/*                                                                          */
/* Note: taken from Atmel web site (www.at91.com)                           */
/* Keil example project: AT91SAM7S-Interrupt_SAM7X                          */
/* ======================================================================== */
irqHandler:
    /* Manage Exception Entry */

    /* Adjust and save LR_irq in IRQ stack */
    sub     lr, lr, #4
    stmfd   sp!, {lr}

    /* Save r0 and SPSR (need to be saved for nested interrupt) */
    mrs     r14, SPSR
    stmfd   sp!, {r0, r14}

    /* Write in the IVR to support Protect Mode */
    /* No effect in Normal Mode */
    /* De-assert the NIRQ and clear the source in Protect Mode */
    ldr     r14, =AIC_BASE
    ldr     r0,  [r14, #AIC_IVR]
    str     r14, [r14, #AIC_IVR]

    /* Enable Interrupt and Switch in Supervisor Mode */
    msr     CPSR_c, #ARM_MODE_SVC

    /* Save scratch/used registers and LR in User Stack */
    stmfd   sp!, {r1-r3, r12, r14}

    /* Branch to the routine pointed by the AIC_IVR */
    mov     r14, pc
    bx      r0

    /* Manage Exception Exit */

    /* Restore scratch/used registers and LR from User Stack */
    ldmia   sp!, {r1-r3, r12, r14}

    /* Disable Interrupt and switch back in IRQ mode */
    msr     CPSR_c, #(I_BIT | ARM_MODE_IRQ)

    /* Mark the End of Interrupt on the AIC */
    ldr     r14, =AIC_BASE
    str     r14, [r14, #AIC_EOICR]

    /* Restore SPSR_irq and r0 from IRQ stack */
    ldmia   sp!, {r0, r14}
    msr     SPSR_cxsf, r14  @ ??????????????????

    /* Restore adjusted LR_irq from IRQ stack directly in the PC */
    ldmia   sp!, {pc}^

        
@ Segment de données
        .data
        .align  4

/* Messages d'erreur */
undefExceptionMsg:  .asciz "Exception !! Undefined Instruction."
                    .align
prefAbrtExceptMsg:  .asciz "Exception !! Prefetch Abort."
                    .align
dataAbrtExceptMsg:  .asciz "Exception !! Data Abort."
                    .align


@ Temporaire
undefHandler:
        ldr     r1, =undefExceptionMsg
        bl      putstring
undefLoop:
        b       undefLoop

swiHandler:
        nop     @ Bidon pour l'instant

prefAbrtHandler:
        ldr     r1, =prefAbrtExceptMsg
        bl      putstring
prefAbrtLoop:
        b       prefAbrtLoop

dataAbrtHandler:
        stmfd   sp!, {r1,lr}
        @ldr    r9, =0xDEADC0DE
        ldr     r1, =dataAbrtExceptMsg
        bl      putstring
dataAbrtLoop:

        ldmfd   sp!, {r1,lr}^

putchar:
        stmfd       sp!,{r1, r2}
        ldr         r1, =USART0_BASE
put_wait:
        ldr         r2, [r1, #US_CSR]
        ands        r2, r2, #US_TXRDY
        beq         put_wait
        @ On place le caractère dans le registre
        @ Transmitter Holding Register (US_THR)
        strb        r0, [r1, #US_THR]
        ldmfd       sp!,{r1, r2}
        mov         pc, lr

putstring:
        stmfd       sp!,{r0,r1,lr}

put_loop:
        ldrb        r0, [r1], #1
        cmp         r0, #0
        beq         put_end
        bl          putchar
        b           put_loop
put_end:
        ldmfd       sp!,{r0,r1,pc}

