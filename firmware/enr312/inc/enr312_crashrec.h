/**
 * @file enr312_crashrec.h
 * @brief Crash recorder: the last 2 s of the control loop at the full 500 Hz.
 *
 * The 50 Hz stream is too coarse to see what moves first when balance is lost
 * (the pendulum or the arm): one stream sample is 10 control ticks. The recorder
 * keeps every tick in a ring buffer. A trigger (any run abort, or the operator's
 * 'k' key, e.g. right after pushing the pendulum on purpose) freezes it after
 * CRASHREC_POST more ticks, so a dump holds 1.5 s before the trigger and 0.5 s
 * after it. The main loop then sends it as text, a few lines per pass, and the
 * recorder re-arms.
 *
 * Push() runs in the control interrupt; Trigger() may run there or in the main
 * loop; the dump functions run in the main loop only. Push() writes nothing once
 * frozen, so the main loop can read the frozen buffer without locking.
 *
 * Dump format (protocol 5, additive; older hosts ignore it):
 *   K,BEGIN,<reason>,<n samples>,<trigger tick>,<ticks per second>
 *   k,<tick>,<rotor mdeg>,<pendulum mdeg>,<u deg/s^2>,<phase>      (n lines, oldest first)
 *   K,END
 */
#ifndef ENR312_CRASHREC_H
#define ENR312_CRASHREC_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define CRASHREC_N      1000u   /**< samples kept: 2 s at 500 Hz (16 kB)            */
#define CRASHREC_POST    250u   /**< ticks still recorded after a trigger: 0.5 s    */

typedef struct {
    uint32_t tick;
    int32_t  rotor_mdeg;
    int32_t  pend_mdeg;
    int16_t  u;                 /**< plant input, deg/s^2, saturated to int16       */
    uint8_t  phase;
    uint8_t  pad_;
} CrashRec_Sample_t;

typedef enum { CRASHREC_RECORDING = 0, CRASHREC_POSTTRIGGER, CRASHREC_FROZEN } CrashRec_State_t;

typedef struct {
    CrashRec_Sample_t buf[CRASHREC_N];
    volatile uint32_t head;          /**< next write index                          */
    volatile uint32_t count;         /**< valid samples, <= CRASHREC_N              */
    volatile uint32_t post_left;
    volatile CrashRec_State_t state;
    volatile uint32_t trigger_tick;
    const char *volatile reason;
    uint32_t dump_i;                 /**< next sample to send; > count: END sent    */
    bool     dump_begun;
} CrashRec_t;

void ENR312_CrashRec_Init(CrashRec_t *r);

/** Record one control tick (interrupt). No effect once frozen. */
void ENR312_CrashRec_Push(CrashRec_t *r, uint32_t tick, double rotor_deg, double pend_deg,
                          double u, uint8_t phase);

/** Start the post-trigger countdown. Ignored unless recording; returns true if accepted. */
bool ENR312_CrashRec_Trigger(CrashRec_t *r, const char *reason);

bool ENR312_CrashRec_IsFrozen(const CrashRec_t *r);

/**
 * Next dump line into buf (with CR LF). Returns false when there is nothing to
 * send: not frozen, or the dump is complete (the recorder is then re-armed).
 */
bool ENR312_CrashRec_NextLine(CrashRec_t *r, char *buf, size_t len);

#endif /* ENR312_CRASHREC_H */
