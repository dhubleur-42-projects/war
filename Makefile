NAME		=	War
TMP_NAME	=	build/War.tmp

SRCS		= 	\
				final_main.s

INCLUDES	=	includes/

_OBJS		=	${SRCS:.s=.o}
OBJS		=	$(addprefix build/, $(_OBJS))

NASM		=	nasm
NFLAGS		=	-felf64

LD			=	ld

EMPTY_PROGRAM	=	build/empty_program
EMPTY_SRC		=	srcs/empty.c

all		:	$(NAME)

$(EMPTY_PROGRAM)	:	$(EMPTY_SRC)
	@if [ ! -d $(dir $@) ]; then\
		mkdir -p $(dir $@);\
	fi
	gcc -nostartfiles -static -nolibc -masm=intel  -o $(EMPTY_PROGRAM) $(EMPTY_SRC)

build/%.o	:	srcs/%.s
	@if [ ! -d $(dir $@) ]; then\
		mkdir -p $(dir $@);\
	fi
	$(NASM) ${NFLAGS} -I ${INCLUDES} $< -o $@

srcs/final_main.s	:	srcs/main.s
	./tools/convert_payload.sh

$(TMP_NAME)	:	$(OBJS)
	$(LD) $(OBJS) -o $(TMP_NAME)

$(NAME): $(TMP_NAME) $(EMPTY_PROGRAM)
	mkdir -p /tmp/test
	cp $(EMPTY_PROGRAM) /tmp/test
	./$(TMP_NAME)
	mv /tmp/test/$(notdir $(EMPTY_PROGRAM)) $(NAME)

clean	:	
	rm -Rf build/

fclean	:	clean
	rm -f ${NAME}

re		:	fclean
			make ${NAME}

test	:	${NAME}
	rm -rf /tmp/test
	rm -rf /tmp/test2
	mkdir -p /tmp/test
	cp /bin/echo /tmp/test
	./${NAME}

.PHONY	:	all clean fclean re test
