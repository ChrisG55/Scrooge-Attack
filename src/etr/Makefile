# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

all: mulX_bench mulX_bench_print

clean:
	$(RM) -Rf *.o mulX_bench mulX_bench_print

# XPG needed for getopt()
mulX_bench: mulX_bench.c
	$(CC) -D_GNU_SOURCE -g -O0 -o $@ -std=c99 -Wall -Wpedantic $< -lpthread

mulX_bench_print: mulX_bench_print.c
	$(CC) -D_GNU_SOURCE -g -O0 -o $@ -std=c99 -Wall -Wpedantic $< -lpthread

.PHONY: all clean
