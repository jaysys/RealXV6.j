# ==========================================================================
# NOTE: This Makefile requires Open Watcom 'wmake'.
# It uses specific syntax (like .symbolic, %make, & line continuation)
# that is not compatible with GNU make or Microsoft nmake.
# ==========================================================================

CC = wcc
CFLAGS = -i=h -ms -0 -s -zls -ecc -bt=dos -ohs -zq -j -zl
LD = wlink
LDFLAGS = SYSTEM dos com OPTION map,nodefaultlibs

all: .symbolic
    %make clean
    %make build
    cd usr && wmake all
    cd boot && wmake Unix360.img unix.img

.EXTENSIONS:
.EXTENSIONS: .obj .c
.c:dmr;ken

dmr/m86.obj: dmr/m86.asm
	wasm -bt=DOS -mt -0 $< -fo=$@

.c.obj :
	$(CC) $(CFLAGS) -fo=$@ $<

OBJS = dmr/bio.obj dmr/ide.obj dmr/kbd.obj dmr/kl.obj dmr/mem.obj dmr/pc.obj dmr/rk.obj dmr/tty.obj dmr/uart.obj &
	ken/alloc.obj ken/clock.obj ken/fio.obj ken/iget.obj ken/main.obj ken/malloc.obj ken/nami.obj &
	ken/pipe.obj ken/prf.obj ken/rdwri.obj ken/sig.obj ken/slp.obj ken/subr.obj ken/sys1.obj &
	ken/sys2.obj ken/sys3.obj ken/sys4.obj ken/sysent.obj ken/text.obj ken/trap.obj 

build: .symbolic dmr/m86.obj $(OBJS)
    $(LD) @<<
$(LDFLAGS)
NAME unix.com
FILE dmr/m86.obj
FILE $(OBJS: =, )
<<

clean : .symbolic
	rm -f *.obj *.com *.map
	rm -f dmr/*.obj ken/*.obj
	cd boot && wmake clean
	cd usr && wmake clean
