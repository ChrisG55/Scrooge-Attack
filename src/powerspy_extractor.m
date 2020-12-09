#!/usr/bin/octave-cli -qf

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2020 Christian Göttel

# Usage:
#   ./powerspy_extractor.m <path to powerspy.csv> <output file> <timestamp start> <timestamp end>
#     csv  CSV file name

arg_list = argv();

# CSV input layout:
# 1. timestamp with nanosecond accuracy
# 2. RMS voltage
# 3. RMS current
# 4. RMS power
# 5. Peak voltage
# 6. Peak current
D = csvread(arg_list{1});
tsfirst = str2double(arg_list{3});
tslast  = str2double(arg_list{4});

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
  # Calculate the slope
  a = (D(ilast+1, 2:end) - D(ilast, 2:end)) ./ (D(ilast+1, 1) - D(ilast, 1));
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

# Write the extracted matrix to a CSV file
csvwrite(arg_list{2}, E);
