You approach Facility terminal -> interact -> order panel UI hud opens (two pane, left pane is an order (quest) list, right pane is order details (cargo weight, type, fragility, destination)) -> you select an order from the list -> cargo management UI panel (assign cargo from Facility Storage)



definitions

Facility - a base, unique locations placed in the world
Facility Storage - player's inventory at the facility, unique to each
Order - a quest, given from the Facility terminal, once accepted it spawns the order items in the Facility's Storage or in the world (depending on the order type, it can be cargo delivery from current Facility to other Facility, it can be Cargo retrieval from other facility and transport to another facility, or it can spawn in world, where it needs to be found and retrieved and brought to the target facility)

so, each quest order cargo needs to have these properties:
Origin
Destination
Weight
Fragility
Time limit (when it needs to be transported to a destination, counter starts on pickup)

to simplify tracking and editing orders, we can assign an unique 3 number numeric code  to each order.

and I think storing these orders in TSV file would be great, so we can edit them easily later (we made a tsv editor tool for StarChef earlier, we can reuse some of it for Space Stranding too)

And there should be a second type of quest cargo - loose cargo placed in the world (either spawned by special event, like an orbital drop, or just laying out in the wild). After picking it up and holding it in player's inventory (either rover cargo or on the back) should list it in the quest orders list (that's something we also need to make, a panel with player's inventory cargo management and order management)


cargo types:

materials (player can use it for construction)
materials quest order (player can't use it, it needs to be delivered to it's destination)
upgrade items - packages with upgrades that can be installed on the rover on the player's suit


I am not yet sure if there will be much or any combat, so possible cargo variants may include weapons, but we can park it for now.