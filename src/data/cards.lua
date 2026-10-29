-- Kid cards (GDD §7). The effect of each card lives in sim/cardfx.lua; this file is only content.
-- steps: what the player has to pick, in order. bug = a bug, tile = a tile, dir = one of the 4 tiles next to the previous pick.
-- exhaust = "Used up" for the rest of the fight.
-- cost = ticks it takes to play. price = marbles it costs at the Swap Shop (data/shop.lua says where it is sold).

return {
  flick = {
    name = "Flick", cost = 1, price = 1, type = "nudge", steps = { "bug", "dir" }, art = "flick",
    text = "Push a Light or Medium bug 1 tile.",
    flavor = "Works on anything smaller than your thumb.",
  },
  crumb = {
    name = "Crumb", cost = 1, price = 1, type = "lure", steps = { "tile" }, art = "crumb",
    text = "Put food on an empty tile. Ants go for it.",
    flavor = "Dropped from a half-eaten cookie.",
  },
  stick = {
    name = "Stick", cost = 2, price = 2, type = "terrain", steps = { "tile", "dir" }, art = "stick",
    text = "Lay a stick across 2 tiles. Walkers can't pass; flyers and jumpers hop over it.",
    flavor = "Found under the slide. Best stick ever.",
  },
  shadow = {
    name = "Shadow", cost = 0, price = 2, type = "timing", steps = { "bug" }, art = "shadow",
    text = "A bug freezes in the shadow of your hand: +1 timer.",
    flavor = "Bugs are cold-blooded. Shade makes them sluggish.",
  },
  sun = {
    name = "Sun Patch", cost = 1, price = 2, type = "timing", steps = { "tile" }, art = "sun",
    text = "Step aside! Your bugs in a 3x3 area get -1 timer.",
    flavor = "Warm bugs are fast bugs.",
  },
  water = {
    name = "Water Bottle", cost = 2, price = 2, type = "terrain", steps = { "tile", "dir" }, art = "water",
    text = "Pour a 2-tile puddle. Walkers can't enter; a bug in it is Soaked (+2 timer).",
    flavor = "Half empty. Or half full?",
  },
  sugar = {
    name = "Sugar Cube", cost = 1, price = 2, type = "lure", steps = { "tile" }, art = "sugar",
    text = "Sweet food. Attracts ants AND wasps (yours and theirs).",
    flavor = "Lifted from the kitchen. Don't tell Mom.",
  },
  juice = {
    name = "Juice Box", cost = 2, price = 3, type = "lure", steps = { "tile" }, art = "juice", exhaust = true,
    text = "A sweet lure nobody can finish: it stays all fight. Used up.",
    flavor = "The straw is still in it.",
  },
  shove = {
    name = "Shove with a Twig", cost = 2, price = 3, type = "nudge", steps = { "bug", "dir" }, art = "shove",
    text = "Push ANY bug 1 tile, even a Heavy one.",
    flavor = "For things too big to flick.",
  },
  tap = {
    name = "Tap the Ground", cost = 1, price = 2, type = "timing", steps = { "tile" }, art = "tap",
    text = "Bugs in a 3x3 area freeze (+1 timer). Pill bugs curl up.",
    flavor = "Pill bugs roll up when the ground shakes.",
  },
  blow = {
    name = "Blow", cost = 1, price = 2, type = "nudge", steps = { "tile", "dir" }, art = "blow",
    text = "Light bugs in a line slide 1 tile (flyers slide 2).",
    flavor = "Huff, puff...",
  },
  leaf = {
    name = "Leaf", cost = 1, price = 2, type = "terrain", steps = { "tile" }, art = "leaf",
    text = "Cover: bugs under it are Hidden. Over a puddle it's a bridge.",
    flavor = "Shelter, shade and a boat for a bug.",
  },
  pebble = {
    name = "Pebble", cost = 1, price = 1, type = "terrain", steps = { "tile" }, art = "pebble",
    text = "A 1-tile obstacle.",
    flavor = "Tiny for you. A boulder for them.",
  },
}
