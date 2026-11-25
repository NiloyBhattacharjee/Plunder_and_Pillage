class_name RivalBases
## Bases the named pirate captains make for themselves (data/settlement.json "rivals"), kept in Bases.rivals.
## A pirate captain whose name has grown sets up in an unclaimed cove; it grows each month while they live, and the
## navy may find and burn it, the more readily the hotter the waters. You find one as you find any cove; there,
## an ally gives you rest and water, and anyone else's can be raided, or sold to a governor.


static func cfg() -> Dictionary:
	return Data.table("settlement").rivals


static func at(id: String) -> Dictionary:
	return Bases.rivals.get(id, {})


## Once a month: founding, growing, and the navy's visits. Returns news worth telling.
static func monthly(s: Dictionary) -> Array:
	var c := cfg()
	var out := []
	var rng: RandomNumberGenerator = Bases.rng
	for id in Bases.rivals.keys():
		var r: Dictionary = Bases.rivals[id]
		var cap := People.person(r.captain) if People.chars.has(r.captain) else {}
		if cap.is_empty() or not cap.get("alive", true):
			Bases.rivals.erase(id)
			continue
		r.garrison = mini(int(c.garrison_max), r.garrison + int(c.garrison_growth))
		r.gold += cap.get("fame", 0) * float(c.gold_per_fame)
		if r.fort < int(c.fort_max) and r.gold >= float(c.fort_cost):
			r.gold -= float(c.fort_cost)
			r.fort += 1
		var g := Politics.ground_of(Bases.nearest_port(id))
		var heat: float = Economy.model.brethren.heat.get(g, 0.0) if g != "" else 0.0
		if rng.randf() < float(c.burn_chance) * (1.0 + heat * float(c.burn_per_heat)):
			Bases.rivals.erase(id)
			cap.history.append("Lost their base at %s to the navy, %s." % [Bases.cove(id).name, Clock.date_string()])
			if id in Bases.discovered:
				out.append("The navy has found %s's base at %s and burned it." % [cap.name, Bases.cove(id).name])
	var housed: Array = Bases.rivals.values().map(func(x): return x.captain)
	for cid in Bonds.roster().filter(func(x): return People.person(x).get("faction", "") == "pirates" and not x in housed):
		var cap := People.person(cid)
		if cap.get("fame", 0) < int(c.found_fame) or rng.randf() >= float(c.found_chance):
			continue
		var free: Array = Data.table("coves").keys().filter(func(id): return not id.begins_with("_") and not Bases.bases.has(id) and not Bases.rivals.has(id) and not Maroons.is_landing(id))
		if free.is_empty():
			break
		var id: String = free[rng.randi() % free.size()]
		Bases.rivals[id] = {"captain": cid, "since": Clock.day, "garrison": int(c.garrison_start), "gold": float(c.gold_start), "fort": 0}
		cap.history.append("Made a base at %s, %s." % [Bases.cove(id).name, Clock.date_string()])
		Economy.add_news("Talk in the havens: %s has made a base of their own somewhere near %s." % [cap.name, Ports.port(Bases.nearest_port(id)).name], Bases.nearest_port(id))
	return out


## The rival's defence ashore, for a raid: [[label, amount]].
static func defence_parts(id: String) -> Array:
	var r := at(id)
	var cap := People.person(r.captain)
	return [["%d men ashore" % r.garrison, int(r.garrison / float(cfg().men_per_point))], ["Guns on the point", r.fort * int(cfg().fort_strength)],
		["%s's name" % cap.name, int(cap.get("fame", 0) / 20)]]


static func raid_parts(s: Dictionary) -> Array:
	var cap := ShipStats.captain(s)
	return [["%d men landing" % Crew.able(s), int(Crew.able(s) / float(cfg().men_per_point))], ["Your swordplay", Dice.mod(People.value(cap, "swordplay"))]]


## You land and take it. Win: their gold and stores, a burned base, an enemy for life. Lose: men and a feud.
static func raid(s: Dictionary, id: String) -> String:
	var r := at(id)
	var cap := People.person(r.captain)
	var check := Dice.contest(Bases.rng, "Storm %s's base" % cap.name, raid_parts(s), defence_parts(id))
	var c := cfg()
	if check.success:
		var gold := int(r.gold)
		s.gold += gold
		Bases.rivals.erase(id)
		cap.history.append("Lost their base at %s to %s, %s." % [Bases.cove(id).name, ShipStats.captain(s).name, Clock.date_string()])
		var feud := Bonds.start_rivalry(s, r.captain, int(c.raid_rivalry), "you burned their base")
		return "You carry the stockade at the second rush. %d gold from %s's strongbox, and their huts burn behind you. %s" % [gold, cap.name, feud]
	var lost := mini(int(c.raid_losses), Crew.able(s) - 1)
	for i in lost:
		var hands: Array = s.crew.filter(func(x): return not x in s.officers.values())
		if not hands.is_empty():
			Crew.remove_hand(s, hands.pick_random())
	var feud := Bonds.start_rivalry(s, r.captain, 1, "you raided their base")
	return "Beaten back from the stockade, %d men left on the beach. %s will remember. %s" % [lost, cap.name, feud]


## You sell the way in to a governor of a nation that hangs pirates: gold now, a burned base, and the Brethren know.
static func betray(s: Dictionary, id: String) -> String:
	var r := at(id)
	var cap := People.person(r.captain)
	var c := cfg()
	s.gold += int(c.sell_gold)
	s.relations.pirates = s.relations.get("pirates", 0) - int(c.sell_pirates)
	Bases.rivals.erase(id)
	cap.history.append("Their base at %s was burned by the navy, sold by %s, %s." % [Bases.cove(id).name, ShipStats.captain(s).name, Clock.date_string()])
	var feud := Bonds.start_rivalry(s, r.captain, int(c.sell_rivalry), "you sold their base to the navy")
	return "The governor's men pay %d gold for the way in. A month later the navy burns %s's base, and the havens learn who told (standing with the Brethren -%d). %s" % [c.sell_gold, cap.name, c.sell_pirates, feud]
