# Working Title: Logistics Roguelike — Game Design Document

*v1.0 — Sep 21, 2026. Consolidates the design one-pager (v0.6) and the three prototype specs. Appendices A–C are the handoff specs verbatim.*

## Contents
1. Overview
2. The Map
3. Economy & Logistics
4. Armies & Combat
5. The Empire
6. Characters
7. Crises
8. The World & Nations
9. AI Architecture
10. Open Questions
Appendix A — Combat Prototype Spec
Appendix B — Logistics & Trade Prototype Spec
Appendix C — Nation AI Spec

## 1. Overview

### Pitch
A Total War–scale strategy game compressed into a 45–180 minute roguelike run. The player rules one nation on a hand-authored map through three eras, each ending in a crisis. Settlement management is replaced by **region posture**; battles are **stripped-down block battles** on a crop of the campaign map, resolved in 60–90 seconds. The core thesis: **the army is not the player's only weapon — the world is.** Terrain, supply, and time force generals' hands; the player wins by reading the clocks and choosing when, and where, to stop retreating.

### Pillars
1. **Decision density stays flat.** The unit of decision scales with the player's power. Trivial fights auto-resolve; real fights are always played. Regions merge into provinces and frontiers as the empire grows, so per-turn decision count holds steady while stakes rise.
2. **Every fight is chosen.** No auto-resolve on non-trivial battles. Retreating and giving ground are legitimate, low-casualty moves that cost position and supply, not regiments.
3. **The world has a history, not a seed.** One fixed map, simulated nations, tuned tendencies. Replayability comes from seat, timing, and crisis draw — not procedural terrain.
4. **Crises escalate from transformative to binary.** Eras 1–2 reshape the nation; era 3 ends it or crowns it.

### Run structure
- **Length:** 45–180 minutes; ~90 is the default, map size and difficulty stretch or compress it.
- **Three eras**, each ~25–30 minutes, each ending in a crisis. Eras 1–2 are transformative; era 3 is binary.
- **Two verbs** the whole game teaches: *outlast* (let the world's clocks run) and *hunt* (act before a threat compounds). Each crisis tells the player which it demands.
- **Flat decision density.** As the empire grows, regions consolidate into provinces and frontiers, trivial fights auto-resolve, and one-click planner verbs (Forage here, Escort, Mass at) replace micro. The per-turn decision count stays roughly constant while stakes rise.

## 2. The Map

### One authored map, two zooms
There is **one fixed, hand-authored map** shared by every run, and **one terrain dataset** rendered at two zoom levels. Nothing is authored twice.
- **Strategic zoom** shows the whole map: regions, sites, roads, rivers with bridges, and terrain *features* (hills, forests, swamps, bridges, cliffs, passes) as icons and patches. Hovering any point shows the terrain type, its battle modifiers, and — with an army selected — turns to reach it and the supply cost. Armies are points on features, not owners of regions.
- **Battle zoom** is a crop of the same data around an engagement. Whoever was standing on the hill is on the hill; the bridge is one block wide; the forest hides blocks. There is no separate battle map and no deployment phase — your position *is* your deployment.
- **Readability rule:** everything that affects a battle is visible at strategic zoom. If the player must zoom in to know the ford is there, the map has lied.
- **Scale rule:** a region is ~10 army-widths across so it holds several features worth choosing between. Campaign movement is turn-based ("commit a path, it resolves over turns"); battles trigger when paths bring hostile stacks within engagement range at end of turn.

### Regions and sites
Regions are containers for **ownership, posture, and 3–6 sites**. Sites are where every resource actually lives: farms hold Supply, villages hold levies, mines and market towns hold Coin, depots hold stock, nodes hold access tags. Roads and rivers are edges between *sites*, crossing region borders freely. An army is always on a site or a feature. (Site yields, foraging capacities, and pillage effects are in Appendix B.)

### Culture (map layer)
Every region has a dominant culture and a minority share. A nation has a *home* culture. Conquering a foreign-culture region gives the land, not the people: reduced posture yields, unrest, no levies, a court that reads it as a liability. Taking a region of your own culture is nearly free — the reclamation fantasy the ailing empire runs on. Culture changes only through occupation measured in **eras**, settlement (a horde planting itself), or Social posture backed by a tradition. It is the slow ceiling on how big an empire can usefully be, and the mechanism behind Overextension. Home culture also gates what a nation knows how to use (the hill folk can't field iron regiments even with access; the steppe can't garrison).

### Religion (map layer)
Same shape — dominant faith and minority share per region — but it **moves**: along trade edges and through Social posture, like rebellion through villages. Mismatch with the ruler's faith is unrest and lost Influence; match is the opposite. Raiders can't cut it and armies can't hold it; it's fought with posture. Marriages carry faith into the court. Trade routes carry faith as well as Coin — the trading empire is a missionary by accident.
- **State faiths (3–4):** each is the ruler's faith of one or more nations with a home region. Shared faith is a diplomatic fact: cheaper peace, marriages that don't rock the court, a coalition trigger when a co-religionist is invaded — and a rivalry axis over who is its true protector (the claimant crisis with a religious face).
- **Stateless faiths (2–3):** held by no nation, only by regions — an old faith the state faiths displaced (strong in the hills and the empire's poor provinces) and a new one spreading along trade. They can only rebel or convert a ruler. A stateless majority in a neglected corridor is the rebellion's recruitment pool; crossing a threshold in your core is the Crisis of faith.
- Faith roster slots: `STATE_1..4`, `OLD_FAITH`, `NEW_FAITH` — names TBD.

## 3. Economy & Logistics

### Resources
Three currencies, one per posture. No tech tree; regiment quality comes from rulers, relics, veterancy, and node access.
- **Coin** (Economic) — recruits and maintains regiments, pays mercenaries, builds depots and roads. Empire-wide.
- **Supply** (Military posture + geography) — feeds armies. Local: lives in regions and depots and must physically move.
- **Influence** (Social) — diplomacy and the shop (see below).

Manpower is folded into recruitment gated by a region's population: Social regions levy more, burned ones levy nothing.

### Resource nodes
Nodes are **access tags on regions, not currencies** — you either control or trade for them. Horses (cavalry; plains quality), Iron (heavy regiments; quality), Grain (region Supply and depot cap doubled), Salt / spice / dye (trade goods; Coin scaled by the receiver's scarcity), Timber (river throughput or ships). Nodes are part of the authored map: the steppe has horses and nothing else; the empire has grain and iron but no horses. **Wanting drives crises and beats** — Hildegard raids south because he has horses and no iron. Nodes give every crisis a concrete objective (the rebellion marches for the grain belt; the claimant wants the iron province).

### Region posture
Each region (later: province, frontier) is set to **Military**, **Economic**, or **Social**. Posture is a *bet with exposure*, not a dial:
- Military: levies and supply for armies; drains food from neighbors; raises unrest under neglect.
- Economic: coin and trade throughput; high-value raid target.
- Social: unrest → growth; slow to mobilize; starves rebel recruitment.
Posture should want to change turn to turn as enemy proximity, supply, and unrest shift.

### Supply
Supply is a **network**, not a number.
- Regions produce Supply and hold a small stock. **Depots** (few, Coin-built, capped) hold large stock and are the network's nodes.
- Supply flows along roads and rivers between adjacent friendly regions with a per-turn throughput cap: roads = base, rivers = ×2–3, mountains / winter = halved.
- Each army has a **supply level** (0–100%). It draws upkeep from its region; shortfall comes from the nearest depot along the network minus a loss per **hop**; if neither covers it, the level drops. Level scales effective strength — gently above 50%, steeply below.
- Distance is felt in hops, not tiles. Giving ground means retreating *up* your network while the enemy advances *down* theirs — or off it entirely.
- **Foraging:** hordes and rebels draw Supply directly from the region they occupy and destroy its stock — mechanically why they must keep moving, grow through rich land, and starve in poor land.
- **Enemy supply is visible on their stack**, computed the same way: level, drop rate, and hops to their nearest depot.

**Chosen model: hops + depot stock.** Of the four candidate models (hops, flow network, convoys, radius), supply uses hops so every army reads as one number, plus a **stock** on each depot that drains by the upkeep of armies leaning on it and refills from farms within reach. A siege or famine is a depot running dry — visible as a fill bar, no solver. **Sites set the foraging ceiling:** a farm feeds ~3 regiments a turn, so a large stack on one farm starves and must disperse to eat.

**Upkeep scales superlinearly with stack size** (×1.5 above 8 regiments, ×2 above 12). This is the anti-doomstack rule: a 16-stack sitting still bleeds supply and its depot; the same regiments split across four farms hold steady. The doomstack is not forbidden — it still *wins the battle* when it forms — it is simply the wrong shape for most turns, and forming it is a deliberate act for ground the player has chosen. Worked numbers are in Appendix B.

### Trade
Trade routes are **a second, discrete graph on the same physical map**. A route links one of your regions to a node (yours or another nation's) along a road, river, or sea lane. It pays Coin per turn, grants the node's access tag to both ends, and can carry a little Supply. Routes exist internally and externally. Because routes are physical they can be raided, blockaded, or cut by a hostile posture flip on a region along them. Embargo is a standard Influence action. Trade-focused nations' uniques live here: more routes, exclusive sea lanes, Supply-carrying routes, Influence from trade, cheap embargoes.

**Chosen model: convoys.** Trade routes auto-dispatch **caravans** — physical tokens that travel the roads and rivers at edge speed, pay Coin and grant node access on arrival. Caravans are what raiders hit and escorts protect; the trading empire's map is alive with them, and a hill-folk raid is literally watching a caravan die. Dispatch is automated (a route sends every N turns until cancelled) so the player only ever touches escorts, interceptions, and route choice. Supply and trade share the roads but read differently: supply as a number that ticks, trade as a token that moves.

### Army roles, detachments, and raiding
Supply and trade edges are **cut by presence**: a stack sitting unopposed on a region severs the edges through it — no battle needed. Cutting is one turn; repair is free the moment the raider leaves. The pressure is presence, not damage.
- **Line armies** — big, slow, hungry. Take and hold.
- **Raiders** — small, fast, cheap. Can't win a real fight; don't need to. Cut a trade edge and the route stops paying and access drops; cut a supply edge and everything downstream counts one more hop.
- **Garrisons** — static, cheap, no supply draw. Make an edge safe.

Counterplay: escorts stationed on a route, redundant roads and rivers (what Coin is for), and foraging attrition on poor regions. AI nations raid too — a neighbor's raider on your edges is legible pressure short of war, and raiders on your supply edges are a natural early tell for a rebellion.

**Detachments are a first-class verb.** "Detach 3 regiments to that farm" is one click; merging is automatic when friendly stacks meet. A detachment without its own character leads at a penalty, which gives the family roster a job. **Occupation needs presence:** a region is held by garrisons on its villages and market town, not by a stack passing through — leave the villages empty and its levies keep going to the enemy and the rebellion has a place to grow. Holding a region *is* splitting. The strategic loop is disperse to eat, concentrate to fight, and read the enemy's clock to know which.

### Clocks
Every side has visible pressures that eventually force a fight: campaign seasons, supply rot, mercenary desertion, legitimacy bleed, provinces burning. Clocks differ by actor — a horde starves faster than a garrison; a besieger bleeds coin; a pretender's claim loses credibility every season uncrowned. The player's job is to make the enemy's clock run out first.

## 4. Armies & Combat

### Regiments and blocks
Armies are stacks of regiments. In battle each regiment is a **block**: a rectangle with a role glyph (infantry, cavalry, archers for now), a health fill, a morale fill, and a facing notch. No individual models, no formations, no fatigue.

### Which fights are played
No auto-resolve on any non-trivial fight — every battle the player sees is one that matters. **Threshold auto-resolve** covers the trivial ones: when effective strength (after supply and quality) exceeds the enemy's by a visible ratio, the fight resolves in the player's favor at a cost in attrition, supply, and a turn. The ratio is shown so progression is felt ("this used to be a battle, now it's a march"), and it can rarely fail via hidden supply, terrain, or trait factors — a "should have been free" loss is itself a tell.

### Positioning is the tactical decision
Before any battle, the campaign layer has already decided the ground. Camping on the hill costs a turn and a little supply; the forest hides your composition; the ford halves whoever crosses it. The battle is executing on that choice and punishing whoever misjudged it.

### The battle
Real-time, one small field, 60–90 seconds at roughly twice Total War's pace, 4–8 blocks a side. Four orders only: **Move, Attack, Hold, Withdraw**, plus Retreat-all. The rules that matter:
- **Facing.** Damage and morale drain scale with the angle of attack: front ×1, flank ×1.5, rear ×2. A block engaged front and flank is *flanked* and its morale collapses — position beats numbers.
- **Charges.** Cavalry that has moved before contact deals a burst; braced infantry (Hold for a second) stops a frontal charge cold and counter-bursts. Charging braced infantry from the flank ignores the brace.
- **Routing.** Morale at zero means the block flees, uncontrollable, taking double damage. **Cavalry that catches a routing block deletes it.** Pursuit is real, and so is a covered withdrawal.
- **Withdraw is not rout.** An ordered pull-back keeps morale and responsiveness, but a withdrawing block hit from the rear suffers like anyone else — so covered withdrawals (a holding block screening the rest) are the skill, and uncovered ones become routs. This is the cheap retreat the campaign layer promises.
- **Terrain** applies per block: uphill defenders hit harder and take less; forests hide and slow cavalry; swamps bar it; bridges are one block wide and engaged only front and back.

Full stats, rules, AI behaviors, and scenarios are in Appendix A. Alternative battle models considered (commit sliders, press/hold/withdraw rounds, objective clocks, hex grids, phase cards, order queues) were rejected in favor of this because pre-positioning already moves the interesting decision onto the campaign map.

## 5. The Empire

### Eras and rulers
Three eras, ~25–30 min each, crisis occupying the last third. The ruler who emerges from each crisis carries its consequences as traits (the general who broke the siege vs. the diplomat who negotiated). **Ruler traits are the run's relics; postures are the deck.** Era boundaries are a clean place to reshuffle postures and consolidate map grain.

### Influence (borrowed from Endless Legend)
One currency for diplomacy and empire-level upgrades. Its income doubles as the read on legitimacy.

- **Generation:** primarily Social posture. Income falls when you lose the capital, burn provinces, or have a contested heir; a pretender on your soil drains stockpile each season. "The claim has a shelf life" is his Influence clock vs. yours, both visible.
- **Sink 1 — Diplomacy (everyday):** peace, tribute, border closure, coalition pressure, marriage. Priced by target strength and disposition. **Actions cost far more against an actor whose crisis has fired** — early diplomatic spending is prevention and should be able to nudge a world beat's fire rate down.
- **Sink 2 — The shop:** available any turn; stock refreshes at era edges and when a crisis fires. Semi-random, tiered:
  - *Staples* (cheap, always stocked): consolidate a region, flip a frontier's posture in one turn, buy a season of peace, restock a depot, retire a ruler trait. The remove-a-card / heal of the run.
  - *Mid* (rotating): a specific action against a specific nation, a mercenary regiment, temporary supply-decay immunity, an early tell on the coming crisis.
  - *Rare* (expensive, rarely stocked): a new posture option, a permanent clock edit, a vassal offer.
  - *Uniques:* nation- and ruler-specific entries with higher roll weight in that nation's pool — eligible, not guaranteed.
- **Era relic pick (separate from the shop):** free, one choice at each era edge, offered set shaped by the crisis resolution and the ruler it produced. Answers *what did this era make of you*; the shop answers *what will you pay for*. The resolution never touches shop stock.
- **Use-it-or-lose-it:** the new ruler inherits only a fraction (~⅓) of unspent Influence, so the last turns of an era are a real spend-or-hold decision.
- **AI parity:** AI nations earn, spend on demands against the player, and shop. A neighbor who bought mercenaries or a border closure is a visible tell.
- **Other draft points (candidates):** crisis onset (choose which advisor leads the response) and mid-crisis (a few ways to force the opening, paid in real costs rather than Influence).

### Traditions (accreted in-run)
The era relic picks *are* traditions: each has sides (the granary network makes famine survivable and Military posture worse; a martial tradition raises levy quality and makes a League court fractious). Two or three by era three is the run's build, visible in one row. Traditions can conflict (mercantile + martial → schism tell), and carry across the unlock tree (a nation unlocked by vassalizing it starts *Subjugated*). Assimilation, Tolerance, and Syncretism are the traditions that let a culture convert a region or live with not doing so.

### Government (how the sub-regions hold power)
Provinces are constituencies with a power base (governor, garrison, wealth). The government type says how much that base counts against the throne — and **succession falls out of it**:
- **Centralized** — provinces are administrative; the ruler appoints and designates. Strong and brittle: no check on a bad ruler, no voice for a distant province, so clash and secession fester silently. *The empire.*
- **Provincial** — provinces are estates; governors semi-hereditary and holding levies. Succession is a count of provinces backing each claimant; every conquest is a new voter. *Client-state seats live here.*
- **League** — cities are the constituencies; elective among city governors; trade routes are the political network. *The trading empire.*
- **Warband** — the army is the constituency; generals are power bases; succession goes to whoever the regiments follow, readable by who holds the veterans. *The warlord; the hill folk before they settle.*

Each type has a soft cap on constituencies before it destabilizes (Centralized ~6 provinces, Provincial ~10, League any number of cities, Warband by veteran share) — exceeding it is the Revolution trigger. Government can change through a tradition pick or a crisis resolution and it is always a big deal: hill folk settling is Warband → Provincial; the ailing empire's golden age likely requires Centralized → Provincial to keep its clients. Assignments carry political weight (the heir governing the richest province stacks the count), marriage into a power base buys a vote, Influence spent on the court buys more, and map-grain consolidation is a political act — merging two provinces removes a constituency. Succession crises split the constituencies: under Provincial, a civil war with a map; under Warband, two generals with two stacks.

### Client states
A nation with a suzerain: pays tribute (Coin or Supply routed up the empire's network), can't declare war without permission, part of its Influence is the empire's to spend; in exchange the empire's line armies are obligated to defend it — so a client can **drag the empire into wars**. Internally, a client has a **court of 2–3 factions** (loyalist, independence, the regional leader's own base) that leans each turn on what you do: prompt tribute feeds loyalists, a deal with Hildegard feeds independence, an unanswered raid feeds both against the emperor. The player manages whether the court lets them *not* secede. Verbs: use the empire's armies and Influence for your own wars while building the depots and routes to stand alone. Era-one crisis: the empire is weak and the court leans out — break away, renegotiate autonomy, or double down as the loyal province and inherit its problems. Governors who led a secession are unlockable seats. Open: fixed 2–3 clients on the map vs. any conquered nation becoming one.

## 6. Characters

A royal family plus a few adoptees — 5–12 people per run, ~30 traits total, each doing one legible thing, three visible at a glance.

- **Slots:** *Ruler* (one; traits are empire-wide modifiers). *General* (leads a stack; traits modify battle calls — a cautious general makes withdraw cheap, a rash one makes press strong and hold weak — plus supply draw and raiding). *Governor* (sits on a province or client state; traits modify posture yields and court leanings). *Idle court* — still matters: they're the claimants in a succession.
- **Age bands tick with eras:** young → prime → elderly → dead, one step per era edge. A ruler crowned in prime rules one era well, one declining, and is gone by the finale. **Elderly** keeps every trait but adds a decline modifier: Influence income drops, the court leans toward heirs, some traits invert (Bold → Stubborn). Keeping an elderly ruler is a real option — continuity of relics vs. a court already picking sides.
- **Government sets the succession rule** (see Peoples and power): the rule decides whether era-edge succession is a choice or a result; a prime-age ruler can stay if the government allows, so change is forced at most every two eras.
- **Trait acquisition — pick 3, seeded by behavior.** When a character earns a trait, the pool of three is built from what they did (won two fights and retreated once → Confident / Veteran / Cautious); the player picks one. Randomness is which three appear; agency is the pick. Pool weighting is visible ("next pool: 60% martial"), so assignment is deliberate fishing — put the heir on a Social province to seed Beloved, keep him off the wall so Cowardly never enters.
  - *Who picks:* ruler and heir at era edges and after any crisis they were in; generals and governors on triggers (won/lost a real battle, governed through a crisis, cut three edges); idle court auto-rolls or nothing.
  - *Bad traits are forced, not picked.* Sacking a city, fleeing a winnable fight, or idling a whole era attaches a negative trait with no choice. Pick-3 is the reward; the forced trait is the consequence — and the job of the shop's "retire a trait" staple.
- **Era edge is a two-pick moment:** nation relic first (the granary network), then the ruler's trait (Savior of the People).
- **Family as a resource with a clock:** marriages (Influence) bring foreign traits and node access; adoption promotes a general into the line at a legitimacy cost. Both have a two-era horizon — the longest-term decision in a 90-minute game. The family's shape at era edge is the succession draft: a deep bench is smooth, one brilliant heir is a bet, two rivals is the crisis firing.
- **Traits as tells:** Ambitious governor on a client state = secession tell; Beloved general who loses = schism seed. Court schism is just the trait graph crossing a threshold.

## 7. Crises

**Two verbs:** *outlast* (play the world, let clocks run) and *hunt* (act aggressively before a threat compounds). Each crisis tells the player which it demands.

### Crisis anatomy
Every crisis — nation-facing or world-scale — is **one object with the same shape**:

`trigger conditions → discrete announcement → authored intent + tells → clocks → resolution branches`

- **Simulated buildup, scripted payoff.** The *whether* is simulated: a crisis becomes eligible only when real conditions are met (the warlord's stack, treasury, and a weak southern border; the empire's legitimacy below a threshold; a plague roll). The *what* is authored: on firing, the crisis is a discrete event the world announces, and the actor's AI switches to a **crisis brain** with a stated intent — Hildegard drives south toward the client state and absorbs the tribes en route into his horde, rather than dithering over weak, poor targets.
- **Direction is fixed; outcome is not.** The crisis brain has a goal and a route but still obeys supply, terrain, and battles. He *will* go south — but if the player holds the river he sieges instead of marches, and the horde-of-tribes starves on schedule. The script points; the world decides.
- **Why:** legibility (a stated intent is something the player can read and counter), drama (consuming the tribes shows the crisis's scale), and guaranteed pressure (eligibility is tuned so something fires each era — the sim isn't relied on to produce tension by itself).
- Authoring a new crisis is filling in the five slots, which keeps rebellion, plague, and the warlord in one system.

### Tier 1 (transformative; era 1 starters)
| Crisis | Verb | What forces your hand | Legacy examples |
|---|---|---|---|
| Rebellion | Hunt | Rebel stack grows per village passed; wants an objective you can deny or move | Hardened or pacified peasantry; general- or reformer-ruler |
| Plague / Famine | Triage | No enemy; supply crisis. Abandon provinces deliberately | Granary network; consolidated core; "savior" religious ruler |
| Succession | Choose | Heirs are all bad; provinces declare. You start the civil war | Which traits the dynasty carries; which provinces resent you |
| Crisis of faith | Convert | A stateless faith crosses a majority threshold in your core; no army to hunt | Convert the ruler (court reacts by government, co-religionist nations react); Tolerance tradition; Suppress (Military corridor, unrest, martyr tell) |
| Claimant rival | Outmaneuver | Stronger in the field, but the claim has a shelf life. Deny the coronation objective, break the coalition | Repelled (martial ruler, rival seeds era 3); Negotiated (merged claim, rival-blooded heir); Usurped-but-survived (rule from the provinces, reclaim in era 2) |

### Tier 2 (need a large empire)
- **Migration / Horde** — outlast, then hunt. Starves fast, destroys what it touches, wants to *settle*.
- **Overextension** — cut. No external enemy; your own supply lines are the crisis. Release territory on purpose → vassals/federation.
- **Court schism** — purge or reconcile. Generals ignore orders; act on your own people before outsiders exploit it.
- **Divine reckoning** — convert, at scale. A stateless faith already spread across three nations fires as a world beat.
- **Revolution** — reconstitute. Trigger: the constituencies have outgrown the government type (a Centralized empire past its province cap; a Warband whose generals hold more veterans than the ruler; a League whose hinterlands have no vote). Intent: the excluded power bases organize under a named leader (an Ambitious governor or general) toward the capital or assembly. Resolutions: *Concede* (change government, keep the ruler; the relic pick is the new constitution), *Crush* (keep the type, lose the provinces or generals that backed it; martyr tell), *Replaced* (the leader becomes ruler, the family goes to court or exile — a different dynasty on the same map; the old heir is the era-three claimant). Tier 2 deliberately, so the new constitution has a full era to be tested.

### Tier 3 (binary finale)
Type is not chosen at run start — it **emerges from tier 1–2 resolutions and is revealed through tells.** Candidates: hegemon + overextension (the hegemon arrives when you're largest and least supplied); the repelled pretender returning with the hegemon behind them. Each transformative legacy is what *reveals* the finale.

## 8. The World & Nations

### The world
- **One hand-authored map**, ~40–60 regions, 6–8 starting nations, a few never-playable wild zones for hordes and migrations.
- **AI nations run the real simulation outside of crises** — same posture, supply, battle, and crisis-eligibility rules as the player. Between crises, no scripting: they expand, fight, catch plagues, and can die.
- **Tuned tendencies decide *if* a beat fires; the crisis object decides *what happens*.** Initial conditions (armies, postures, unrest, rivalries) are authored so the timeline usually rhymes: Hildegard becomes eligible to invade around turn 20; the client state's secession triggers when the empire's legitimacy dips. Beats fire on *conditions*, not dates. Player action or plain randomness (a plague kills the warlord on turn 10) can prevent, delay, or redirect them. Once fired, a beat has authored intent (see Crisis anatomy). Prevented beats mutate rather than vanish.
- **Target rates** (to verify by headless simulation): a signature beat should fire in roughly 50–80% of unaided runs. Higher is a script; lower isn't texture.
- **Nation crises are guaranteed structure; world beats are texture.** An unlucky world must still pressure the player.

### Nations and unlocks
- Nations are **different flavors of difficulty, not stat modifiers.** The ailing empire is hard because three world beats are aimed at it and its starting postures are wrong for all of them. The warlord is allowed to dominate his corner — the drama is the point.
- **Nation archetypes (so far):**
  - *The ailing empire* — ancient, splintering; three world beats aimed at it, postures wrong for all of them. Golden age is the hard-mode win.
  - *The warlord* — expansionist, feared by distrustful neighbors; allowed to dominate his corner.
  - *The hill-folk tribes* — no depots, forage and raid; must stay mobile against the belly of the empire, cutting its edges, until they can hold ground and become a nation.
  - *The trading empire* — broad, dispersed network of rich cities; strong in routes and Influence, weak to blockade and to a raider parked on its corridor.
- **Unlocks are keyed to world state**, not just victory: "end a run with the delta nation as your vassal" unlocks the delta nation, with starting attributes reflecting what you did to them. Some nations unlock only after you've faced their beat from the other side (beat Hildegard as the empire → play Hildegard).

## 9. AI Architecture

AI nations must use every system above **competently and legibly**, and the same machinery must drive the player's automation verbs and the headless simulation that tunes the world.

- **Three layers per nation.** *Strategic* — utility AI scores a small goal catalogue (feed armies, hold depot, take region, raid edge, escort route, build depot, seek peace, shop) from visible numbers; personality is a **weight vector** per nation. *Operational* — a supply-aware graph planner turns goals into tasks (forage, garrison, raid, escort, mass at site by turn); because of the upkeep curve it disperses to eat and masses to fight without being told to. *Tactical* — a short per-army behavior tree (starving → withdraw; outmatched → withdraw; opportunity → attack; raider on my edge → contest; else execute task).
- **Crisis brains are weight overrides plus a forced goal**, not a separate system. Direction is authored; the same planner decides the route and the same tactical rules decide when to starve or fall back. An `absorb` flag is how the warlord consumes the tribes on his way south.
- **Shared world-state inputs:** a deterministic **supply projection** N turns ahead (the single most important function), a **threat map** (hostile strength reachable in 1–3 turns), and per-edge **value** (how much supply and trade flows over it). The threat map doubles as a player overlay.
- **Legibility hooks:** every chosen goal writes a public intent record surfaced as a delayed tell — the muster marker the player sees two turns before the stack arrives.
- **Headless tuning:** the whole AI runs at hundreds of turns per second so thousands of sims can hill-climb each nation's weights toward target beat-fire rates (a signature beat should fire in ~50–80% of unaided runs).
- **Avoid:** deep search at the strategic level (slow, opaque) and LLM-driven turn AI (unpredictable). Short rollouts are fine in the tiny battle field.

Full goal formulas, starting weights, task types, and acceptance tests are in Appendix C.

## 10. Open Questions

- Numeric supply model: hop loss, throughput caps, depot cap, decay curve below 50%.
- Supply movement: passive flow to armies each turn vs. deliberate depot stocking.
- Exact per-turn loop at era 1 vs era 3 — verify decision count really holds flat.
- Retreat's cost: free posture flip for the enemy vs. shortened supply line vs. both.
- How much diplomacy exists beyond posture-driven province loyalty.
- Map grain consolidation rules (when do regions become provinces?).
- Simulation performance budget for 6–8 fully simulated AI nations at 20+ turns/era.
- Minority-share display: how culture and faith mixes read on the map at a glance.
- Client states: fixed set on the map vs. dynamic (any conquered nation can become one).
- Crisis brain scope: how much of an actor's AI does the crisis override, and does it hand control back on resolution?
- Battle: whether infantry-only charges, ammunition, or a fourth role are ever needed.
- Logistics: winter as a standing system vs. a crisis; exact depot cap and hop-loss curve after prototype feedback.
- Fog of war: none in prototypes; if added, AI gets the same fog.
- Auto-resolve ratio and the hidden-failure rate.
- Platform and input (the map is hover-driven; mobile needs a tap equivalent).

---

# Appendix A — Combat Prototype Spec

## Combat Prototype — Handoff Spec

*v0.1 — Sep 17, 2026. Companion to `logistics-roguelike-design.md`. This document is the brief for a coding session; it is self-contained.*

### Goal

A playable prototype that proves two things:

1. **Positioning on the strategic map is the real tactical decision.** The player parks an army on a hill, ford, forest, etc., and that position *is* their deployment when a battle starts.
2. **A stripped-down real-time block battle is fun at 60–90 seconds.** Blocks with role glyphs, health/morale fills, and only four orders — where charges, flanks, and pursuit of routing units decide the fight.

Nothing else from the design doc (posture, supply network, crises, characters) is in scope. A single supply-level number per army may be stubbed as a strength multiplier.

### Tech

Prototype-grade. Recommended: a single self-contained web page (HTML + canvas + vanilla JS or a light framework), no build step required to run. If the repo already has an engine, use it; the spec is engine-agnostic. Target 60 fps with ≤ 16 blocks on screen. Must run on a laptop; mobile is nice-to-have.

### One map, two zooms

There is **one terrain dataset** rendered at two zoom levels. Nothing is authored twice.

#### Terrain data
- A small hand-authored map, ~1200 × 800 world units. Store as:
  - `height[x][y]` — float, coarse grid (e.g. 60 × 40 cells, 20 units each). Hills are height bumps.
  - `biome[x][y]` — enum: `plain | forest | swamp | cliff | water`.
  - `roads[]` — polylines.
  - `bridges[]` — points on water where crossing is allowed (one block wide).
- Derived **features** (computed at load, not authored): contiguous regions of high `height` → `hill`; contiguous `forest` cells → `forest`; `swamp`; `water` polylines → `river`; `bridge`; `cliff` edges. Each feature has a centroid, bounds, and a type.

#### Strategic zoom (default)
- Whole map visible. Features rendered as simple icons/patches; roads as lines; rivers as lines with bridge markers.
- **Hover tooltip** on any point: terrain type, its battle modifiers (see table), and — if an army is selected — turns to get there and stub supply cost.
- Armies are **points** with a small marker. Click to select; click a destination to set a path. Path snaps to roads where cheaper. Movement resolves on **End Turn** (button): an army moves up to its movement budget along its path.
- Turn-based. No AI on the strategic layer beyond a single enemy army that follows a scripted path or holds a feature (configurable per scenario).

#### Battle zoom
- Triggered when two hostile armies come within **engagement range** (~60 units) at end of a turn. The camera zooms to a crop ~300 × 200 units centered between them. The crop *is* the battle field — the same height/biome/roads/water data.
- Each army's blocks are spawned at its position, facing the enemy, in a default line (infantry center, archers behind, cavalry on the outer flanks). The defender (the army that didn't move this turn) may pre-arrange blocks before the clock starts; the attacker cannot.
- Real-time from there. Player may zoom out at any time to see the strategic map (paused).

#### Terrain modifiers (battle)
| Terrain | Effect |
|---|---|
| Plain | none |
| Hill (upslope) | defender on higher ground: +25% melee damage dealt, −25% received; charging uphill halves charge bonus |
| Forest | blocks inside are hidden until within 40 units; cavalry moves at 50%, charge bonus 0; archers −50% range |
| Swamp | all movement 50%; cavalry cannot enter; morale drains slowly while inside |
| River | impassable except at bridges |
| Bridge | only one block wide; a block on the bridge can be engaged only from front and back |
| Cliff | impassable edge; blocks cannot be pushed through |
| Road | movement +25% (strategic and battle) |

### Units

Three roles, each a **block**: a rectangle with a glyph (⚔ infantry, ♞ cavalry, ➶ archers — or any clear icon), a **health fill** (vertical, inside the block) and a **morale fill** (outline thickness or a second bar). Facing is shown by a small notch.

| Stat | Infantry | Cavalry | Archers |
|---|---|---|---|
| Size (world units) | 24 × 12 | 20 × 12 | 24 × 10 |
| Health | 100 | 80 | 60 |
| Morale | 100 | 90 | 70 |
| Speed | 20 u/s | 45 u/s | 20 u/s |
| Melee dmg / s (front) | 8 | 6 | 3 |
| Ranged dmg / s | — | — | 5 at ≤ 120 u, needs line of sight, no target in melee with own block |
| Charge bonus | 0 | +40 burst on contact if moved ≥ 30 u before contact | 0 |
| Brace | can `hold` → braced: takes 25% of charge burst, counter-bursts 20 | — | — |

Numbers are starting points; expose all of them in a tuning panel or a `config` object.

### Battle rules

#### Orders (the only four)
- **Move** — right-click / tap a point: block moves there, faces its movement direction on arrival.
- **Attack** — right-click / tap an enemy block: move to contact, engage. Cavalry auto-charges.
- **Hold** — block stops and faces its current direction; infantry becomes **braced** after 1 s of holding.
- **Withdraw** — block disengages and moves toward the friendly map edge at 75% speed. Keeps morale (see Routing). While withdrawing it deals no damage.

Select by click or drag-box; multi-select supported; Shift-click to queue nothing — keep it simple.

#### Engagement
- Two blocks engage when their rectangles overlap or touch. Damage flows per second based on the attacker's melee dmg, modified by terrain, facing, and supply stub.
- **Facing matters.** Damage taken is multiplied by the angle of attack relative to the defender's facing:
  - Front (±45°): ×1.0 health damage, morale −2/s
  - Flank (45°–135°): ×1.5 health damage, morale −8/s
  - Rear (>135°): ×2.0 health damage, morale −15/s
- A block can be engaged from multiple sides; effects stack.
- A block engaged from the flank or rear while already engaged from the front is **flanked**: morale drain is doubled on top of the above. This is the primary way fights are decided.

#### Charges
- Cavalry (and only cavalry, for now) that has moved ≥ 30 units in a straight-ish line before contact deals its **charge burst** on contact, then engages normally. After a charge, cavalry gets a 4 s cooldown before it can charge again and should be pulled out; cavalry stuck in prolonged melee with infantry loses.
- Charging **braced infantry** from the front: charge burst reduced to 25%, cavalry takes the counter-burst. Charging braced infantry from flank or rear ignores the brace.
- Charging into a **routing** block: see below.

#### Morale and routing
- Morale drains from taking damage (1 morale per 3 health lost), from flank/rear contact (above), from seeing a nearby friendly block rout (−15, once, within 80 units), and from being outnumbered (−1/s while engaged by ≥ 2 blocks). Morale recovers +3/s when not engaged and not withdrawing under fire.
- At **morale 0** the block **routs**: it flees toward its own map edge at 120% speed, ignores orders, deals no damage, takes ×2 damage, and can only recover (morale back to 20, controllable again) if unengaged for 6 s and still on the field. A routing block that reaches the edge is removed from the battle (survives at 50% health for the campaign — stub).
- **Cavalry vs routing block:** contact with a routing block by cavalry deletes it outright (0 health, removed). Infantry catching a routing block deals normal damage.
- **Withdraw is not rout.** A withdrawing block keeps its morale fill and its order responsiveness. But if it is contacted from the rear while withdrawing, it takes rear damage and rear morale drain like anyone else — so covered withdrawals (a holding block screening the withdrawing ones) are the correct technique, and uncovered ones become routs.

#### Ranged
- Archers fire at the nearest enemy block within range and line of sight (forest and hills block LOS; height gives +20% range). They stop firing when any friendly block is in melee with the target. Archers in melee fight as weak infantry.

#### End of battle
- Battle ends when one side has no blocks on the field that are not routing, or after **90 s**, or when the player chooses **Retreat all** (issues Withdraw to every block).
- Result screen: per block, health remaining, whether it routed/withdrew/was destroyed; total losses each side; who holds the field (the side with a non-routing block nearest the field center at end). Feature held is shown.

#### Enemy AI (battle)
Minimal, legible. Behaviors, pick one per scenario:
- **Attacker:** advance line toward the player; cavalry tries to reach the player's flank (path around the outside of the player's line) and charge; archers stop at range.
- **Defender:** hold on its feature; infantry brace; cavalry counter-charges any player block that gets within 60 units of a flank; archers fire; if morale on ≥ half its blocks < 30, withdraw all.
- No pathfinding beyond straight lines with obstacle slide for water/cliff; use the bridge if the straight line crosses water.

### Supply stub
Each army has `supply` in [0, 1]. Multiply every block's damage dealt by `0.5 + 0.5 * supply` and its starting morale by the same. Show it on the army marker at strategic zoom. Editable in the scenario config. This is enough to demonstrate "fight them when they're at 55%."

### UI

- Strategic: map, army markers with supply %, hover tooltip, End Turn button, selected army's path preview showing turns and terrain of the destination.
- Battle: crop of the map, blocks with glyph + fills + facing notch, selection highlights, order buttons (Move / Attack / Hold / Withdraw) plus **Retreat all**, a 90 s clock, a speed toggle (1× / 2×), pause on space.
- A tuning panel (dev only) exposing the stat table and terrain modifiers live.
- Colors: player blue, enemy red, routing blocks flash, braced infantry shows a thicker front edge.

### Scenarios (ship all three)

1. **The Ford.** Player holds a bridge with 2 infantry, 1 archer, 1 cavalry; enemy attacks with 3 infantry, 2 cavalry, 1 archer at supply 0.6. Should be winnable by bracing on the bridge and using cavalry on whatever crosses.
2. **The Hill.** Player and enemy start 200 units apart on plain; a hill sits between them. Player has one strategic turn to reach it first (movement budget tuned so the hill is reachable). Whoever holds the hill should have a clear edge.
3. **The Forest Ambush.** Player's army is on the road; enemy cavalry is hidden in a forest beside it. Demonstrates hidden blocks, flank charges, and covered withdrawal — the intended "lesson" is to withdraw infantry in a screened line rather than fight.

### Milestones

1. Map data + strategic render + hover tooltip + army path + End Turn. *(Zoom not needed yet.)*
2. Battle zoom crop + block spawn + four orders + engagement damage + facing multipliers.
3. Charges, braces, morale, routing, cavalry-vs-rout, withdraw.
4. Archers + LOS + terrain modifiers.
5. Enemy AI behaviors + end-of-battle result screen.
6. Three scenarios + tuning panel + speed toggle.

### Acceptance

- A player can hover the strategic map and learn a feature's battle effect without zooming.
- Parking on the hill/bridge before a battle visibly changes the outcome against the same enemy.
- A cavalry flank charge on an engaged infantry block reliably routs it within ~5 s; the same charge into braced infantry from the front reliably fails.
- An uncovered withdrawal under cavalry pursuit is a disaster; a covered one preserves most blocks.
- Battles resolve in ≤ 90 s at 1× speed.
- All numbers live in one config and can be changed without touching logic.

### Out of scope

Multiple regions, posture, supply network, trade, characters, crises, campaign AI, save/load, sound, art beyond glyphs and fills, formations, fatigue, ammunition, unit upgrades.

---

# Appendix B — Logistics & Trade Prototype Spec

## Logistics & Trade Prototype — Handoff Spec

*v0.1 — Sep 18, 2026. Companion to `logistics-roguelike-design.md` and `combat-prototype-spec.md`. Self-contained brief for a coding session.*

### Goal

A turn-based prototype on a small map that proves the logistics layer is both **the star** and **quick to parse**:

1. **Supply is a number you can read on every army**, driven by distance to depots and by what the ground can feed. Big stacks bleed; dispersed ones eat.
2. **Trade is things moving** — caravans on roads that raiders can catch and escorts can protect.
3. **Splitting an army is the normal shape of a campaign**; concentrating is a deliberate act for a chosen battle.

Battles are out of scope: when stacks meet, resolve by a stub (compare strength × supply, apply losses) or hand off to the combat prototype if it exists.

### Model summary

- **Supply** = hop model + depot stock. An army's supply level is set by its hop distance to a depot with stock, and by what the site it stands on can feed.
- **Trade** = convoys. A route auto-dispatches caravans that physically travel; raiders intercept tokens.
- **Sites** hold all resources. Regions are containers for sites, posture, and ownership.
- **Detachments** are a one-click verb; merging is automatic.

### Map data

Reuse the combat prototype's terrain if available; otherwise a graph is enough for this prototype.

- **Regions:** ~12, each with an owner, a posture stub (`military | economic | social`, affects yields ±25%), and 3–6 **sites**.
- **Sites:** a point in the region with a type and a stock.

| Site | Holds | Per-turn yield | Feeds (foraging) | Pillage |
|---|---|---|---|---|
| Farm | Supply | +6 Supply | up to 3 regiments/turn | destroys 2 turns of yield per turn pillaged |
| Village | Levies | +1 levy/2 turns | up to 1 regiment/turn | +2 Coin, then yield halved for 4 turns |
| Mine | Coin | +4 Coin | 0 | +8 Coin once, then 0 for 6 turns |
| Market town | Coin, trade endpoint | +3 Coin, ×1.5 trade income for routes ending here | up to 2 regiments/turn | +10 Coin, routes through it cut for 3 turns |
| Depot | Supply stock | — (filled by the network) | any number, from stock | captures stock if taken |
| Node (horses/iron/grain/dye) | access tag | +2 Coin | 0 | tag denied to owner for 3 turns |

- **Edges:** roads and rivers between adjacent sites (not regions). Each edge has a type: `road | river | trail | mountain`. Edges cross region borders freely.

| Edge | Movement cost | Hop loss (supply) | Caravan speed |
|---|---|---|---|
| Road | 1 | −10% per hop | 2 edges/turn |
| River | 1 | −5% per hop | 3 edges/turn |
| Trail | 2 | −20% per hop | 1 edge/turn |
| Mountain | 3 | −35% per hop | cannot use |

- **Winter** (every 8th–12th turn, 3 turns long): all hop losses +10%, farm yield 0, river speed halved. Optional for v1.

### Supply

#### Depots
- A depot holds **stock** (max 120). Each turn it gains from every farm that can reach it along edges within 3 hops (each farm's yield goes to its nearest depot; if none within 3 hops, the farm's yield stays local for foraging only).
- Each turn a depot loses the **upkeep** of every army leaning on it (see below). If stock hits 0, armies leaning on it lose supply as if they had no depot.
- Depots are built on any friendly site for 40 Coin, take 2 turns, max 1 per region. Capturing an enemy depot takes its stock.
- Show stock as a fill bar on the depot marker.

#### Army supply level
Each army has `supply` in [0, 100]. Each turn, in order:

1. **Upkeep** = `regiments × 2` Supply, × `1.5` if `regiments > 8`, × `2.0` if `regiments > 12`.
2. **Local feed** = sum of foraging capacity of the site the army stands on (a stack on a farm gets ≤ 3 regiments' worth = 6 Supply). If the site is friendly, this is free; if hostile, it is **foraging** and applies that site's pillage effect.
3. **Depot feed** = remaining upkeep, requested from the nearest friendly depot with stock along edges. The delivered amount is reduced by cumulative hop loss (road −10%/hop, etc.). Only edges through friendly or unoccupied sites count; **a hostile stack on a site severs edges through it** (see Raiding).
4. **Shortfall** = upkeep − local feed − depot feed. Supply level changes by `+10` if shortfall ≤ 0, else `−(shortfall / regiments) × 5`, clamped [0, 100].
5. **Effects of supply level:** effective strength multiplier `0.5 + 0.5 × (supply/100)`. Below 30, the army loses 1 regiment every 2 turns (desertion). Below 10, movement halved.

Display on the army marker: `supply%`, a small arrow (rising / falling), hops to depot, and a tooltip breaking down upkeep / local / depot / shortfall.

#### Worked example
A 12-regiment stack on an enemy farm, 3 road hops from its depot (stock 80): upkeep = 24 × 1.5 = 36. Local feed = 6 (foraging, pillaging the farm). Depot request 30, delivered 30 × 0.9³ ≈ 22. Shortfall 8 → supply −3.3/turn, depot −30/turn (dry in 3 turns). Split into two 6-stacks on two farms, 3 hops each: upkeep 12 each, local 6 each, depot 6 → 4.4 delivered, shortfall 1.6 → −1.3/turn, depot −12/turn. Same army, three times the endurance.

### Detachments

- **Detach:** select an army, choose a number of regiments and a target site → a new army is created and paths there. One click plus a count.
- **Merge:** two friendly armies ending a turn on the same site merge automatically unless one is flagged *hold separate*.
- **Leaders:** each army has an optional character. A detachment with no character uses the parent's general's traits at −50% (stub: a single `quality` multiplier 1.0 vs 0.5). Characters are a small roster (3–4 names) so the player feels the constraint.
- **Movement:** an army moves up to 4 movement points/turn along edges (road 1, trail 2, mountain 3, river 1). Stacks > 8 regiments move at 3 points; > 12 at 2.

### Occupation

- A region's owner is whoever garrisons the majority of its **villages and market town**. An army passing through changes nothing. A garrison is any army of ≥ 1 regiment ordered to *hold* on a site; garrisons draw upkeep normally but from the site's own yield first.
- An unoccupied enemy region keeps its posture and yields for the enemy. (This is the hook for rebellion later; out of scope here beyond ownership.)

### Trade

#### Routes
- A route is created between a **market town** you own and any **node or market town** (yours or another faction's) reachable along edges. Route length ≤ 8 edges.
- A route **auto-dispatches a caravan every 2 turns** until cancelled. Max 6 active routes (tune; the trading faction gets 10).
- Caravans are tokens that travel along the route at edge caravan speed. On arrival they pay **Coin** to the market town's owner and grant the node's **access tag** to that owner for 4 turns (refreshed by each arrival). Value: `base 12 × (1.5 if the receiver lacks the good) × (1.5 if the route ends at a market town)`.
- Show caravans as small tokens moving on edges, with the route drawn faintly.

#### Escorts and interception
- A caravan on the same site as a hostile army at end of turn is **captured**: its Coin goes to the captor, the access tag is not granted, and the route's next dispatch is delayed 2 turns.
- An **escort** is a detachment ordered to *escort* a route: it moves with each caravan. A caravan with an escort of ≥ 2 regiments is not captured by a hostile army of ≤ 2 regiments; larger hostile stacks trigger the battle stub.
- A market town with a hostile army on it has all its routes **cut** (no dispatch) while occupied.

### Raiding

- Any hostile army standing on a site **severs** all supply edges through that site for hop-distance calculation and blocks caravans through it. Severing is immediate; **repair is immediate the turn the raider leaves**. Presence is the cost, not damage.
- A raider of ≤ 3 regiments moves at 5 movement points (fast) and forages at full local feed; it is meant to sit on edges, not sites of value.
- Pillage effects (table above) apply while a hostile army forages a site.

### Enemy AI (strategic, minimal)

Two scripted behaviors per scenario:
- **Marcher:** one large stack (10–14) follows a road toward the player's depot, foraging sites along the way; splits into two if its supply falls below 40.
- **Raider:** one 3-regiment cavalry stack that targets the edge between the player's depot and their largest army, or the nearest caravan, whichever is closer; flees any army > 3.

### UI

- Map with regions, sites (glyph per type + a fill bar for stock/yield), edges (line style per type), armies (glyph + regiment count + supply% + arrow), depots (fill bar), caravans (moving tokens).
- **Hover** any site: type, yield, foraging capacity, who it feeds. Hover any edge: hop loss, caravan speed. Hover any army: the supply breakdown.
- Buttons: End Turn, Detach (count + target), Hold/Garrison, Escort route, Build depot, New route (pick two endpoints), Cancel route.
- **One-glance rule:** every number that changes an army's supply next turn is visible without clicking. Depot stock, hops, site capacity, and severed edges all render on the map itself (severed edges drawn dashed red).
- Dev tuning panel exposing every number in this document.

### Scenarios

1. **The March.** Player has one 12-stack and one depot; the enemy region across the border has 4 farms and 2 villages. Take the region and hold it for 6 turns without dropping below 50 supply. Intended lesson: split to forage and garrison, don't march as one.
2. **The Corridor.** Player is the trading faction with 3 routes through a valley; enemy runs a raider. Keep ≥ 2 routes paying for 10 turns. Intended lesson: escorts and route redundancy beat chasing.
3. **The Siege.** Enemy marcher (14 regiments) sits on the player's frontier depot region. Player has 8 regiments. Don't fight — cut its supply edges with a raider, let it starve to < 40 and split, then take the pieces. Intended lesson: the world is the weapon.

### Milestones

1. Graph + sites + edges + rendering + hover.
2. Armies, movement, upkeep, depot stock, supply level with the breakdown tooltip.
3. Detach / merge / garrison / occupation.
4. Routes, caravans, arrival income, access tags.
5. Raiding: severed edges, capture, escort.
6. Enemy behaviors, battle stub, three scenarios, tuning panel.

### Acceptance

- The supply breakdown on any army is understandable in under five seconds.
- A 12-stack foraging one farm visibly starves; the same regiments split across four farms hold steady.
- A raider on a road between depot and army raises that army's shortfall the same turn, and the edge shows as severed on the map.
- A caravan with no escort dies to a raider; with an escort it arrives.
- Scenario 3 is winnable without ever fighting the 14-stack at full strength.
- Every number lives in one config.

### Out of scope

Real battles, posture beyond a yield stub, Influence, characters beyond a name-and-multiplier, crises, culture/religion, winter (optional), multiple factions beyond player and one enemy, save/load.

---

# Appendix C — Nation AI Spec

## Nation AI — Handoff Spec

*v0.1 — Sep 18, 2026. Companion to `logistics-roguelike-design.md`, `logistics-prototype-spec.md` and `combat-prototype-spec.md`. Self-contained brief for a coding session; builds on the logistics prototype's graph.*

### Goal

An AI that drives a nation through the logistics systems **competently and legibly**:

1. It feeds its armies, splits to forage, masses to fight, raids edges, escorts caravans, and holds ground — because those are the cheapest moves under the rules, not because they're scripted.
2. Its intent is **readable on the map** before it acts. A player watching the AI should be able to say "he's mustering for the ford" two turns early.
3. Its personality is a **weight vector** so nations can be tuned by simulation, and a crisis can override it by clamping weights.

Battle AI is out of scope (see the combat spec). Diplomacy and the shop are stubbed as two goals.

### Architecture

Three layers per nation, run in order each turn. Each layer only writes to the one below it.

```
Strategic  (utility AI)   → a ranked list of Goals with resource budgets
Operational (graph planner) → each Goal becomes a Plan: ordered Tasks bound to armies/sites
Tactical   (behavior tree) → each army executes its Task, with local overrides
```

A **Crisis brain** is a modifier on the strategic layer, not a fourth layer.

Everything the AI reads is the same world state the player sees. No hidden information advantage. (Fog is out of scope; if added later, give AI the same fog.)

### World-state inputs (computed once per turn, shared by all nations)

- **Supply projection** `proj(army, plan, N)`: simulate the army's supply level N turns forward along a candidate path using the logistics rules (upkeep, local feed, depot feed, hop loss). Deterministic; cache per (army, path). This is the single most important function in the AI.
- **Threat map** `threat[nation][site][k]`: total hostile effective strength (`regiments × quality × (0.5 + 0.5·supply)`) that can reach `site` within `k` turns (k = 1, 2, 3) under movement rules. Also `exposure[site]` = threat at k=2 minus friendly strength there.
- **Edge value** `edgeValue[nation][edge]`: how much of the nation's supply and trade flows through the edge (sum of depot-feed deliveries and caravan value routed over it this turn). High-value edges are what raiders target and what escorts protect.
- **Region value** `regionValue[nation][region]`: yield of all sites × posture multiplier + node access value + a constant for market towns.
- **Reachability**: Dijkstra from every army over the site graph with supply-aware cost (see Operational).

### Strategic layer — Utility AI

Runs once per nation per turn. Produces up to `maxGoals` (default 4) goals, each with a score and a budget (regiments, Coin, Influence).

#### Goal catalogue (v1)

| Goal | Score sketch | Budget |
|---|---|---|
| **FeedArmies** | Σ over armies of `max(0, 60 − proj(army, current, 3))` | none; forces re-planning |
| **HoldDepot(d)** | `exposure[d] × depotStock(d) × W.defend` | regiments = exposure + margin |
| **HoldRegion(r)** | `regionValue[r] × exposure[r] × W.defend` | regiments = exposure |
| **TakeRegion(r)** | `regionValue[r] × (myReach − theirDefence) × W.expand`, only if `proj(mass, path, turnsToArrive+3) > 45` | regiments = theirDefence × 1.5 |
| **RaidEdge(e)** | `edgeValue[enemy][e] × (1 − threat[e][1]/raiderStrength) × W.raid` | 2–3 fast regiments |
| **EscortRoute(route)** | `routeValue × threat[route][2] × W.trade` | 2 regiments |
| **BuildDepot(site)** | `Σ armies' hop loss saved × W.logistics`, Coin ≥ 40 | 40 Coin |
| **NewRoute(town, node)** | `routeValue × (1 if lacks good else 0.5) × W.trade` | 1 route slot |
| **Garrison(region)** | `regionValue[r] × (1 − ownedFraction) × W.hold` | 1 regiment per village |
| **SeekPeace(nation)** | `(my exposure − their exposure) × W.diplomacy`, Influence ≥ cost | Influence |
| **Shop(item)** | stub: `itemValue × W.shop` | Influence |

Scores are compared after normalisation to [0, 1] per goal type so weights are meaningful. Goals of the same type for different targets compete directly (the AI takes the best 1–2 regions, not all of them).

#### Personality = weight vector

```
W = { defend, expand, raid, trade, logistics, hold, diplomacy, shop, caution }
```
Examples (starting points):
- Warlord: `expand 1.6, raid 1.2, defend 0.6, trade 0.3, caution 0.5`
- Trading empire: `trade 1.6, diplomacy 1.3, defend 1.0, expand 0.5, raid 0.4`
- Hill folk: `raid 1.8, caution 1.4, expand 0.4, hold 0.3`
- Empire: `defend 1.4, hold 1.3, logistics 1.2, expand 0.7`

`caution` scales the supply threshold in TakeRegion (45 → 45 + 20·caution) and the withdraw threshold in the tactical layer.

#### Hysteresis
A goal chosen last turn gets `+0.15` this turn so plans don't thrash. A goal abandoned gets `−0.3` for 3 turns.

#### Legibility hooks
Every chosen goal writes a **public intent** record: `{nation, goalType, target, turnChosen, expectedTurn}`. The UI can surface these as tells (a muster marker, an "eyes on your corridor" icon) with a delay of 1–2 turns. This is also the debug view.

### Operational layer — Graph planner

Turns each goal into a Plan: a list of Tasks bound to specific armies and sites with target turns.

#### Supply-aware pathing
Dijkstra over the site graph where edge cost = `movementCost + λ × supplyPenalty`, and `supplyPenalty` is the drop in `proj` from taking that edge (hop loss, foraging capacity at the destination site, hostile presence). λ = 2 by default; `caution` raises it. This alone makes armies prefer roads, hug depots, and route around raiders.

#### Mass and disperse (the doomstack rule, emergent)
- For a goal needing `N` regiments at site `S` by turn `T`, the planner picks the set of armies whose (arrival turn ≤ T) and whose combined `proj` at S is highest. If no single army suffices it schedules a **Mass** at a staging site with a depot within 2 hops of S.
- While waiting (turn < T − 1), armies are assigned **Forage** tasks: split into detachments ≤ the foraging capacity of nearby farms (≤ 3 regiments per farm), within 1 turn of the staging site. Merge fires automatically the turn before T.
- Because upkeep is ×1.5 above 8 and ×2 above 12, `proj` for a merged stack sitting still is worse than for its dispersed parts — so the planner disperses without being told to.

#### Task types
`Move(site)`, `Forage(site)`, `Garrison(site)`, `Raid(edge)`, `Escort(route)`, `Mass(site, turn)`, `Withdraw(depot)`, `Build(depot, site)`, `Route(town, node)`, `Detach(n, site)`.

#### Replanning
Plans are recomputed every turn from scratch (cheap on a ~60-site graph). Bound armies keep their Task if the new plan agrees; otherwise they're reassigned. The hysteresis at the strategic layer keeps this from thrashing.

### Tactical layer — Behavior tree (per army)

Evaluated every turn, top to bottom, first match wins. Overrides the operational Task.

1. **Starving** — `proj(current, 2) < 25` → `Withdraw(nearestDepotWithStock)`. Detach a raider-size screen if an enemy is adjacent.
2. **Outmatched** — `threat[here][1] > myStrength × (1.2 + 0.4·caution)` and not `Garrison` → `Withdraw` one hop along the best supply edge; if none, `Hold`.
3. **Opportunity** — an enemy army adjacent with `theirStrength × (0.5+0.5·theirSupply) < myStrength × 0.7` → `Attack` (battle stub / combat prototype).
4. **Raider on my edge** — this army is ≥ 4 regiments and a hostile ≤ 3-regiment army sits on an edge with `edgeValue > 0` within 1 hop → `Move` to contest (raiders flee; that's fine — presence is the cost, and displacement repairs the edge).
5. **Execute Task** — otherwise do the operational Task.
6. **Idle** — no Task: `Forage` at the best local site, or `Garrison` if in a region we own below 100%.

Raider armies (≤ 3 fast regiments) use a variant: never rule 3; rule 2 threshold ×0.6 (they flee earlier); rule 5's `Raid(edge)` re-targets each turn to the highest `edgeValue` edge with `threat[edge][1] == 0` within reach.

### Crisis brain

When a crisis fires for a nation, it applies a **weight override** and a **forced goal** for its duration:

```
crisis = {
  actor, intent: {goalType, target},        // e.g. TakeRegion(clientState)
  weightOverride: {expand: 3.0, caution: 0.2, raid: 1.5},
  forcedGoalScore: 10,                       // always top of the list
  absorb: true,                              // optional: merge conquered levies into the stack
  endsWhen: predicate on world state
}
```

The forced goal goes through the **same planner and tactical layer**, so the actor still forages, masses, routes around held fords, and withdraws when starving — direction is authored, outcome is not. The `absorb` flag is the "consumes the tribes on the way south" behavior: on taking a region, its villages' levies join the stack immediately instead of over turns.

### Simulation & tuning

- The whole AI must run **headless** at ≥ 200 turns/second for 8 nations on the prototype map so that world-beat tuning can run thousands of games. No per-turn allocation-heavy work; cache projections and threat maps.
- Provide `simulate(mapSeedlessFixedMap, weights[], turns) → stats` returning per-nation: regions held per era, battles fought/won, average army supply, caravans lost, beats fired (a beat is a named predicate, e.g. `warlordHoldsClientStateBy(turn 30)`).
- A tuning script: hill-climb each nation's `W` toward a target beat-fire rate (e.g. 60–75%) while keeping that nation's average army supply above 50 (so we don't "win" by starving it).

### Player-side reuse

Expose the operational layer as player commands: **Forage here** (plans detachments across the region's farms), **Escort this route**, **Mass at** (site, turn). These run the same planner for the player's armies and are the anti-doomstack convenience verbs.

### UI / debug

- Toggle to show each AI nation's current goals with scores and targets, and each army's active tactical rule.
- Draw planned paths and Mass points for one selected nation.
- Threat-map overlay for the player (threat at k=2 as shading) — this is a real feature, not just debug: it's how the player reads "where can they be in two turns."

### Milestones

1. World-state inputs: `proj`, threat map, edge value, region value. Unit tests against hand-checked cases.
2. Strategic layer with FeedArmies, HoldDepot, TakeRegion, RaidEdge, Garrison. Debug view.
3. Operational planner: supply-aware Dijkstra, Mass/Forage/merge, Task binding.
4. Tactical behavior tree incl. raider variant.
5. Escort, BuildDepot, NewRoute, SeekPeace/Shop stubs.
6. Crisis brain with one authored crisis (marcher toward a target region, absorb on).
7. Headless sim + tuning script + beat predicates.

### Acceptance

- Against no opponent, a 14-regiment AI stack ordered to take a region 4 hops out arrives above 60 supply, having dispersed to forage en route and merged the turn before.
- An AI raider finds and sits on the player's highest-value supply edge within 3 turns of it becoming exposed, and leaves when a ≥4-regiment army approaches.
- The trading-empire weights produce escorts on its two most threatened routes without an explicit escort script.
- Public intent records let a debug overlay show "TakeRegion(ford)" at least 2 turns before the AI's stack arrives.
- With the crisis brain on, the warlord takes the target region in 60–80% of 500 headless runs; with a player-controlled garrison holding the intermediate ford (scripted), that drops below 30%.
- 8 nations × 100 turns simulate in under 5 seconds.

### Out of scope

Battle AI, diplomacy beyond SeekPeace stub, the shop beyond a stub, characters/traits (a per-army `quality` multiplier is enough), culture/religion, fog of war, learning/ML.
