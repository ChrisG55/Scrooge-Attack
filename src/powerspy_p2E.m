#!/usr/bin/octave-cli -qf

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Computes the consumed energy by integrating PowerSpy power measurements over
# time using the trapezoidal method.
# usage: ./powerspy_p2E.m <PowerSpy CSV extracted>

args = argv();
if (numel(args) != 1)
  error("Invalid number of arguments");
endif

D = csvread(args{1});
trapz(D(:,1), D(:,4))
