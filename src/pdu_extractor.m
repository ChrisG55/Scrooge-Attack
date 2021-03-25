#!/usr/bin/octave-cli -qf

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Usage:
#   ./pdu_extractor.m <path to pdu.csv> <output file> <port> <timestamp start> <timestamp end>
#     csv  CSV file name

arg_list = argv();

# CSV input layout:
# 1. timestamp with second accuracy
# 2. port (A1-6 and B1-6)
# 3. voltage
# 4. current
# 5. active power
# 6. power factor
D = csvread(arg_list{1}, 1, 0);
port = str2double(arg_list{3});
tsfirst = str2double(arg_list{4});
tslast  = str2double(arg_list{5});

# Extract the port
iport = find(D(:, 2) == port);
D = D(iport, [1, 3, 4, 5, 6, 2]);

# NOTE: the clocks are off by one hour. One is running at UTC+0 the other at UTC+1 (CET)
D(:, 1) -= 3600;

# NOTE: it can happen that ilast < ifirst, when the timeframe is smaller than
# the sample interval and falls inbetween two samples.
ifirst = find(D(:, 1) >= tsfirst, 1);
ilast  = find(D(:, 1) <= tslast, 1, "last");

# Do a linear interpolation if necessary and return a data line.
# TODO: export this to a function or maybe use an existing function.
eplus = 0;
if (tsfirst != D(ifirst, 1))
  # Calculate the slope
  a = (D(ifirst, 2:end) - D(ifirst-1, 2:end)) ./ (D(ifirst, 1) - D(ifirst-1, 1));
  # Calculate the y-intercept
  b = D(ifirst, 2:end) - a .* D(ifirst, 1);
  # Calculate the linearly interpolated column value
  efirst = [tsfirst, a .* tsfirst + b];
  eplus = 1;
endif
if (tslast != D(ilast, 1))
  offset = 0;
  if (ilast == rows(D))
    offset = -1;
  endif
  # Calculate the slope
  a = (D(ilast+offset+1, 2:end) - D(ilast+offset, 2:end)) ./ (D(ilast+offset+1, 1) - D(ilast+offset, 1));
  # Calculate the y-intercept
  b = D(ilast, 2:end) - a .* D(ilast, 1);
  # Calculate the linearly interpolated column value
  elast = [tslast, a .* tslast + b];
  eplus += 2;
endif

# Stitch together the extracted matrix
if (eplus == 0)
  E = zeros(numel(ifirst:ilast), columns(D));
  E(:, :) = D(ifirst:ilast, :);
elseif (eplus == 1)
  E = zeros(numel(ifirst:ilast) + 1, columns(D));
  E(1, :) = efirst;
  E(2:end, :) = D(ifirst:ilast, :);
elseif (eplus == 2)
  E = zeros(numel(ifirst:ilast) + 1, columns(D));
  E(1:end-1, :) = D(ifirst:ilast, :);
  E(end, :) = elast;
else
  E = zeros(numel(ifirst:ilast) + 2, columns(D));
  E(1, :) = efirst;
  E(2:end-1, :) = D(ifirst:ilast, :);
  E(end, :) = elast;
endif

# CSV input layout:
# 1. timestamp with second accuracy
# 2. voltage
# 3. current
# 4. active power
# 5. power factor
# 6. port (A1-6 and B1-6)
#
# Write the extracted matrix to a CSV file
csvwrite(arg_list{2}, E);
