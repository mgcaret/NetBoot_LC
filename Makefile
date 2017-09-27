ACMD=java -jar ~/bin/AppleCommander-1.3.5-ac.jar

.PHONY: all
all: NetBoot_LC.mac.bin ;

test.po: NetBoot_LC.bin
	$(ACMD) -pro140 test.po NETBOOT.LC.TST
	$(ACMD) -p test.po NETBOOT.LC BIN 0x0800 < NetBoot_LC.bin

emulate: boot.dsk test.po
	open boot.dsk test.po -a 'Virtual ]['

NetBoot_LC.mac.bin: NetBoot_LC
	rm -f NetBoot_LC.mac.bin
	macbinary encode -t 2 -o NetBoot_LC.mac.bin NetBoot_LC

NetBoot_LC: NetBoot_LC.r
	Rez -rd -o NetBoot_LC NetBoot_LC.r

NetBoot_LC.r: NetBoot_LC.bin
	utils/blocks2rez.sh NetBoot_LC.bin > NetBoot_LC.r

NetBoot_LC.bin: NetBoot_LC.o
	ld65 -t none -o NetBoot_LC.bin Netboot_LC.o

NetBoot_LC.o: NetBoot_LC.s
	ca65 -o NetBoot_LC.o -l NetBoot_LC.lst NetBoot_LC.s

.PHONY: clean
clean:
	rm -f NetBoot_LC *.bin *.r *.o *.lst test.po

