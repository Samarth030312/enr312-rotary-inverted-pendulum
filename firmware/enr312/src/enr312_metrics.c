/**
 * @file    enr312_metrics.c
 * @brief   Online step-response metrics. See enr312_metrics.h.
 */

#include "enr312_metrics.h"
#include <math.h>

void ENR312_StepMetrics_Init(ENR312_StepMetrics_t *m, ENR312_SettleMode_t mode,
                             double final_value, double tol, double ts_s)
{
    m->mode           = mode;
    m->tol            = (tol > 0.0) ? tol : 0.02;
    m->final_value    = final_value;
    m->ts_s           = (ts_s > 0.0) ? ts_s : 0.002;
    m->peak           = 0.0;
    m->peak_time_s    = 0.0;
    m->last_outside_s = 0.0;
    m->samples        = 0u;
    m->any_sample     = false;
}

void ENR312_StepMetrics_Update(ENR312_StepMetrics_t *m, double value, double t_s)
{
    if (!isfinite(value)) {
        return;                       /* never let a NaN poison the metrics */
    }

    double a = fabs(value);
    if (a > m->peak) {
        m->peak        = a;
        m->peak_time_s = t_s;
    }

    /* The band differs by mode -- see the header. In SETTLE_TO_ZERO the band is
     * relative to the peak SO FAR, which is why the result is only meaningful
     * after the excursion has happened. */
    double centre = (m->mode == ENR312_SETTLE_TO_FINAL) ? m->final_value : 0.0;
    double band   = (m->mode == ENR312_SETTLE_TO_FINAL)
                        ? m->tol * fabs(m->final_value)
                        : m->tol * m->peak;

    if (fabs(value - centre) > band) {
        m->last_outside_s = t_s;
    }

    m->samples++;
    m->any_sample = true;
}

double ENR312_StepMetrics_Overshoot(const ENR312_StepMetrics_t *m)
{
    if (m->mode != ENR312_SETTLE_TO_FINAL || fabs(m->final_value) < 1e-12) {
        return NAN;                   /* undefined without a final value */
    }
    return 100.0 * (m->peak - fabs(m->final_value)) / fabs(m->final_value);
}

double ENR312_StepMetrics_Settling(const ENR312_StepMetrics_t *m)
{
    return m->any_sample ? m->last_outside_s : 0.0;
}
