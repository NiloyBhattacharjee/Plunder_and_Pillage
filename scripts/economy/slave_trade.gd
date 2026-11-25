class_name SlaveTrade
extends RefCounted
## The Atlantic slave trade as the world runs it (data/economy.json "slave_trade"), shown and never traded:
## docs/representation.md. Ships sail from the forts on the African coast for the plantation islands of their own
## nation, and, while a nation holds the asiento, for the Spanish ports too. The people aboard are never cargo or a
## number the player sees: a voyage carries no goods, and nothing here is sold to or by the player.
## The people aboard resist: some voyages see a rising, which the world hears of. A slaver the player takes ends
## in an event where the freed people decide what happens to them (data/events/slave_trade.json).
##   voyages: [{id, faction, fort, dest, ship, depart, arrive, rose}]

var m: EconomyModel
var voyages: Array = []
var events: Array = []   # [{text, port}] for the game's news
var next_id := 1


func _init(model: EconomyModel) -> void:
	m = model


func cfg() -> Dictionary:
	return m.cfg.get("slave_trade", {})


## The nation holding the asiento this year (its slavers may sell in Spanish ports), or "".
func asiento(year: int) -> String:
	for a in cfg().get("asiento", []):
		if year >= int(a.from) and year < int(a.until):
			return a.faction
	return ""


## Where a slaver from this fort may be bound.
func destinations(fort: String, year: int) -> Array:
	var f: String = m.ports[fort].faction
	var spain := asiento(year) == f
	return m.stock.keys().filter(func(id): return not m.ports[id].has("gates") and (
		(m.ports[id].faction == f and "plantation" in m.ports[id].tags) or (spain and m.ports[id].faction == "spain" and id in cfg().asiento_ports)))


func step(day: int, year: int) -> void:
	if cfg().is_empty():
		return
	for fort in cfg().forts:
		if not m.ports.has(fort) or m.world_has("sailings:" + fort):
			continue
		if m.rng.randf() < float(cfg().forts[fort]) / 365.0:
			var dests := destinations(fort, year)
			if not dests.is_empty():
				_sail(fort, dests[m.rng.randi() % dests.size()], day)
	for v in voyages.duplicate():
		if not v.rose and day >= (v.depart + v.arrive) / 2:  # the open sea, far from either coast: when risings came
			v.rose = true
			if m.rng.randf() < float(cfg().rising_chance):
				_rising(v)
		if day >= v.arrive:
			voyages.erase(v)


func _sail(fort: String, dest: String, day: int) -> void:
	var days: float = m.traffic.days(fort, dest) * float(cfg().days_mult)
	var names: Array = cfg().ship_names
	voyages.append({"id": "sl%d" % next_id, "faction": m.ports[fort].faction, "fort": fort, "dest": dest,
		"ship": names[m.rng.randi() % names.size()], "depart": day, "arrive": day + int(round(days)), "rose": false})
	next_id += 1


## The people in the hold rise. Most risings were put down; some took the ship.
func _rising(v: Dictionary) -> void:
	var won := m.rng.randf() < float(cfg().rising_won)
	var key := "won" if won else "lost"
	events.append({"text": cfg().rising_text[key].format({"ship": v.ship, "fort": m.ports[v.fort].name}), "port": v.dest})
	if won:
		voyages.erase(v)


func find(id: String) -> Dictionary:
	for v in voyages:
		if v.id == id:
			return v
	return {}


## The player took her: she never reaches port.
func lose(id: String) -> void:
	voyages.erase(find(id))


func take_events() -> Array:
	var out := events
	events = []
	return out


func save_state() -> Dictionary:
	return {"voyages": voyages, "next_id": next_id}


func load_state(d: Dictionary) -> void:
	voyages = d.get("voyages", [])
	next_id = int(d.get("next_id", 1))
