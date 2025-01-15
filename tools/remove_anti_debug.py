import sys

SEARCH = b"\xb8\x65\x00\x00\x00\xbf\x00\x00\x00\x00\x48\x31\xf6\x48\x31\xd2\x0f\x05"
REPLACE = b"\x90\x90\x90\x90\x90\x90\x90\x90\x90\x90\x90\x90\x90\xb8\x00\x00\x00\x00"

# Search:  b8 65 00 00 00 bf 00 00 00 00 48 31 f6 48 31 d2 0f 05
#          ^ syscall(PTRACE_TRACEME)
# Replace: 90 90 90 90 90 90 90 90 90 90 90 90 90 b8 00 00 00 00
#          ^ NOP                                  ^ mov rax, 0

if len(sys.argv) != 2:
	print("Usage: python3 remove_anti_debug.py <path>")
	exit(1)

with open(sys.argv[1], "r+b") as f:
	data = f.read()
	if SEARCH not in data:
		print("Pattern not found")
		exit(1)
	data = data.replace(SEARCH, REPLACE)
	f.seek(0)
	f.write(data)
	f.truncate()
	print("Pattern replaced")
	exit(0)