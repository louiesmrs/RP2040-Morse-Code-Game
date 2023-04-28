#include "hardware/regs/addressmap.h"
#include "hardware/regs/io_bank0.h"
#include "hardware/regs/timer.h"
#include "hardware/regs/m0plus.h"

.syntax unified
.cpu    cortex-m0plus
.thumb
.global main_asm
.align  4

.equ    DFLT_STATE_STRT, 1            @ Specify the value to start flashing
.equ    DFLT_STATE_STOP, 0            @ Specify the value to stop flashing
.equ    DFLT_ALARM_TIME, 1000000     @ Specify the default alarm timeout
.equ    SLEEP_TIME, 1000000

.equ    GPIO_BTN_EN_MSK, 0x00400000   @ Bit-22 for falling-edge event on GP21

.equ    GPIO_BTN_RISE_MSK, 0x00400000                           @ Bit-22 for RISING-edge event on GP21
.equ    GPIO_BTN_FALL_MSK, 0x00800000                           @ Bit-23 for falling-edge event on GP21


.equ    DOT, 300                                            @ Input time for a dot is between 0 and 255 ms
                                                                @ Input time for a dash is 255 ms and greater



.equ    GPIO_BTN_EN,  21              @ Specify pin for the "enter" button
.equ    GPIO_LED_PIN, 28             @ Specify pin for the built-in LED
.equ    GPIO_DIR_IN,   0              @ Specify input direction for a GPIO pin
.equ    GPIO_DIR_OUT,  1              @ Specify output direction for a GPIO pin


.equ    GPIO_ISR_OFFSET, 0x74         @ GPIO is int #13 (vector table entry 29)
.equ    ALRM_ISR_OFFSET, 0x40         @ ALARM0 is int #0 (vector table entry 16)

@ Entry point to the ASM portion of the program
main_asm:
        ldr     r4, =#0               @ global variable to store dot or dash
        ldr     r5, =#100             @ global variable to check if input unfinished   
        ldr     r6, =#0               @ global variable to count how many alarms have gone off
        ldr     r7, =#0               @ global variable to store time between inputs
        BL      init_gpio_btn         @ initialise buttons
        BL      set_alarm0_isr        @ set the interrupt handler
        BL      set_gpio_isr          @ set gpio interupt handler
        bl      select_level_display    @ go to for restarting the game
        b       read_level_input
start_game:
        bl      sleep_asm               @ Sleep until SLEEP_TIME has elapsed 
        bl      select_level_display    @ go to for restarting the game
        bl      asm_watchdog
        movs    r0, #0
        bl      set_word                @ resetting index to list of words
        bl      restart_game            @ resetting lives and level

       

@First loop that sets an alarm and waits for user input to select a level.
@ After 2 seconds have passed, finish the loop and set the level.
read_level_input:
        push    {LR}                       @ Store the link register to the stack as we will call nested subroutines
        bl      init_input
        movs    r6, #0                     @ initialse the input to be blank and set the number of alarms to be 0
        level_input_loop:
                bl      set_alarm0         @ set alarm between user inputs
                wfi     
                bl      read_user_input    @ call user input to write dot or dash or check if input finished
                cmp     r4, #1
                beq     input_started
                cmp    r4, #2
                beq     input_started      @ check if dot or dash is inputed, if not set r4 to 0
                movs    r4, #0
                input_started:
                cmp     r6, #2             @ check if input is finished i.e. there have been two alarms
                bne     level_input_loop   @ if there has not been 2 alarms loop again
        
        cmp     r0, #0                     @ if r0 equals 0 here that means there was not a valid input
        beq     restart_level_select       @ during the level select so the game is restarted
        level_selected:
        movs     r0, r5                    @ mov global variable with level ouput it r0
        bl      set_level                  @ set level in r0
     
        b       finish_level_select

        restart_level_select:
        bl      start_game

        finish_level_select:
        bl      boolean_level             @ switch level selected to true
        bl      RGB_Display               @ display lives with RGB
        bl      asm_watchdog
        bl      set_question              @ branch to assembly code with loop for quesitons
        POP     {PC}                      @ Pop the link register from the stack to the program counter





@ Decides whether to write dot(.) or dash(-) to input.
@ if two alarms have gone off finishes inputs.
read_user_input:
        push    {LR}                       @ Store the link register to the stack as we will call nested subroutines

        cmp     r6, #2
        beq     finish_input               @ if there has been 2 alarms the user input is finished
        cmp     r4, #1
        beq     write_dot_to_input         @ else write dot if r4 is 1
        cmp     r4, #2
        beq     write_dash_to_input        @ else write dash if r4 is dash
        b       finish_char


finish_input:
        movs    r0, #4                    @ set r4 to zero since input is finished
        bl      write_input               @ get the level selected from the output of write_input() into r0
        movs    r5, r0                    @ record selected level in r5
        b       finish_char

write_dot_to_input:
        movs    r0, #1                    @ write dot to input array
        bl      write_input
        b       finish_char

write_dash_to_input:    
        movs    r0, #2                    @ write dash to input array
        bl      write_input 
        b       finish_char

finish_char:
        movs    r4, #0
        POP     {PC}                      @ Pop the link register from the stack to the program counter
        

@ Similar to read_level_input but instead calls print_question()
@ and then waits for a user input. After the input is finished, 
@ check if it is correct and if the level/game is complete.


set_question:
        push    {LR}                       @ Store the link register to the stack as we will call nested subroutines
      
        movs    r6, #0                     @ set number of alarms to 0
        bl      print_question             @ print question of current level
        Bl      init_input                 @ clear the input array
        question_input_loop:
                bl      set_alarm0         @ set alarm for user inputs
                wfi     
                bl      read_user_input    @ call user input to write dot or dash or check if input finished
                cmp     r4, #1
                beq     qinput_started
                 cmp    r4, #2
                beq     qinput_started     @ check if dot or dash is inputed, if not set r4 to 0
                movs    r4, #0
                qinput_started:
                cmp     r6, #2              @ check if input is finished i.e. there have been two alarms
                bne     question_input_loop @ if there has not been 2 alarms loop again
          

        bl      check_input                 @ call check input to see if input was correct
        bl      check_level_complete        @ check if level complete or remaining lives equals 0
        cmp     r0, #0                      @ if the output of check_level_complete is 0 then the level is not complete so loop back
        beq     set_question
        cmp     r0, #1                      @ if the output of check_level_complete is 1 then the level is complete so loop back 
        beq     set_question             @ printing new questions corresponding to next level
        cmp     r0, #2                      @ if the output of check_level_complete is 2 then the level 4 is complete or
        beq     start_game                  @ remaining lives == 0, either way restart game
        
                
        POP     {PC}                      @ Pop the link register from the stack to the program counter

@ Call the subroutine to initialise the GPIO buttons
init_gpio_btn:

        push    {LR}                       @ Store the link register to the stack as we will call nested subroutines
       
        MOVS    R0, #GPIO_BTN_EN           @ GPIO PIN 21
        BL      asm_gpio_init              @ Call the subroutine to initialise the GPIO pin specified by r0
        MOVS    R0, #GPIO_BTN_EN           @ GPIO PIN 21
        MOVS    R1, #GPIO_DIR_IN           @ Set state to input pin
        BL      asm_gpio_set_dir           @ Call the subroutine to set the GPIO pin specified by r0 to state specified by r1
        MOVS    R0, #GPIO_BTN_EN           @ Enable falling-edge interrupt for GPIO PIN 21
        BL      asm_gpio_set_irq           @ call subroutine to enable interrupt for button 21

        POP     {PC}                      @ Pop the link register from the stack to the program counter


set_alarm0:
        @ Set's the next alarm on alarm 0
        @ Enable timer 0 interrupt
         push  {lr}                                         @ Store the link register to the stack as we will call nested subroutines
    
    
        ldr   r1, =(TIMER_BASE + TIMER_TIMELR_OFFSET)       
        ldr   r2, [r1]                                      @ Get the current timer count from r1
        ldr   r1, =DFLT_ALARM_TIME     
        add   r1, r1, r2                                    @ Add the time delay you want to wait for to the current timer count
        ldr   r2, =(TIMER_BASE + TIMER_ALARM0_OFFSET)      
        str   r1, [r2]                                      @ Push the updated value to (TIMER_BASE + TIMER_ALARM0_OFFSET)
                
        ldr   r1, =(TIMER_BASE + TIMER_INTE_OFFSET)         @ Enable alarm timer interrupts using r1
        ldr   r2, [r1]      
        ldr   r1, =0x1      
        orrs  r2, r2, r1                                      
        ldr   r1, =(TIMER_BASE + TIMER_INTE_OFFSET)         
        str   r2, [r1]      
        pop   {pc}                                          @ Pop the link register from the stack to the program counter
       
@ installs the interrupt for the alarm
set_alarm0_isr:
        ldr     r2, =(PPB_BASE + M0PLUS_VTOR_OFFSET)        @ Get the address of the RAM vector table
        ldr     r1, [r2]                                    @ Store the address of the alrm_isr handler to the correct offset
        movs    r2, #ALRM_ISR_OFFSET                        @
        add     r2, r1
        ldr     r0, =alarm_isr
        str     r0, [r2]
        
        ldr     r1, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)   @ Disable the ALARM0 IRQ by writing the correct value 
        ldr     r2, [r1]
        movs    r1, #0x1
        orrs    r2, r2, r1
        ldr     r1, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)
        str     r2, [r1]
        
        ldr     r1, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)   @ Enable the ALARM0 IRQ by writing the correct value 
        ldr     r2, [r1]
        movs    r1, #0x1
        orrs    r2, r2, r1
        ldr     r1, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)
        str     r2, [r1]

        bx      lr                                          @ Exit subroutine
        
.thumb_func @ necessary for interrupt handlers
@ Alarm 0 interrupt handler 
alarm_isr:
        PUSH    {lr}                                   @ Store the link register to the stack as we will call nested subroutines
     
        ldr     r1, =(TIMER_BASE + TIMER_INTR_OFFSET)  @ Disable pending interrupt from TIMER by writing correct value to (TIMER_BASE + TIMER_INTR_OFFSET)
        ldr     r2, =#0x1
        str     r2, [r1]

        cmp     r7, #0                                 @ check if time between inputs, if not 0 button is still being held
        bne     button_press
        bl      check_input_empty                      @ check if input is started if not do not record alarm
        cmp     r0, #1
        beq     button_press                           @ check if currrent input is " ", if equal input is still going on

        ldr     r3, =#1
        add     r6, r6, r3                             @ add 1 to number of alarms that have gone off


        button_press:
        pop     {pc}                                    @ Pop the link register from the stack to the program counter

@ installs the gpio interrupt for the buttons
set_gpio_isr:
                                
        @ Set IRQ Handler to our routine
        LDR     R2, =(PPB_BASE)                         
        LDR     R1, =(M0PLUS_VTOR_OFFSET)               @ get address of RAM VECTOR TABLE 
        ADD     R2, R1                                  @ load value into r1
        LDR     R1, [R2]
        MOVS    R2, #GPIO_ISR_OFFSET @ slot for GPIO    @ get correct offset for GPIO 
        ADD     R2, R1                                  @ add to vector table
        LDR     R0, =gpio_isr
        STR     R0, [R2]                                @ store the address or gpoi_isr in the correct offset in vector table
        @ Enable  IRQ (clear then set)
        ldr     R0, =#8192 @ gpio is IRQ0               
        LDR     R2, =(PPB_BASE)
        LDR     R1, =(M0PLUS_NVIC_ICPR_OFFSET)
        ADD     R1, R2
        STR     R0, [R1]                                @ Disable the GPIO IRQ by writing in correct value
        LDR     R1, =(M0PLUS_NVIC_ISER_OFFSET)
        ADD     R1, R2
        STR     R0, [R1]                                @ Enable the gpoi IRQ by writing in correct value
        BX      LR                                      @ Exit subroutine

@ Service the gpio interrupt for the buttons
@  Interrupt handler for GPIO21 button press and release.
@  Decides whether to write dot(.) or dash(-) to input.
.thumb_func @ necessary for interrupt handlers
gpio_isr:
        push   {lr}                                                     @ Store the link register to the stack as we will call nested subroutines
        ldr     r2, =(IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET)      @ Read the interrupt event
        ldr     r1, [r2]                                                
        ldr     r0, =0x2000
        str     r0, [r2]
        ldr     r2, =GPIO_BTN_RISE_MSK
        cmp     r2, r1                                                  @ Detect whether button was pressed or released by Comparing button masks with the value loaded in from the interrupt event (r1). 
        beq     button_pressed

        ldr     r2, =GPIO_BTN_FALL_MSK
        cmp     r2, r1
        beq     button_released
        b       finish_gpio

        
        button_pressed:
            ldr     r2, =(IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)              @ Disable pending interrupt from TIMER by writing correct value to (IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)
            ldr     r1,=GPIO_BTN_RISE_MSK                                            @ GPIO_BTN_EN_MSK FOR GPIO 21
            str     r1,[r2]
            
            bl      get_time                                                  @ record time when button pressed storing it in global variable
            movs    r7, r0
            bl      finish_gpio
            
        button_released:
            ldr     r2, =(IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)              @ Disable pending interrupt from TIMER by writing correct value to (IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)
            ldr     r1,=GPIO_BTN_FALL_MSK                                            @ GPIO_BTN_EN_MSK FOR GPIO 21
            str     r1,[r2]
            bl      get_time                                                  @ record time when button released
            movs    r1, r7                                                    @ move time stored when button pressed to r1
            bl      get_time_difference                                       @ get time difference to decide when whether input is dot or dash
            bl      asm_watchdog
            
            movs    r7, #0                                                      @ Clear the time stored in r7
            ldr     r1, =DOT
            cmp     r0, r1                                                      @ If(time < 300ms)
            blt     input_dot                                                   @   input = dot
            bge     input_dash                                                  @ else
            b       finish_gpio                                                 @   input = dash

                input_dot:
                    ldr     r4, =1                                              @ 1 = "."
                    b       finish_gpio

                input_dash:
                    ldr     r4, =2                                              @ 2 = "-"
                                
        finish_gpio: 
       
        pop    {pc}                                                                @ Pop the link register from the stack to the program counter





.align 4


.data
lstate: .word   DFLT_STATE_STRT
ltimer: .word   DFLT_ALARM_TIME
state: .word 0
