# First-Principles Methodology

## 1. Physical system first

Before writing equations, identify:

- masses;
- lengths;
- inertias;
- friction;
- damping;
- motor;
- transmission;
- encoder;
- pendulum;
- electrical limits;
- mechanical limits.

Ask:

- What moves?
- What produces torque?
- What measures motion?
- What resists motion?
- What couples the degrees of freedom?

## 2. Coordinates

Define:

- generalized coordinates;
- origin;
- positive direction;
- positive rotation;
- units.

Never assume the sign convention from a reference implementation.

## 3. Assumptions

Every model must explicitly state assumptions.

Examples may include:

- rigid bodies;
- small-angle approximation;
- negligible compliance;
- negligible backlash;
- linear motor region;
- constant parameters.

An assumption is not a fact.

## 4. Dynamics

Begin from physical laws.

For translational motion:

    F = m a

For rotational motion:

    τ = I α

Then add physically justified effects:

- gravity;
- damping;
- friction;
- actuator torque;
- coupling;
- electrical dynamics.

## 5. States

A state is the minimum information required to predict future evolution.

Candidate rotary inverted pendulum states may include:

- rotary position;
- rotary velocity;
- pendulum angle;
- pendulum angular velocity.

The final state vector must follow from the chosen model.

## 6. Inputs and outputs

Distinguish:

    physical state
    measured output
    estimated state
    control input
    actuator command

Do not treat these as interchangeable.

## 7. Continuous-time model

Derive:

    physical laws
        ↓
    differential equations
        ↓
    state-space representation

Record:

    x_dot = f(x,u)

and, where appropriate:

    y = h(x,u)

## 8. Equilibrium

Define the operating point.

For an equilibrium:

    x_dot = 0

Identify whether the equilibrium is stable or unstable.

## 9. Linearization

Linearization is local.

Around an equilibrium:

    x_dot ≈ A δx + B δu
    y     ≈ C δx + D δu

Always state:

- equilibrium;
- perturbation variables;
- assumptions;
- valid region.

## 10. Discrete implementation

For a digital controller:

    measure
      ↓
    sample
      ↓
    compute
      ↓
    command
      ↓
    wait
      ↓
    repeat

The sampling period is therefore part of the control system.

## 11. Nonidealities

Begin with the ideal model.

Then investigate:

- sampling;
- delay;
- actuator saturation;
- sensor noise;
- quantization;
- friction;
- backlash;
- unmodelled dynamics.

Do not add complexity without evidence.

## 12. Three-way comparison

The strongest validation is:

    MODEL
      ↕
    SIMULATION
      ↕
    HARDWARE

Disagreement is information.

Possible causes:

- incorrect parameters;
- sign errors;
- sensor bias;
- friction;
- backlash;
- delay;
- sampling;
- saturation;
- wiring;
- software defects;
- unmodelled dynamics.

## 13. Final engineering question

Do not ask only:

    Did it work?

Ask:

    What happened?
    Why did it happen?
    Does the model explain it?
    What does the discrepancy teach us?
