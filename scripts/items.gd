extends RefCounted
## Item definitions: name, icon (inventory / tools bar), how many fit in one
## inventory slot, and how the item looks lying on the ground. Add an entry here
## to add an item; scripts/pickups.gd, inventory.gd and hud.gd read this table.
##
## "prop" = the map prop image that can be picked up as this item (pebbles and
## sticks already lying in the forest). "world_scale" = size on the ground.

const ITEMS := {
	"axe": {"name": "Axe", "icon": preload("res://assets/ui/axe.png"), "tool": true},
	"stone": {"name": "Stone", "icon": preload("res://assets/props/pebble.png"), "stack": 20,
			"world": preload("res://assets/props/pebble.png"), "world_scale": 1.0, "prop": "pebble.png"},
	"twig": {"name": "Twig", "icon": preload("res://assets/props/stick.png"), "stack": 20,
			"world": preload("res://assets/props/stick.png"), "world_scale": 1.0, "prop": "stick.png"},
	"log": {"name": "Log", "icon": preload("res://assets/props/log.png"), "stack": 10,
			"world": preload("res://assets/props/log.png"), "world_scale": 0.7},
}


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func display_name(id: String) -> String:
	return ITEMS.get(id, {}).get("name", id.capitalize())


static func stack_size(id: String) -> int:
	return int(ITEMS.get(id, {}).get("stack", 1))


## Item id for a map prop image (e.g. "pebble.png" -> "stone"), or "".
static func item_for_prop(image: String) -> String:
	for id: String in ITEMS:
		if ITEMS[id].get("prop", "") == image:
			return id
	return ""
