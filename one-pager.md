# Working Title: Logistics Roguelike — Design One-Pager

*Draft v0.6 — Sep 16, 2026*

## Pitch

A Total War–scale strategy game compressed into a 45–180 minute roguelike run. The player rules one nation on a hand-authored map through three eras, each ending in a crisis. Settlement management is replaced by **region posture**; battles are **regiment squares** resolved in a few readable rounds. The core thesis: **the army is not the player's only weapon — the world is.** Terrain, supply, and time force generals' hands; the player wins by reading the clocks and choosing when, and where, to stop retreating.

## Pillars

1. **Decision density stays flat.** The unit of decision scales with the player's power. Trivial fights auto-resolve; real fights are always played. Regions merge into provinces and frontiers as the empire grows, so per-turn decision count holds steady while stakes rise.
2. **Every fight is chosen.** No auto-resolve on non-trivial battles. Retreating and giving ground are legitimate, low-casualty moves that cost position and supply, not regiments.
3. **The world has a history, not a seed.** One fixed map, simulated nations, tuned tendencies. Replayability comes from seat, timing, and crisis draw — not procedural terrain.
4. **Crises escalate from transformative to binary.** Eras 1–2 reshape the nation; era 3 ends it or crowns it.

## Core systems

### Region posture
Each region (later: province, frontier) is set to **Military**, **Economic**, or **Social**. Posture is a *bet with exposure*, not a dial:
- Military: levies and supply for armies; drains food from neighbors; raises unrest under neglect.
- Economic: coin and trade throughput; high-value raid target.
- Social: unrest → growth; slow to mobilize; starves rebel recruitment.
Posture should want to change turn to turn as enemy proximity, supply, and unrest shift.

### Resources
Three currencies, one per posture. No tech tree; regiment quality comes from rulers, relics, veterancy, and node access.
- **Coin** (Economic) — recruits and maintains regiments, pays mercenaries, builds depots and roads. Empire-wide.
- **Supply** (Military posture + geography) — feeds armies. Local: lives in regions and depots and must physically move.
- **Influence** (Social) — diplomacy and the shop (see below).

Manpower is folded into recruitment gated by a region's population: Social regions levy more, burned ones levy nothing.

### Resource nodes
Nodes are **access tags on regions, not currencies** — you either control or trade for them. Horses (cavalry; plains quality), Iron (heavy regiments; quality), Grain (region Supply and depot cap doubled), Salt / spice / dye (trade goods; Coin scaled by the receiver's scarcity), Timber (river throughput or ships). Nodes are part of the authored map: the steppe has horses and nothing else; the empire has grain and iron but no horses. **Wanting drives crises and beats** — Hildegard raids south because he has horses and no iron. Nodes give every crisis a concrete objective (the rebellion marches for the grain belt; the claimant wants the iron province).

### Supply
Supply is a **network**, not a number.
- Regions produce Supply and hold a small stock. **Depots** (few, Coin-built, capped) hold large stock and are the network's nodes.
- Supply flows along roads and rivers between adjacent friendly regions with a per-turn throughput cap: roads = base, rivers = ×2–3, mountains / winter = halved.
- Each army has a **supply level** (0–100%). It draws upkeep from its region; shortfall comes from the nearest depot along the network minus a loss per **hop**; if neither covers it, the level drops. Level scales effective strength — gently above 50%, steeply below.
- Distance is felt in hops, not tiles. Giving ground means retreating *up* your network while the enemy advances *down* theirs — or off it entirely.
- **Foraging:** hordes and rebels draw Supply directly from the region they occupy and destroy its stock — mechanically why they must keep moving, grow through rich land, and starve in poor land.
- **Enemy supply is visible on their stack**, computed the same way: level, drop rate, and hops to their nearest depot.

### Trade
Trade routes are **a second, discrete graph on the same physical map**. A route links one of your regions to a node (yours or another nation's) along a road, river, or sea lane. It pays Coin per turn, grants the node's access tag to both ends, and can carry a little Supply. Routes exist internally and externally. Because routes are physical they can be raided, blockaded, or cut by a hostile posture flip on a region along them. Embargo is a standard Influence action. Trade-focused nations' uniques live here: more routes, exclusive sea lanes, Supply-carrying routes, Influence from trade, cheap embargoes.

### Army roles and raiding
Supply and trade edges are **cut by presence**: a stack sitting unopposed on a region severs the edges through it — no battle needed. Cutting is one turn; repair is free the moment the raider leaves. The pressure is presence, not damage.
- **Line armies** — big, slow, hungry. Take and hold.
- **Raiders** — small, fast, cheap. Can't win a real fight; don't need to. Cut a trade edge and the route stops paying and access drops; cut a supply edge and everything downstream counts one more hop.
- **Garrisons** — static, cheap, no supply draw. Make an edge safe.

Counterplay: escorts stationed on a route, redundant roads and rivers (what Coin is for), and foraging attrition on poor regions. AI nations raid too — a neighbor's raider on your edges is legible pressure short of war, and raiders on your supply edges are a natural early tell for a rebellion.

### Clocks
Every side has visible pressures that eventually force a fight: campaign seasons, supply rot, mercenary desertion, legitimacy bleed, provinces burning. Clocks differ by actor — a horde starves faster than a garrison; a besieger bleeds coin; a pretender's claim loses credibility every season uncrowned. The player's job is to make the enemy's clock run out first.

### Battles
Regiment squares: strength (health × count) × quality, modified by supply and terrain. A few rounds, one call per round — **press / hold / withdraw / commit reserve**. Terrain modifiers are strong and legible (river crossing halves attacker; pass nullifies numbers; plains favor quality). Orderly withdrawal preserves strength; a broken one collapses quality.

- **Threshold auto-resolve:** if effective strength exceeds the enemy's by a set ratio, the fight resolves in the player's favor at a cost (attrition, supply, a turn). The ratio is visible so progression is felt: "this used to be a battle, now it's a march."
- Auto-resolve can rarely fail via hidden supply/terrain/trait factors — a "should have been free" loss is itself a tell.

### Eras and rulers
Three eras, ~25–30 min each, crisis occupying the last third. The ruler who emerges from each crisis carries its consequences as traits (the general who broke the siege vs. the diplomat who negotiated). **Ruler traits are the run's relics; postures are the deck.** Era boundaries are a clean place to reshuffle postures and consolidate map grain.

### Characters (Rome: Total War traits, roguelike picks)
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

### Client states
A nation with a suzerain: pays tribute (Coin or Supply routed up the empire's network), can't declare war without permission, part of its Influence is the empire's to spend; in exchange the empire's line armies are obligated to defend it — so a client can **drag the empire into wars**. Internally, a client has a **court of 2–3 factions** (loyalist, independence, the regional leader's own base) that leans each turn on what you do: prompt tribute feeds loyalists, a deal with Hildegard feeds independence, an unanswered raid feeds both against the emperor. The player manages whether the court lets them *not* secede. Verbs: use the empire's armies and Influence for your own wars while building the depots and routes to stand alone. Era-one crisis: the empire is weak and the court leans out — break away, renegotiate autonomy, or double down as the loyal province and inherit its problems. Governors who led a secession are unlockable seats. Open: fixed 2–3 clients on the map vs. any conquered nation becoming one.

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

## Crises

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

## Peoples and power

**Culture is sticky, religion moves, traditions are chosen, government can be reconstituted.**

### Culture (map layer)
Every region has a dominant culture and a minority share. A nation has a *home* culture. Conquering a foreign-culture region gives the land, not the people: reduced posture yields, unrest, no levies, a court that reads it as a liability. Taking a region of your own culture is nearly free — the reclamation fantasy the ailing empire runs on. Culture changes only through occupation measured in **eras**, settlement (a horde planting itself), or Social posture backed by a tradition. It is the slow ceiling on how big an empire can usefully be, and the mechanism behind Overextension. Home culture also gates what a nation knows how to use (the hill folk can't field iron regiments even with access; the steppe can't garrison).

### Religion (map layer)
Same shape — dominant faith and minority share per region — but it **moves**: along trade edges and through Social posture, like rebellion through villages. Mismatch with the ruler's faith is unrest and lost Influence; match is the opposite. Raiders can't cut it and armies can't hold it; it's fought with posture. Marriages carry faith into the court. Trade routes carry faith as well as Coin — the trading empire is a missionary by accident.
- **State faiths (3–4):** each is the ruler's faith of one or more nations with a home region. Shared faith is a diplomatic fact: cheaper peace, marriages that don't rock the court, a coalition trigger when a co-religionist is invaded — and a rivalry axis over who is its true protector (the claimant crisis with a religious face).
- **Stateless faiths (2–3):** held by no nation, only by regions — an old faith the state faiths displaced (strong in the hills and the empire's poor provinces) and a new one spreading along trade. They can only rebel or convert a ruler. A stateless majority in a neglected corridor is the rebellion's recruitment pool; crossing a threshold in your core is the Crisis of faith.
- Faith roster slots: `STATE_1..4`, `OLD_FAITH`, `NEW_FAITH` — names TBD.

### Traditions (accreted in-run)
The era relic picks *are* traditions: each has sides (the granary network makes famine survivable and Military posture worse; a martial tradition raises levy quality and makes a League court fractious). Two or three by era three is the run's build, visible in one row. Traditions can conflict (mercantile + martial → schism tell), and carry across the unlock tree (a nation unlocked by vassalizing it starts *Subjugated*). Assimilation, Tolerance, and Syncretism are the traditions that let a culture convert a region or live with not doing so.

### Government (how the sub-regions hold power)
Provinces are constituencies with a power base (governor, garrison, wealth). The government type says how much that base counts against the throne — and **succession falls out of it**:
- **Centralized** — provinces are administrative; the ruler appoints and designates. Strong and brittle: no check on a bad ruler, no voice for a distant province, so clash and secession fester silently. *The empire.*
- **Provincial** — provinces are estates; governors semi-hereditary and holding levies. Succession is a count of provinces backing each claimant; every conquest is a new voter. *Client-state seats live here.*
- **League** — cities are the constituencies; elective among city governors; trade routes are the political network. *The trading empire.*
- **Warband** — the army is the constituency; generals are power bases; succession goes to whoever the regiments follow, readable by who holds the veterans. *The warlord; the hill folk before they settle.*

Each type has a soft cap on constituencies before it destabilizes (Centralized ~6 provinces, Provincial ~10, League any number of cities, Warband by veteran share) — exceeding it is the Revolution trigger. Government can change through a tradition pick or a crisis resolution and it is always a big deal: hill folk settling is Warband → Provincial; the ailing empire's golden age likely requires Centralized → Provincial to keep its clients. Assignments carry political weight (the heir governing the richest province stacks the count), marriage into a power base buys a vote, Influence spent on the court buys more, and map-grain consolidation is a political act — merging two provinces removes a constituency. Succession crises split the constituencies: under Provincial, a civil war with a map; under Warband, two generals with two stacks.

## The world

- **One hand-authored map**, ~40–60 regions, 6–8 starting nations, a few never-playable wild zones for hordes and migrations.
- **AI nations run the real simulation outside of crises** — same posture, supply, battle, and crisis-eligibility rules as the player. Between crises, no scripting: they expand, fight, catch plagues, and can die.
- **Tuned tendencies decide *if* a beat fires; the crisis object decides *what happens*.** Initial conditions (armies, postures, unrest, rivalries) are authored so the timeline usually rhymes: Hildegard becomes eligible to invade around turn 20; the client state's secession triggers when the empire's legitimacy dips. Beats fire on *conditions*, not dates. Player action or plain randomness (a plague kills the warlord on turn 10) can prevent, delay, or redirect them. Once fired, a beat has authored intent (see Crisis anatomy). Prevented beats mutate rather than vanish.
- **Target rates** (to verify by headless simulation): a signature beat should fire in roughly 50–80% of unaided runs. Higher is a script; lower isn't texture.
- **Nation crises are guaranteed structure; world beats are texture.** An unlucky world must still pressure the player.

## Nations and unlocks

- Nations are **different flavors of difficulty, not stat modifiers.** The ailing empire is hard because three world beats are aimed at it and its starting postures are wrong for all of them. The warlord is allowed to dominate his corner — the drama is the point.
- **Nation archetypes (so far):**
  - *The ailing empire* — ancient, splintering; three world beats aimed at it, postures wrong for all of them. Golden age is the hard-mode win.
  - *The warlord* — expansionist, feared by distrustful neighbors; allowed to dominate his corner.
  - *The hill-folk tribes* — no depots, forage and raid; must stay mobile against the belly of the empire, cutting its edges, until they can hold ground and become a nation.
  - *The trading empire* — broad, dispersed network of rich cities; strong in routes and Influence, weak to blockade and to a raider parked on its corridor.
- **Unlocks are keyed to world state**, not just victory: "end a run with the delta nation as your vassal" unlocks the delta nation, with starting attributes reflecting what you did to them. Some nations unlock only after you've faced their beat from the other side (beat Hildegard as the empire → play Hildegard).

## Open questions

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
