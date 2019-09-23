;head.s 包含 32 位保护模式初始化设置代码、时钟中断代码、系统调用中断代码和两个任务的代码。
;在初始化完成之后程序移动到任务 0 开始执行,并在时钟中断控制下进行任务 0 和 1 之间的切换操作。
[BITS 32]
LATCH          equ 11930                                        ;定时器初始计数值,即每隔 10 毫秒发送一次中断请求。
SCRN_SEL  equ 0x18                                           ;屏幕显示内存段选择符
TSS0_SEL   equ 0x20                                           ;任务 0 的 TSS 段选择符。
LDT0_SEL   equ 0x28                                           ;任务 0 的 LDT 段选择符。
TSS1_SEL   equ 0x30                                           ;任务 1 的 TSS 段选择符。
LDT1_SEL   equ 0x38                                           ;任务 1 的 LDT 段选择符。
[SECTION .text]
startup_32:
;首先加载数据段寄存器 DS、堆栈段寄存器 SS 和堆栈指针 ESP。所有段的线性基地址都是 0。
    mov eax, 0x10                                                    ;0x10 是 GDT 中数据段选择符。
    mov ds, ax
    lss esp, [init_stack]
;在新的位置重新设置 IDT 和 GDT 表。
    call setup_idt                                                    ;设置 IDT。先把 256 个中断门都填默认处理过程的描述符。
    call setup_gdt                                                   ;设置 GDT。
    mov eax, 0x10                                                   ;在改变了 GDT 之后重新加载所有段寄存器。
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    lss esp, [init_stack]
;设置 8253 定时芯片。把计数器通道 0 设置成每隔 10 毫秒向中断控制器发送一个中断请求信号。
    mov al, 0x36                                                      ;控制字:设置通道 0 工作在方式 3、计数初值采用二进制。
    mov  edx, 0x43                                                 ;8253 芯片控制字寄存器写端口。
    out dx, al                                                             
    mov eax, LATCH                                               ;初始计数值设置为 LATCH(1193180/100),即频率 100HZ。
    mov edx, 0x40                                                   ;通道 0 的端口。
    out dx, al                                                             ;分两次把初始计数值写入通道 0。
    mov al, ah
    out dx, al
;在 IDT 表第 8 和第 128(0x80)项处分别设置定时中断门描述符和系统调用陷阱门描述符。
    mov eax, 0x00080000                                    ;中断程序属内核,即 EAX 高字是内核代码段选择符 0x0008。
    mov ax, timer_interrupt                               ;设置定时中断门描述符。取定时中断处理程序地址。
    mov dx, 0x8e00                                                ;中断门类型是 14(屏蔽中断),特权级 0 或硬件使用。
    mov ecx, 0x08                                                   ;开机时 BIOS 设置的时钟中断向量号 8。这里直接使用它。
    lea esi, [idt + ecx * 8]                                      ;把 IDT 描述符 0x08 地址放入 ESI 中,然后设置该描述符。
    mov [esi], eax
    mov [esi + 4], edx
    mov ax, system_interrupt                           ;设置系统调用陷阱门描述符。取系统调用处理程序地址。
    mov dx, 0xef00                                                 ;陷阱门类型是 15,特权级 3 的程序可执行。
    mov ecx, 0x80                                                   ;系统调用向量号是 0x80。
    lea esi, [idt + ecx * 8]                                      ;把 IDT 描述符项 0x80 地址放入 ESI 中,然后设置该描述符。
    mov [esi], eax
    mov [esi+4], edx
;好了,现在我们为移动到任务 0 (任务 A)中执行来操作堆栈内容,在堆栈中人工建立中断返回时的场景。
    pushf                                                                    ;复位标志寄存器 EFLAGS 中的嵌套任务标志。
    and esp, 0xffffbfff                                             
    popf
    mov eax, TSS0_SEL                                        ;把任务 0 的 TSS 段选择符加载到任务寄存器 TR。
    ltr ax
    mov eax, LDT0_SEL                                         ;把任务 0 的 LDT 段选择符加载到局部描述符表寄存器 LDTR。
    lldt ax                                                                     ;TR 和 LDTR 只需人工加载一次,以后 CPU 会自动处理。
    mov [current], dword 0                                  ;把当前任务号 0 保存在 current 变量中。
    sti                                                                             ;现在开启中断,并在栈中营造中断返回时的场景。
    push 0x17                                                             ;把任务 0 当前局部空间数据段(堆栈段)选择符入栈。
    push init_stack                                                  ;把堆栈指针入栈(也可以直接把 ESP 入栈)。
    pushf                                                                      ;把标志寄存器值入栈。
    push 0x0f                                                              ;把当前局部空间代码段选择符入栈。
    push task0                                                           ;把代码指针入栈。
    iret                                                                          ;执行中断返回指令,从而切换到特权级 3 的任务 0 中执行。
;以下是设置 GDT 和 IDT 中描述符项的子程序。
setup_gdt:                                                                 ;使用 6 字节操作数 lgdt_opcode 设置 GDT 表位置和长度。
    lgdt [lgdt_opcode]
    ret
;这段代码暂时设置 IDT 表中所有 256 个中断门描述符都为同一个默认值,均使用默认的中断处理过程
;ignore_int。设置的具体方法是:首先在 eax 和 edx 寄存器对中分别设置好默认中断门描述符的 0-3
;字节和 4-7 字节的内容,然后利用该寄存器对循环往 IDT 表中填充默认中断门描述符内容。
setup_idt:                                                                   ;把所有 256 个中断门描述符设置为使用默认处理过程。
    lea edx, [ignore_int]                                           ;设置方法与设置定时中断门描述符的方法一样。
    mov eax, 0x00080000                                        ;选择符为 0x0008。
    mov ax, dx 
    mov dx, 0x8e00                                                    ;中断门类型,特权级为 0。
    lea edi, [idt]
    mov ecx, 256                                                          ;循环设置所有 256 个门描述符项。
rp_idt:
    mov [edi], eax
    mov [edi + 4], edx
    add edi, 8
    dec ecx
    jne rp_idt
    lidt [lidt_opcode]                                                 ;最后用 6 字节操作数加载 IDTR 寄存器。
    ret

;显示字符子程序。取当前光标位置并把 AL 中的字符显示在屏幕上。整屏可显示 80 X 25 个字符。
write_char:
    push gs                                                                     ;首先保存要用到的寄存器,EAX 由调用者负责保存。
    push ebx
    mov ebx, SCRN_SEL                                            ;然后让 GS 指向显示内存段(0xb8000)。
    mov gs, bx 
    mov bx, [scr_loc]                                                  ;再从变量 scr_loc 中取目前字符显示位置值。
    shl ebx, 1                                                                  ;因为在屏幕上每个字符还有一个属性字节,因此字符
    mov [gs:ebx], al                                                        ;实际显示位置对应的显示内存偏移地址要乘 2。
    shr ebx, 1                                                                  ;把字符放到显示内存后把位置值除 2 加 1,此时位置值对
    inc ebx                                                                       ;应下一个显示位置。如果该位置大于 2000,则复位成 0。
    cmp ebx, 2000 
    jb w1
    mov ebx, 0
w1:
    mov [scr_loc], ebx                                                ;最后把这个位置值保存起来(scr_loc),
    pop ebx                                                                     ;并弹出保存的寄存器内容,返回。
    pop gs
    ret

;以下是 3 个中断处理程序:默认中断、定时中断和系统调用中断。
;ignore_int 是默认的中断处理程序,若系统产生了其他中断,则会在屏幕上显示一个字符'C'。
align 4
ignore_int:
    push ds
    push eax
    mov eax, 0x10                                                         ;首先让 DS 指向内核数据段,因为中断程序属于内核。
    mov ds, ax
    mov eax, 67
    call write_char
    pop eax
    pop ds
    iret

;这是定时中断处理程序。其中主要执行任务切换操作。
align 4
timer_interrupt:
    push ds
    push eax
    mov eax, 0x10                                                        ;首先让 DS 指向内核数据段。
    mov ds, ax
    mov al, 0x20                                                           ; 然后立刻允许其他硬件中断,即向 8259A 发送 EOI 命令。
    out 0x20, al
    mov eax, 1                                                               ;接着判断当前任务,若是任务 1 则去执行任务 0,或反之。
    cmp [current], eax
    je t1
    mov [current], eax                                               ;若当前任务是 0,则把 1 存入 current,并跳转到任务 1
    jmp TSS1_SEL:0
    jmp t2
t1:
    mov [current], dword 0                                     ;若当前任务是 1,则把 0 存入 current,并跳转到任务 0
    jmp TSS0_SEL:0
t2:
    pop eax
    pop ds
    iret

;系统调用中断 int 0x80 处理程序。该示例只有一个显示字符功能。
align 4
system_interrupt:
    push ds
    push edx
    push ecx
    push ebx
    push eax
    mov edx, 0x10                                                        ;首先让 DS 指向内核数据段。
    mov ds, dx
    call write_char                                                       ;然后调用显示字符子程序 write_char,显示 AL 中的字符。
    pop eax
    pop ebx
    pop ecx
    pop edx
    pop ds
    iret

;***************************************************************
current dd 0                                                                ;当前任务号(0 或 1)。
scr_loc dd 0                                                                ;屏幕当前显示位置。按从左上角到右下角顺序显示。

align 4
lidt_opcode:
    dw 256*8 - 1                                                              ;加载 IDTR 寄存器的 6 字节操作数:表长度和基地址。
    dd idt
lgdt_opcode:
    dw end_gdt - gdt - 1                                             ;加载 GDTR 寄存器的 6 字节操作数:表长度和基地址。
    dd gdt

align 8
idt:
    times 256*8 db 0                                                 ;IDT 空间。共 256 个门描述符,每个 8 字节,占用 2KB。

gdt:
    dd 0x00000000, 0x00000000                           ;GDT 表。第 1 个描述符不用。
    dd 0x000007ff, 0x00c09a00                             ;第 2 个是内核代码段描述符。其选择符是 0x08。
    dd 0x000007ff, 0x00c09200                             ;第 3 个是内核数据段描述符。其选择符是 0x10。
    dd 0x80000002, 0x00c0920b                           ;第 4 个是显示内存段描述符。其选择符是 0x18。
    dw 0x68, tss0, 0xe900, 0x0                               ;第 5 个是 TSS0 段的描述符。其选择符是 0x20
    dw 0x40, ldt0, 0xe200, 0x0                               ;第 6 个是 LDT0 段的描述符。其选择符是 0x28
    dw 0x68, tss1, 0xe900, 0x0                               ;第 7 个是 TSS1 段的描述符。其选择符是 0x30
    dw 0x40, ldt1, 0xe200, 0x0                               ;第 8 个是 LDT1 段的描述符。其选择符是 0x38
end_gdt:
    times 128*4 db 0                                                  ;初始内核堆栈空间。
init_stack:                                                                   ;刚进入保护模式时用于加载 SS:ESP 堆栈指针值。
    dd init_stack                                                          ;堆栈段偏移位置。
    dw 0x10                                                                    ;堆栈段同内核数据段。

;下面是任务 0 的 LDT 表段中的局部段描述符。
align 8
ldt0:
    dd 0x00000000, 0x00000000                           ;第 1 个描述符,不用。
    dd 0x000003ff, 0x00c0fa00                              ;第 2 个局部代码段描述符,对应选择符是 0x0f。
    dd 0x000003ff, 0x00c0f200                               ;第 3 个局部数据段描述符,对应选择符是 0x17。
;下面是任务 0 的 TSS 段的内容。注意其中标号等字段在任务切换时不会改变。
tss0:
    dd 0                                                                            ; back link 
    dd krn_stk0, 0x10                                                 ;esp0, ss0
    dd 0, 0, 0, 0, 0                                                         ;esp1, ss1, esp2, ss2, cr3
    dd 0, 0, 0, 0, 0                                                         ;eip, eflags, eax, ecx, edx      
    dd 0, 0, 0, 0, 0                                                         ;ebx esp, ebp, esi, edi 
    dd 0, 0, 0, 0, 0, 0                                                    ;es, cs, ss, ds, fs, gs
    dd LDT0_SEL, 0x8000000                                 ; ldt, trace bitmap

    times 128*4 db 0                                                   ;这是任务 0 的内核栈空间。
krn_stk0:

;下面是任务 1 的 LDT 表段内容和 TSS 段内容。
align 8
ldt1:
    dd 0x00000000, 0x00000000                           ;第 1 个描述符,不用。
    dd 0x000003ff, 0x00c0fa00                               ;选择符是 0x0f,基地址 = 0x00000。
    dd 0x000003ff, 0x00c0f200                               ;选择符是 0x17,基地址 = 0x00000。

tss1:
    dd 0                                                                            ;back link
    dd krn_stk1, 0x10                                                ;esp0, ss0
    dd 0, 0, 0, 0, 0                                                        ;esp1, ss1, esp2, ss2, cr3
    dd task1, 0x200                                                    ;eip, eflags
    dd 0, 0, 0, 0                                                             ;eax, ecx, edx,ebx
    dd usr_stk1, 0, 0 ,0                                              ;esp, ebp, esi, edi
    dd 0x17, 0x0f, 0x17, 0x17, 0x17, 0x17          ;es, cs, ss, ds, fs, gs
    dd LDT1_SEL, 0x8000000                                 ;ldt, trace bitmap

    times 128*4 db 0                                                 ;这是任务 1 的内核栈空间。其用户栈直接使用初始栈空间。
krn_stk1:

;下面是任务 0 和任务 1 的程序,它们分别循环显示字符'A'和'B'。
task0:
    mov eax, 0x17
    mov ds, ax
    mov al, 65
    int 0x80
    mov ecx, 0xfff                                                          ;执行循环,起延时作用
    loop $
    jmp task0
task1:
    mov al, 66
    int 0x80
    mov ecx, 0xfff
    loop $
    jmp task1

    times 128*4 db 0                                                   ;这是任务 1 的用户栈空间。
usr_stk1:
