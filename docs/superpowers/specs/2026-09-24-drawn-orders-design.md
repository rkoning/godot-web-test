# Drawn orders: routes and formation lines in battle — design

Status: approved in brainstorming 2026-09-24. Scope: the real-time battle
(`game/scripts/sim/battle_sim.gd`, `block.gd`, the input and drawing in
`game/scripts/ui/battle_view.gd`) and its tests. The campaign layer and the
battle AI are unchanged.

## Goal

Replace Total War-style click orders with drawing. In battle the player's real
decision is the route — round the forest, over the ford, onto a flank — so it
should be one gesture. Drag from a unit to draw where it goes; drag across the
ground to set where the selected units form a line. Time slows while you draw.

## Prerequisite

The three open fixes from the battle-contact final review land first, because
group routes make friendly blocks queue and pass constantly:

1. A routing block can be put into a reform and stands still for up to 2 s —
   guard the reform start with `not b.routing` and cancel a reform whose own
   block can no longer lock.
2. A block deep inside an enemy can never move out (turns are not
   collision-checked) — enemy blocking gets the friends' "an already-deep pair
   may move apart" rule.
3. Friends meeting head-on on one axis deadlock forever — `_try_step` gets a
   perpendicular sidestep candidate.

(Details: `.superpowers/sdd/progress.md`, battle-contact ledger, final review.)

## Design

### 1. Orders in the sim

- **Routes.** `Block` gains `route: PackedVector2Array` (points still to walk)
  and `end_facing: float` (NAN = none). `BattleSim.order_route(b, points,
  end_facing := NAN, target: Block = null)` replaces a plain Move for drawn
  orders (`order_move(b, p)` stays and is a one-point route).
  - The block walks the points in order at normal speed, with turn rates and
    pivots as today; a point counts as reached within 2 units.
  - At the end it turns to `end_facing` if set, then holds.
  - If `target` is set, on arrival (or on touching the target earlier) the
    order becomes Attack on it. A curving route builds no charge run-up until
    its last straight, because turning resets `charge_run`.
  - Lock rules are unchanged: a locked block that is not winning ignores a new
    route exactly as it ignores Move; a winning block's route walks it out.
- **Cleaning a stroke.** `BattleSim.clean_route(b, points) ->
  PackedVector2Array` resamples every `route_sample` (12) units, dropping
  samples on ground impassable for `b`'s role or outside the field. A leg from
  the last kept point to the next sample is kept as a straight line when it is
  walkable — every terrain cell it touches is open for `b`'s role, found by
  exact cell traversal, not a straddle check. An unwalkable leg is replaced by
  an A* path on a per-role grid cached on the sim (`AStarGrid2D` over the
  terrain cells), so a crossing goes over the bridge and a route may start or
  end on the deck; a sample with no path on that grid is dropped. The result
  is smoothed to drop sharp reversals next to a detour (the grid path
  doubling back, or overshooting a turn), and a final sample closer than
  `route_sample / 2` to the stroke's end point is merged into it rather than
  left as a stub leg.
- **Group routes.** `BattleSim.order_group_route(blocks, lead, points,
  end_facing := NAN, target = null)`: every block follows the lead's cleaned
  route offset by where it stood relative to the lead, expressed in the
  route's local frame (along/across the route direction at each point) so the
  shape rotates as the route turns; on open ground the shape is kept the whole
  way. An offset point that is blocked or off the field, or whose leg from the
  follower's last point is not walkable, falls back to the lead's own point
  there (round on the terrain grid if even that leg is not); every leg of every
  route is walkable. Marching friends pass through each other (see "Soft
  marching" below), so a line squeezes into a column through a gap and fans out
  after without jamming. A follower that cannot end on its own offset ends its
  frontage + 6 further back along the lead's route than the one before, so no
  two end on one point; a follower left with no route at all holds. A route
  ending on an enemy gives every block of the group Attack on it at the end.
- **Soft marching (user decision 2026-09-24).** A block that is marching —
  order Move (any route, `order_move` included), not locked, not routing —
  passes through friendly blocks, at `march_overlap_speed` (0.6) × its speed
  while it is deep in one. Every other block (standing, holding, bracing,
  fighting, attacking, withdrawing) stays solid to friends exactly as before,
  and a marching block never moves a friend. It never stacks onto a fight: it
  does not step deeper into a friend that is touching an enemy, nor to where
  it would be deep in a friend and touching an enemy. It waits behind (it
  has no sidestep round a friend; it goes round only if its route does). Two
  blocks on a Move that reach the enemy stacked in each other are split by
  id: the lower id takes the fight, and the other lets go of any lock and
  backs straight out. Friends touching create no locks
  and no damage (contacts are hostile only). The bridge rule is unchanged: a
  bridge cell holds one block, so marching blocks queue over the bridge one by
  one. A marching block that has slid off its cleaned line (a point counts as
  reached 2 units short) with blocked ground straight ahead cleans the rest of
  its route again from where it stands (at most every half second, keeping
  its destination); one set down off the field may walk
  back onto it. This replaces the earlier column-slot and formation-wait
  schemes, which jammed at field edges and never released a wait on a block
  held in a fight.
- **Formation lines.** `BattleSim.order_formation(blocks, stroke)`: slots
  follow the opening deployment's shape — infantry evenly along the stroke,
  archers a rank `formation_rank_gap` (32) behind it, cavalry on the wings past
  the stroke's ends; with no infantry, archers take the line. Within each role,
  slots are assigned in the blocks' current order along the line so paths do
  not cross. Every block faces perpendicular to the stroke, toward the enemy
  side (away from `home_dir[side]`; a stroke drawn straight toward home faces
  the enemy's blocks). A rank holds as many blocks as fit a frontage + 6 apart;
  the rest spill into further ranks behind, the blocks standing furthest
  forward taking the front rank, each rank in the blocks' order along the line.
  A slot that would fall on a bridge deck moves back off it (a block holding
  there would close the crossing). Each block gets
  `order_route(b, clean_route(b, [slot]), facing)`; marching blocks pass
  through each other, so crossing paths never jam.

### 2. Gestures and feedback (BattleView)

- **Drag from one of your blocks** draws a route. If it was not selected it
  becomes the selection; if it was, the whole selection follows as a group.
  Before a defender's Begin, dragging a block still repositions it; drawing
  starts once the clock runs.
- **Drag on empty ground:** with blocks selected, it draws their formation
  line; with nothing selected, it box-selects (as today).
- **Taps unchanged:** tap/click an enemy attacks it head-on; right-click ground
  moves (mouse); tap ground with a selection moves (touch). Deselect: tap empty
  ground (mouse) or tap any selected block again (touch), which clears the
  whole selection.
- **Buttons:** the armed Move and Attack buttons are removed; Hold, Withdraw,
  Select all and Retreat all stay.
- **Slow motion:** while a stroke is in progress the battle runs at
  `draw_time_scale` (0.25); release restores speed. The status line shows
  "DRAWING — slowed".
- **While drawing:** the stroke is drawn live as it will be walked (the cleaned
  route, bending round blocked ground and through the bridge); an enemy under
  the tip gets red brackets (attack at the end); a formation stroke shows ghost
  outlines of every slot and facing. A stroke shorter than 20 px acts as a
  tap; a route released back on its start block is ignored.
- **Off-centre presses:** a drag rarely starts on the block's centre. The view
  drops the stroke's first points that are still on the lead's body or hit pad
  (10 px mouse, 24 px touch, divided by the zoom). The sim then drops leading samples inside the lead or within `route_sample` of its
  centre are dropped, and a group's shape is set in the stroke's own heading
  (its first cleaned point to the first point a frontage on), never the lead
  → press-point direction.
- **After release:** each of your blocks shows its remaining route as the
  dashed line it will walk (not a straight line to the end); a route ending in
  an attack ends in the red arrow. Tags read MOVING / ATTACKING as now.

### 3. Config

`GameConfig.combat`: `route_sample` 12.0, `route_reach` 2.0,
`formation_rank_gap` 32.0, `draw_time_scale` 0.25, `march_overlap_speed` 0.6.
All in the tuning panel.

### 4. Tests

- **`game/tests/test_routes.gd` (new):** a route is walked point by point and
  ends at `end_facing`; a route ending on an enemy becomes Attack on arrival;
  cleaning drops blocked samples and routes a river-crossing stroke through the
  bridge; a group route keeps its shape on open ground and squeezes into a
  column through a gap; a formation line puts infantry on the line, archers
  behind, cavalry on the wings, all facing the enemy side, with no crossing
  paths; a locked, losing block ignores a new route.
- **`game/tests/test_battle_shell.gd`:** driving real mouse events — a drag
  from a block yields a route order; a ground drag with a selection yields
  formation orders and without one still box-selects; the sim runs at 0.25×
  during a stroke and at normal speed after; the Move and Attack buttons are
  gone.
- **Existing claims** (combat checks, East Hill acceptance) must still pass;
  the battle AI does not use routes, so they should not move.

## Out of scope

The battle AI drawing routes; campaign-map changes; editing a route after it
is drawn (draw a new one); waypoint markers or queued orders.
