/**
 * @file    enr312_exp001.c
 * @brief   EXP001 experiment sequencer implementation. See enr312_exp001.h.
 */

#include "enr312_exp001.h"
#include <stdio.h>
#include <math.h>

const double ENR312_EXP001_P1_SETPOINTS_DEG[] = {
    0.0, 45.0, 0.0, -90.0, 0.0
};
const uint32_t ENR312_EXP001_P1_SETPOINT_COUNT =
    (uint32_t)(sizeof(ENR312_EXP001_P1_SETPOINTS_DEG) /
               sizeof(ENR312_EXP001_P1_SETPOINTS_DEG[0]));

void ENR312_Exp001_Init(ENR312_Exp001_t *x, uint16_t raw_counter_now, bool armed)
{
    ENR312_Encoder_Init(&x->encoder, raw_counter_now, ENR312_ENCODER_POLARITY);
    ENR312_Rotor_Init(&x->rotor, ENR312_ROTOR_POLARITY);

    x->phase            = EXP001_PHASE_IDLE;
    x->abort_reason     = EXP001_ABORT_NONE;
    x->tick             = 0u;
    x->phase_tick       = 0u;
    x->armed            = armed;
    x->ts_s             = ENR312_CONTROL_PERIOD_S;
    x->p1_index         = 0u;
    x->p3_cycle         = 0u;
    x->p3_substep       = 0u;
    x->p3_cycles_target = 10u;   /* P3 asks for 10 repetitions */

    x->last.tick                 = 0u;
    x->last.t_s                  = 0.0;
    x->last.phase                = (uint8_t)x->phase;
    x->last.rotor_cmd_microsteps = 0;
    x->last.rotor_cmd_deg        = 0.0;
    x->last.encoder_counts       = 0;
    x->last.pendulum_deg         = 0.0;
    x->last.pendulum_vel_rad_s   = 0.0;
    x->last.abort_reason         = (uint8_t)EXP001_ABORT_NONE;
}

void ENR312_Exp001_Abort(ENR312_Exp001_t *x)
{
    if (x->phase != EXP001_PHASE_ABORTED) {
        x->phase        = EXP001_PHASE_ABORTED;
        x->abort_reason = EXP001_ABORT_OPERATOR;
    }
}

bool ENR312_Exp001_IsFinished(const ENR312_Exp001_t *x)
{
    return (x->phase == EXP001_PHASE_DONE) || (x->phase == EXP001_PHASE_ABORTED);
}

/* Move the arm toward a setpoint, honouring the dry-run flag.
 *
 * When disarmed the commanded position is deliberately NOT advanced. A dry run
 * must not leave the position model believing the arm moved -- that would make
 * the dry run's telemetry indistinguishable from a real run and defeat its
 * purpose. */
static void exp001_goto(ENR312_Exp001_t *x, double target_deg)
{
    if (!x->armed) {
        return;
    }
    int64_t actual = 0;
    ENR312_RotorStatus_t st = ENR312_Rotor_GoToDegrees(&x->rotor, target_deg, &actual);
    if (st == ENR312_ROTOR_CLAMPED_TO_LIMIT) {
        x->phase        = EXP001_PHASE_ABORTED;
        x->abort_reason = EXP001_ABORT_ROTOR_LIMIT;
    }
}

static void exp001_advance_phase(ENR312_Exp001_t *x, ENR312_Exp001Phase_t next)
{
    x->phase      = next;
    x->phase_tick = 0u;
}

const ENR312_Exp001Sample_t *ENR312_Exp001_Tick(ENR312_Exp001_t *x,
                                                uint16_t raw_counter_now)
{
    /* ---- 1. Sense ------------------------------------------------------- */
    ENR312_Encoder_Update(&x->encoder, raw_counter_now);

    double pend_deg = ENR312_Encoder_GetAngleDeg(&x->encoder);
    double pend_vel = ENR312_Encoder_GetVelocityRadS(&x->encoder, x->ts_s);

    /* ---- 2. Safety, evaluated before any command ------------------------ *
     * Checked every tick and in every phase, including IDLE and dry runs, so
     * that the abort path itself is exercised by the dry run rather than being
     * code that has never executed when it is first needed. */
    if (!ENR312_Exp001_IsFinished(x)) {
        if (fabs(pend_deg) > ENR312_PENDULUM_ABORT_DEG) {
            x->phase        = EXP001_PHASE_ABORTED;
            x->abort_reason = EXP001_ABORT_PENDULUM_LIMIT;
        }
    }

    /* ---- 3. Sequence ---------------------------------------------------- */
    switch (x->phase) {

    case EXP001_PHASE_IDLE:
        if (x->phase_tick >= EXP001_IDLE_TICKS) {
            exp001_advance_phase(x, EXP001_PHASE_SENSE_ONLY);
        }
        break;

    case EXP001_PHASE_SENSE_ONLY:
        /* Motor commanded nowhere. The operator rotates the pendulum by hand
         * to establish resolution (P2) and sign (P2b). No motion is issued in
         * this phase in either armed or dry-run mode. */
        if (x->phase_tick >= EXP001_SENSE_ONLY_TICKS) {
            exp001_advance_phase(x, EXP001_PHASE_STEP_P1);
            x->p1_index = 0u;
            exp001_goto(x, ENR312_EXP001_P1_SETPOINTS_DEG[0]);
        }
        break;

    case EXP001_PHASE_STEP_P1:
        if (x->phase_tick >= EXP001_P1_DWELL_TICKS) {
            x->p1_index++;
            if (x->p1_index >= ENR312_EXP001_P1_SETPOINT_COUNT) {
                exp001_advance_phase(x, EXP001_PHASE_RETURN_P3);
                x->p3_cycle   = 0u;
                x->p3_substep = 0u;
                exp001_goto(x, 0.0);   /* substep 0 command, issued on entry */
            } else {
                x->phase_tick = 0u;
                exp001_goto(x, ENR312_EXP001_P1_SETPOINTS_DEG[x->p1_index]);
            }
        }
        break;

    case EXP001_PHASE_RETURN_P3: {
        /* Zero-net-motion cycles. One cycle is four dwells: 0 -> +A -> 0 -> -A
         * -> 0, so the net commanded motion per cycle is exactly zero. Any
         * residual PHYSICAL offset after N cycles is therefore lost steps --
         * which is the entire point of P3.
         *
         * The command for a substep is issued when that substep is ENTERED,
         * not on a modulo test against phase_tick. phase_tick is incremented
         * at the end of the tick, so it is never observed as 0 inside a phase,
         * and a modulo-based trigger would silently skip the first move. */
        if (x->phase_tick >= EXP001_P3_DWELL_TICKS) {
            x->phase_tick = 0u;
            x->p3_substep = (x->p3_substep + 1u) & 3u;
            if (x->p3_substep == 0u) {
                x->p3_cycle++;
                if (x->p3_cycle >= x->p3_cycles_target) {
                    /* Return to zero BEFORE finishing. Breaking out here without
                     * issuing the substep-0 command would leave the arm parked
                     * at -90 deg and would leave the commanded position at -800
                     * microsteps -- i.e. a "zero-net-motion" test that does not
                     * end at zero net motion, silently invalidating P3. */
                    exp001_goto(x, 0.0);
                    exp001_advance_phase(x, EXP001_PHASE_DONE);
                    break;
                }
            }
            switch (x->p3_substep) {
            case 0u: exp001_goto(x, 0.0);                      break;
            case 1u: exp001_goto(x, +EXP001_P3_AMPLITUDE_DEG); break;
            case 2u: exp001_goto(x, 0.0);                      break;
            case 3u: exp001_goto(x, -EXP001_P3_AMPLITUDE_DEG); break;
            default: break;
            }
        }
        break;
    }

    case EXP001_PHASE_DONE:
    case EXP001_PHASE_ABORTED:
    default:
        break;
    }

    /* ---- 4. Telemetry --------------------------------------------------- */
    x->last.tick                 = x->tick;
    x->last.t_s                  = (double)x->tick * x->ts_s;
    x->last.phase                = (uint8_t)x->phase;
    x->last.rotor_cmd_microsteps = x->rotor.position_microsteps;
    x->last.rotor_cmd_deg        = ENR312_Rotor_GetAngleDeg(&x->rotor);
    x->last.encoder_counts       = ENR312_Encoder_GetRelativeCounts(&x->encoder);
    x->last.pendulum_deg         = pend_deg;
    x->last.pendulum_vel_rad_s   = pend_vel;
    x->last.abort_reason         = (uint8_t)x->abort_reason;

    x->tick++;
    x->phase_tick++;
    return &x->last;
}

const char *ENR312_Exp001_CsvHeader(void)
{
    return "tick,t_s,phase,rotor_cmd_microsteps,rotor_cmd_deg,"
           "encoder_counts,pendulum_deg,pendulum_vel_rad_s,abort_reason";
}

int ENR312_Exp001_FormatCsv(const ENR312_Exp001Sample_t *s, char *buf, int buflen)
{
    return snprintf(buf, (size_t)buflen,
                    "%lu,%.6f,%u,%lld,%.6f,%lld,%.6f,%.6f,%u",
                    (unsigned long)s->tick,
                    s->t_s,
                    (unsigned)s->phase,
                    (long long)s->rotor_cmd_microsteps,
                    s->rotor_cmd_deg,
                    (long long)s->encoder_counts,
                    s->pendulum_deg,
                    s->pendulum_vel_rad_s,
                    (unsigned)s->abort_reason);
}
