# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

all: test

clean:
	rm -Rf *.o test

test: test.c
	gcc -std=c99 -Wpedantic -Wall -D_XOPEN_SOURCE=500 -g -O0 -o $@ $<

.PHONY: all clean
