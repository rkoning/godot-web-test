// Two small word lists; the product is large enough that collisions in a room
// are rare, and assign_name() disambiguates the ones that do happen.
const ADJECTIVES = [
  "Brisk", "Candid", "Dusty", "Eager", "Frosty", "Gilded", "Hollow", "Idle",
  "Jolly", "Keen", "Lucky", "Molten", "Nimble", "Odd", "Placid", "Quiet",
  "Restless", "Salty", "Tidy", "Upright", "Velvet", "Wary", "Yonder", "Zealous",
];

const NOUNS = [
  "Badger", "Cormorant", "Dromedary", "Ermine", "Falcon", "Gannet", "Heron",
  "Ibis", "Jackal", "Kestrel", "Lynx", "Marten", "Newt", "Otter", "Pelican",
  "Quail", "Raven", "Stoat", "Tapir", "Urchin", "Viper", "Walrus", "Yak", "Zebu",
];

function pick(list) {
  return list[Math.floor(Math.random() * list.length)];
}

/**
 * Pick a name that nobody in `taken` is already using.
 * Falls back to suffixing a number once the random attempts keep colliding,
 * so this always terminates even in a very full room.
 */
export function assignName(taken) {
  for (let i = 0; i < 12; i++) {
    const name = `${pick(ADJECTIVES)} ${pick(NOUNS)}`;
    if (!taken.has(name)) return name;
  }
  const base = `${pick(ADJECTIVES)} ${pick(NOUNS)}`;
  let n = 2;
  while (taken.has(`${base} ${n}`)) n++;
  return `${base} ${n}`;
}
