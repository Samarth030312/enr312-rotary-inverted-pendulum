/**
 * @file    enr312_encoder.c
 * @brief   EXP001 sensing chain implementation. See enr312_encoder.h.
 */

#include "enr312_encoder.h"

int32_t ENR312_Encoder_WrappedDiff(uint16_t now, uint16_t prev)
{
    /* Equation (8):  d = ((now - prev + 2^15) mod 2^16) - 2^15
     *
     * The subtraction is performed in uint16_t so it wraps modulo 2^16 by the
     * language's own rules for unsigned arithmetic -- no explicit masking is
     * needed and none is used, because a mask would invite a width bug.
     *
     * Adding 2^15 before reducing, then subtracting it after, re-centres the
     * result on zero so that a raw difference of 0xFFFF is correctly read as
     * -1 rather than as +65535.
     */
    uint16_t raw = (uint16_t)(now - prev);
    return (int32_t)raw - (int32_t)((raw & 0x8000u) ? 0x10000 : 0);
}

void ENR312_Encoder_Init(ENR312_Encoder_t *e, uint16_t raw_now, int32_t polarity)
{
    e->last_raw        = raw_now;
    e->accum_counts    = 0;
    e->origin_counts   = 0;
    e->polarity        = (polarity == -1) ? -1 : +1;  /* reject anything else */
    e->prev_rel_counts = 0;
    e->have_prev       = false;
    e->wrap_events     = 0u;
}

void ENR312_Encoder_Update(ENR312_Encoder_t *e, uint16_t raw_now)
{
    int32_t d = ENR312_Encoder_WrappedDiff(raw_now, e->last_raw);

    /* Diagnostic only: a "wrap" is when the raw value crosses the 16-bit
     * boundary. Detected by the raw difference and the sign disagreeing about
     * which side of the modulus we are on. Counted, never acted upon -- the
     * arithmetic above is already correct without knowing about wraps. */
    if ((d > 0 && raw_now < e->last_raw) || (d < 0 && raw_now > e->last_raw)) {
        e->wrap_events++;
    }

    e->prev_rel_counts = ENR312_Encoder_GetRelativeCounts(e);
    e->accum_counts   += (int64_t)d;
    e->last_raw        = raw_now;
    e->have_prev       = true;
}

int64_t ENR312_Encoder_GetRelativeCounts(const ENR312_Encoder_t *e)
{
    return e->accum_counts - e->origin_counts;
}

double ENR312_Encoder_GetAngleRad(const ENR312_Encoder_t *e)
{
    return (double)e->polarity
         * (double)ENR312_Encoder_GetRelativeCounts(e)
         * ENR312_ENCODER_RAD_PER_COUNT;
}

double ENR312_Encoder_GetAngleDeg(const ENR312_Encoder_t *e)
{
    return (double)e->polarity
         * (double)ENR312_Encoder_GetRelativeCounts(e)
         * ENR312_ENCODER_DEG_PER_COUNT;
}

double ENR312_Encoder_GetVelocityRadS(const ENR312_Encoder_t *e, double ts_s)
{
    if (!e->have_prev || ts_s <= 0.0) {
        return 0.0;
    }
    int64_t d = ENR312_Encoder_GetRelativeCounts(e) - e->prev_rel_counts;
    return (double)e->polarity * (double)d * ENR312_ENCODER_RAD_PER_COUNT / ts_s;
}

void ENR312_Encoder_SetOriginHere(ENR312_Encoder_t *e)
{
    e->origin_counts   = e->accum_counts;
    e->prev_rel_counts = 0;
    e->have_prev       = false;   /* first velocity after re-zeroing is undefined */
}
