class_name Atlantic
## Crossings to the ports across the Atlantic (data/rules.json "atlantic"). The map stays the Caribbean: its
## gates on the edge lead out to London, Boston, the Guinea coast... (ports.json entries with "gates").
## The crossing itself is played by WorldMap.cross: the days pass as at sea, and something may happen on the way.


static func cfg() -> Dictionary:
	return Data.rules.atlantic


static func gates() -> Array:
	return cfg().gates.keys()


static func gate_name(g: String) -> String:
	return cfg().gates[g].name


static func gate_pos(g: String) -> Vector2:
	return Geo.latlon_to_px(cfg().gates[g].lat, cfg().gates[g].lon)


## The ports a crossing through this gate can make.
static func reachable(g: String) -> Array:
	return Data.table("ports").keys().filter(func(id): return g in Data.table("ports")[id].get("gates", []))


## Days at sea from a gate (or an Atlantic port) to an Atlantic port (or a gate), for a ship this fast.
static func days(from: String, to: String, knots: float) -> int:
	var a := _where(from)
	var b := _where(to)
	var la := deg_to_rad(a.x)
	var lb := deg_to_rad(b.x)
	var c := acos(clampf(sin(la) * sin(lb) + cos(la) * cos(lb) * cos(deg_to_rad(b.y - a.y)), -1.0, 1.0))
	var nm := c * 3440.0 * float(cfg().detour)
	return maxi(int(cfg().min_days), ceili(nm / (maxf(knots, 1.0) * 24.0 * float(cfg().speed_share))))


## The gate a crossing from this Atlantic port back to the Caribbean is shortest by.
static func best_gate(port_id: String, knots: float) -> String:
	var best := ""
	for g in Data.table("ports")[port_id].gates:
		if best == "" or days(port_id, g, knots) < days(port_id, best, knots):
			best = g
	return best


## [lat, lon] of a gate or a port.
static func _where(id: String) -> Vector2:
	if cfg().gates.has(id):
		return Vector2(cfg().gates[id].lat, cfg().gates[id].lon)
	var p: Dictionary = Data.table("ports")[id]
	return Vector2(p.lat, p.lon)
