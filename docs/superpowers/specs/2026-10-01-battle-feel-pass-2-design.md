# Battle feel, pass 2: weight and momentum — design

Status: DRAFT for review, 2026-10-01. Follows the feel pass of 2026-09-30
(slower marching, halved contact slide, range rings, click-to-shoot). Runs in
parallel with the nation AI (`2026-10-01-nation-ai-design.md`); the two touch
disjoint files (see "Ownership").

## Problem

After pass 1 the battle is slower but still reads as "slidy":

1. **No momentum.** A block goes from standing to full speed in one tick and
   stops dead on arrival (`BattleSim._move` takes a full `speed × dt` stride
   every step). Nothing has weight.
2. **Crab-walking.** A block walks in the direction of its destination while
   its facing is still up to `pivot_angle` (45°) away, so it drifts sideways
   at full speed while it turns.
3. **Sliding along obstacles.** When a step is blocked, `_try_step` tries the
   two axis directions at the same full stride, so a block that meets water,
   a cliff or a solid friend skates along it instead of slowing.
4. **Snapping on contact.** Seating is a fixed-rate slide (15 u/s) toward the
   flush position, and the push moves blocks at a steady rate, both with no
   build-up or settling.

## Goal

Blocks have weight: they build up speed, carry it, slow before they stop,
move the way they face, and slow down rather than skate when something is
in the way. Contact settles rather than snaps. All of it tunable, with the
existing rules (locks, push, charges, reforms, routes, soft marching)
unchanged in meaning.

## Design

### 1. Momentum (`block.gd`, `battle_sim.gd` `_move`)

- `Block` gains `velocity: float` (current speed along its facing, u/s).
- Each step a moving block's target speed is its role speed × terrain
  multiplier (× `march_overlap_speed` inside a friend), and its velocity
  moves toward it by at most `accel × dt` (speeding up) or `decel × dt`
  (slowing down). Per-role `accel` / `decel` in `GameConfig.units`:
  infantry 10 / 16 u/s², archers 12 / 18, cavalry 14 / 12 (heavy to stop).
- **Arriving:** a block caps its velocity at `sqrt(2 · decel · distance
  left)`, so it slows into its destination (route end, formation slot, shoot
  stand-off) instead of stopping dead. Intermediate route points don't brake.
- **Turning bleeds speed:** target speed is scaled by `cos(off)` of the angle
  between facing and heading (clamped ≥ 0), so a block slows into a turn and
  speeds out of it.
- Standing, holding, locked and reforming blocks have velocity 0; a block
  that is stopped (blocked, locked) loses its velocity at once — no momentum
  carried into a wall.
- **Charges:** `charge_run` keeps counting straight distance as now; the
  charge burst additionally scales with the charging block's velocity
  relative to its full speed (`charge_speed_floor` 0.5 → a slow charge does
  half), so a run-up means getting up to speed, not just covering ground.

### 2. Move the way you face

A non-routing block steps along its **facing**, not toward its destination;
it steers by turning (at its turn rate) toward the destination. With the
momentum model it pivots on the spot from standstill (as now) and arcs when
it is already moving. `pivot_angle` stays as the "turn before you start
walking" threshold. Routing blocks keep running toward home while they turn
(unchanged).

### 3. No skating along obstacles

`_try_step`'s axis slides go. A block whose step along its facing is blocked
(terrain, field edge, a solid friend, an enemy it isn't locked with):

- loses its velocity (stops), and
- if its destination is still ahead, turns toward the nearest open heading
  (sampled ±15°, ±30°, … ±90° off the facing) and moves off along it once
  that heading is clear — a deliberate sidestep at walking pace, not a skate.

Existing behaviour that depended on the slides keeps working through this:
the head-on sidestep between friends (`_sidestep`) becomes one of these
open-heading searches; routes are already cleaned round water and cliffs.

### 4. Contact that settles

- **Seating** eases instead of sliding at a fixed rate: the initiator's seat
  speed is `seat_speed × min(1, gap / seat_ease)` (`seat_ease` 6 u), so it
  closes quickly from a distance and settles into the last few units.
- **Push** keeps its rate rule but uses the momentum model: the loser and
  its followers accelerate to the push speed at `push_accel` (8 u/s²) and
  decelerate when the gap closes, instead of jumping between rates.
- An arriving attacker keeps the velocity it had at contact for the charge
  rule above, then drops to 0 (it is locked).

### 5. Feedback (`battle_view.gd`)

- A short **dust trail** behind any block moving faster than half its full
  speed: 3–5 fading dots along its recent path, in the terrain colour,
  thicker for cavalry. Lets the eye read speed and momentum.
- The **MOVING** tag becomes **MARCHING** / **CHARGING** (velocity above
  80 % of full speed with `charge_run` past `charge_min_distance`).
- Nothing else in the view changes.

### 6. Config (all in the tuning panel)

`GameConfig.units[role]`: `accel`, `decel`. `GameConfig.combat`:
`charge_speed_floor` 0.5, `seat_ease` 6.0, `push_accel` 8.0,
`sidestep_max_angle` 90.

## Ownership

Owns `game/scripts/sim/battle_sim.gd` (movement, `_try_step`, seating and
push motion, charges), `game/scripts/sim/block.gd`, `game/scripts/ui/battle_view.gd`,
and their tests (`test_contact.gd`, `test_routes.gd`, `test_battle_shell.gd`,
`test_combat.gd`). Appends to `GameConfig.units` / `GameConfig.combat` only.
Does **not** touch the campaign (`scripts/sim/world`, `logistics`, `battle/`,
`phases/`, `ai/`) — the nation-AI workstream owns those. The only shared file
is `game_config.gd`, where both append separate keys.

## Tests

Rules and relative claims only — no test pins how a battle ends or exactly
when.

- **Momentum:** from standstill a block's speed after 0.2 s is below its full
  speed and reaches it within `speed / accel` + a margin; on arrival it slows
  continuously and stops within 1 u of the destination without overshooting;
  a block passing a route's intermediate point doesn't slow there.
- **Turning:** a moving block that turns 90° is slower mid-turn than on the
  straight before and after it.
- **Facing:** each step's displacement is within a few degrees of the block's
  facing (no sideways drift) for non-routing blocks.
- **No skating:** a block walked into a wall of water at 45° ends the step
  stopped; it then turns to an open heading and continues, reaching its
  destination round the obstacle; its lateral speed along the wall never
  exceeds walking pace.
- **Charges:** a charge from a standing start does less burst damage than the
  same charge after a full run-up (relative claim).
- **Contact:** the seat gap shrinks every step and the last few units take
  longer than the first few; the push speed ramps up rather than jumping.
- **Existing claims** (flank charge routs an engaged block within ~5 s,
  braced front blunts a charge, withdrawals, hill and bridge beat open
  ground, every battle ends within the clock) still pass; timing windows in
  tests that only encode old speeds are scaled, never their assertions.

## Open questions for review

1. Move-along-facing (§2) changes how every block looks when it turns — arcs
   instead of crab-walks. Wanted, or keep crab-walking and only add momentum?
2. Removing the axis slides (§3) is the biggest risk of new jams (the old
   slides quietly unstuck things). Proposed: remove them and rely on the
   open-heading sidestep; alternative: keep them at ≤ 30 % speed.
3. Should the charge burst scale with speed (§1, last bullet)? It makes
   cavalry run-ups matter more and slows nothing else, but it is a balance
   change, not just feel.
4. Dust trails (§5) — keep, or keep the view untouched this pass?
