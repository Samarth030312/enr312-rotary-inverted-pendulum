/**
 * @file enr312_crashrec.c
 * @brief Crash recorder (see the header). Portable C, no HAL: host-tested.
 */
#include "enr312_crashrec.h"

#include <stdio.h>

static int32_t to_mdeg(double deg)
{
    double m = deg * 1000.0;
    if (m > 2.0e9) { m = 2.0e9; } else if (m < -2.0e9) { m = -2.0e9; }
    return (int32_t)(m + ((m >= 0.0) ? 0.5 : -0.5));
}

static int16_t sat16(double v)
{
    if (v > 32767.0) { return (int16_t)32767; }
    if (v < -32768.0) { return (int16_t)-32768; }
    return (int16_t)(v + ((v >= 0.0) ? 0.5 : -0.5));
}

void ENR312_CrashRec_Init(CrashRec_t *r)
{
    r->head = 0u; r->count = 0u; r->post_left = 0u;
    r->state = CRASHREC_RECORDING; r->trigger_tick = 0u; r->reason = "";
    r->dump_i = 0u; r->dump_begun = false;
}

void ENR312_CrashRec_Push(CrashRec_t *r, uint32_t tick, double rotor_deg, double pend_deg,
                          double u, uint8_t phase)
{
    if (r->state == CRASHREC_FROZEN) { return; }
    CrashRec_Sample_t *s = &r->buf[r->head];
    s->tick = tick; s->rotor_mdeg = to_mdeg(rotor_deg); s->pend_mdeg = to_mdeg(pend_deg);
    s->u = sat16(u); s->phase = phase; s->pad_ = 0u;
    r->head = (r->head + 1u) % CRASHREC_N;
    if (r->count < CRASHREC_N) { r->count++; }
    if (r->state == CRASHREC_POSTTRIGGER) {
        if (r->post_left > 0u) { r->post_left--; }
        if (r->post_left == 0u) { r->state = CRASHREC_FROZEN; r->dump_i = 0u; r->dump_begun = false; }
    }
}

bool ENR312_CrashRec_Trigger(CrashRec_t *r, const char *reason)
{
    if (r->state != CRASHREC_RECORDING) { return false; }
    r->reason = reason;
    r->trigger_tick = (r->count > 0u) ? r->buf[(r->head + CRASHREC_N - 1u) % CRASHREC_N].tick : 0u;
    r->post_left = CRASHREC_POST;
    r->state = CRASHREC_POSTTRIGGER;
    return true;
}

bool ENR312_CrashRec_IsFrozen(const CrashRec_t *r)
{
    return r->state == CRASHREC_FROZEN;
}

bool ENR312_CrashRec_NextLine(CrashRec_t *r, char *buf, size_t len)
{
    if (r->state != CRASHREC_FROZEN || len == 0u) { return false; }
    if (!r->dump_begun) {
        r->dump_begun = true; r->dump_i = 0u;
        (void)snprintf(buf, len, "K,BEGIN,%s,%lu,%lu,500\r\n", r->reason,
                       (unsigned long)r->count, (unsigned long)r->trigger_tick);
        return true;
    }
    if (r->dump_i < r->count) {
        /* oldest first: when the ring is full the oldest is at head */
        uint32_t start = (r->count < CRASHREC_N) ? 0u : r->head;
        const CrashRec_Sample_t *s = &r->buf[(start + r->dump_i) % CRASHREC_N];
        (void)snprintf(buf, len, "k,%lu,%ld,%ld,%d,%u\r\n", (unsigned long)s->tick, (long)s->rotor_mdeg,
                       (long)s->pend_mdeg, (int)s->u, (unsigned)s->phase);
        r->dump_i++;
        return true;
    }
    (void)snprintf(buf, len, "K,END\r\n");
    ENR312_CrashRec_Init(r);                                   /* re-arm, start a fresh window */
    return true;
}
