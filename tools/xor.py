#!/bin/python3
import sys

data1=None
data2=None

if len(sys.argv) < 4:
    print("Bad usage of xor.py", file=sys.stderr)
    exit(1)

file1_name = sys.argv[1]
file2_name = sys.argv[2]
output_file_name = sys.argv[3]


with open(file1_name, 'rb') as file1:
    data1 = file1.read()
with open(file2_name, 'rb') as file2:
    data2 = file2.read()
if len(data1) != len(data2):
    print(f"len(file1) = {len(data1)} != len(file2) = {len(data2)}")
    exit(2)
with open(output_file_name, 'wb') as output_file:
    for i in range(len(data1)):
        output_file.write((data1[i] ^ data2[i]).to_bytes(1, 'little'))
