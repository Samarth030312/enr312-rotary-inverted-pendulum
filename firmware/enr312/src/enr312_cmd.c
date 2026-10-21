/**
 * @file    enr312_cmd.c
 * @brief   '$' line commands from the host. See enr312_cmd.h.
 */
#include "enr312_cmd.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int ENR312_Cmd_FormatFixed(char *buf, int len, double v)
{
    if (!isfinite(v)) { return snprintf(buf, (size_t)len, "nan"); }
    long m = (long)(fabs(v) * 1000.0 + 0.5);
    return snprintf(buf, (size_t)len, "%s%ld.%03ld", (v < 0.0 && m != 0) ? "-" : "",
                    m / 1000, m % 1000);
}

static void report(const ENR312_RunnerConfig_t *c, char *out, int n)
{
    /* the first 8 values are protocol 2 (unchanged order); protocol 3 appends the rest */
    const double v[] = {c->kp, c->kd, c->kpp, c->kdp, c->step_deg, c->dist, c->u_limit, c->v_max,
                        c->ki, c->fdr, c->fdp, c->k1, c->k2, c->k3, c->k4, c->bv, c->imp_deg,
                        c->uon, c->db, c->ref_rate, (double)c->div, (double)c->ma,
                        (double)c->seq, c->wg2,    /* protocol 4 appends seq, wg2 */
                        c->amp};                   /* protocol 5 appends amp     */
    int k = snprintf(out, (size_t)n, "C,%u", (unsigned)c->exp);
    for (unsigned i = 0; i < sizeof v / sizeof v[0] && k > 0 && k < n; ++i) {
        k += snprintf(out + k, (size_t)(n - k), ",");
        if (k < n) { k += ENR312_Cmd_FormatFixed(out + k, n - k, v[i]); }
    }
}

ENR312_CmdAction_t ENR312_Cmd_Line(const char *line, ENR312_RunnerConfig_t *cfg,
                                   double *move_deg, char *reply, int reply_len)
{
    char key[16];
    size_t i = 0;
    while (line[i] == ' ') { line++; }
    while (line[i] != '\0' && line[i] != '=' && i < sizeof key - 1u) {
        key[i] = line[i]; i++;
    }
    key[i] = '\0';
    while (i > 0u && key[i - 1u] == ' ') { key[--i] = '\0'; }
    const char *val = (line[i] == '=') ? line + i + 1 : NULL;

    if (strcmp(key, "cfg") == 0)  { report(cfg, reply, reply_len); return ENR312_CMD_REPLY; }
    if (strcmp(key, "go") == 0)   { snprintf(reply, (size_t)reply_len, "GO"); return ENR312_CMD_GO; }
    if (strcmp(key, "stop") == 0) { snprintf(reply, (size_t)reply_len, "STOP"); return ENR312_CMD_STOP; }
    if (strcmp(key, "defaults") == 0) {
        ENR312_Runner_Defaults(cfg, cfg->exp);
        report(cfg, reply, reply_len);
        return ENR312_CMD_REPLY;
    }
    if (val == NULL) {
        snprintf(reply, (size_t)reply_len, "ERR unknown command '%s'", key);
        return ENR312_CMD_REPLY;
    }
    char *end = NULL;
    double x = strtod(val, &end);
    if (end == val || !isfinite(x)) {
        snprintf(reply, (size_t)reply_len, "ERR %s: not a number", key);
        return ENR312_CMD_REPLY;
    }
    if (strcmp(key, "ref") == 0) {
        if (fabs(x) > 90.0) {
            snprintf(reply, (size_t)reply_len, "ERR ref limited to +/-90 deg");
            return ENR312_CMD_REPLY;
        }
        *move_deg = x;
        snprintf(reply, (size_t)reply_len, "REF");
        return ENR312_CMD_REF;
    }
    if (strcmp(key, "move") == 0) {
        if (fabs(x) > 90.0) {
            snprintf(reply, (size_t)reply_len, "ERR move limited to +/-90 deg");
            return ENR312_CMD_REPLY;
        }
        *move_deg = x;
        snprintf(reply, (size_t)reply_len, "MOVE");
        return ENR312_CMD_MOVE;
    }

    ENR312_RunnerConfig_t trial = *cfg;
    if (strcmp(key, "exp") == 0) {
        if (x != floor(x) || !((x >= 2.0 && x <= 10.0) || (x >= 21.0 && x <= 24.0))) {
            snprintf(reply, (size_t)reply_len, "ERR exp must be 2..10 or 21..24 (EXP001 is open loop: move=, +, -)");
            return ENR312_CMD_REPLY;
        }
        ENR312_Runner_Defaults(&trial, (uint8_t)x);
    }
    else if (strcmp(key, "kp") == 0)   { trial.kp = x; }
    else if (strcmp(key, "kd") == 0)   { trial.kd = x; }
    else if (strcmp(key, "kpp") == 0)  { trial.kpp = x; }
    else if (strcmp(key, "kdp") == 0)  { trial.kdp = x; }
    else if (strcmp(key, "step") == 0) { trial.step_deg = x; }
    else if (strcmp(key, "dist") == 0) { trial.dist = x; }
    else if (strcmp(key, "ulim") == 0) { trial.u_limit = x; }
    else if (strcmp(key, "vmax") == 0) { trial.v_max = x; }
    else if (strcmp(key, "ki") == 0)   { trial.ki = x; }
    else if (strcmp(key, "fdr") == 0)  { trial.fdr = x; }
    else if (strcmp(key, "fdp") == 0)  { trial.fdp = x; }
    else if (strcmp(key, "k1") == 0)   { trial.k1 = x; }
    else if (strcmp(key, "k2") == 0)   { trial.k2 = x; }
    else if (strcmp(key, "k3") == 0)   { trial.k3 = x; }
    else if (strcmp(key, "k4") == 0)   { trial.k4 = x; }
    else if (strcmp(key, "bv") == 0)   { trial.bv = x; }
    else if (strcmp(key, "imp") == 0)  { trial.imp_deg = x; }
    else if (strcmp(key, "uon") == 0)  { trial.uon = x; }
    else if (strcmp(key, "db") == 0)   { trial.db = x; }
    else if (strcmp(key, "rrate") == 0) { trial.ref_rate = x; }
    else if (strcmp(key, "wg2") == 0)  { trial.wg2 = x; }
    else if (strcmp(key, "amp") == 0)  { trial.amp = x; }
    else if (strcmp(key, "seq") == 0) {
        if (x != 0.0 && x != 1.0) {
            snprintf(reply, (size_t)reply_len, "ERR seq must be 0 or 1");
            return ENR312_CMD_REPLY;
        }
        trial.seq = (uint8_t)x;
    }
    else if (strcmp(key, "div") == 0 || strcmp(key, "ma") == 0) {
        if (x != floor(x) || x < 1.0 || x > 255.0) {
            snprintf(reply, (size_t)reply_len, "ERR %s must be a whole number", key);
            return ENR312_CMD_REPLY;
        }
        if (key[0] == 'd') { trial.div = (uint8_t)x; } else { trial.ma = (uint8_t)x; }
    }
    else {
        snprintf(reply, (size_t)reply_len, "ERR unknown parameter '%s'", key);
        return ENR312_CMD_REPLY;
    }
    const char *why = ENR312_Runner_Validate(&trial);
    if (why != NULL) {
        snprintf(reply, (size_t)reply_len, "ERR %s", why);
        return ENR312_CMD_REPLY;
    }
    *cfg = trial;
    report(cfg, reply, reply_len);
    return ENR312_CMD_REPLY;
}
