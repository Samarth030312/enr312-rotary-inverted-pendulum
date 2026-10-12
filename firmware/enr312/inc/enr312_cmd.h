/**
 * @file    enr312_cmd.h
 * @brief   '$' line commands from the host (MATLAB). Hardware-independent.
 *
 * Grammar (one per line, CR or LF terminated, leading '$' already stripped):
 *   exp=N          select experiment 2..5 and load its Tutorial defaults
 *   kp= kd=        rotor (outer) PD gains
 *   kpp= kdp=      pendulum (inner) PD gains
 *   step=          rotor reference step [deg]
 *   dist=          EXP002 load-disturbance step [deg/s^2]
 *   ulim=          plant-input clamp [deg/s^2]
 *   vmax=          rotor speed ceiling [deg/s]
 *   defaults       reload the defaults of the selected experiment
 *   cfg            report the configuration
 *   go             start the selected experiment   (board layer checks RUNNING)
 *   stop           graceful stop
 *   move=D         EXP001: move the rotor by D degrees (|D| <= 90) at 200 microsteps/s
 * Every change is validated against ENR312_Runner_Validate; an invalid value
 * is rejected and the previous configuration kept.
 * Replies: "OK ..." / "ERR ..." / "C,exp,kp,kd,kpp,kdp,step,dist,ulim,vmax".
 */
#ifndef ENR312_CMD_H
#define ENR312_CMD_H
#include "enr312_runner.h"

typedef enum {
    ENR312_CMD_REPLY = 0,   /**< reply holds the answer; nothing else to do */
    ENR312_CMD_GO,
    ENR312_CMD_STOP,
    ENR312_CMD_MOVE         /**< *move_deg holds the request                 */
} ENR312_CmdAction_t;

ENR312_CmdAction_t ENR312_Cmd_Line(const char *line, ENR312_RunnerConfig_t *cfg,
                                   double *move_deg, char *reply, int reply_len);

/** Format v with 3 decimals into buf (no float printf on newlib-nano). */
int ENR312_Cmd_FormatFixed(char *buf, int len, double v);
#endif
