/**
 * @file test_enr312_crashrec.c
 * @brief Host tests for the 500 Hz crash recorder.
 */
#include "enr312_crashrec.h"
#include "test_harness.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static CrashRec_t R;

/* dump everything; returns the number of 'k' lines, checks they are consecutive ticks */
static unsigned dump(unsigned long *first, unsigned long *last, char *begin, size_t blen)
{
    char l[64]; unsigned n = 0; unsigned long prev = 0; int consecutive = 1;
    begin[0] = '\0';
    while (ENR312_CrashRec_NextLine(&R, l, sizeof l)) {
        if (strncmp(l, "K,BEGIN", 7) == 0) { strncpy(begin, l, blen - 1); begin[blen - 1] = '\0'; continue; }
        if (strncmp(l, "K,END", 5) == 0) { continue; }
        unsigned long t = strtoul(l + 2, NULL, 10);
        if (n == 0) { *first = t; } else if (t != prev + 1u) { consecutive = 0; }
        prev = t; *last = t; n++;
    }
    CHECK(consecutive, "ticks consecutive, oldest first");
    return n;
}

int main(void)
{
    printf("Crash recorder tests\n");
    char b[96]; unsigned long f = 0, l = 0;

    /* 1. a short record: 300 ticks, trigger, 250 more */
    ENR312_CrashRec_Init(&R);
    for (uint32_t t = 1; t <= 300; ++t) { ENR312_CrashRec_Push(&R, t, 0.0, 0.0, 0.0, 0u); }
    CHECK(ENR312_CrashRec_Trigger(&R, "PENDULUM_LOST"), "trigger accepted while recording");
    CHECK(!ENR312_CrashRec_Trigger(&R, "OPERATOR"), "a second trigger is ignored");
    for (uint32_t t = 301; t <= 549; ++t) { ENR312_CrashRec_Push(&R, t, 0.0, 0.0, 0.0, 0u); }
    CHECK(!ENR312_CrashRec_IsFrozen(&R), "still recording 249 ticks after the trigger");
    ENR312_CrashRec_Push(&R, 550, 0.0, 0.0, 0.0, 0u);
    CHECK(ENR312_CrashRec_IsFrozen(&R), "frozen 250 ticks after the trigger");
    ENR312_CrashRec_Push(&R, 551, 0.0, 0.0, 0.0, 0u);
    unsigned n = dump(&f, &l, b, sizeof b);
    CHECK_EQ_I(n, 550, "all 550 samples");
    CHECK_EQ_I(f, 1, "first tick"); CHECK_EQ_I(l, 550, "last tick: nothing recorded once frozen");
    CHECK(strcmp(b, "K,BEGIN,PENDULUM_LOST,550,300,500\r\n") == 0, "header: %s", b);
    CHECK(!ENR312_CrashRec_IsFrozen(&R) && R.count == 0u, "re-armed after the dump");

    /* 2. the ring wraps: 1.5 s before and 0.5 s after the trigger */
    for (uint32_t t = 1; t <= 2500; ++t) { ENR312_CrashRec_Push(&R, t, 0.0, 0.0, 0.0, 0u); }
    (void)ENR312_CrashRec_Trigger(&R, "OPERATOR");
    for (uint32_t t = 2501; t <= 2800; ++t) { ENR312_CrashRec_Push(&R, t, 0.0, 0.0, 0.0, 0u); }
    n = dump(&f, &l, b, sizeof b);
    CHECK_EQ_I(n, CRASHREC_N, "a full ring");
    CHECK_EQ_I(f, 1751, "oldest = 1.5 s before the trigger"); CHECK_EQ_I(l, 2750, "newest = 0.5 s after");
    CHECK(strcmp(b, "K,BEGIN,OPERATOR,1000,2500,500\r\n") == 0, "header: %s", b);

    /* 3. values: millidegrees rounded both ways, u saturated to int16 */
    ENR312_CrashRec_Push(&R, 7, -1.23456, 180.0004, 40000.0, 8u);
    (void)ENR312_CrashRec_Trigger(&R, "OPERATOR");
    for (uint32_t t = 0; t < CRASHREC_POST; ++t) { ENR312_CrashRec_Push(&R, 8u + t, 0.0, 0.0, -40000.0, 8u); }
    char line[64];
    CHECK(ENR312_CrashRec_NextLine(&R, line, sizeof line), "header");
    CHECK(ENR312_CrashRec_NextLine(&R, line, sizeof line) && strcmp(line, "k,7,-1235,180000,32767,8\r\n") == 0, "sample: %s", line);
    CHECK(ENR312_CrashRec_NextLine(&R, line, sizeof line) && strcmp(line, "k,8,0,0,-32768,8\r\n") == 0, "sample: %s", line);
    CHECK(!ENR312_CrashRec_NextLine(&R, line, 0u), "zero-length buffer refused");

    /* 4. not frozen: nothing to send */
    ENR312_CrashRec_Init(&R);
    CHECK(!ENR312_CrashRec_NextLine(&R, line, sizeof line), "nothing to dump while recording");

    printf("test_enr312_crashrec                     %d checks, %d failed\n", enr312_tests_run, enr312_tests_failed);
    return enr312_tests_failed ? 1 : 0;
}
