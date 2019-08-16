; Oscar A. Carrera
; oacarrera@techadit.com
; 2/11/2015
; src/mbr.rx
; Master Boot Record boot loader for spx64
;
; Processor must support CPUID instruction
; BIOS must support E820 Memory Map feature
; Assembled with nasm
;

[MAP symbols ../debug/mbr.map]

;===========================================
;			Constants
;===========================================
kernel			equ		0x100000			; Kernel entry point

bootdrive		equ 		0x7E00				; Drive we are getting boot from, if any

vesa_enabled		equ		0x7E02				; VESA Enabled tag (1=enabled)
vesa_info		equ		0x7E04				; VESA Mode Info Block

pmap_len		equ		0x7F04				; Ram map entries length
pmap_end		equ		0x7F38				; End of Ram map				
pmap			equ		0x7F3C				; Ram map entry

pm4lt			equ		0x200000			; The PM4LT
pdpt			equ		pm4lt+4096			; The Page Directory Pointer Table
pdt			equ		pdpt+4096			; The Page Directory Table
pdtend			equ		pdt+4096			; End of Page Tables

;===========================================
;			MBR Entry
;===========================================
section .mbr vstart=0x7C00
bits 16									; Real Mode Here
;org 0x7C00								; Origin we getting boot
mbr_entry:
	xor		ax, ax						; Reset segment registers
	mov		ds, ax
	mov		es, ax
	cld	

	mov		byte[bootdrive], dl				; Store drive number we are getting boot from
	
;===========================================
;	Set VESA via VBE
;   It will leave the kernel on video mode
;   With a 800x600 Resolution
;===========================================	
vesa_grph:	
	mov		di, vesa_info
	mov		cx, 0x0117					; Sets the parameter for a 800x600 Resolution
	mov		ax, 0x4F01
	int		0x10
;	cmp		ax, 0x004f					; Comment here to force text mode
	cmp		ax, 0x0000					; Uncomment here to force text mode
	jne		.novesa	
	bt		word[di], 7
	jnc		.novesa	
	mov		byte[vesa_enabled], 0x01
	mov		ax, 0x4F02
	mov		bx, 0xC117; 
	int		0x10
	cmp		ax, 0x004F
	jne		.novesa
	jmp		mmap
.novesa:	
	mov		byte[vesa_enabled], 0x00

;===========================================
;	Read memory map (E820)
;   and stores at the address set to
;   constant 'pmap'
;===========================================
mmap:
	xor		ebx, ebx					; set ebx to 0x00
	xor		si, si						; used here as a counter
	mov 		edi, pmap-24					; our destination buffer
rammap:
	add 		di, 24
	mov 		eax, 0x0000E820					; BIOS command
	mov 		ecx, 0x00000018					; Try to retrieve 24 bytes
	mov 		edx, 0x534D4150					; 'SMAP' signature
	mov 		[es:di+20], dword 0x01				; Ask for valid ACPI 3
	int 		0x15						; 
	jc 		mbr_dead					; Map failed, we depend on it
	inc 		si						; add one to the length
	cmp 		ebx, 0x00000000					; if last entry
	jne 		rammap						; continue to next task
	mov 		[pmap_len], si
	add 		di, 0x18
	mov 		[pmap_end], di


;===========================================
;	CPUID Support Check/Vendor/Features
;===========================================
;	pushf								; Save EFLAG status
;	pop 		eax						; Pop at EAX
;	xor 		eax, 0x200000					; Flip the ID bit
;	push 		eax						; Push it
;	popf								; Pop it at EFLAG
;	pushf								; Push it
;	pop 		eax						; Pop for testing
;	xor 		eax, 0x200000					; Test if EFLAG changed
;	je 		mbr_dead					; if it did, CPUID not supported


;===========================================
; Reset Floppy
;===========================================
	mov 		dl, [bootdrive]					; Drive we got boot from
	mov 		cx, 0x03					; Try 3 times
drive_reset:
	xor 		ax, ax						; Drive read command
	int 		0x13						; Ask BIOS to do it
	jnc 		drive_load					; No carry/error then continue
	loop 		drive_reset					; Repeat if carry
	jmp 		mbr_dead					; Reset drive failed


;===========================================
; Load Rest of the Kernel
; It currently loads about 18KB 
;
; For more information about the
; BIOS int 13 command:
; https://en.wikipedia.org/wiki/INT_13H
;===========================================
drive_load:
	mov 		bx, 0x0000					; We load the rest of	 
	mov 		es, bx						; the kernel into
	mov 		bx, [pmap_end]					; 0x00:ram end
	mov 		ax, 0x0220					; Read command + number of sectors (18k)
	mov 		cx, 0x0002					; Head + sector
	mov 		dh, 0x00					; Cylinder
	mov 		dl, [bootdrive]
	int 		0x13
	jc 		mbr_dead					; If read fails
	mov 		dx, 0x3F2					; Turn off the drive
	mov 		al, 0 
	out 		dx, al


;===========================================
;	A20 Line Check/Enable
;===========================================											
	cli								; Disable Interrupts
	mov 		ax, 0xFFFF
	mov 		es, ax
	xor 		ax, ax
	mov 		ds, ax
	mov 		cx, ax
	mov 		si, ax
	mov 		di, 0x0010
	mov 		ax, [es:di]					; Read value at 0xFFFF:0x0010
	cmp 		ax, [ds:si]					; Check if same as 0x0000:0x0000
	jne 		pm_init						; if not equal, then its enabled											
	not 		word[ds:si]					; Invert the value at 0x0000:0x0000
	mov 		ax, [es:di]					; Read value at 0xFFFF:0x0010
	cmp 		ax, [ds:si]					; Check if same as 0x0000:0x0000
	jne 		pm_init						; if not equal then it should be enabled

a20clear:
	xor 		cx, cx						; Enable A20 Address Line
	in 		al, 0x64					; Read input from keyboard status port
	test 		al, 0x02					; Test if the buffer is full
	loopnz 		a20clear					; Retry until is empty
	mov 		al, 0xD1					; Write to output port
	out 		0x64, al					; Keyboard command
a20enable:
	in 		al, 0x64					; Read input from keyboard status port
	test 		al, 0x02					; Test if the buffer is full
	loopnz 		a20enable					; Retry until is empty
	mov 		al, 0xDF					; Set A20
	out 		0x60, al					; Keyboard command
;mov cx, 0x14								; Loop delay to wait for
;rep out 0xED, ax							; keyboard controller to execute


;===========================================
;	Load the GDT
;===========================================	
pm_init:
	lgdt 		[gdt32ptr]					; Load GDT (null, code, data)
	mov 		eax, CR0					; Load CR0 content
	or 		eax, 0x01					; Set the PE bit
	mov 		CR0, eax					; Store it in CRO

	jmp 		0x08:pmflush									

mbr_dead:
	mov 		ax, 0x0e21					; Print ! on error	
	int 		0x10 						; for now..
	jmp $
	

;===========================================
;	Protected Mode Section
;===========================================		
bits 32									; Protected Mode here
pmflush:
	mov 		ax, 0x10					; Load the Data and Stack Segments
	mov 		ds, ax						; with correct values
	mov 		es, ax
	mov 		fs, ax
	mov 		gs, ax
	mov 		ss, ax
	mov 		esp, 0x9000
	mov 		ebp, 0x9000


;===========================================
;	Long Mode Test/Set up/Kernel Jump
;===========================================		
	mov 		eax, 0x80000000					; CPUID extended function support
	cpuid								; Execute
	cmp 		eax, 0x80000001					; Should at least support
	jb 		mbr32_dead					; The Extended Feature Bits
	mov 		eax, 0x80000001					;
	cpuid								; Execute
	bt 		edx, 0x1D					; Bit 29 (long mode) show be set
	jnc 		mbr32_dead					; if not, we can't continue

	mov 		edi, pm4lt					; Clear Page Table
	mov 		ecx, 0x40000					; area with 0's
	xor		eax, eax
	rep 		stosd						; we don't want garbage

	mov 		edi, pm4lt					; Identity map the first 2MB
	mov 		cr3, edi					; from 0x00000000 to 0x003FFFFF
	mov 		dword[edi], pdpt|0x03				; Set the first PM4E present/read&write
	mov 		edi, pdpt					; Store it
	mov 		dword[edi], pdt|0x03				; Set the first PDE present/read&write
	mov 		edi, pdt					; and
	mov 		dword[edi], 0x0000018B				; Map the first 6MB (0x00000000-0x005FFFFF)
	mov 		dword[edi+8], 0x0020018B			; Kernel gets loaded at 1MB boundary with 5MB available
	mov 		dword[edi+16], 0x0040018B			; 
	
 
	mov 		eax, cr4					; Prepare Control Register 4 
	or 		eax, 0x30					; Enable PAE/Page Size Extension (2MB)/Disable VIF
	mov 		cr4, eax					; Commit
	mov 		ecx, 0xC0000080					;
	rdmsr								;
	or 		eax, 0x100					;
	wrmsr								;
	mov 		eax, cr0					;
	or 		eax, 0x80000001					; Set PG, and PE (just in case)
	mov 		cr0, eax					;

	lgdt 		[gdt64ptr]					; Load 'Legacy' segment descriptors
	mov 		edi, kernel					; Move kernel to 0x100000
	mov 		esi, [pmap_end]					; From where it was loaded
	mov 		ecx, 0x3000					; only 6KB here (to be changed as kernel grows)
	rep 		movsd

	jmp 		0x08:kernel					; GLHF!


mbr32_dead:
	jmp $


;===========================================
;	Data declaration
;===========================================
gdt32:			dw 0x0000, 0x0000, 0x0000, 0x0000
			dw 0xFFFF, 0x0000, 0x9A00, 0x00CF
			dw 0xFFFF, 0x0000, 0x9200, 0x00C7
gdt32ptr:		dw gdt32+17
			dd gdt32

				
gdt64:			dw 0x0000, 0x0000, 0x0000, 0x0000
			dw 0x0000, 0x0000, 0x9800, 0x0020
			dw 0x0000, 0x0000, 0x9300, 0x0000
gdt64ptr		dw gdt64+17
			dd gdt64
				
times 510-($-$$) 	db 0
db 0x55, 0xAA
mbr_end:
