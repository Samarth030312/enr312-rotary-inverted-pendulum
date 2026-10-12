/**
 * @file test_enr312_cmd.c
 * @brief Host tests for the '$' host command parser.
 */
#include "enr312_cmd.h"
#include "test_harness.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    ENR312_RunnerConfig_t c; char r[128]; double mv = 0.0;
    printf("Host command parser tests\n");
    ENR312_Runner_Defaults(&c, 5);

    CHECK_EQ_I(ENR312_Cmd_Line("exp=2", &c, &mv, r, sizeof r), ENR312_CMD_REPLY, "exp");
    CHECK_EQ_I(c.exp, 2, "exp selected");
    CHECK(strcmp(r, "C,2,5.000,2.500,0.000,0.000,2.000,1.000,400.000,360.000") == 0, "defaults reported: %s", r);
    ENR312_Cmd_Line("kp=6.55", &c, &mv, r, sizeof r);
    CHECK_NEAR(c.kp, 6.55, 1e-12, "kp set");
    ENR312_Cmd_Line("kp=500", &c, &mv, r, sizeof r);
    CHECK(strncmp(r, "ERR", 3) == 0 && fabs(c.kp - 6.55) < 1e-12, "invalid kp rejected, old kept: %s", r);
    ENR312_Cmd_Line("kp=abc", &c, &mv, r, sizeof r);
    CHECK(strncmp(r, "ERR", 3) == 0, "non-number rejected");
    ENR312_Cmd_Line("exp=1", &c, &mv, r, sizeof r);
    CHECK(strncmp(r, "ERR", 3) == 0 && c.exp == 2, "exp 1 is not a closed-loop experiment");
    ENR312_Cmd_Line("exp=5", &c, &mv, r, sizeof r);
    ENR312_Cmd_Line("ulim=1600", &c, &mv, r, sizeof r);
    CHECK(strncmp(r, "ERR", 3) == 0, "EXP005 ulim ceiling enforced");
    ENR312_Cmd_Line("step=-1.5", &c, &mv, r, sizeof r);
    CHECK_NEAR(c.step_deg, -1.5, 1e-12, "negative step ok");
    CHECK_EQ_I(ENR312_Cmd_Line("go", &c, &mv, r, sizeof r), ENR312_CMD_GO, "go");
    CHECK_EQ_I(ENR312_Cmd_Line("stop", &c, &mv, r, sizeof r), ENR312_CMD_STOP, "stop");
    CHECK_EQ_I(ENR312_Cmd_Line("move=12.5", &c, &mv, r, sizeof r), ENR312_CMD_MOVE, "move");
    CHECK_NEAR(mv, 12.5, 1e-12, "move value");
    ENR312_Cmd_Line("move=200", &c, &mv, r, sizeof r);
    CHECK(strncmp(r, "ERR", 3) == 0, "move limited");
    ENR312_Cmd_Line("nonsense", &c, &mv, r, sizeof r);
    CHECK(strncmp(r, "ERR", 3) == 0, "unknown command");
    char b[32]; ENR312_Cmd_FormatFixed(b, sizeof b, -0.0004);
    CHECK(strcmp(b, "0.000") == 0, "no negative zero: %s", b);
    ENR312_Cmd_FormatFixed(b, sizeof b, -2.5);
    CHECK(strcmp(b, "-2.500") == 0, "negative: %s", b);
    TEST_REPORT("test_enr312_cmd");
    return enr312_tests_failed ? 1 : 0;
}
