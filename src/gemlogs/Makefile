CFLAGS  = -Os
LDFLAGS = -flto -march=native -lsqlite3
SRC     = scoop.c xdg.c

all: scoop

scoop:
	$(CC) $(SRC) -o $@ $(CFLAGS) $(LDFLAGS)

.PHONY: clean
clean:
	rm -f scoop
