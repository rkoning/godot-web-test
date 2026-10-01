# Nation AI (WS-D): enemy nations that play — design

Status: DRAFT for review, 2026-10-01. Workstream WS-D in
`docs/superpowers/plans/2026-09-21-logistics-roguelike-workstreams.md`;
detailed rules in `game-design-doc.md` §9 and Appendix C. Runs in parallel
with the battle-feel pass (`2026-10-01-battle-feel-pass-2-design.md`); the
two touch disjoint files (see "Ownership").

## Goal

In the open campaign the Warlord does nothing unless a scenario scripts it.
After this work an AI nation reads the map and plays through the same
`Orders` the player uses: it feeds its armies, splits to forage, masses to
fight, raids the player's supply edges, holds and takes ground, and walks
into battles — and it shows its intent on the map before it acts, so the
player can say "he's mustering for the ford" two turns early.

## Scope

In: Appendix C milestones 1–4 (world-state inputs, strategic goals, the
operational planner, the tactical tree incl. the raider variant), the public
intent records and their tells, the threat-map overlay, an AI debug view,
and the headless harness with a speed test.

Out (later workstreams): the crisis brain and weight hill-climbing (WS-K);
EscortRoute / NewRoute (need WS-B trade — their scores are 0 until
`world.routes` exists); SeekPeace and Shop beyond 0-scoring stubs (WS-E);
player automation verbs "Forage here / Mass at" (WS-L); battle AI (exists).

## Design

### 1. World-state inputs (`game/scripts/sim/ai/world_inputs.gd`)

Computed once per turn, shared by every AI nation, cached on the turn:

- **`proj(stack, path, n) -> float`** — the stack's supply level `n` turns
  ahead walking `path`, using WS-A's `SupplyRules` (upkeep, local feed,
  depot feed with hop loss, foraging) and `Movement`'s points. Pure,
  deterministic, cached per (stack id, path) per turn. The most important
  function in the AI.
- **`threat[nation][site][k]`** for k = 1, 2, 3: total hostile effective
  strength (`Stack.strength()`) that can reach the site within k turns under
  the movement rules. `exposure[site]` = threat at k=2 minus friendly
  strength there.
- **`edge_value[nation][edge]`** — supply delivered over the edge this turn
  (from WS-A's supply reports; caravan value joins when WS-B lands).
- **`region_value[nation][region]`** — `Yields` of its sites × posture
  multiplier + a constant for a market town.

### 2. Strategic layer (`strategic.gd`, `goal.gd`)

Utility scores per Appendix C for **FeedArmies, HoldDepot, HoldRegion,
TakeRegion, RaidEdge, Garrison, BuildDepot** (Escort/NewRoute/SeekPeace/Shop
present and scoring 0). Scores are normalised to [0, 1] per goal type, then
weighted by the nation's personality vector `W = {defend, expand, raid,
trade, logistics, hold, diplomacy, shop, caution}`. At most `max_goals` (4)
goals per turn; hysteresis +0.15 for last turn's goals, −0.3 for 3 turns on
an abandoned one. Starting vectors (Warlord, Empire, Trading empire, Hill
folk) from Appendix C live in `GameConfig.ai`; the map data names which
vector each AI nation uses (`"ai": "warlord"` on the nation).

### 3. Operational layer (`planner.gd`, `task.gd`)

- **Supply-aware Dijkstra:** edge cost = movement cost + λ × the drop in
  `proj` from taking the edge (λ = 2, raised by caution). Armies prefer
  roads, hug depots and route round raiders without special cases.
- **Mass and disperse:** a goal needing N regiments at site S by turn T
  picks the armies that can arrive in time with the best `proj` at S; if no
  single army suffices it schedules a **Mass** at a staging site within 2
  hops of a depot near S. Until T−1 those armies **Forage** as detachments
  sized to nearby farms (≤ 3 regiments a farm) within a turn of the staging
  site; they merge the turn before T.
- **Tasks:** Move, Forage, Garrison, Raid, Mass, Withdraw, Build, Detach —
  each executed only through `Orders` (move / detach / hold / build_depot),
  so the AI obeys exactly the player's rules.
- **Replanning** every turn from scratch; an army keeps its task if the new
  plan agrees.

### 4. Tactical layer (`tactical.gd`)

Per army, first match wins (Appendix C): starving → withdraw to a depot with
stock (leaving a screen if an enemy is adjacent); outmatched → withdraw one
hop, else hold; opportunity (an adjacent enemy it clearly outmatches) →
move onto it, which WS-C turns into a battle (auto-resolved between AI
nations, played by the human if the player is involved); a raider on my
edge → contest it; else the task; else forage or garrison. Raiders (≤ 3
regiments) use the variant: never attack, flee earlier, re-target the
highest-value unthreatened enemy edge each turn.

### 5. Turn pipeline and ownership

- `AiPhase.run` (WS-D owns it) computes inputs, then for each non-player,
  non-scripted nation runs strategic → planner → tactical. Nations with
  `weights["scripted"]` stay with WS-A's `ScriptedEnemy` (the March and
  Siege are unchanged).
- New fields (the only shared-class edits): `Nation.intents:
  Array[Dictionary]` and `Nation.goals_last_turn`, `Stack.task:
  Dictionary`, `GameConfig.ai`. Map data: an `"ai"` key on the Warlord.
- WS-D owns `game/scripts/sim/ai/`, `phases/ai_phase.gd`,
  `ui/layers/ai_layer.gd`, `tests/test_ai.gd`, `tests/test_ai_perf.gd`. It
  appends one line each to `CampaignRoot.LAYERS` and `_tables()`. It does
  **not** touch `battle_sim.gd`, `block.gd`, `battle_view.gd` or
  `battle_ai.gd` (the battle-feel pass owns those).

### 6. Legibility (`ui/layers/ai_layer.gd`)

- **Intents:** every chosen goal writes `{goal, target, turn_chosen,
  expected_turn}` to `Nation.intents`. The map shows them as tells after a
  delay of `ai.tell_delay` (1) turn: a muster marker on a Mass site, an
  "eyes on" icon on a raid target edge, a banner on a region it means to
  take. Hover explains it ("Warlord: TakeRegion(River East), expected turn
  9").
- **Threat overlay** (a player feature): a HUD toggle shades every site by
  threat at k=2 against the player — "where can they be in two turns".
- **Debug view** (a HUD toggle, off by default): each AI goal with its
  score, each AI army's active tactical rule and task, planned paths and
  Mass points.

### 7. Headless harness (`headless_sim.gd`)

`HeadlessSim.simulate(map_data, turns, seed) -> Dictionary` runs whole
campaigns with no scene: every nation AI-driven (the player nation too,
with a chosen vector), battles via `AutoResolve`. Returns per nation:
regions held per era, battles fought and won, average army supply, and a
`beats` dictionary (empty for now; WS-K adds predicates). Speed target: on
the prototype map (2 nations) 1000 turns in under 5 s headless — the
Appendix C "8 nations × 100 turns" target waits for WS-J's map, and the
perf test says so.

### 8. Config (`GameConfig.ai`, all in the tuning panel)

`max_goals` 4, `hysteresis_keep` 0.15, `hysteresis_drop` 0.3,
`hysteresis_turns` 3, `lambda` 2.0, `take_supply_floor` 45 (+20 × caution),
`starving_below` 25, `outmatched_ratio` 1.2 (+0.4 × caution),
`opportunity_ratio` 0.7, `tell_delay` 1, `proj_turns` 3, and the four weight
vectors.

## Tests (`tests/test_ai.gd`, `tests/test_ai_perf.gd`)

Rules and relative claims only — no test pins how a campaign or battle ends
or exactly when (see memory: no outcome-baseline tests).

- **Inputs:** `proj` matches a hand-worked WS-A example (the 12-stack on an
  enemy farm three road hops out) turn by turn; threat at k=1 counts a stack
  one move away and not one three moves away; a raider on a road raises that
  edge's value loss for the cut side.
- **Strategic:** a starving army makes FeedArmies outrank everything; a
  threatened depot outranks a distant TakeRegion for the Empire vector and
  not for the Warlord vector; hysteresis keeps last turn's goal against a
  marginally better one.
- **Planner:** a 14-regiment army sent to take a region 4 hops out disperses
  to forage en route and merges the turn before arrival, arriving above the
  supply warning level, and does better on supply than the same army marched
  as one stack; the supply-aware path takes the road over a shorter trail
  when the trail costs more supply.
- **Tactical:** a starving army withdraws toward a depot with stock; an
  outmatched army steps back; a clearly stronger adjacent army moves onto the
  enemy (a pending battle appears); an AI raider reaches the player's
  highest-value supply edge within 3 turns of it becoming exposed and leaves
  when a ≥ 4-regiment army approaches.
- **Legibility:** an intent for a TakeRegion appears at least 2 turns before
  the AI's stack arrives; the tell is drawn only after `tell_delay`.
- **Integration:** a 40-turn open-campaign run with the Warlord AI-driven
  ends with no stack stranded at 0 supply for 5+ turns and every order issued
  through `Orders`; the March and Siege scenarios behave as before (their
  scripted enemies are untouched).
- **Perf:** the 1000-turn headless run finishes under 5 s.

## Open questions for review

1. Personality for the open campaign's Warlord: the Appendix C "Warlord"
   vector (expand 1.6, raid 1.2, defend 0.6) — or start calmer while the
   campaign has so few systems?
2. Should the player's own nation get an "AI general" toggle (the same AI
   driving the player's armies) for testing and watching? It costs little
   since the harness already does it.
3. The threat overlay: always available as a toggle (proposed), or on only
   while a stack is selected?
