/* Minimal assertion harness for the ENR312 host unit tests.
 * Deliberately tiny and dependency-free: the tests must be runnable with
 * nothing but a C compiler, on any machine that has the repository. */
#ifndef ENR312_TEST_HARNESS_H
#define ENR312_TEST_HARNESS_H

#include <stdio.h>
#include <math.h>

static int enr312_tests_run = 0;
static int enr312_tests_failed = 0;

#define CHECK(cond, ...)                                                      \
    do {                                                                      \
        enr312_tests_run++;                                                   \
        if (!(cond)) {                                                        \
            enr312_tests_failed++;                                            \
            printf("  FAIL %s:%d: ", __FILE__, __LINE__);                     \
            printf(__VA_ARGS__);                                              \
            printf("\n");                                                     \
        }                                                                     \
    } while (0)

#define CHECK_EQ_I(a, b, ...)                                                 \
    do {                                                                      \
        long long _a = (long long)(a), _b = (long long)(b);                   \
        enr312_tests_run++;                                                   \
        if (_a != _b) {                                                       \
            enr312_tests_failed++;                                            \
            printf("  FAIL %s:%d: got %lld want %lld: ",                      \
                   __FILE__, __LINE__, _a, _b);                               \
            printf(__VA_ARGS__);                                              \
            printf("\n");                                                     \
        }                                                                     \
    } while (0)

#define CHECK_NEAR(a, b, tol, ...)                                            \
    do {                                                                      \
        double _a = (double)(a), _b = (double)(b), _t = (double)(tol);        \
        enr312_tests_run++;                                                   \
        if (!(fabs(_a - _b) <= _t)) {                                         \
            enr312_tests_failed++;                                            \
            printf("  FAIL %s:%d: got %.12g want %.12g (tol %.3g): ",         \
                   __FILE__, __LINE__, _a, _b, _t);                           \
            printf(__VA_ARGS__);                                              \
            printf("\n");                                                     \
        }                                                                     \
    } while (0)

#define TEST_REPORT(name)                                                     \
    do {                                                                      \
        printf("%-40s %3d checks, %d failed\n",                               \
               (name), enr312_tests_run, enr312_tests_failed);                \
    } while (0)

#endif /* ENR312_TEST_HARNESS_H */
