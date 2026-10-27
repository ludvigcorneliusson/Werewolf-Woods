extends Node
## The settler's backpack: a fixed number of slots, each holding one kind of
## item up to its stack size (scripts/items.gd). hud.gd draws it; pickups.gd
## fills it. Slot = {"id": String, "count": int}, or {} when empty.

signal changed

const Items := preload("res://scripts/items.gd")

var slots: Array[Dictionary] = []


func _init(size := 6) -> void:
	name = "Inventory"
	resize(size)


func resize(size: int) -> void:
	slots.resize(size)
	for i in size:
		if slots[i] == null:
			slots[i] = {}
	changed.emit()


## Adds up to n of an item: tops up existing stacks first, then empty slots.
## Returns how many did NOT fit (0 = all added).
func add(id: String, n := 1) -> int:
	var cap := Items.stack_size(id)
	for s in slots:
		if n <= 0:
			break
		if s.get("id", "") == id and s.count < cap:
			var put := mini(cap - s.count, n)
			s.count += put
			n -= put
	for i in slots.size():
		if n <= 0:
			break
		if slots[i].is_empty():
			var put := mini(cap, n)
			slots[i] = {"id": id, "count": put}
			n -= put
	changed.emit()
	return n


## Room for at least one more of this item?
func can_add(id: String) -> bool:
	for s in slots:
		if s.is_empty() or (s.get("id", "") == id and s.count < Items.stack_size(id)):
			return true
	return false


func count(id: String) -> int:
	var total := 0
	for s in slots:
		if s.get("id", "") == id:
			total += int(s.count)
	return total


## Takes up to n of an item out (last slots first). Returns how many were taken.
func remove(id: String, n := 1) -> int:
	var taken := 0
	for i in range(slots.size() - 1, -1, -1):
		if taken >= n:
			break
		var s := slots[i]
		if s.get("id", "") == id:
			var t := mini(int(s.count), n - taken)
			s.count -= t
			taken += t
			if s.count <= 0:
				slots[i] = {}
	changed.emit()
	return taken
