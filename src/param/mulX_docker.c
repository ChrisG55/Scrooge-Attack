/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Copyright (C) 2021 Christian Göttel */

#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include <sched.h>
#include <unistd.h>

#include <pthread.h>

enum var
{
	MULTIPLIER,
        MULTIPLICANT,
	PRODUCT,
	NVARS
};

uint64_t vars[NVARS];
int cores; /* total number of processor cores */

struct thread_info {
	int id; /* thread ID */
	int core; /* core ID */
	uint64_t product; /* thread-local product */
	uint64_t flipped_bits; /* thread-local flipped bits */
	uint64_t i; /* thread-local iterator i */
};

/*
 * Returns the number of (online) cores available on the system.
 */
static long get_cores(void)
{
	long cores = 1;

#ifdef _SC_NPROCESSORS_CONF
	cores = sysconf(_SC_NPROCESSORS_CONF);
	if (cores == -1)
		goto fail;
#endif /* _SC_NPROCESSORS_CONF */
#ifdef _SC_NPROCESSORS_ONLN
	cores = sysconf(_SC_NPROCESSORS_ONLN);
	if (cores == -1)
		goto fail;
#endif /* _SC_NPROCESSORS_ONLN */

	return cores;

#if defined(_SC_NPROCESSORS_CONF) || defined(_SC_NPROCESSORS_ONLN)
fail:
	perror("sysconf");
	return 1;
#endif
}

static void infinite_multiply(struct thread_info *ti)
{
	while (1) {
		ti->product = vars[MULTIPLIER] * vars[MULTIPLICANT];
		if (ti->product != vars[PRODUCT])
			break;
	        ti->product = vars[MULTIPLICANT] * vars[MULTIPLIER];
		if (vars[PRODUCT] != ti->product)
			break;
	}
}

static void usage(const char *progname)
{
	printf("%s [-h]\n", progname);
	puts("  -h  print help message");
}

static int parse_args(int argc, char *argv[])
{
	int c;
	int errflg = 0;
	
	while ((c = getopt(argc, argv, "h")) != -1) {
		switch (c) {
		case 'h':
			usage(argv[0]);
			exit(EXIT_SUCCESS);
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

static void *thread_main(void *arg)
{
	struct thread_info *ti = arg;
	cpu_set_t set;

	CPU_ZERO(&set);
	CPU_SET(ti->core, &set);
	
	if (sched_setaffinity(0, sizeof(cpu_set_t), &set) == -1) {
		fprintf(stderr, "thread[%d]: ", ti->id);
		perror("sched_setaffinity");
		goto thread_end;
	}

	if (sched_getaffinity(0, sizeof(cpu_set_t), &set) == -1) {
		fprintf(stderr, "thread[%d]: ", ti->id);
		perror("sched_getaffinity");
	}

	infinite_multiply(ti);

thread_end:
	return NULL;
}

int main(int argc, char *argv[])
{
	int i, rv;
	long cores;
	pthread_t *threads;
	pthread_attr_t attr;
	struct thread_info *ti;

	parse_args(argc, argv);

	// Initialize operands
	srand48(time(NULL));
	vars[MULTIPLIER] = lrand48();
	vars[MULTIPLICANT] = lrand48();
	vars[PRODUCT] = vars[MULTIPLIER] * vars[MULTIPLICANT];

	// Initialize threads
	cores = get_cores();

	threads = calloc(cores, sizeof(*threads));
	if (threads == NULL) {
		perror("calloc");
		return EXIT_FAILURE;
	}

	ti = calloc(cores, sizeof(*ti));
	if (ti == NULL) {
		perror("calloc");
		return EXIT_FAILURE;
	}

	if (pthread_attr_init(&attr) != 0) {
		perror("pthread_attr_init");
		return EXIT_FAILURE;
	}
	
	for (i = 0; i < cores; i++) {
		ti[i].id = i;
		ti[i].core = i;
		rv = pthread_create(&threads[i], &attr, thread_main, &ti[i]);
		if (rv != 0) {
			fprintf(stderr, "pthread_create: %d\n", rv);
			break;
		}
	}

	for (i = 0; i < cores; i++) {
		rv = pthread_join(threads[i], NULL);
		if (rv != 0)
			fprintf(stderr, "pthread_join: %d\n", rv);
	}

	if (pthread_attr_destroy(&attr) != 0)
		perror("pthread_attr_destroy");

	free(ti);
	free(threads);

	if (rv)
		return EXIT_FAILURE;

	return EXIT_SUCCESS;
}
