-- Pocket items (GDD §7.4): passive, they last the whole run, like relics in Slay the Spire. The van sells them, and every
-- Gang leader you get past lets you pick one. Their effects live where they apply (sim/kid.lua, sim/fight.lua,
-- sim/trap.lua, sim/duel.lua, sim/park.lua); `icon` is a sprite of the ui atlas. price = marbles at the van in the Morning.

return {
    lucky = { name = "Lucky Marble", icon = "icon_marble", price = 5,
              text = "Start every fight with 1 extra card in your hand." },
    lunchbox = { name = "Lunchbox", icon = "icon_lunchbox", price = 5,
                 text = "Your first Lure in every fight costs no time." },
    sneakers = { name = "Sneakers", icon = "icon_sneaker", price = 4,
                 text = "Releasing a bug costs 1 tick less (never less than 1)." },
    bandaid = { name = "Band-Aid", icon = "icon_bandaid", price = 4,
                text = "Once per act, wake up one napping bug." },
    watch = { name = "Wristwatch", icon = "icon_watch", price = 5,
              text = "Every Sun clock lasts 10 ticks longer." },
    net = { name = "Bug Net", icon = "icon_net", price = 6,
            text = "In Bug Hunts, flyers that fly over your jar are caught too." },
    sweep = { name = "Sweep Net", icon = "icon_sweep", price = 5,
              text = "In Bug Hunts, a Flick on a wild bug hidden in the grass or under a leaf catches it straight away." },
    pooter = { name = "Pooter", icon = "icon_pooter", price = 6,
               text = "In Bug Hunts, at the end of every tick, a Light wild bug next to your jar is sucked into it." },
    album = { name = "Sticker Album", icon = "icon_album", price = 4,
              text = "+2 marbles every time you break a rival." },
}
