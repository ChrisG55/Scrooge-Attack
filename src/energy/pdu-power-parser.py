#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2017 Guillaume Fieni
# Copyright (C) 2018 Christian Göttel

# This is a parser for the json metrics returned by the web interface of the Lindy Ipower Control 2x6 XM
# It writes the Voltage, Current, Active Power and Power factor to a CSV file
# usage:
#       ./pdu-parser.py pdu-outputs-power.csv "http://example-pdu.url" 1
#
# hit Ctrl-C when you want to stop the capture

import argparse
import time
import json
import urllib.request
import csv
import http.client
import socket
import sys

# write metrics (voltage, current, active power, power factor) for all PDU outputs
def write_outputs_metrics(timestamp, metrics_values, csv_writer):
    for output_id in range(len(metrics_values)):
        # The voltage U [V]
        voltage = metrics_values[output_id][0]['v']
        # The alternating current I [A]
        current = metrics_values[output_id][1]['v']
        # The frequency f [Hz]
        #frequency = metrics_values[output_id][2]['v']
        # The phase phi = arg(V) - arg(I) expressed in [°]
        #phase = metrics_values[output_id][3]['v']        
        # The real power P [W]
        active_power = metrics_values[output_id][4]['v']
        # "Phantom power" Q [var] when voltage and current are out of phase
        #reactive_power = metrics_values[output_id][5]['v']
        # Magnitude |S| [VA] of the complet power S [VA]
        #apparent_power = metrics_values[output_id][6]['v']
        # Ratio of active power to apparent power: cos(phi) = P / |S|
        power_factor = metrics_values[output_id][7]['v']
        # The following relations among the metrics exist:
        #   P ^ 2 + Q ^ 2 = |S| ^ 2
        #   P = |S| * cos(phi)
        #   Q = |S| * sin(phi)

        csv_writer.writerow({'timestamp': timestamp, 'output-id': output_id, 'voltage': voltage, 'current': current, 'active-power': active_power, 'power-factor': power_factor})
    
    print('Values for timestamp ' + str(timestamp) + ' written to the file (took ' + str(int(time.time()) - timestamp) + ' seconds)', flush=True)

# periodicaly fetch the PDU status to extract power metrics
def main(output_file, status_url, frequency):
    with open(output_file, 'w', newline='') as csvfile:
        csv_fieldnames = ['timestamp', 'output-id', 'voltage', 'current', 'active-power', 'power-factor']
        csv_writer = csv.DictWriter(csvfile, fieldnames=csv_fieldnames)
        csv_writer.writeheader()
        print('Starting PDU monitoring...', flush=True)

        try:
            while True:
                # The Unix time timestamp does not take into account the
                # processing and transmission delays for the following HTTP
                # request. A network performance measurement with 100 ping
                # messages yield these results:
                #   received: 67%, loss: 33%
                #   min RTT:     0.727 ms
                #   avg RTT: 1'722.141 ms
                #   max RTT: 3'569.343 ms
                #   std dev:   967.828 ms
                # Given this performance measurement, the following network
                # throughput is obtained:
                #   65536 B / 1.722141 s ~= 40 KiB/s ~= 304 Kibit/s
                # The size of the JSON response amounts to ~10 KiB.
                # A reasonable approximation would be to subtract 1s from the
                # timestamp, in order to obtain a timestamp that is closer to
                # the true timestamp.
                timestamp = int(time.time()) - 1
                try:
                    # The LINDY iPower control 2x6M device is not designed to be
                    # a high throughput HTTP status information server. Requests
                    # cannot consistently be handled at a frquency of 1 req/s,
                    # especially not if multiple users are requesting status
                    # information at the same time. Introducing a timeout of 8
                    # seconds seems to be a reasonable saturation/data loss
                    # compromise.
                    response = urllib.request.urlopen(status_url + '/statusjsn.js?components=16384', None, 8)
                    obj = response.readline().decode('utf8')
                    metrics = json.loads(obj)
                    write_outputs_metrics(timestamp, metrics['sensor_values'][1]['values'], csv_writer)
                    # Due to the computational limitations of the LINDY iPower
                    # Control 2x6M several exceptions can occur that need to be
                    # handled, in order to successfully run the script as a cron
                    # job.
                except urllib.error.HTTPError as e:
                    print('Values for timestamp ' + str(timestamp) + ' raised exception ' + str(e.code) + ' ' + str(e.reason) + ' (took ' + str(int(time.time()) - timestamp) + ' seconds)', flush=True)
                except urllib.error.URLError as e:
                    print('Values for timestamp ' + str(timestamp) + ' raised exception ' + str(e.reason) + ' (took ' + str(int(time.time()) - timestamp) + ' seconds)', flush=True)
                except http.client.RemoteDisconnected as e:
                    print('Values for timestamp ' + str(timestamp) + ' raised exception ' + str(e.reason) + ' (took ' + str(int(time.time()) - timestamp) + ' seconds)', flush=True)
                except socket.timeout as e:
                    print('Values for timestamp ' + str(timestamp) + ' timed out (took ' + str(int(time.time()) - timestamp) + ' seconds)', flush=True)
                time.sleep(frequency)
        except KeyboardInterrupt:
            print('PDU monitoring have been interrupted.', flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=str, help="The output csv file")
    parser.add_argument("url", type=str, help="The PDU status URL")
    parser.add_argument("freq", type=int, help="The metrics refresh frequency in seconds")
    args = parser.parse_args()

    main(args.out, args.url, args.freq)
