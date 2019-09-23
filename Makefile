AS = nasm
OBJ = boot head

all: disk

Image: $(OBJ)
	dd bs=512 if=boot of=Image count=1
	dd bs=512 if=head of=Image seek=1
disk:Image
	dd bs=8192 if=Image of=a.img
	rm -f Image

$(OBJ):%: %.s
	$(AS) $< -o $@

clean:
	rm -f a.img $(OBJ) bochsout.txt
