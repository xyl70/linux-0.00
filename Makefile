AS = nasm
OBJ = boot head

all: a.img

a.img: $(OBJ)
	dd bs=512 if=boot of=a.img count=1
	dd bs=512 if=head of=a.img seek=1

$(OBJ):%: %.s
	$(AS) $< -o $@

clean:
	rm -f a.img $(OBJ) bochsout.txt
