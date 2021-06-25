#!/usr/bin/octave-cli -qf

# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021 Christian Göttel

# Return statistical information on the data and search for outliers. The script
# provides two modes:
#   1. cln  clean the standard input data from outliers. Return line indices of
#           outliers over standard output.
#   2. cov  compute the sample covariance for two data sets over standard input
#           separated by a comma. Return the covariance of the two data sets.
#   3. sta  return the mean and "corrected" sample standard deviation, separated
#           by a comma over standard output, of clean data.
#
# Usage:
#   printf "x1\nx2\n...xn\n" | ./stats.m [cln|cov|sta <precision>]

# Student t table for alpha = 5%
talpha5 = [12.7062 4.3027 3.1824 2.7764 2.5706 2.4469 2.3646 2.3060 2.2622 2.2231 2.2010 2.1788 2.1604 2.1448 2.1314 2.1199 2.1098 2.1009 2.0930 2.0860 2.0796 2.0736 2.0687 2.0639 2.0595 2.0555 2.0518 2.0484 2.0452 2.0423 2.0395];
p = [0.25; 0.5; 0.75];

arg_list = argv();

function clean_data()
  # Parse the data from standard input
  i = 1;
  while (!feof(stdin()))
    line = fgetl(stdin());
    x(i++, 1) = str2double(line);
  endwhile

  # Compute the quartiles and find outliers
  p = [0.25 0.75];
  q = quantile(x, p);
  iqr = q(2)-q(1);
  if (any(outlier = find((x < (q(1)-1.5*iqr)) | ((q(2)+1.5*iqr) < x))))
    # Write the line index of outliers to standard output and standard error
    fprintf(stdout(), "%d\n", outlier);
    fprintf(stderr(), "outlier: x[%d] = %f\n", [outlier x(outlier)]');
  endif
endfunction

function compute_cov()
  # Parse the data from standard input
  i = 1;
  j = 1;
  while (!feof(stdin()))
    line = strsplit(fgetl(stdin()), ",");
    n = str2double(line{1});
    if (!isnan(n))
      x(i++, 1) = n;
    endif
    n = str2double(line{2});
    if (!isnan(n))
      y(j++, 1) = n;
    endif
  endwhile
  k = min(i-1,j-1);
  fprintf(stderr(), "n=%d\n", k);

  # Write the sample covariance to standard ooutput
  fprintf(stdout(), "%f\n", cov(x(1:k),y(1:k)));
endfunction

function compute_statistics(precision)
  # Parse the data from standard input
  i = 1;
  while (!feof(stdin()))
    line = fgetl(stdin());
    x(i++, 1) = str2double(line);
  endwhile

  # Write the mean and corrected sample standard deviation to standard output
  tmp = "%f,%f\n";
  if (precision > 0)
    tmp = ["%." precision "f,%f\n"];
  endif
  fprintf(stdout(), tmp, mean(x), std(x));
endfunction

if (strncmp(arg_list{1}, "cln", 3))
  clean_data();
elseif (strncmp(arg_list{1}, "sta", 3))
  if (nargin == 2)
    compute_statistics(arg_list{2});
  else
    compute_statistics(0);
  endif
else
  compute_cov();
endif
