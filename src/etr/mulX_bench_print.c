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

#ifdef __linux__
#include <linux/version.h>
#endif /* __linux__ */

enum var
{
	MULTIPLIER,
        MULTIPLICANT,
	PRODUCT,
	NVARS
};

int infinite;
int verbose;
uint64_t vars[NVARS];
int cores; /* total number of processor cores */
clockid_t clkid = CLOCK_REALTIME;

struct thread_info {
	int id; /* thread ID */
	int core; /* core ID */
	double cpu_time;
	struct timespec rt_clock_start;
	struct timespec rt_clock_stop;
	struct timespec duration;
	uint64_t product; /* thread-local product */
	uint64_t flipped_bits; /* thread-local flipped bits */
	uint64_t i; /* thread-local iterator i */
};

static void clock_diff(struct timespec *start, struct timespec *stop, struct timespec *tdiff)
{
	tdiff->tv_nsec = stop->tv_nsec - start->tv_nsec;
	if (tdiff->tv_nsec < 0)
	{
		tdiff->tv_sec = stop->tv_sec - start->tv_sec - 1;
		tdiff->tv_nsec = 1000000000L + tdiff->tv_nsec;
	}
	else
	{
		tdiff->tv_sec = stop->tv_sec - start->tv_sec;
	}
}

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

static void init_clock()
{
	/*
	 * See paragraph on "Constants for Options and Option Groups" in the
	 * unistd.h description
	 */
#if defined _POSIX_MONOTONIC_CLOCK || _POSIX_MONOTONIC_CLOCK > 0 || defined(_POSIX_THREAD_CPUTIME) || _POSIX_THREAD_CPUTIME > 0 || defined(__linux__) || LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,12)
	struct timespec tp;
#endif /* _POSIX_MONOTONIC_CLOCK, _POSIX_THREAD_CPUTIME */

	puts("real-time: CLOCK_REALTIME");
	
#if !defined _POSIX_MONOTONIC_CLOCK || _POSIX_MONOTONIC_CLOCK < 0
	clkid = CLOCK_REALTIME;
#elif _POSIX_MONOTONIC_CLOCK > 0
	clkid = CLOCK_MONOTONIC;
#else
	/* Mandatory runtime test */
	if (clock_gettime((clkid = CLOCK_MONOTONIC), &tp))
		clkid = CLOCK_REALTIME;
#endif /* _POSIX_MONOTONIC_CLOCK */
#ifdef __linux__
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,28)
	/* Mandatory runtime test */
	if (clock_gettime(CLOCK_MONOTONIC_RAW, &tp) == 0) {
		clkid = CLOCK_MONOTONIC_RAW;
		puts("monotonic: CLOCK_MONOTONIC_RAW");
	} else if (clkid == CLOCK_MONOTONIC) {
		puts("monotonic: CLOCK_MONOTONIC");
	} else {
		puts("monotonic: CLOCK_REALTIME");
	}
#endif /* LINUX_VERSION_CODE */
#endif /* __linux__ */
	
#if defined(_POSIX_THREAD_CPUTIME) || _POSIX_THREAD_CPUTIME > 0
#ifdef __linux__
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,12)
	/* Mandatory runtime test */
	if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &tp) == -1) {
		perror("clock_gettime");
	        exit(EXIT_FAILURE);
	} else {
		puts("CPU time: CLOCK_THREAD_CPUTIME_ID");
	}
#else
	puts("CPU time: clock()");
#endif /* LINUX_VERSION_CODE */
#endif /* __linux__ */
#endif /* _POSIX_THREAD_CPUTIME */

	if (clkid == CLOCK_REALTIME)
		fprintf(stderr, "WARNING: using CLOCK_REALTIME; negative clock jumps can happen.\n");
}

/*
 * Log the result to STDOUT in case of a bit filp and write the results to a CSV
 * file.
 * Returns 0 on success and non-zero in case of an error.
 */
static int log_result(struct thread_info *ti)
{
	int rv = 0;
	double cpu_usage;
	double duration;

	printf("TID[%d] start        = %ld.%09ld\n", ti->id, (long)ti->rt_clock_start.tv_sec, ti->rt_clock_start.tv_nsec);
	printf("TID[%d] stop         = %ld.%09ld\n", ti->id, (long)ti->rt_clock_stop.tv_sec, ti->rt_clock_stop.tv_nsec);
	printf("TID[%d] duration     = %ld.%09ld s\n", ti->id, (long)ti->duration.tv_sec, ti->duration.tv_nsec);
	printf("TID[%d] cpu time     = %lf s\n", ti->id, ti->cpu_time);
	duration = ti->duration.tv_sec;
	duration += ((double)ti->duration.tv_nsec) / 1000000000;
	cpu_usage = ti->cpu_time / duration;
	printf("TID[%d] cpu usage    = %lf\n", ti->id, cpu_usage);
	
	if (ti->flipped_bits) {
		printf("TID[%d] multiplier   = 0x%016" PRIX64 "\n", ti->id, vars[MULTIPLIER]);
		printf("TID[%d] multiplicant = 0x%016" PRIX64 "\n", ti->id, vars[MULTIPLICANT]);
		printf("TID[%d] product init = 0x%016" PRIX64 "\n", ti->id, vars[PRODUCT]);
		printf("TID[%d] product last = 0x%016" PRIX64 "\n", ti->id, ti->product);
		printf("TID[%d] flipped_bits = 0x%016" PRIX64 "\n", ti->id, ti->flipped_bits);
		printf("TID[%d] iterations   = %" PRIu64 "\n", ti->id, ti->i);
	}

	puts("=== mulX_bench.csv ===");
	rv = printf("%ld.%09ld,%ld.%09ld,0x%016" PRIX64 ",0x%016"	\
		    PRIX64 ",0x%016" PRIX64 ",0x%016" PRIX64 ",0x%016" PRIX64 \
		    ",%" PRIu64 ",%ld.%09ld,%lf\n",
		    (long)ti->rt_clock_start.tv_sec, ti->rt_clock_start.tv_nsec,
		    (long)ti->rt_clock_stop.tv_sec, ti->rt_clock_stop.tv_nsec,
		    vars[MULTIPLIER], vars[MULTIPLICANT], vars[PRODUCT],
		    ti->product, ti->flipped_bits, ti->i,
		    (long)ti->duration.tv_sec, ti->duration.tv_nsec,
		    cpu_usage);

	return rv;
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

static void multiply(struct thread_info *ti)
{
	struct timespec mon_clock_start;
	struct timespec mon_clock_stop;
#if defined(_POSIX_THREAD_CPUTIME) || _POSIX_THREAD_CPUTIME > 0
#ifdef __linux__
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,12)
	struct timespec thread_clock_start;
	struct timespec thread_clock_stop;
	struct timespec cpu_time;
#endif /* LINUX_VERSION_CODE */
#endif /* __linux__ */
#endif /* _POSIX_THREAD_CPUTIME */

	if (clock_gettime(CLOCK_REALTIME, &ti->rt_clock_start) == -1)
		goto mulfail;

	if (clock_gettime(clkid, &mon_clock_start) == -1)
		goto mulfail;
	
#if defined(_POSIX_THREAD_CPUTIME) || _POSIX_THREAD_CPUTIME > 0
#ifdef __linux__
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,12)	
	if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &thread_clock_start) == -1)
		goto mulfail;
#endif /* LINUX_VERSION_CODE */
#endif /* __linux__ */
#endif /* _POSIX_THREAD_CPUTIME */
#if !defined(_POSIX_THREAD_CPUTIME) || _POSIX_THREAD_CPUTIME < 0 || !defined(__linux__) || LINUX_VERSION_CODE < KERNEL_VERSION(2,6,12)
	ti->cpu_clock_start = clock();
#endif /* otherwise */
	
	for (ti->i = 0; ti->i < 1000000000; ti->i++) {
		ti->product = vars[MULTIPLIER] * vars[MULTIPLICANT];
		if (ti->product != vars[PRODUCT])
			break;
		ti->product = vars[MULTIPLICANT] * vars[MULTIPLIER];
		if (vars[PRODUCT] != ti->product)
			break;
	}

#if defined(_POSIX_THREAD_CPUTIME) || _POSIX_THREAD_CPUTIME > 0
#ifdef __linux__
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,12)	
	if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &thread_clock_stop) == -1)
		goto mulfail;
#endif /* LINUX_VERSION_CODE */
#endif /* __linux__ */
#endif /* _POSIX_THREAD_CPUTIME */
#if !defined(_POSIX_THREAD_CPUTIME) || _POSIX_THREAD_CPUTIME < 0 || !defined(__linux__) || LINUX_VERSION_CODE < KERNEL_VERSION(2,6,12)
	cpu_clock_stop = clock();
#endif /* otherwise */

	if (clock_gettime(clkid, &mon_clock_stop) == -1)
		goto mulfail;
	
	if (clock_gettime(CLOCK_REALTIME, &ti->rt_clock_stop) == -1)
		goto mulfail;
	
#if defined(_POSIX_THREAD_CPUTIME) || _POSIX_THREAD_CPUTIME > 0
#ifdef __linux__
#if LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,12)
	clock_diff(&thread_clock_start, &thread_clock_stop, &cpu_time);
	ti->cpu_time = cpu_time.tv_sec;
	ti->cpu_time += ((double)cpu_time.tv_nsec) / 1000000000;
#endif /* LINUX_VERSION_CODE */
#endif /* __linux__ */
#endif /* _POSIX_THREAD_CPUTIME */
#if !defined(_POSIX_THREAD_CPUTIME) || _POSIX_THREAD_CPUTIME < 0 || !defined(__linux__) || LINUX_VERSION_CODE < KERNEL_VERSION(2,6,12)
	if ((cpu_clock_start == (clock_t)-1) ||
	    (cpu_clock_stop == (clock_t)-1))
		fprintf(stderr, "clock(): processor time not available or its value cannot be represented.\n");
	ti->cpu_time = ((double)(cpu_clock_stop - cpu_clock_start)) / CLOCKS_PER_SEC;
	ti->cpu_time /= cores;
#endif /* otherwise */

	clock_diff(&mon_clock_start, &mon_clock_stop, &ti->duration);
	
	ti->flipped_bits = ti->product ^ vars[PRODUCT];
return;
mulfail:
perror("clock_gettime");
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

static void *thread_main(void *arg)
{
	int niceness = -5;
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

	errno = 0;
	niceness = nice(niceness);
	if (niceness == -1 && errno != 0) {
		fprintf(stderr, "thread[%d]: ", ti->id);
		perror("nice");
	}

	if (infinite)
		infinite_multiply(ti);
	else
		multiply(ti);

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

	// Initialize clocks
	init_clock();
	
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

	if (verbose)
		for (i = 0; i < cores; i++)
			rv = log_result(&ti[i]);

	if (rv)
		return EXIT_FAILURE;

	return EXIT_SUCCESS;
}
