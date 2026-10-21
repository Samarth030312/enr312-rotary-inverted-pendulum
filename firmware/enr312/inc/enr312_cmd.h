/**
 * @file    enr312_cmd.h
 * @brief   '$' line commands from the host (MATLAB). Hardware-independent.
 *
 * Grammar (one per line, CR or LF terminated, leading '$' already stripped):
 *   exp=N          select experiment 2..10 or 21..23 and load its defaults
 *   kp= kd=        rotor (outer) PD gains
 *   kpp= kdp=      pendulum (inner) PD gains
 *   step=          rotor reference step [deg]
 *   dist=          EXP002 load-disturbance step [deg/s^2]
 *   ulim=          plant-input clamp [deg/s^2]
 *   vmax=          rotor speed ceiling [deg/s]
 *   ki=            rotor integral gain (experiments 6-10, 21-24: enr312_ctrl.h)
 *   fdr= fdp=      derivative low-pass corners, rotor / pendulum [Hz]
 *   k1= .. k4=     state-feedback gains;  bv= virtual rotor damping b
 *   imp=           Tutorial 7 pendulum-reference impulse [deg]
 *   uon= db=       on-off level [deg/s^2], dead band [deg]
 *   rrate=         live set-point slew [deg/s]
 *   div=           controller every div ticks (500/div Hz);  ma= moving average length
 *   ref=D          live rotor set-point [deg] (HOLD / REGULATE of experiments 6-23)
 * While an experiment of the general core runs, gain changes apply immediately.
 *   defaults       reload the defaults of the selected experiment
 *   cfg            report the configuration
 *   go             start the selected experiment   (board layer checks RUNNING)
 *   stop           graceful stop
 *   move=D         EXP001: move the rotor by D degrees (|D| <= 90) at 200 microsteps/s
 * Every change is validated against ENR312_Runner_Validate; an invalid value
 * is rejected and the previous configuration kept.
 * Replies: "ERR ..." / "C,exp,kp,kd,kpp,kdp,step,dist,ulim,vmax,ki,fdr,fdp,k1,k2,k3,k4,
 *          bv,imp,uon,db,rrate,div,ma" (protocol 3; protocol 2 = first 9 fields).
 */
#ifndef ENR312_CMD_H
#define ENR312_CMD_H
#include "enr312_runner.h"

typedef enum {
    ENR312_CMD_REPLY = 0,   /**< reply holds the answer; nothing else to do */
    ENR312_CMD_GO,
    ENR312_CMD_STOP,
    ENR312_CMD_MOVE,        /**< *move_deg holds the request                 */
    ENR312_CMD_REF          /**< *move_deg holds the live set-point          */
} ENR312_CmdAction_t;

ENR312_CmdAction_t ENR312_Cmd_Line(const char *line, ENR312_RunnerConfig_t *cfg,
                                   double *move_deg, char *reply, int reply_len);

/** Format v with 3 decimals into buf (no float printf on newlib-nano). */
int ENR312_Cmd_FormatFixed(char *buf, int len, double v);
#endif
