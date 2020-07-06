/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Copyright (C) 2020 Christian Göttel */

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

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

uint64_t vars[NVARS];
int infinite = 0;
int verbose = 0;

/*
 * Log the result to STDOUT in case of a bit filp and write the results to a CSV
 * file.
 * Returns 0 on success and non-zero in case of an error.
 */
int log_result(void)
{
	int rv = 0;
	FILE *csv;
	
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
	rv = fprintf(csv, "0x%016" PRIX64 ",0x%016" PRIX64 ",0x%016" PRIX64 \
		     ",0x%016" PRIX64 ",0x%016" PRIX64 ",%" PRIu64 "\n",
		     vars[MULTIPLIER], vars[MULTIPLICANT], vars[PRODUCT],
		     vars[P], vars[FLIPPED_BITS], vars[I]);
	if (rv < 0)
		perror("fprintf");
	else
		fflush(csv);

	if ((rv = fclose(csv)) != 0)
		perror("fclose");
	
log_end:
	return rv;
}

void infinite_multiply(void)
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

void multiply(void)
{
	for (vars[I] = 0; vars[I] < 1000000000L; vars[I]++) {
		vars[P] = vars[MULTIPLIER] * vars[MULTIPLICANT];
		if (vars[P] != vars[PRODUCT])
			break;
		vars[P] = vars[MULTIPLICANT] * vars[MULTIPLIER];
		if (vars[PRODUCT] != vars[P])
			break;
	}

	vars[FLIPPED_BITS] = vars[P] ^ vars[PRODUCT];
}

void usage(const char *progname)
{
	printf("%s [-hl]\n", progname);
	puts("  -h  print help message");
	puts("  -l  log results to CSV file");
}

int parse_args(int argc, char *argv[])
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
