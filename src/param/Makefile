#SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

all: mulX_docker

clean:
	$(RM) -Rf *.o mulX_docker

# XPG needed for getopt()
mulX_docker: mulX_docker.c
	$(CC) -D_GNU_SOURCE -g -O0 -o $@ -std=c99 -Wall -Wpedantic $< -lpthread

.PHONY: all clean
