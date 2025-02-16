FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
	build-essential \
	nasm \
    make \
	lldb \
	bc \
	python3 \
	xxd \
	netcat-traditional \
	ncat

CMD ["bash"]