# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

all: mul_bench

clean:
	$(RM) *.o mul_bench

# XPG needed for getopt()
mul_bench: mul_bench.c
	$(CC) -D_XOPEN_SOURCE=500 -g -O0 -o $@ -std=c99 -Wall -Wpedantic $<

.PHONY: all clean
