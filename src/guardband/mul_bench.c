/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Copyright (C) 2020 Christian Göttel */

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

enum clock
{
	START,
	STOP,
	NCLOCKS
};

enum var
{
	MULTIPLIER,
        MULTIPLICANT,
	PRODUCT,
	P,
	FLIPPED_BITS,
	I,
	NVARS
};

clock_t cpu_clocks[NCLOCKS];
struct timespec clocks[NCLOCKS];
uint64_t vars[NVARS];
int infinite = 0;
int verbose = 0;

static void clock_diff(struct timespec *tdiff)
{
	tdiff->tv_nsec = clocks[STOP].tv_nsec - clocks[START].tv_nsec;
	if (tdiff->tv_nsec < 0)	{
		tdiff->tv_sec = clocks[STOP].tv_sec - clocks[START].tv_sec - 1;
		tdiff->tv_nsec = 1000000000L + tdiff->tv_nsec;
	} else {
		tdiff->tv_sec = clocks[STOP].tv_sec - clocks[START].tv_sec;
	}
}

static void init_clock(clockid_t *clockid)
{
	/*
	 * See paragraph on "Constants for Options and Option Groups" in the
	 * unistd.h description
	 */
#if defined _POSIX_MONOTONIC_CLOCK
	struct timespec tp;
#endif /* _POSIX_MONOTONIC_CLOCK */

#if !defined _POSIX_MONOTONIC_CLOCK || _POSIX_MONOTONIC_CLOCK < 0
	*clockid = CLOCK_REALTIME;
#elif _POSIX_MONOTONIC_CLOCK > 0
	*clockid = CLOCK_MONOTONIC;
#else
	/* Mandatory runtime test */
	if (clock_gettime((*clockid = CLOCK_MONOTONIC), &tp))
		*clockid = CLOCK_REALTIME;
#endif /* _POSIX_MONOTONIC_CLOCK */
}

/*
 * Log the result to STDOUT in case of a bit filp and write the results to a CSV
 * file.
 * Returns 0 on success and non-zero in case of an error.
 */
static int log_result(void)
{
	int rv = 0;
	FILE *csv;
	struct timespec td;
	double cpu_time = ((double)(cpu_clocks[STOP] - cpu_clocks[START])) / CLOCKS_PER_SEC;
	double duration;

	printf("start        = %ld.%09ld\n", (long)clocks[START].tv_sec, clocks[START].tv_nsec);
	printf("stop         = %ld.%09ld\n", (long)clocks[STOP].tv_sec, clocks[STOP].tv_nsec);
	clock_diff(&td);
	printf("duration     = %ld.%09ld s\n", (long)td.tv_sec, td.tv_nsec);
	printf("cpu time     = %lf s\n", cpu_time);
	duration = td.tv_sec;
	duration += ((double)td.tv_nsec) / 1000000000L;
	printf("cpu usage    = %lf\n", cpu_time / duration);
	
	if (vars[FLIPPED_BITS]) {
		printf("multiplier   = 0x%016" PRIX64 "\n", vars[MULTIPLIER]);
		printf("multiplicant = 0x%016" PRIX64 "\n", vars[MULTIPLICANT]);
		printf("product init = 0x%016" PRIX64 "\n", vars[PRODUCT]);
		printf("product last = 0x%016" PRIX64 "\n", vars[P]);
		printf("flipped_bits = 0x%016" PRIX64 "\n", vars[FLIPPED_BITS]);
		printf("iterations   = %" PRIu64 "\n", vars[I]);
	}

	csv = fopen("./uvbench.csv", "a");
	if (csv == NULL) {
		perror("fopen");
		rv = 1;
		goto log_end;
	}
	rv = fprintf(csv, "%ld.%09ld,%ld.%09ld,0x%016" PRIX64 ",0x%016" \
		     PRIX64 ",0x%016" PRIX64 ",0x%016" PRIX64 ",0x%016" PRIX64 \
		     ",%" PRIu64 ",%lf\n",
		     (long)clocks[START].tv_sec, clocks[START].tv_nsec,
		     (long)clocks[STOP].tv_sec, clocks[STOP].tv_nsec,
		     vars[MULTIPLIER], vars[MULTIPLICANT], vars[PRODUCT],
		     vars[P], vars[FLIPPED_BITS], vars[I], cpu_time);
	if (rv < 0)
		perror("fprintf");
	else
		fflush(csv);

	if ((rv = fclose(csv)) != 0)
		perror("fclose");
	
log_end:
	return rv;
}

static void infinite_multiply(void)
{
	while (1) {
		vars[P] = vars[MULTIPLIER] * vars[MULTIPLICANT];
		if (vars[P] != vars[PRODUCT])
			break;
		vars[P] = vars[MULTIPLICANT] * vars[MULTIPLIER];
		if (vars[PRODUCT] != vars[P])
			break;
	}
}

static void multiply(void)
{
	clockid_t clkid;

	init_clock(&clkid);

	cpu_clocks[START] = clock();
	clock_gettime(clkid, &clocks[START]);

	for (vars[I] = 0; vars[I] < 1000000000L; vars[I]++) {
		vars[P] = vars[MULTIPLIER] * vars[MULTIPLICANT];
		if (vars[P] != vars[PRODUCT])
			break;
		vars[P] = vars[MULTIPLICANT] * vars[MULTIPLIER];
		if (vars[PRODUCT] != vars[P])
			break;
	}

	vars[FLIPPED_BITS] = vars[P] ^ vars[PRODUCT];

	cpu_clocks[STOP] = clock();
	clock_gettime(clkid, &clocks[STOP]);
}

static void usage(const char *progname)
{
	printf("%s [-hil]\n", progname);
	puts("  -h  print help message");
	puts("  -i  go into infinite loop (must be killed)");
	puts("  -l  log results to CSV file");
}

static int parse_args(int argc, char *argv[])
{
	int c;
	int errflg = 0;
	
	while ((c = getopt(argc, argv, "hil")) != -1) {
		switch (c) {
		case 'h':
			usage(argv[0]);
			exit(EXIT_SUCCESS);
		case 'i':
			infinite = 1;
			break;
		case 'l':
			verbose = 1;
			break;
		case ':':
			fprintf(stderr, "Option -%c requires an operand\n", optopt);
			errflg++;
			break;
		case '?':
			fprintf(stderr, "Unrecognized option: '-%c'\n", optopt);
			errflg++;
		}
	}
	if (errflg) {
		usage(argv[0]);
		exit(EXIT_FAILURE);
	}

	return 0;
}

int main(int argc, char *argv[])
{
	int rv;

	parse_args(argc, argv);

	// Initialize operands
	srand48(time(NULL));
	vars[MULTIPLIER] = lrand48();
	vars[MULTIPLICANT] = lrand48();
	vars[PRODUCT] = vars[MULTIPLIER] * vars[MULTIPLICANT];

	if (infinite)
		infinite_multiply();
	else
		multiply();

	if (verbose)
		rv = log_result();

	if (rv)
		return EXIT_FAILURE;

	return EXIT_SUCCESS;
}
