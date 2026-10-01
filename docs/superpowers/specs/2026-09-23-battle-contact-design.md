# Battle contact: locking, pushing, facing and reform — design

Status: approved in brainstorming 2026-09-23. Scope: the real-time battle
(`game/scripts/sim/battle_sim.gd`, `block.gd`, `battle_ai.gd`, the battle
drawing in `game/scripts/ui/battle_view.gd`) and its tests. The campaign layer
is untouched.

## Problem

Blocks are moved by hand each 1/60 s tick; there is no physics engine. Three
things make fights feel like bumper cars:

1. `_separate()` shoves overlapping friendly blocks apart by 0.6 units per tick
   (~36 u/s, faster than infantry marches at 20 u/s).
2. Enemies are hard walls, but a moving block that hits one slides along each
   axis in turn (`_try_step`), so it scrapes around the enemy instead of
   stopping. Contact only stops a block that has an Attack order.
3. Facing snaps instantly to the movement direction every tick; nothing makes
   two blocks in contact face each other.

## Goal

When blocks meet they lock together. The side winning the damage trade slowly
pushes the other back until it breaks. An attack pulls the attacker flush
against the face it struck; a front-to-front contact squares both blocks up. A
block hit on the flank can be ordered to attack its flanker, and turns to face
it only after a visible, risky reform.

## Design

### 1. Engagements (new `game/scripts/sim/contact.gd`, `class_name Contact`)

An engagement is an explicit record created when two enemy blocks touch:
`{initiator: Block, target: Block, face: "front"|"left"|"right"|"rear",
pressure_i: float, pressure_t: float}` (the face is the side of the target the
initiator struck, by the existing 45°/135° arc rule; left/right by the sign of
the cross product). The initiator is the block whose front points more
squarely at the other (ties: the lower id); if the pair struck each other's
fronts, the engagement is front-to-front. `BattleSim` owns the list; `Contact`
holds the static functions that create, update and end engagements.

Each tick, engagements are updated before any free movement:

- **Seating.** The initiator turns (at its turn rate) until its front is
  parallel to the struck face, and slides (at `seat_speed`) until its front edge
  sits against that face, centred on the face as far as the target's size
  allows. A front-to-front engagement squares both blocks: they turn toward
  exactly opposite facings, meeting halfway.
- **A flank or rear hit moves only the attacker.** The victim keeps its facing
  and keeps taking flank ×1.5 / rear ×2 damage until it reforms (section 3).
- **One block, several engagements.** Each attacker seats against its own face;
  the victim's facing follows only its front engagement.

### 2. Pressure, push and breaking

- **Pressure.** Each engagement keeps the damage per second each side deals the
  other *through this contact*, smoothed as an exponential moving average over
  `push_smoothing` seconds (1.5 s). Damage already includes supply, uphill,
  brace, flank/rear multipliers and the charge burst, so every existing rule
  feeds the push; a charge's burst shows as a shove on impact.
- **Push.** Gap = winner's pressure − loser's pressure. Below `push_deadband`
  nobody moves (stalemate). Otherwise the loser moves at
  `min(push_per_dps × gap, push_max)` along the contact normal (away from the
  winner: backward for a front engagement, sideways along the attacker's
  facing for a flank, forward for a rear), and the winner follows so the pair
  stays seated. A victim in several engagements moves by the capped vector sum.
- **Giving ground is not always possible.** If the loser's next position is
  blocked (terrain, field edge, a friendly block), the push stops; nobody
  overlaps and the fight grinds in place. No extra penalty. A loser gives
  ground only if every winner against it can follow (a winner in other fights,
  already moved this step, or blocked cannot); otherwise the fight grinds in
  place too. Pushes stall on a bridge: a winner cannot follow into the cell the
  loser is leaving, since a bridge cell holds one block.
- **Who may walk away.** A block whose pressure exceeds its opponent's by more
  than `push_deadband` in every engagement it is in is *winning*: its Move order
  walks it out of contact, ending those engagements (the loser is then free,
  and may charge it). Any other engaged block ignores Move and Hold; its only
  ways out are Withdraw / Retreat all (existing rules, rear exposure included),
  routing, or being destroyed. An even fight counts as losing for both. A
  pair released by a winner walking out that keeps touching fights on
  unlocked (no seating, no push) until it separates; only then may it lock
  again.
- **Breaking.** Unchanged: at morale 0 the loser routs, its engagements end, and
  a winner with an Attack order on it pursues.

### 3. Turning, reform, friendly spacing

- **Turn rates.** New per-role `turn_rate` (deg/s) in `GameConfig.units`:
  infantry 90, archers 120, cavalry 180. Facing turns toward the desired
  heading at that rate. A block more than `pivot_angle` (45°) off its heading
  pivots in place before moving. Withdraw still turns the block's back to walk
  home.
- **Reform.** An Attack order, given to an engaged block, on an enemy engaged
  with it on its flank or rear, starts a reform lasting the role's
  `reform_time` (infantry 2.0 s, archers 1.5 s, cavalry 1.5 s):
  - the block is *disordered*: it cannot move and deals ×`reform_damage` (0.5);
  - it keeps taking damage by its current arcs until the reform completes;
  - on completion its facing flips to face the flanker, that engagement becomes
    front-to-front, and whoever was on its old front is now on its flank or
    rear (arcs are recomputed from the new facing); locks the reformer had
    initiated on anyone else are recast with that foe as the initiator, so the
    old foe strikes the reformed block rather than turning it back;
  - Withdraw, Retreat all, or a rout cancels it;
  - re-issuing Attack on the same target during or after the reform does not
    restart it (BattleAI re-issues orders every 0.4 s).
  - **Controller decision (beyond this spec):** a reform is also cancelled if
    its target dies, routs, withdraws or leaves contact — reforming to face an
    enemy that is no longer there made no sense.
  An unengaged block ordered to attack something behind it just turns at its
  turn rate; no reform.
- **Friendly spacing: solid.** `_separate()`'s shove is removed. A block may not
  overlap a friendly block beyond the existing 5-unit slack; a moving block
  that would slides along it if the existing axis fallback finds room, and
  otherwise waits. Two friends meeting head-on (each walking at the other)
  sidestep along their frontage and pass; a queue behind a standing or slower
  friend still waits. A pair already deep in each other (turns are not
  collision-checked), friend or enemy, may only move apart. An engaged block
  is never displaced by friends. Risk: jams
  at gaps and on the bridge; the battle-clock and scenario tests are the
  guard, and paths/AI are tuned before this rule is relaxed.
  **Relaxed for marching blocks (user decision 2026-09-24, drawn orders):** a
  block that is marching — order Move or a route, not locked, not routing —
  passes through friends, at `march_overlap_speed` (0.6) × its speed while deep
  in one, and never moves them. Standing, holding, bracing, fighting,
  attacking and withdrawing blocks stay solid to friends as above, so a
  screen still screens and a queue of attackers still queues. The bridge's
  one-block-per-cell rule is unchanged.

### 4. Drawing (BattleView)

- The reform is drawn procedurally in the existing block renderer: the outline
  loosens into small rank marks that scatter slightly, the cluster rotates
  smoothly (ease in-out) from the old facing to the new over the reform time,
  then tightens back into the rectangle. A thin progress ring shows the time
  left and the block tag reads REFORMING. The sim's facing flips only at the
  end; the drawing interpolates.
- Seating and pushing need no new drawing: blocks now move and turn smoothly.
- Selection tooltip adds "reforming (1.2s)" and "pushing / giving ground".

### 5. Config (all tunable, in the tuning panel)

`GameConfig.combat`: `seat_speed` 30, `push_per_dps` 0.45 (0.5 until the drawn-orders last gate), `push_max` 6.0,
`push_deadband` 1.0, `push_smoothing` 1.5, `pivot_angle` 45, `reform_damage`
0.5. `GameConfig.units[role]`: `turn_rate`, `reform_time` as above. Starting
values were `push_per_dps` 1.0, `push_deadband` 0.5, `push_smoothing` 1.0 and
`pivot_angle` 30; tuned against the tests in section 6 (see
`.superpowers/sdd/progress.md` "Battle contact ledger" for the tuning history).

### 6. Tests and balance

- **New suite `game/tests/test_contact.gd`**, one check per rule: a charge
  seats flush within a set time; front-to-front squares both; a flank hit
  leaves the victim's facing alone; a mirror duel on flat ground does not
  drift while an uphill duel drifts downhill; the winner's Move walks out, the
  loser's Move is ignored and its Withdraw works; a loser backed onto the river
  stops the push; a 180° infantry turn takes ~2 s; friendly blocks never
  overlap; reform gives REFORMING for `reform_time` at half damage, then
  front-to-front with the flanker; Withdraw cancels it; re-issuing the same
  Attack does not restart it.
- **Existing combat checks (87).** Every design claim stays a pass/fail bar: a
  flank charge on an engaged block routs it within ~5 s; the same charge into a
  braced front fails; an uncovered withdrawal under cavalry is a disaster and a
  covered one survives; hill and bridge beat open ground; battles end within
  the clock. Battles are never pinned to an exact outcome or duration (user
  decision 2026-09-30: the Ford exact-count checks were removed). Measured values (trade
  +40 hp, the Ford's 5 of 6, the README table) are re-measured and updated. If a
  claim fails, tune section 5's values first; if tuning cannot keep a claim,
  stop and bring it to the user rather than weaken the check. WS-C's East Hill
  acceptance must still hold.
- **View.** A shell test drives a reform through `BattleView` and checks it
  renders and shows REFORMING. Look and feel is play-tested by the user.

## Out of scope

Sprite art; campaign-layer changes; new orders; pinned-against-a-wall
penalties; AI behaviour changes beyond not restarting reforms.
