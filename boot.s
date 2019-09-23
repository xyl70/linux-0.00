;boot.s程序
;首先利用BISO中断把内核代码(head 代码)加载到内存 0x10000 处,然后移动到内存 0 处。
;最后进入保护模式,并跳转到内存 0(head 代码)开始处继续运行。
[BITS 16]
SYSSEG equ 0x1000 ;内核(head)先加载到 0x10000 处,然后移动到 0x0 处。
SYSLEN equ 17           ;内核占用的最大磁盘扇区数。
BOOTSEG equ  0x07c00
    org BOOTSEG
    mov ax, cs
    mov ds, ax
    mov ss, ax
    mov sp, 0x400 ;设置临时栈指针。其值需大于程序末端并有一定空间即可
    
;加载内核代码到内存 0x10000 开始处。
load_system:                                                                                                                                                           ;BIOS 中断 int 0x13 定义
    mov dx, 0x0000 ;利用 BIOS 中断 int 0x13 功能 2 从启动盘读取 head 代码。     |  参数寄存器                 涵义     
    mov cx, 0x0002 ;DH - 磁头号;DL - 驱动器号;CH - 10 位磁道号低 8 位;                   |   AH                                 功能号＝0x02，指明要使用读取扇区的功能
    mov ax, SYSSEG ;CL - 位 7、 6 是磁道号高 2 位,位 5-0 起始扇区号(从 1 计)。    |   AL                                 需要读取的扇区的数量
    mov es, ax            ;ES:BX - 读入缓冲区位置(0x1000:0x0000)                                      |   CH                                 磁道号的低8位
    xor bx, bx                                                                                                                                    ; |   CL                                  0-5位表示从哪个扇区开始读取。6-7位是磁道号的高2位
    mov ax, 0x200+SYSLEN                                                                                                        ; |   DH                                 磁头号
    int 0x13                                                                                                                                       ; |   DL                                  驱动器号
    jnc ok_load          ;若没有发生错误则跳转继续运行,否则死循环。                            |   ES:BX                           数据缓冲区。就是把扇区的内容读到ES:BX这个位置
    jmp $                                                                                                                                             ;|   返回值                          如果出错，标志寄存器CF置位，AH中存放出错码

;把内核代码移动到内存 0 开始处。共移动 8KB 字节(内核长度不超过 8KB)。
ok_load:
    cli                               ;关中断
    mov ax, SYSSEG   ;移动开始位置 DS:SI = 0x1000:0;目的位置 ES:DI=0:0。
    mov ds, ax
    xor ax, ax
    mov es, ax
    mov cx, 0x1000    ;设置共移动 4K 次,每次移动一个字(word)。
    sub si, si
    sub di, di
    rep movsw               ;执行重复移动指令。
;加载 IDT 和 GDT 基地址寄存器 IDTR 和 GDTR。
    mov ax, 0
    mov ds, ax                ;让 DS 重新指向 0 段。
    lidt [idt_48]              ;加载 IDTR。 6 字节操作数: 2 字节表长度, 4 字节线性基地址。
    lgdt [gdt_48]            ;加载 GDTR。 6 字节操作数: 2 字节表长度, 4 字节线性基地址。
;设置控制寄存器 CR0(即机器状态字),进入保护模式。段选择符值 8 对应 GDT 表中第 2 个段描述符。
    mov ax, 0x0001    ;在 CR0 中设置保护模式标志 PE(位 0)。
    lmsw ax                   ;然后跳转至段选择符值指定的段中,偏移 0 处。
    jmp  dword 8:0      ;注意此时段值已是段选择符。该段的线性基地址是 0。

;下面是全局描述符表 GDT 的内容。其中包含 3 个段描述符。第 1 个不用,另 2 个是代码和数据段描述符。
gdt:
    dw 0, 0, 0, 0           ;段描述符 0,不用。每个描述符项占 8 字节。

    dw 0x07ff               ;段描述符 1。8Mb - 段限长值=2047 (2048*4096=8MB)。
    dw 0x0000             ;段基地址=0x00000。
    dw 0x9a00             ;是代码段,可读/执行。
    dw 0x00c0             ;段属性颗粒度=4KB,80386。

    dw 0x07ff               ;段描述符 2。8Mb - 段限长值=2047 (2048*4096=8MB)。
    dw 0x0000             ;段基地址=0x00000。
    dw 0x9200             ;是数据段,可读写。
    dw 0x00c0             ;段属性颗粒度=4KB,80386。
;下面分别是 LIDT 和 LGDT 指令的 6 字节操作数。
idt_48:
    dw 0                          ;IDT 表长度是 0。
    dw 0, 0                     ;IDT 表的线性基地址也是 0。
gdt_48:
    dw 0x07ff                ;GDT 表长度是 2048 字节,可容纳 256 个描述符项。
    dw gdt, 0                 ;GDT 表的线性基地址在 0x7c0 段的偏移 gdt 处。
    
    times 510-($-$$) db 0
    dw 0xAA55