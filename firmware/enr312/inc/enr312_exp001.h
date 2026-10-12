/**
 * @file    enr312_exp001.h
 * @brief   EXP001 experiment sequencer -- "Actuator and Angle Sensing".
 *
 * Drives the EXP001 procedure as an explicit state machine and emits one
 * telemetry record per control tick. Structured so that:
 *
 *   - the sequence is data, not scattered control flow, so it can be reviewed
 *     before it is ever allowed to move real hardware;
 *   - it is HAL-free and therefore executable on the host, so the entire
 *     sequence can be exercised against a simulated rig before power is applied;
 *   - every motion is bounded and every phase has a defined exit.
 *
 * SAFETY MODEL. The sequencer never enables the motor driver itself. It emits a
 * desired step command; the board layer decides whether to act on it. The
 * `armed` flag defaults to false, and while disarmed the sequencer runs the
 * full sequence and produces telemetry with zero commanded motion -- a dry run.
 * This is the intended way to validate the sequence on a bench before the first
 * powered move.
 */

#ifndef ENR312_EXP001_H
#define ENR312_EXP001_H

#include <stdint.h>
#include <stdbool.h>
#include "enr312_rig_config.h"
#include "enr312_encoder.h"
#include "enr312_rotor.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    EXP001_PHASE_IDLE = 0,       /**< settling; nothing commanded            */
    EXP001_PHASE_SENSE_ONLY,     /**< motor still; operator turns pendulum   */
    EXP001_PHASE_STEP_P1,        /**< commanded-angle staircase (P1)         */
    EXP001_PHASE_RETURN_P3,      /**< zero-net-motion cycles (P3)            */
    EXP001_PHASE_DONE,
    EXP001_PHASE_ABORTED
} ENR312_Exp001Phase_t;

typedef enum {
    EXP001_ABORT_NONE = 0,
    EXP001_ABORT_PENDULUM_LIMIT, /**< |pendulum angle| exceeded abort bound  */
    EXP001_ABORT_ROTOR_LIMIT,    /**< rotor travel limit hit                 */
    EXP001_ABORT_OPERATOR
} ENR312_Exp001Abort_t;

/** One telemetry record. Field order matches the CSV header emitted by
 *  ENR312_Exp001_CsvHeader(), and the analysis script depends on that. */
typedef struct {
    uint32_t tick;                  /**< control ticks since start           */
    double   t_s;                   /**< nominal time = tick * Ts            */
    uint8_t  phase;
    int64_t  rotor_cmd_microsteps;  /**< commanded net microsteps            */
    double   rotor_cmd_deg;         /**< commanded arm angle (no sensor!)    */
    int64_t  encoder_counts;        /**< relative counts since origin        */
    double   pendulum_deg;          /**< measured pendulum angle             */
    double   pendulum_vel_rad_s;    /**< raw backward difference; noisy      */
    uint8_t  abort_reason;
} ENR312_Exp001Sample_t;

typedef struct {
    ENR312_Encoder_t     encoder;
    ENR312_Rotor_t       rotor;

    ENR312_Exp001Phase_t phase;
    ENR312_Exp001Abort_t abort_reason;
    uint32_t             tick;
    uint32_t             phase_tick;

    bool                 armed;         /**< false => dry run, no motion     */
    double               ts_s;

    uint32_t             p1_index;      /**< index into the P1 setpoint table*/
    uint32_t             p3_cycle;      /**< completed P3 cycles             */
    uint32_t             p3_substep;    /**< 0..3 within the current cycle    */
    uint32_t             p3_cycles_target;

    ENR312_Exp001Sample_t last;
} ENR312_Exp001_t;

/** Commanded arm setpoints for phase P1, in degrees.
 *  +45 and -90 are the values the ENR312 student handout asks for; 0 entries
 *  bracket them so each move is observed from a known datum. */
extern const double ENR312_EXP001_P1_SETPOINTS_DEG[];
extern const uint32_t ENR312_EXP001_P1_SETPOINT_COUNT;

/** Ticks spent settling at each P1 setpoint before advancing (1 s at 500 Hz). */
#define EXP001_P1_DWELL_TICKS      (ENR312_CONTROL_RATE_HZ * 1u)
/** Ticks of motor-idle sensing at the start (10 s at 500 Hz). */
#define EXP001_SENSE_ONLY_TICKS    (ENR312_CONTROL_RATE_HZ * 10u)
/** Ticks of initial settle (1 s). */
#define EXP001_IDLE_TICKS          (ENR312_CONTROL_RATE_HZ * 1u)
/** P3 half-cycle amplitude, degrees, and dwell. */
#define EXP001_P3_AMPLITUDE_DEG    90.0
#define EXP001_P3_DWELL_TICKS      (ENR312_CONTROL_RATE_HZ / 2u)

/**
 * @brief Initialise the sequencer.
 * @param raw_counter_now  present hardware encoder counter value
 * @param armed            false for a dry run (recommended first)
 */
void ENR312_Exp001_Init(ENR312_Exp001_t *x, uint16_t raw_counter_now, bool armed);

/**
 * @brief Advance one control tick.
 *
 * Call at exactly the control rate. Reads the encoder, evaluates safety, drives
 * the sequence, and fills the telemetry record.
 *
 * @param raw_counter_now present hardware encoder counter value
 * @return pointer to this tick's telemetry record (never NULL)
 */
const ENR312_Exp001Sample_t *ENR312_Exp001_Tick(ENR312_Exp001_t *x,
                                                uint16_t raw_counter_now);

/** @brief Request an operator abort. Idempotent. */
void ENR312_Exp001_Abort(ENR312_Exp001_t *x);

/** @brief true once the sequence has finished or aborted. */
bool ENR312_Exp001_IsFinished(const ENR312_Exp001_t *x);

/** @brief CSV header matching ENR312_Exp001Sample_t field order. */
const char *ENR312_Exp001_CsvHeader(void);

/** @brief Format one record as a CSV line. Returns chars written (excl. NUL). */
int ENR312_Exp001_FormatCsv(const ENR312_Exp001Sample_t *s, char *buf, int buflen);

#ifdef __cplusplus
}
#endif
#endif /* ENR312_EXP001_H */
