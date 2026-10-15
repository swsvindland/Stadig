#!/usr/bin/env python3
"""Builds Sources/ExerciseLibrary/Resources/library.json.

Inputs:
  - Scripts/legacy_library.json: the previous app's 258 rep-based exercises (frozen; ids, names,
    aliases, equipment, pattern, muscle weights, unilateral, load kind, rep range and cue are kept).
  - The tables below: apparatus, joint stress and fatigue for every legacy id, the rules for
    safety tier, failure multiplier, rest role, rest and reps, strength mappings, and every new entry
    (timed holds, mobility drills, warm-ups, stretches and conditioning).

Run from anywhere: python3 Packages/ExerciseLibrary/Scripts/build_library.py
The script fails loudly if a legacy id has no tag row or a row names an unknown id.
"""

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LEGACY = HERE / "legacy_library.json"
OUT = HERE.parent / "Sources" / "ExerciseLibrary" / "Resources" / "library.json"

MACHINES = {"machine", "cable", "plateLoaded", "smith"}
FREE_WEIGHTS = {"barbell", "ezBar", "trapBar", "dumbbell", "kettlebell"}
COMPOUND_PATTERNS = {"horizontalPress", "inclinePress", "verticalPress", "dip", "horizontalRow", "verticalPull",
                     "squat", "lunge", "legPress", "hinge", "hipThrust", "carry"}
SMALL_MUSCLES = {"biceps", "triceps", "frontDelts", "sideDelts", "rearDelts", "forearms", "calves", "abs"}

# ---------------------------------------------------------------------------------------------
# Tags for every strength exercise: apparatus | joints (joint:stress) | systemic local stimulus.
# Joint stress: 1 low, 2 moderate, 3 high. Systemic: a conventional deadlift is 1.0.
# ---------------------------------------------------------------------------------------------
TAGS = """
# Flat pressing
barbell-bench-press              | bench rack        | shoulder:3 elbow:2 wrist:2                   | .55 .50 .85
barbell-bench-press-paused       | bench rack        | shoulder:3 elbow:2 wrist:2                   | .50 .50 .80
barbell-decline-bench-press      | bench rack        | shoulder:2 elbow:2 wrist:2                   | .50 .45 .80
db-bench-press                   | bench             | shoulder:2 elbow:2 wrist:1                   | .45 .45 .85
db-decline-bench-press           | bench             | shoulder:2 elbow:2 wrist:1                   | .40 .40 .80
db-bench-press-single            | bench             | shoulder:2 elbow:2 wrist:1 lowerBack:1       | .35 .40 .75
db-floor-press                   |                   | shoulder:1 elbow:2 wrist:1                   | .35 .35 .70
db-squeeze-press                 | bench             | shoulder:1 elbow:2 wrist:1                   | .25 .35 .70
smith-bench-press                | bench             | shoulder:3 elbow:2 wrist:1                   | .45 .45 .80
machine-chest-press              |                   | shoulder:2 elbow:2 wrist:1                   | .35 .40 .85
plate-loaded-chest-press         |                   | shoulder:2 elbow:2 wrist:1                   | .35 .40 .85
plate-loaded-decline-press       |                   | shoulder:2 elbow:2 wrist:1                   | .30 .40 .80
cable-chest-press                |                   | shoulder:2 elbow:1 wrist:1                   | .25 .35 .70
push-up                          |                   | wrist:2 shoulder:2 elbow:1                   | .20 .35 .70
deficit-push-up                  |                   | shoulder:2 wrist:1 elbow:1                   | .22 .40 .75
close-grip-bench-press           | bench rack        | elbow:3 shoulder:2 wrist:2                   | .50 .45 .80
smith-close-grip-bench-press     | bench             | elbow:3 shoulder:2 wrist:1                   | .40 .40 .75
diamond-push-up                  |                   | wrist:2 elbow:2 shoulder:1                   | .15 .35 .65

# Incline pressing
barbell-incline-bench-press      | bench rack        | shoulder:3 elbow:2 wrist:2                   | .50 .50 .85
db-incline-bench-press           | bench             | shoulder:2 elbow:2 wrist:1                   | .42 .45 .85
db-low-incline-press             | bench             | shoulder:2 elbow:2 wrist:1                   | .42 .45 .85
smith-incline-press              | bench             | shoulder:3 elbow:2 wrist:1                   | .40 .45 .80
machine-incline-chest-press      |                   | shoulder:2 elbow:2 wrist:1                   | .33 .40 .85
plate-loaded-incline-press       |                   | shoulder:2 elbow:2 wrist:1                   | .35 .40 .85

# Flies
pec-deck                         |                   | shoulder:2 elbow:1                           | .10 .35 .85
cable-crossover                  |                   | shoulder:2 elbow:1                           | .10 .35 .80
cable-fly                        |                   | shoulder:2 elbow:1                           | .10 .35 .80
cable-fly-low-to-high            |                   | shoulder:2 elbow:1                           | .10 .35 .75
cable-fly-single                 |                   | shoulder:2 elbow:1                           | .08 .30 .80
cable-fly-incline                | bench             | shoulder:2 elbow:1                           | .10 .35 .80
db-fly                           | bench             | shoulder:3 elbow:2                           | .12 .40 .75
db-incline-fly                   | bench             | shoulder:3 elbow:2                           | .12 .40 .75

# Dips
chest-dip                        | dipStation        | shoulder:3 elbow:3 wrist:2                   | .40 .50 .85
assisted-dip                     |                   | shoulder:3 elbow:2 wrist:2                   | .25 .40 .75
triceps-dip                      | dipStation        | shoulder:3 elbow:3 wrist:2                   | .40 .50 .85
bench-dip                        | bench             | shoulder:3 elbow:2 wrist:2                   | .12 .35 .60
machine-dip                      |                   | shoulder:2 elbow:2 wrist:1                   | .25 .35 .80

# Rows
barbell-row                      |                   | lowerBack:3 shoulder:1 elbow:1               | .60 .50 .80
pendlay-row                      |                   | lowerBack:3 shoulder:1 elbow:1               | .60 .50 .80
barbell-row-underhand            |                   | lowerBack:3 elbow:2 shoulder:1               | .60 .50 .80
t-bar-row                        | landmine          | lowerBack:3 shoulder:1 elbow:1               | .55 .50 .80
t-bar-row-chest-supported        |                   | lowerBack:1 shoulder:1 elbow:1               | .30 .40 .85
seal-row                         | bench             | lowerBack:1 shoulder:1 elbow:1               | .35 .40 .85
db-seal-row                      | bench             | lowerBack:1 shoulder:1 elbow:1               | .30 .40 .85
chest-supported-db-row           | bench             | lowerBack:1 shoulder:1 elbow:1               | .30 .40 .85
db-row-single                    | bench             | lowerBack:1 shoulder:1 elbow:1               | .35 .40 .85
db-row-bent-over                 |                   | lowerBack:2 shoulder:1 elbow:1               | .45 .45 .80
meadows-row                      | landmine          | lowerBack:2 shoulder:1 elbow:1               | .40 .45 .80
cable-row                        |                   | lowerBack:1 shoulder:1 elbow:1               | .30 .40 .85
cable-row-wide                   |                   | lowerBack:1 shoulder:1 elbow:1               | .30 .40 .80
cable-row-single                 |                   | lowerBack:1 shoulder:1 elbow:1               | .22 .35 .80
machine-row                      |                   | lowerBack:1 shoulder:1 elbow:1               | .28 .40 .85
plate-loaded-row                 |                   | lowerBack:1 shoulder:1 elbow:1               | .30 .40 .85
plate-loaded-low-row             |                   | lowerBack:1 shoulder:1 elbow:1               | .30 .40 .85
smith-row                        |                   | lowerBack:2 shoulder:1 elbow:1               | .45 .45 .75
inverted-row                     | rack              | shoulder:1 elbow:1 lowerBack:1               | .20 .35 .70
band-row                         |                   | shoulder:1 elbow:1                           | .08 .25 .55

# Vertical pulls
lat-pulldown                     |                   | shoulder:2 elbow:1                           | .30 .40 .85
lat-pulldown-close-grip          |                   | shoulder:2 elbow:1                           | .30 .40 .85
lat-pulldown-neutral             |                   | shoulder:2 elbow:1                           | .30 .40 .85
lat-pulldown-underhand           |                   | shoulder:2 elbow:2                           | .30 .40 .85
lat-pulldown-single              |                   | shoulder:2 elbow:1                           | .20 .35 .85
machine-pulldown                 |                   | shoulder:2 elbow:1                           | .30 .40 .85
plate-loaded-pulldown            |                   | shoulder:2 elbow:1                           | .30 .40 .85
plate-loaded-high-row            |                   | shoulder:1 elbow:1                           | .30 .40 .80
pull-up                          | pullUpBar         | shoulder:2 elbow:2                           | .45 .50 .85
chin-up                          | pullUpBar         | shoulder:2 elbow:2                           | .45 .50 .85
neutral-grip-pull-up             | pullUpBar         | shoulder:2 elbow:1                           | .45 .50 .85
assisted-pull-up                 |                   | shoulder:2 elbow:1                           | .30 .40 .80

# Pullovers
straight-arm-pulldown            |                   | shoulder:2 elbow:1                           | .12 .30 .75
db-pullover                      | bench             | shoulder:3 elbow:1                           | .15 .35 .70
machine-pullover                 |                   | shoulder:2 elbow:1                           | .12 .30 .80

# Shrugs
barbell-shrug                    |                   | neck:1 shoulder:1 lowerBack:1 wrist:1        | .20 .30 .75
db-shrug                         |                   | neck:1 shoulder:1 wrist:1                    | .15 .30 .75
db-shrug-incline                 | bench             | neck:1 shoulder:1                            | .10 .30 .75
smith-shrug                      |                   | neck:1 shoulder:1 lowerBack:1                | .15 .30 .75
trap-bar-shrug                   |                   | neck:1 shoulder:1 lowerBack:1                | .20 .30 .75
machine-shrug                    |                   | neck:1 shoulder:1                            | .12 .30 .75
cable-shrug                      |                   | neck:1 shoulder:1                            | .10 .25 .70

# Overhead pressing
barbell-overhead-press           | rack              | shoulder:3 lowerBack:2 elbow:2 wrist:2       | .50 .50 .80
barbell-seated-overhead-press    | bench rack        | shoulder:3 elbow:2 wrist:2 lowerBack:1       | .42 .50 .80
push-press                       | rack              | shoulder:3 lowerBack:2 elbow:2 wrist:2 knee:1 | .55 .50 .70
db-shoulder-press                | bench             | shoulder:2 elbow:2 wrist:1                   | .40 .45 .85
db-shoulder-press-standing       |                   | shoulder:2 elbow:2 wrist:1 lowerBack:1       | .42 .45 .80
db-shoulder-press-single         |                   | shoulder:2 elbow:2 wrist:1 lowerBack:1       | .30 .40 .80
arnold-press                     | bench             | shoulder:3 elbow:2 wrist:1                   | .38 .45 .80
smith-overhead-press             | bench             | shoulder:3 elbow:2 wrist:1                   | .35 .45 .80
machine-shoulder-press           |                   | shoulder:2 elbow:2 wrist:1                   | .30 .40 .85
plate-loaded-shoulder-press      |                   | shoulder:2 elbow:2 wrist:1                   | .30 .40 .85
landmine-press                   | landmine          | shoulder:1 elbow:2 wrist:1 lowerBack:1       | .30 .40 .75
pike-push-up                     |                   | shoulder:2 wrist:2 elbow:1                   | .15 .35 .65

# Raises
db-front-raise                   |                   | shoulder:2                                   | .05 .25 .60
cable-front-raise                |                   | shoulder:2                                   | .05 .25 .60
db-lateral-raise                 |                   | shoulder:2                                   | .06 .25 .80
db-lateral-raise-seated          | bench             | shoulder:2                                   | .06 .25 .80
db-lateral-raise-lean-away       |                   | shoulder:2                                   | .06 .25 .80
db-lateral-raise-lying           | bench             | shoulder:2                                   | .05 .25 .75
db-y-raise                       | bench             | shoulder:2                                   | .05 .25 .75
cable-lateral-raise-single       |                   | shoulder:2                                   | .06 .25 .85
cable-lateral-raise-lean-away    |                   | shoulder:2                                   | .06 .25 .85
cable-lateral-raise-behind-back  |                   | shoulder:2                                   | .06 .25 .80
cable-y-raise                    |                   | shoulder:2                                   | .06 .25 .80
machine-lateral-raise            |                   | shoulder:2                                   | .06 .25 .85
band-lateral-raise               |                   | shoulder:1                                   | .04 .20 .60
barbell-upright-row              |                   | shoulder:3 wrist:2 elbow:1                   | .12 .35 .65
cable-upright-row                |                   | shoulder:2 wrist:1 elbow:1                   | .10 .30 .70
db-upright-row                   |                   | shoulder:2 wrist:1                           | .10 .30 .70

# Rear delts
reverse-pec-deck                 |                   | shoulder:1                                   | .05 .20 .80
cable-rear-delt-fly              |                   | shoulder:1                                   | .05 .20 .80
cable-rear-delt-fly-single       |                   | shoulder:1                                   | .05 .20 .80
db-rear-delt-fly                 |                   | shoulder:1 lowerBack:1                       | .06 .20 .75
db-rear-delt-fly-chest-supported | bench             | shoulder:1                                   | .05 .20 .80
db-rear-delt-row                 |                   | shoulder:1 elbow:1 lowerBack:1               | .08 .25 .75
band-pull-apart                  |                   | shoulder:1                                   | .03 .20 .55
face-pull                        |                   | shoulder:1 elbow:1                           | .06 .20 .75
band-face-pull                   |                   | shoulder:1                                   | .04 .20 .55

# Curls
barbell-curl                     |                   | elbow:2 wrist:2                              | .08 .30 .80
ez-bar-curl                      |                   | elbow:2 wrist:1                              | .08 .30 .80
ez-bar-preacher-curl             | bench             | elbow:2 wrist:1                              | .07 .30 .85
db-preacher-curl-single          | bench             | elbow:2 wrist:1                              | .06 .30 .85
machine-preacher-curl            |                   | elbow:2 wrist:1                              | .06 .30 .85
db-curl                          |                   | elbow:2 wrist:1                              | .08 .30 .80
db-hammer-curl                   |                   | elbow:2 wrist:1                              | .08 .30 .80
cross-body-hammer-curl           |                   | elbow:2 wrist:1                              | .08 .30 .75
rope-hammer-curl                 |                   | elbow:2 wrist:1                              | .07 .30 .75
db-incline-curl                  | bench             | elbow:2 shoulder:1 wrist:1                   | .07 .30 .85
db-concentration-curl            | bench             | elbow:2 wrist:1                              | .05 .25 .80
db-spider-curl                   | bench             | elbow:2 wrist:1                              | .06 .30 .80
ez-bar-spider-curl               | bench             | elbow:2 wrist:1                              | .06 .30 .80
cable-curl                       |                   | elbow:2 wrist:1                              | .07 .30 .80
cable-curl-single                |                   | elbow:2 wrist:1                              | .05 .25 .80
bayesian-curl                    |                   | elbow:2 shoulder:1 wrist:1                   | .05 .25 .85
cable-curl-high                  |                   | elbow:2 shoulder:1                           | .06 .25 .75
zottman-curl                     |                   | elbow:2 wrist:2                              | .08 .30 .75
band-curl                        |                   | elbow:1 wrist:1                              | .04 .20 .55

# Triceps
cable-pushdown-rope              |                   | elbow:2                                      | .08 .30 .80
cable-pushdown-bar               |                   | elbow:2 wrist:1                              | .08 .30 .80
cable-pushdown-single            |                   | elbow:2                                      | .08 .25 .80
cable-overhead-extension         |                   | elbow:2 shoulder:1                           | .08 .30 .85
cable-overhead-extension-single  |                   | elbow:2 shoulder:1                           | .08 .25 .85
cable-cross-body-extension       |                   | elbow:2                                      | .08 .25 .80
ez-bar-skull-crusher             | bench             | elbow:3 wrist:1 shoulder:1                   | .10 .35 .85
db-skull-crusher                 | bench             | elbow:3 shoulder:1                           | .09 .35 .80
ez-bar-overhead-extension        |                   | elbow:3 shoulder:2 wrist:1                   | .10 .35 .85
db-overhead-extension            |                   | elbow:3 shoulder:2                           | .10 .35 .85
db-overhead-extension-single     |                   | elbow:2 shoulder:2                           | .08 .30 .80
jm-press                         | bench rack        | elbow:3 wrist:2 shoulder:1                   | .12 .40 .80
smith-jm-press                   | bench             | elbow:3 wrist:1 shoulder:1                   | .10 .35 .80
machine-triceps-extension        |                   | elbow:2                                      | .08 .30 .80
db-kickback                      |                   | elbow:1 shoulder:1                           | .08 .25 .70
cable-triceps-kickback           |                   | elbow:1 shoulder:1                           | .08 .25 .75
band-pushdown                    |                   | elbow:1                                      | .05 .20 .55

# Forearms
ez-bar-reverse-curl              |                   | elbow:2 wrist:2                              | .06 .30 .75
db-reverse-curl                  |                   | elbow:2 wrist:2                              | .06 .30 .70
cable-reverse-curl               |                   | elbow:2 wrist:1                              | .05 .30 .70
barbell-wrist-curl               | bench             | wrist:2                                      | .04 .25 .70
db-wrist-curl                    | bench             | wrist:2                                      | .04 .25 .70
barbell-reverse-wrist-curl       | bench             | wrist:2 elbow:1                              | .04 .25 .65
db-reverse-wrist-curl            | bench             | wrist:2 elbow:1                              | .04 .25 .65
cable-wrist-curl                 |                   | wrist:2                                      | .04 .25 .70
behind-back-wrist-curl           |                   | wrist:2                                      | .04 .25 .70

# Squats
barbell-back-squat               | rack              | knee:3 hip:2 lowerBack:2 ankle:2             | .85 .60 .90
high-bar-squat                   | rack              | knee:3 hip:2 lowerBack:2 ankle:2             | .85 .60 .90
low-bar-squat                    | rack              | hip:3 lowerBack:3 knee:2 shoulder:2 ankle:1  | .90 .60 .85
pause-squat                      | rack              | knee:3 hip:2 lowerBack:2 ankle:2             | .80 .60 .85
front-squat                      | rack              | knee:3 hip:2 upperBack:2 ankle:2 lowerBack:1 wrist:1 | .80 .60 .90
safety-bar-squat                 | rack              | knee:3 hip:2 lowerBack:2 upperBack:2 ankle:2 | .85 .60 .85
smith-squat                      |                   | knee:3 hip:2 lowerBack:1 ankle:1             | .55 .50 .80
hack-squat                       |                   | knee:3 hip:2 lowerBack:1                     | .60 .55 .90
reverse-hack-squat               |                   | hip:2 knee:2 lowerBack:1                     | .55 .50 .80
pendulum-squat                   |                   | knee:3 hip:2 lowerBack:1                     | .55 .55 .90
belt-squat                       |                   | knee:3 hip:2                                 | .50 .55 .85
v-squat                          |                   | knee:3 hip:2 lowerBack:1                     | .55 .55 .85
goblet-squat                     |                   | knee:2 hip:2 ankle:2 lowerBack:1             | .40 .45 .75
bodyweight-squat                 |                   | knee:2 hip:1 ankle:1                         | .12 .25 .50
pistol-squat                     |                   | knee:3 hip:2 ankle:2                         | .25 .45 .70

# Leg press
leg-press                        |                   | knee:3 hip:2 lowerBack:1                     | .55 .55 .85
leg-press-seated                 |                   | knee:3 hip:2 lowerBack:1                     | .45 .50 .80
leg-press-single                 |                   | knee:3 hip:2                                 | .35 .50 .80
leg-press-high-foot              |                   | hip:2 knee:2 lowerBack:1                     | .55 .55 .80

# Lunges and split squats
db-bulgarian-split-squat         | bench             | knee:3 hip:2 ankle:2                         | .50 .60 .90
smith-bulgarian-split-squat      | bench             | knee:3 hip:2 ankle:2                         | .45 .55 .85
db-split-squat                   |                   | knee:3 hip:2 ankle:2                         | .45 .55 .85
smith-split-squat                |                   | knee:3 hip:2 ankle:2                         | .40 .50 .80
db-walking-lunge                 |                   | knee:3 hip:2 ankle:2                         | .50 .60 .85
db-reverse-lunge                 |                   | knee:2 hip:2 ankle:2                         | .45 .55 .85
db-deficit-reverse-lunge         | box               | knee:2 hip:2 ankle:2                         | .50 .60 .85
barbell-reverse-lunge            | rack              | knee:2 hip:2 ankle:2 lowerBack:2             | .55 .55 .85
smith-reverse-lunge              |                   | knee:2 hip:2 ankle:2                         | .40 .50 .80
db-lunge                         |                   | knee:3 hip:2 ankle:2                         | .50 .55 .80
db-step-up                       | box               | knee:3 hip:2 ankle:1                         | .40 .50 .80
bodyweight-bulgarian-split-squat | box               | knee:2 hip:2 ankle:1                         | .20 .45 .70
bodyweight-reverse-lunge         |                   | knee:2 hip:1 ankle:1                         | .15 .35 .60

# Knee extension
leg-extension                    |                   | knee:3                                       | .15 .35 .85
leg-extension-single             |                   | knee:3                                       | .10 .30 .85
sissy-squat                      |                   | knee:3 ankle:1                               | .15 .40 .75
reverse-nordic                   |                   | knee:3                                       | .12 .40 .75

# Hinges
conventional-deadlift            |                   | lowerBack:3 hip:3 knee:2                     | 1.0 .60 .80
sumo-deadlift                    |                   | lowerBack:3 hip:3 knee:2                     | .95 .60 .80
trap-bar-deadlift                |                   | hip:2 knee:2 lowerBack:2                     | .85 .55 .85
rack-pull                        | rack              | lowerBack:3 hip:2                            | .75 .55 .65
barbell-rdl                      |                   | lowerBack:2 hip:2                            | .65 .55 .85
db-rdl                           |                   | lowerBack:2 hip:2                            | .50 .50 .80
db-rdl-single-leg                |                   | hip:2 lowerBack:1 ankle:1 knee:1             | .35 .45 .80
smith-rdl                        |                   | lowerBack:2 hip:2                            | .50 .50 .80
stiff-leg-deadlift               |                   | lowerBack:3 hip:2                            | .70 .55 .80
good-morning                     | rack              | lowerBack:3 hip:2 shoulder:1                 | .70 .55 .75
cable-pull-through               |                   | hip:2 lowerBack:1                            | .20 .35 .70
kb-swing                         |                   | hip:2 lowerBack:2 knee:1                     | .40 .40 .60

# Back extensions
back-extension-45                | backExtensionBench | lowerBack:2 hip:1                           | .20 .35 .75
back-extension-machine           |                   | lowerBack:2                                  | .15 .35 .70
reverse-hyper                    |                   | lowerBack:2 hip:1                            | .20 .35 .75

# Hip thrusts and glutes
barbell-hip-thrust               | bench             | hip:2 lowerBack:1                            | .45 .45 .85
machine-hip-thrust               |                   | hip:2 lowerBack:1                            | .30 .40 .85
smith-hip-thrust                 | bench             | hip:2 lowerBack:1                            | .35 .40 .85
db-hip-thrust                    | bench             | hip:2 lowerBack:1                            | .25 .35 .75
hip-thrust-single-leg            | bench             | hip:2 lowerBack:1                            | .15 .35 .75
barbell-glute-bridge             |                   | hip:2 lowerBack:1                            | .35 .40 .80
glute-bridge                     |                   | hip:1 lowerBack:1                            | .08 .25 .55
cable-glute-kickback             |                   | hip:1 lowerBack:1                            | .06 .25 .75
machine-glute-kickback           |                   | hip:1 lowerBack:1                            | .06 .25 .75

# Leg curls
seated-leg-curl                  |                   | knee:2                                       | .15 .35 .90
seated-leg-curl-single           |                   | knee:2                                       | .10 .30 .85
lying-leg-curl                   |                   | knee:2 lowerBack:1                           | .15 .35 .85
standing-leg-curl-single         |                   | knee:2                                       | .10 .30 .80
cable-leg-curl                   |                   | knee:2                                       | .08 .30 .75
db-leg-curl                      | bench             | knee:2                                       | .10 .30 .70
nordic-curl                      |                   | knee:3                                       | .20 .60 .85
glute-ham-raise                  | gluteHamBench     | knee:2 hip:1                                 | .25 .50 .85
sliding-leg-curl                 |                   | knee:2 hip:1 lowerBack:1                     | .10 .35 .75

# Adductors and abductors
hip-adduction-machine            |                   | hip:2                                        | .08 .25 .75
cable-hip-adduction              |                   | hip:2                                        | .06 .25 .70
hip-abduction-machine            |                   | hip:1                                        | .06 .25 .75
cable-hip-abduction              |                   | hip:1                                        | .05 .25 .70
band-hip-abduction               |                   | hip:1                                        | .04 .20 .55

# Calves
standing-calf-raise              |                   | ankle:2 lowerBack:1                          | .10 .30 .80
seated-calf-raise                |                   | ankle:2                                      | .08 .30 .75
leg-press-calf-raise             |                   | ankle:2 knee:1                               | .10 .30 .80
smith-calf-raise                 |                   | ankle:2 lowerBack:1                          | .10 .30 .75
db-calf-raise-single             | box               | ankle:2                                      | .08 .30 .80
bodyweight-calf-raise-single     | box               | ankle:2                                      | .06 .25 .70
donkey-calf-raise                |                   | ankle:2 lowerBack:1                          | .10 .30 .80

# Abs
cable-crunch                     |                   | neck:1 lowerBack:1                           | .08 .25 .85
machine-crunch                   |                   | neck:1 lowerBack:1                           | .08 .25 .80
crunch                           |                   | neck:1 lowerBack:1                           | .05 .20 .65
decline-sit-up                   | bench             | lowerBack:2 neck:1 hip:1                     | .08 .30 .75
hanging-leg-raise                | pullUpBar         | shoulder:1 lowerBack:1 hip:1                 | .10 .30 .85
hanging-knee-raise               | pullUpBar         | shoulder:1 lowerBack:1 hip:1                 | .08 .25 .75
captains-chair-knee-raise        | dipStation        | shoulder:1 lowerBack:1 hip:1                 | .08 .25 .75
toes-to-bar                      | pullUpBar         | shoulder:2 lowerBack:1 hip:1                 | .10 .30 .80
lying-leg-raise                  |                   | lowerBack:1 hip:1                            | .06 .25 .65
reverse-crunch                   |                   | lowerBack:1                                  | .05 .25 .70
ab-wheel-rollout                 |                   | lowerBack:2 shoulder:2                       | .10 .35 .85
barbell-rollout                  |                   | lowerBack:2 shoulder:2                       | .10 .35 .85
pallof-press                     |                   | lowerBack:1 shoulder:1                       | .05 .20 .60
cable-woodchop                   |                   | lowerBack:1 shoulder:1                       | .06 .25 .65
db-side-bend                     |                   | lowerBack:2                                  | .06 .25 .65
dead-bug                         |                   | lowerBack:1                                  | .03 .20 .55

# New strength entries (defined in NEW_STRENGTH below)
box-squat                        | rack box          | hip:3 lowerBack:2 knee:2 ankle:1             | .80 .55 .80
deficit-deadlift                 |                   | lowerBack:3 hip:3 knee:2                     | 1.0 .60 .80
plank                            |                   | lowerBack:1 shoulder:1                       | .05 .20 .55
side-plank                       |                   | lowerBack:1 shoulder:1                       | .05 .20 .55
dead-hang                        | pullUpBar         | shoulder:2 elbow:1 wrist:1                   | .05 .30 .60
wall-sit                         |                   | knee:2 hip:1                                 | .10 .35 .50
farmers-carry                    |                   | lowerBack:2 hip:1 shoulder:1 wrist:1         | .35 .45 .70
suitcase-carry                   |                   | lowerBack:2 hip:1 shoulder:1 wrist:1         | .25 .40 .70
"""

# New strength entries the legacy library lacked: references for strength mappings, timed holds
# and carries. Tags come from TAGS above.
NEW_STRENGTH = [
    dict(id="box-squat", name="Box Squat", aliases=["Barbell Box Squat"], equipment="barbell", pattern="squat",
         muscles=[["quads", 1], ["glutes", 1], ["adductors", 0.5]], reps=[5, 8],
         cue="Sit back to the box under control, stay tight, drive up without rocking."),
    dict(id="deficit-deadlift", name="Deficit Deadlift", aliases=["Deficit Pull"], equipment="barbell", pattern="hinge",
         muscles=[["glutes", 1], ["hamstrings", 0.5], ["lowerBack", 0.5], ["quads", 0.5]], reps=[4, 8],
         cue="Stand on a 3–5 cm plate; hips lower than usual, chest up, push the floor away."),
    dict(id="plank", name="Plank", aliases=["Front Plank", "Forearm Plank"], equipment="bodyweight", pattern="core",
         muscles=[["abs", 1]], timed=45, cue="Elbows under shoulders, squeeze glutes, ribs down; a straight line head to heel."),
    dict(id="side-plank", name="Side Plank", aliases=["Side Bridge"], equipment="bodyweight", pattern="core",
         muscles=[["abs", 1]], unilateral=True, timed=30, cue="Elbow under shoulder, hips high, body in one line."),
    dict(id="dead-hang", name="Dead Hang", aliases=["Bar Hang", "Passive Hang"], equipment="bodyweight", pattern="wrist",
         muscles=[["forearms", 1]], timed=30, cue="Full grip, arms straight, let the shoulders open; breathe."),
    dict(id="wall-sit", name="Wall Sit", aliases=["Wall Squat Hold"], equipment="bodyweight", pattern="squat",
         muscles=[["quads", 1], ["glutes", 0.5]], timed=45, cue="Back flat on the wall, thighs parallel, knees over ankles."),
    dict(id="farmers-carry", name="Farmer's Carry", aliases=["Farmer's Walk", "Farmer Carry", "Loaded Carry"],
         equipment="dumbbell", pattern="carry", muscles=[["forearms", 1], ["traps", 1], ["abs", 0.5]], timed=40,
         loaded=True, cue="Heavy bells, tall posture, short quick steps; set them down before the grip goes."),
    dict(id="suitcase-carry", name="Suitcase Carry", aliases=["Single-Arm Farmer's Carry", "One-Arm Carry"],
         equipment="dumbbell", pattern="carry", muscles=[["abs", 1], ["forearms", 1], ["traps", 0.5]],
         unilateral=True, timed=30, loaded=True, cue="One bell, stay level; don't lean toward or away from it."),
]

# Only free-weight variants with a known ratio to the category's reference lift. Factor =
# reference 1RM per kg of this exercise's 1RM; dumbbell loads are per hand.
MAPPINGS = {
    "barbell-back-squat": ("squat", 1.0), "high-bar-squat": ("squat", 1.0), "low-bar-squat": ("squat", 1.0),
    "pause-squat": ("squat", 1.1), "front-squat": ("squat", 1.2), "safety-bar-squat": ("squat", 1.08),
    "box-squat": ("squat", 1.05),
    "conventional-deadlift": ("floorPull", 1.0), "sumo-deadlift": ("floorPull", 1.0),
    "trap-bar-deadlift": ("floorPull", 0.92), "deficit-deadlift": ("floorPull", 1.08),
    "barbell-bench-press": ("horizontalPress", 1.0), "barbell-bench-press-paused": ("horizontalPress", 1.05),
    "close-grip-bench-press": ("horizontalPress", 1.1), "db-bench-press": ("horizontalPress", 2.4),
    "barbell-incline-bench-press": ("inclinePress", 1.0), "db-incline-bench-press": ("inclinePress", 2.4),
    "barbell-overhead-press": ("verticalPress", 1.0), "barbell-seated-overhead-press": ("verticalPress", 0.95),
    "db-shoulder-press": ("verticalPress", 2.5), "db-shoulder-press-standing": ("verticalPress", 2.5),
    "pull-up": ("verticalPull", 1.0), "chin-up": ("verticalPull", 0.95), "neutral-grip-pull-up": ("verticalPull", 0.97),
    "barbell-row": ("horizontalPull", 1.0), "pendlay-row": ("horizontalPull", 1.0), "db-row-single": ("horizontalPull", 2.2),
}

# Safety tier exceptions to the equipment and pattern rules in safety_tier().
NEVER_TO_FAILURE = {
    "barbell-overhead-press", "push-press", "barbell-row", "pendlay-row", "barbell-row-underhand", "t-bar-row",
    "db-row-bent-over", "barbell-rdl", "db-rdl", "db-rdl-single-leg", "smith-rdl", "stiff-leg-deadlift",
    "good-morning", "kb-swing", "ez-bar-skull-crusher", "ez-bar-overhead-extension", "db-overhead-extension",
    "db-overhead-extension-single", "db-pullover", "barbell-reverse-lunge", "farmers-carry", "suitcase-carry",
}
FAIL_WITH_SETUP = {"chest-dip", "triceps-dip", "barbell-upright-row"}
SAFE_TO_FAIL = {"db-row-single", "chest-supported-db-row", "db-seal-row", "seal-row", "db-hip-thrust", "db-kickback"}
# Free-weight patterns where failure just means the weight stops: curls, raises, shrugs, abs.
SAFE_FREE_PATTERNS = {"curl", "wrist", "lateralRaise", "frontRaise", "rearDeltFly", "facePull", "shrug", "calfRaise",
                      "crunch", "legRaise", "core", "hipAbduction", "hipAdduction"}

HEAVY_COMPOUNDS = {
    "barbell-bench-press", "barbell-bench-press-paused", "barbell-decline-bench-press", "barbell-incline-bench-press",
    "close-grip-bench-press", "barbell-row", "pendlay-row", "barbell-row-underhand", "t-bar-row",
    "barbell-overhead-press", "barbell-seated-overhead-press", "push-press", "barbell-back-squat", "high-bar-squat",
    "low-bar-squat", "pause-squat", "front-squat", "safety-bar-squat", "box-squat", "conventional-deadlift",
    "sumo-deadlift", "trap-bar-deadlift", "deficit-deadlift", "rack-pull", "barbell-rdl", "stiff-leg-deadlift",
}
# Compound patterns that work as accessories.
ACCESSORIES = {"db-squeeze-press", "bench-dip", "band-row", "cable-glute-kickback", "machine-glute-kickback",
               "glute-bridge", "wall-sit"}
DEADLIFTS = {"conventional-deadlift", "sumo-deadlift", "trap-bar-deadlift", "deficit-deadlift", "rack-pull"}
BODYWEIGHT_HEAVY = {"chest-dip", "triceps-dip", "pull-up", "chin-up", "neutral-grip-pull-up"}

# What strength work also helps.
ALSO_MOBILIZES = {
    "goblet-squat": ["hips", "ankles"], "front-squat": ["ankles", "thoracicSpine"], "pistol-squat": ["ankles", "hips"],
    "db-bulgarian-split-squat": ["hips"], "smith-bulgarian-split-squat": ["hips"],
    "bodyweight-bulgarian-split-squat": ["hips"], "db-deficit-reverse-lunge": ["hips"],
    "barbell-rdl": ["hamstrings"], "db-rdl": ["hamstrings"], "db-rdl-single-leg": ["hamstrings"],
    "stiff-leg-deadlift": ["hamstrings"], "good-morning": ["hamstrings"],
    "db-pullover": ["shoulders", "thoracicSpine"], "dead-hang": ["shoulders"],
}


def parse_tags():
    tags = {}
    for line in TAGS.strip().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        ident, apparatus, joints, numbers = [part.strip() for part in line.split("|")]
        systemic, local, stimulus = (float(n) for n in numbers.split())
        if ident in tags:
            sys.exit(f"duplicate tag row: {ident}")
        tags[ident] = dict(
            apparatus=apparatus.split(),
            joints=[{"joint": j, "stress": int(s)} for j, s in (pair.split(":") for pair in joints.split())],
            systemic=systemic, local=local, stimulus=stimulus,
        )
    return tags


def safety_tier(e):
    ident, equipment, pattern = e["id"], e["equipment"], e["pattern"]
    if ident in NEVER_TO_FAILURE:
        return "neverToFailure"
    if ident in FAIL_WITH_SETUP:
        return "failWithSetup"
    if ident in SAFE_TO_FAIL:
        return "safeToFail"
    if equipment in MACHINES or equipment in ("band", "bodyweight"):
        return "safeToFail"
    if pattern in SAFE_FREE_PATTERNS:
        return "safeToFail"
    return "failWithSetup"


def rest_role(e):
    if e["id"] in HEAVY_COMPOUNDS:
        return "heavyCompound"
    if e["id"] in ACCESSORIES or e["equipment"] == "band":
        return "accessory"
    return "compound" if e["pattern"] in COMPOUND_PATTERNS else "accessory"


def failure_multiplier(e, role):
    ident, equipment = e["id"], e["equipment"]
    if ident in DEADLIFTS:
        return 2.0
    if equipment == "barbell" and e["pattern"] == "squat":
        return 1.6
    if role == "accessory":
        return 1.1
    if equipment in ("barbell", "ezBar", "trapBar"):
        return 1.5
    if equipment in ("dumbbell", "kettlebell") or ident in BODYWEIGHT_HEAVY:
        return 1.35
    return 1.2


def rest_for(role, muscles):
    if role == "heavyCompound":
        return {"strength": 180, "hypertrophy": 150}
    if role == "compound":
        return {"strength": 150, "hypertrophy": 120}
    primary = [m for m, w in muscles if w >= 1]
    if primary and all(m in SMALL_MUSCLES for m in primary):
        return {"strength": 75, "hypertrophy": 60}
    return {"strength": 90, "hypertrophy": 75}


def strength_reps(e, role):
    lo, hi = e["reps"]
    weighted = any("weighted" in a.lower() for a in e.get("aliases", []))
    if e["equipment"] == "band" or (e["equipment"] == "bodyweight" and not weighted and lo >= 8):
        return [lo, hi]
    if e["id"] == "kb-swing":
        return [10, 15]
    if role == "heavyCompound":
        return [3, 6]
    if role == "compound":
        return [5, 8]
    return [lo, hi] if lo < 8 else [8, 12]


def load_basis(e):
    if e.get("timed") and not e.get("loaded"):
        return "none"
    if e.get("load") == "bodyweight":
        return "bodyweightPlus"
    if e.get("load") == "assisted":
        return "assisted"
    if e["equipment"] in ("dumbbell", "kettlebell"):
        return "perHand"
    if e["equipment"] == "band":
        return "none"
    return "external"


def rng(pair):
    return {"lower": pair[0], "upper": pair[1]}


def strength_entry(e, tag):
    role = rest_role(e)
    timed = e.get("timed")
    hyp = [1, 1] if timed else e["reps"]
    entry = {
        "id": e["id"],
        "name": e["name"],
        "aliases": e.get("aliases", []),
        "kind": "strength",
        "pattern": e["pattern"],
        "equipment": e["equipment"],
        "apparatus": tag["apparatus"],
        "muscles": [{"muscle": m, "weight": float(w)} for m, w in e["muscles"]],
        "joints": tag["joints"],
        "fatigue": {"systemic": tag["systemic"], "local": tag["local"], "stimulus": tag["stimulus"],
                    "failureMultiplier": failure_multiplier(e, role)},
        "safetyTier": safety_tier(e),
    }
    if e["id"] in MAPPINGS:
        category, factor = MAPPINGS[e["id"]]
        entry["strength"] = {"category": category, "factor": factor}
    entry.update({
        "loadBasis": load_basis(e),
        "unilateral": bool(e.get("unilateral", False)),
        "reps": {"strength": rng([1, 1] if timed else strength_reps(e, role)), "hypertrophy": rng(hyp)},
        "rest": rest_for(role, e["muscles"]),
        "restRole": role,
        "mobilityTargets": ALSO_MOBILIZES.get(e["id"], []),
        "timed": bool(timed),
    })
    if timed:
        entry["seconds"] = timed
    entry["cue"] = e["cue"]
    entry["custom"] = False
    return entry


# ---------------------------------------------------------------------------------------------
# Mobility, warm-ups, stretches and conditioning.
# ---------------------------------------------------------------------------------------------

def light(ident, name, kind, cue, *, aliases=(), equipment="bodyweight", apparatus=(), muscles=(), joints="",
          targets=(), reps=None, seconds=None, unilateral=False, fatigue=(0.02, 0.05, 0.3), rest=30,
          conditioning=None):
    """A non-strength entry: always safe, never loaded, never mapped."""
    entry = {
        "id": ident,
        "name": name,
        "aliases": list(aliases),
        "kind": kind,
        "pattern": kind,
        "equipment": equipment,
        "apparatus": list(apparatus),
        "muscles": [{"muscle": m, "weight": float(w)} for m, w in muscles],
        "joints": [{"joint": j, "stress": int(s)} for j, s in (pair.split(":") for pair in joints.split())],
        "fatigue": {"systemic": fatigue[0], "local": fatigue[1], "stimulus": fatigue[2], "failureMultiplier": 1.0},
        "safetyTier": "safeToFail",
        "loadBasis": "none",
        "unilateral": unilateral,
        "reps": {"strength": rng(reps or [1, 1]), "hypertrophy": rng(reps or [1, 1])},
        "rest": {"strength": rest, "hypertrophy": rest},
        "restRole": "accessory",
        "mobilityTargets": list(targets),
        "timed": seconds is not None,
    }
    if seconds is not None:
        entry["seconds"] = seconds
    if conditioning:
        entry["conditioning"] = conditioning
    entry["cue"] = cue
    entry["custom"] = False
    return entry


def mobility(ident, name, cue, **kw):
    return light(ident, name, "mobility", cue, **kw)


MOBILITY = [
    # Hips
    mobility("hip-90-90-switches", "90/90 Hip Switches", "Sit tall in 90/90, rotate both knees to the other side without hands.",
             aliases=["90/90 Switches", "Hip 90/90", "90-90 Hip Switch"], joints="hip:1 knee:1", targets=["hips"], reps=[8, 10]),
    mobility("pigeon-stretch", "Pigeon Stretch", "Front shin across, back leg long, hips square; breathe into the front hip.",
             aliases=["Pigeon Pose"], joints="hip:1 knee:1", targets=["hips"], seconds=45, unilateral=True),
    mobility("couch-stretch", "Couch Stretch", "Back knee in the corner, shin up the wall; squeeze the glute, ribs down.",
             aliases=["Rear-Foot-Elevated Hip Flexor Stretch"], joints="knee:1 hip:1", targets=["hips"], seconds=45, unilateral=True),
    mobility("frog-rocks", "Frog Rocks", "Knees wide on the floor, spine long; rock hips back toward the heels and forward.",
             aliases=["Frog Stretch Rocks", "Adductor Rocks"], joints="hip:1 knee:1", targets=["hips"], reps=[10, 12]),
    mobility("hip-airplanes", "Hip Airplanes", "Hinge on one leg, rotate the pelvis open and closed under control.",
             aliases=["Hip Airplane"], joints="hip:1 ankle:1", targets=["hips"], reps=[5, 8], unilateral=True),
    mobility("cossack-squat", "Cossack Squat", "Shift into one deep side squat, other leg straight, heel down; stand and switch.",
             aliases=["Side Squat", "Cossack Squat to Stand"], joints="knee:2 hip:1 ankle:1", targets=["hips", "ankles"],
             reps=[6, 8], unilateral=True),
    mobility("squat-to-stand", "Squat to Stand", "Hold the toes, sink into a deep squat, then straighten the legs keeping hold.",
             aliases=["Toe Touch to Squat"], joints="hip:1 knee:1 lowerBack:1", targets=["hamstrings", "hips"], reps=[6, 8]),
    mobility("deep-squat-pry", "Deep Squat Pry", "Sit in the bottom of a squat, elbows inside the knees; pry the knees open.",
             aliases=["Squat Pry", "Goblet Squat Hold"], joints="hip:1 knee:2 ankle:1", targets=["hips", "ankles"], seconds=45),
    # Ankles
    mobility("knee-to-wall-rocks", "Knee-to-Wall Ankle Rocks", "Heel down, drive the knee over the little toes to the wall.",
             aliases=["Knee to Wall", "Ankle Rocks", "Wall Ankle Mobilisation"], joints="ankle:1 knee:1", targets=["ankles"],
             reps=[10, 12], unilateral=True),
    mobility("banded-ankle-mobilisation", "Banded Ankle Mobilisation",
             "Band low on the front of the ankle pulling back; rock the knee forward over the toes.",
             aliases=["Banded Ankle Mobilization", "Banded Ankle Distraction"], equipment="band", joints="ankle:1",
             targets=["ankles"], reps=[10, 15], unilateral=True),
    mobility("elevated-calf-stretch", "Elevated Calf Stretch", "Ball of the foot on a step, knee straight, let the heel sink.",
             aliases=["Step Calf Stretch", "Calf Stretch on a Step"], apparatus=["box"], joints="ankle:1",
             targets=["ankles"], seconds=30, unilateral=True),
    mobility("ankle-cars", "Ankle CARs", "Hold the shin still; draw the biggest slow circle you can with the foot.",
             aliases=["Ankle Controlled Articular Rotations", "Ankle Circles"], joints="ankle:1", targets=["ankles"],
             reps=[5, 8], unilateral=True),
    # Hamstrings
    mobility("leg-swings", "Front-to-Back Leg Swings", "Hold a wall, swing the leg forward and back, growing the range each rep.",
             aliases=["Leg Swings", "Forward Leg Swings"], joints="hip:1", targets=["hamstrings", "hips"], reps=[10, 15],
             unilateral=True),
    mobility("active-straight-leg-raise", "Active Straight-Leg Raise", "On your back, lift one straight leg as high as it goes; lower slowly.",
             aliases=["ASLR", "Active SLR"], joints="hip:1", targets=["hamstrings"], reps=[8, 10], unilateral=True),
    mobility("hamstring-floss", "Hamstring Floss", "Seated or lying, hold behind the thigh; straighten and bend the knee with the foot flexed.",
             aliases=["Hamstring Flossing", "Hamstring Nerve Floss"], joints="knee:1 hip:1", targets=["hamstrings"],
             reps=[10, 12], unilateral=True),
    mobility("bodyweight-good-morning", "Bodyweight Good Morning", "Hands behind head, soft knees; push the hips back until the hamstrings pull.",
             aliases=["BW Good Morning"], joints="hip:1 lowerBack:1", targets=["hamstrings"], reps=[10, 15]),
    mobility("jefferson-curl", "Jefferson Curl", "Very light or no weight; roll down one vertebra at a time and roll back up.",
             aliases=["Jefferson Curls"], joints="lowerBack:2 hip:1", targets=["hamstrings"], reps=[5, 8]),
    # Shoulders
    mobility("wall-slides", "Wall Slides", "Back and forearms on the wall, ribs down; slide up without losing contact.",
             aliases=["Wall Angels", "Forearm Wall Slides"], joints="shoulder:1", targets=["shoulders", "thoracicSpine"], reps=[10, 12]),
    mobility("band-dislocates", "Band Dislocates", "Wide grip on a light band; arc it overhead and behind with straight arms.",
             aliases=["Band Pass-Throughs", "Shoulder Dislocates", "Shoulder Pass-Throughs"], equipment="band",
             joints="shoulder:1", targets=["shoulders"], reps=[10, 15]),
    mobility("sleeper-stretch", "Sleeper Stretch", "Lie on the side, upper arm at 90°; ease the forearm down with the other hand.",
             aliases=["Sleeper Stretch for Shoulder"], joints="shoulder:1", targets=["shoulders"], seconds=30, unilateral=True),
    mobility("prone-y-t-w", "Prone Y-T-W", "Face down, thumbs up; lift into a Y, then a T, then a W, squeezing the shoulder blades.",
             aliases=["Prone YTW", "Y-T-W Raises", "YTWs"], joints="shoulder:1", targets=["shoulders", "thoracicSpine"], reps=[6, 8]),
    # Thoracic spine
    mobility("open-books", "Open Books", "Side-lying, knees stacked; open the top arm across to the floor behind, eyes follow.",
             aliases=["Open Book Stretch", "Side-Lying Thoracic Rotation"], joints="upperBack:1 shoulder:1",
             targets=["thoracicSpine"], reps=[8, 10], unilateral=True),
    mobility("cat-cow", "Cat-Cow", "On hands and knees, round the whole spine up, then arch it down, slowly.",
             aliases=["Cat Camel", "Cat-Camel"], joints="upperBack:1 lowerBack:1", targets=["thoracicSpine"], reps=[8, 10]),
    mobility("thread-the-needle", "Thread the Needle", "On all fours, reach one arm under the body, then open it to the ceiling.",
             aliases=["Thread-the-Needle Rotation"], joints="upperBack:1 shoulder:1", targets=["thoracicSpine", "shoulders"],
             reps=[8, 10], unilateral=True),
    mobility("foam-roller-thoracic-extension", "Foam Roller Thoracic Extensions",
             "Roller across the upper back, hands behind head; extend over it, move up a segment, repeat.",
             aliases=["T-Spine Extensions", "Thoracic Extensions", "Foam Roller Extensions"], joints="upperBack:1 neck:1",
             targets=["thoracicSpine"], reps=[8, 10]),
    mobility("quadruped-thoracic-rotation", "Quadruped T-Spine Rotation", "On all fours, hand behind head; rotate the elbow down then up to the ceiling.",
             aliases=["Quadruped Thoracic Rotation", "Hand-Behind-Head Rotation", "T-Spine Rotation"], joints="upperBack:1",
             targets=["thoracicSpine"], reps=[8, 10], unilateral=True),
]


def warmup(ident, name, cue, **kw):
    kw.setdefault("fatigue", (0.03, 0.08, 0.3))
    kw.setdefault("rest", 15)
    return light(ident, name, "warmup", cue, **kw)


# In routine order: general openers, then upper-day moves, then lower-day moves.
WARMUPS = [
    warmup("easy-bike-warmup", "5-Minute Easy Bike", "Easy spin, conversational; just get warm.",
           aliases=["Bike Warm-Up", "Easy Bike"], equipment="bike", joints="knee:1", seconds=300, fatigue=(0.03, 0.05, 0.3)),
    warmup("easy-row-warmup", "5-Minute Easy Row", "Easy strokes, legs then back then arms; build gently.",
           aliases=["Rower Warm-Up", "Easy Row"], equipment="rower", joints="knee:1 lowerBack:1", seconds=300,
           fatigue=(0.03, 0.05, 0.3)),
    # Upper days
    warmup("arm-circles", "Arm Circles", "Small to big circles, forwards then backwards.", aliases=["Arm Swings"],
           muscles=[["frontDelts", 0.5], ["sideDelts", 0.5], ["rearDelts", 0.5]], joints="shoulder:1",
           targets=["shoulders"], reps=[10, 15]),
    warmup("band-pull-apart-warmup", "Light Band Pull-Aparts", "Light band, straight arms; pull to the chest, squeeze, return slowly.",
           aliases=["Warm-Up Band Pull-Aparts"], equipment="band", muscles=[["rearDelts", 0.5], ["upperBack", 0.5]],
           joints="shoulder:1", targets=["shoulders"], reps=[15, 20]),
    warmup("face-pull-warmup", "Light Face Pulls", "Light stack, rope to the eyes, elbows high, pause at the back.",
           aliases=["Warm-Up Face Pulls"], equipment="cable", muscles=[["rearDelts", 0.5], ["upperBack", 0.5]],
           joints="shoulder:1", targets=["shoulders"], reps=[15, 20]),
    warmup("band-external-rotation", "Band External Rotations", "Elbow pinned at the side, rotate the forearm out against a light band.",
           aliases=["Banded External Rotation", "Rotator Cuff External Rotation"], equipment="band",
           muscles=[["rearDelts", 0.5]], joints="shoulder:1", targets=["shoulders"], reps=[12, 15], unilateral=True),
    warmup("scap-push-up", "Scap Push-Ups", "Arms straight in a plank; let the chest sink between the shoulder blades, then push away.",
           aliases=["Scapular Push-Ups", "Push-Up Plus"], muscles=[["chest", 0.5], ["upperBack", 0.5]],
           joints="shoulder:1 wrist:1", targets=["shoulders"], reps=[10, 12]),
    warmup("push-up-to-downward-dog", "Push-Up to Downward Dog", "One easy push-up, then push the hips up and back into downward dog.",
           aliases=["Push-Up to Down Dog"], muscles=[["chest", 0.5], ["triceps", 0.5], ["frontDelts", 0.5]],
           joints="shoulder:1 wrist:1", targets=["shoulders", "hamstrings"], reps=[6, 10]),
    # Lower days
    warmup("glute-bridge-warmup", "Activation Glute Bridges", "Feet flat, drive through the heels, squeeze the glutes at the top.",
           aliases=["Warm-Up Glute Bridges"], muscles=[["glutes", 0.5], ["hamstrings", 0.5]], joints="hip:1",
           targets=["hips"], reps=[10, 15]),
    warmup("lateral-band-walk", "Lateral Band Walks", "Band above the knees, half squat; step sideways keeping tension.",
           aliases=["Monster Walks", "Banded Side Steps", "Band Walks"], equipment="band", muscles=[["glutes", 0.5]],
           joints="hip:1 knee:1", targets=["hips"], reps=[10, 15]),
    warmup("lateral-leg-swings", "Lateral Leg Swings", "Face a wall, swing one leg across the body and out to the side.",
           aliases=["Side-to-Side Leg Swings", "Leg Swings"], muscles=[["adductors", 0.5], ["glutes", 0.5]], joints="hip:1",
           targets=["hips"], reps=[10, 15], unilateral=True),
    warmup("bodyweight-squat-warmup", "Slow Air Squats", "Slow bodyweight squats, sitting deeper each rep.",
           aliases=["Warm-Up Squats", "Bodyweight Squats"], muscles=[["quads", 0.5], ["glutes", 0.5]],
           joints="knee:1 hip:1 ankle:1", targets=["hips", "ankles"], reps=[10, 15]),
    warmup("walking-lunge-warmup", "Bodyweight Walking Lunges", "Long steps, back knee kisses the floor, torso tall.",
           aliases=["Walking Lunges (Warm-Up)"], muscles=[["quads", 0.5], ["glutes", 0.5]], joints="knee:1 hip:1 ankle:1",
           targets=["hips"], reps=[8, 10], unilateral=True),
    warmup("worlds-greatest-stretch", "World's Greatest Stretch", "Lunge, elbow to the instep, rotate the arm to the ceiling, then straighten the front leg.",
           aliases=["WGS", "Lunge with Rotation"], muscles=[["glutes", 0.5], ["hamstrings", 0.5], ["adductors", 0.5]],
           joints="hip:1 knee:1 upperBack:1", targets=["hips", "hamstrings", "thoracicSpine"], reps=[4, 6], unilateral=True),
]


def stretch(ident, name, cue, **kw):
    kw.setdefault("fatigue", (0.0, 0.02, 0.2))
    kw.setdefault("rest", 10)
    kw.setdefault("seconds", 30)
    return light(ident, name, "stretch", cue, **kw)


STRETCHES = [
    stretch("doorway-chest-stretch", "Doorway Chest Stretch", "Forearm on the frame at shoulder height; step through until the chest opens.",
            aliases=["Doorway Pec Stretch", "Chest Stretch"], muscles=[["chest", 1], ["frontDelts", 0.5]], joints="shoulder:1",
            targets=["shoulders"], unilateral=True),
    stretch("lat-stretch", "Lat Stretch", "Hold a post or rack, sit the hips back and away; feel it along the side.",
            aliases=["Hanging Lat Stretch", "Rack Lat Stretch"], muscles=[["lats", 1]], joints="shoulder:1",
            targets=["shoulders", "thoracicSpine"], unilateral=True),
    stretch("childs-pose", "Child's Pose", "Knees wide, sit back to the heels, arms long; breathe into the back.",
            aliases=["Childs Pose", "Balasana"], muscles=[["lowerBack", 1], ["lats", 0.5], ["upperBack", 0.5]],
            joints="lowerBack:1 knee:1", targets=["thoracicSpine", "hips"], seconds=45),
    stretch("cross-body-shoulder-stretch", "Cross-Body Shoulder Stretch", "Pull the straight arm across the chest just below the shoulder.",
            aliases=["Cross-Body Stretch", "Rear Delt Stretch"], muscles=[["rearDelts", 1], ["sideDelts", 0.5], ["upperBack", 0.5]],
            joints="shoulder:1", targets=["shoulders"], unilateral=True),
    stretch("upper-trap-stretch", "Upper Trap Stretch", "Ear toward shoulder, gentle hand assist, opposite shoulder down.",
            aliases=["Neck Side Stretch", "Trap Stretch"], muscles=[["traps", 1]], joints="neck:1", unilateral=True),
    stretch("overhead-triceps-stretch", "Overhead Triceps Stretch", "Hand down the upper back, other hand eases the elbow behind the head.",
            aliases=["Triceps Stretch", "Overhead Stretch"], muscles=[["triceps", 1], ["lats", 0.5]], joints="shoulder:1 elbow:1",
            targets=["shoulders"], unilateral=True),
    stretch("biceps-wall-stretch", "Biceps Wall Stretch", "Palm on the wall behind you at shoulder height, thumb up; turn the body away.",
            aliases=["Biceps Stretch"], muscles=[["biceps", 1], ["chest", 0.5], ["frontDelts", 0.5]], joints="shoulder:1 elbow:1",
            targets=["shoulders"], unilateral=True),
    stretch("wrist-flexor-stretch", "Wrist Flexor Stretch", "Arm straight, palm up; ease the fingers back with the other hand.",
            aliases=["Forearm Stretch", "Wrist Stretch"], muscles=[["forearms", 1]], joints="wrist:1", unilateral=True),
    stretch("cobra-stretch", "Cobra Stretch", "Face down, hands under shoulders; press the chest up, hips stay down.",
            aliases=["Cobra", "Prone Press-Up", "Abs Stretch"], muscles=[["abs", 1]], joints="lowerBack:1"),
    stretch("standing-quad-stretch", "Standing Quad Stretch", "Hold the ankle behind you, knees together, tuck the pelvis.",
            aliases=["Quad Stretch"], muscles=[["quads", 1]], joints="knee:1", targets=["hips"], unilateral=True),
    stretch("hamstring-stretch", "Hamstring Stretch", "Straight leg, hinge from the hips with a flat back until it pulls.",
            aliases=["Standing Hamstring Stretch", "Seated Hamstring Stretch"], muscles=[["hamstrings", 1]],
            joints="hip:1", targets=["hamstrings"], unilateral=True),
    stretch("kneeling-hip-flexor-stretch", "Kneeling Hip Flexor Stretch", "Half kneeling, squeeze the back glute and shift forward; ribs down.",
            aliases=["Hip Flexor Stretch", "Half-Kneeling Hip Flexor Stretch"], muscles=[["quads", 1]],
            joints="hip:1 knee:1", targets=["hips"], unilateral=True),
    stretch("figure-four-stretch", "Figure-4 Glute Stretch", "On your back, ankle over the opposite knee; pull the thigh in.",
            aliases=["Figure Four Stretch", "Glute Stretch", "Supine Piriformis Stretch"], muscles=[["glutes", 1]],
            joints="hip:1 knee:1", targets=["hips"], unilateral=True),
    stretch("butterfly-stretch", "Butterfly Stretch", "Soles together, sit tall, let the knees fall; hinge forward gently.",
            aliases=["Adductor Stretch", "Groin Stretch"], muscles=[["adductors", 1]], joints="hip:1", targets=["hips"]),
    stretch("wall-calf-stretch", "Wall Calf Stretch", "Hands on the wall, back leg straight, heel down; lean in.",
            aliases=["Calf Stretch", "Standing Calf Stretch"], muscles=[["calves", 1]], joints="ankle:1",
            targets=["ankles"], unilateral=True),
]


def cardio(ident, name, cue, equipment, style, zones, seconds, joints, fatigue, *, work=None, rest=None, aliases=()):
    spec = {"style": style, "zones": zones}
    if work is not None:
        spec["workSeconds"] = work
        spec["restSeconds"] = rest
    return light(ident, name, "conditioning", cue, aliases=aliases, equipment=equipment, joints=joints,
                 seconds=seconds, fatigue=fatigue, rest=0, conditioning=spec)


CONDITIONING = [
    cardio("stairmaster-zone-2", "StairMaster Zone 2", "Steady pace you could talk through; stand tall, light hands on the rails.",
           "stairClimber", "steady", [2, 2], 1800, "knee:1 ankle:1 hip:1", (0.2, 0.25, 0.7),
           aliases=["Stair Climber Zone 2", "Stairs Steady"]),
    cardio("stairmaster-intervals", "StairMaster Intervals", "Hard minute, easy minute; let the heart rate fall before the next push.",
           "stairClimber", "intervals", [4, 5], 1200, "knee:2 ankle:1 hip:1", (0.4, 0.35, 0.8), work=60, rest=60,
           aliases=["Stair Climber Intervals", "Stair Intervals"]),
    cardio("bike-zone-2", "Bike Zone 2", "Steady spin at a pace you could hold a conversation at.",
           "bike", "steady", [2, 2], 1800, "knee:1", (0.15, 0.2, 0.7), aliases=["Cycling Zone 2", "Easy Bike Ride"]),
    cardio("bike-30-30-intervals", "Bike 30/30 Intervals", "30 seconds hard, 30 easy; keep every hard rep the same power.",
           "bike", "intervals", [4, 5], 1200, "knee:1", (0.35, 0.3, 0.8), work=30, rest=30,
           aliases=["Bike Intervals", "Bike Sprints", "30-30 Bike"]),
    cardio("rower-zone-2", "Rower Zone 2", "Steady strokes, about 20 a minute; legs, back, arms.",
           "rower", "steady", [2, 2], 1800, "lowerBack:1 knee:1", (0.2, 0.25, 0.7), aliases=["Rowing Zone 2", "Erg Steady"]),
    cardio("rower-500m-repeats", "Rower 500 m Repeats", "Hold one hard split for every 500; rest easy between.",
           "rower", "intervals", [4, 5], 1440, "lowerBack:2 knee:1", (0.45, 0.35, 0.85), work=120, rest=120,
           aliases=["500m Repeats", "Row Intervals", "Erg Intervals"]),
    cardio("treadmill-incline-walk", "Treadmill Incline Walk", "Brisk walk on a steep incline; don't hold the rails.",
           "treadmill", "steady", [2, 2], 1800, "ankle:1 knee:1", (0.12, 0.2, 0.65), aliases=["Incline Walk", "12-3-30"]),
    cardio("treadmill-intervals", "Treadmill Intervals", "Fast minute, then walk or jog easy until breathing settles.",
           "treadmill", "intervals", [4, 5], 1200, "knee:2 ankle:2 hip:1", (0.4, 0.35, 0.8), work=60, rest=90,
           aliases=["Treadmill Sprints", "Run Intervals"]),
    cardio("outdoor-run", "Outdoor Run", "Easy to moderate; you should be able to speak in sentences.",
           "bodyweight", "steady", [2, 3], 1800, "knee:2 ankle:2 hip:1", (0.25, 0.3, 0.75), aliases=["Run", "Easy Run", "Jog"]),
    cardio("brisk-walk", "Brisk Walk", "Purposeful pace, arms swinging; hills welcome.",
           "bodyweight", "steady", [2, 2], 1800, "ankle:1", (0.08, 0.15, 0.55), aliases=["Walk", "Power Walk"]),
    cardio("jump-rope-intervals", "Jump Rope Intervals", "Light bounces on the balls of the feet; 30 on, 30 off.",
           "bodyweight", "intervals", [4, 5], 600, "ankle:2 knee:1", (0.3, 0.3, 0.75), work=30, rest=30,
           aliases=["Skipping Intervals", "Jump Rope"]),
]


def main():
    legacy = json.loads(LEGACY.read_text())
    tags = parse_tags()
    known = {e["id"] for e in legacy} | {e["id"] for e in NEW_STRENGTH}
    unknown = sorted(set(tags) - known)
    missing = sorted(known - set(tags))
    if unknown or missing:
        sys.exit(f"tag rows out of sync. unknown: {unknown} missing: {missing}")
    for table in (MAPPINGS, ALSO_MOBILIZES):
        stray = sorted(set(table) - known)
        if stray:
            sys.exit(f"unknown ids in tables: {stray}")

    entries = [strength_entry(e, tags[e["id"]]) for e in legacy]
    entries += [strength_entry(e, tags[e["id"]]) for e in NEW_STRENGTH]
    entries += MOBILITY + WARMUPS + STRETCHES + CONDITIONING

    ids = [e["id"] for e in entries]
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        sys.exit(f"duplicate ids: {dupes}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(entries, indent=1, ensure_ascii=False) + "\n")
    counts = {}
    for e in entries:
        counts[e["kind"]] = counts.get(e["kind"], 0) + 1
    print(f"wrote {len(entries)} entries to {OUT}: {counts}")


if __name__ == "__main__":
    main()
