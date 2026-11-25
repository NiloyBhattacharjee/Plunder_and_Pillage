class_name Settlement
## Your coves as places people live (data/settlement.json): a haven the Brethren use, the folk who settle by a
## base, the named settlers among them with their boons and their asks, and supply runs between your bases.
## State lives on the base (Bases.bases[id]), so it saves with it:
##   haven (bool), people (float), settlers [ids], asks [{who, ask, due}], loans [{who, gold, due}],
##   runs [{to, good, qty, every, next}], inbound [{from, good, qty, arrive}]
## Settlers are People with role "settler", a trade and an opinion of you (c.opinion, -100..100).


static func cfg() -> Dictionary:
	return Data.table("settlement")


# ---- a haven for the Brethren ------------------------------------------------------------

## Your coves open to the Brethren (they need a tavern; a town you hold is a port, not a haven of yours).
static func havens() -> Array:
	return Bases.bases.keys().filter(func(id): return Bases.bases[id].get("haven", false) and not Bases.bases[id].has("town") \
		and Bases.has(Bases.bases[id], cfg().haven.needs))


## The pirate companies working from this cove.
static func companies_at(id: String) -> Array:
	return Economy.model.brethren.companies.filter(func(co): return co.get("cove", "") == id and not co.away)


static func haven_problem(id: String) -> String:
	var b: Dictionary = Bases.bases[id]
	if b.has("town"):
		return "A town you hold is already open to whoever you let in."
	if not Bases.has(b, cfg().haven.needs):
		return "The Brethren want a %s before they'll call a place a haven." % Bases.building(cfg().haven.needs).name.to_lower()
	return ""


static func set_haven(id: String, on: bool) -> String:
	var b: Dictionary = Bases.bases[id]
	if on and haven_problem(id) != "":
		return haven_problem(id)
	b.haven = on
	return ("Word goes round the Brethren: %s is open to them, and asks no questions." if on else "You close %s to the Brethren. Some of them won't like it.") % b.name


# ---- the days ---------------------------------------------------------------------------

static func daily(s: Dictionary) -> Array:
	var out := []
	for id in Bases.bases.keys():
		var b: Dictionary = Bases.bases[id]
		if not b.has("town"):
			_haven_day(b, id, out)
			_people_day(b, id, s, out)
		_runs_day(b, id, out)
	return out


static func _haven_day(b: Dictionary, id: String, out: Array) -> void:
	var h: Dictionary = cfg().haven
	var cos := companies_at(id) if id in havens() else []
	var men: float = cos.reduce(func(a, co): return a + co.men, 0.0)
	b.gold += men * float(h.fee_per_man)
	b.recruits = minf(Bases.cfg().recruits_cap, b.recruits + cos.size() * float(h.recruits_per_company) + boon(b, "recruits"))
	b.visibility = clampf(b.visibility + cos.size() * float(h.visibility_per_company), 0.0, 100.0)
	if not cos.is_empty() and not b.get("haven_used", false):
		b.haven_used = true
		out.append("Sails in the cove at %s: %s and %s's men have come to sell their plunder and drink it. Your treasury takes its cut." % [b.name, cos[0].name, cos[0].captain])


## How many live by this base, and why: [[label, people]] the number drifts toward.
static func people_parts(b: Dictionary, id: String) -> Array:
	var p: Dictionary = cfg().people
	var parts := []
	for bid in b.buildings:
		if p.per_building.has(bid):
			parts.append([Bases.building(bid).name, float(p.per_building[bid])])
	var n := companies_at(id).size() if id in havens() else 0
	if n > 0:
		parts.append(["The Brethren's trade (%d compan%s)" % [n, "y" if n == 1 else "ies"], n * float(p.per_company)])
	return parts


static func _people_day(b: Dictionary, id: String, s: Dictionary, out: Array) -> void:
	var p: Dictionary = cfg().people
	var target := minf(float(p.cap), people_parts(b, id).reduce(func(a, x): return a + x[1], 0.0))
	b.people = lerpf(b.get("people", 0.0), target, float(p.drift))
	if b.storage.get("food", 0.0) <= 0.0 and b.garrison > 0:
		b.people *= 1.0 - float(p.hungry_leave)
	if b.get("raided", false):  # a raid empties the shanties
		b.people *= 1.0 - float(p.raid_leave)
		b.raided = false
	_settlers_day(b, id, s, out)


# ---- settlers -----------------------------------------------------------------------------

static func settlers(b: Dictionary) -> Array:
	return b.get("settlers", []).filter(func(cid): return People.chars.has(cid))


## A settler's boon to the base, if they think well of you: the sum for this kind ("recruits", "build", "price", "loyalty", "keel").
static func boon(b: Dictionary, kind: String) -> float:
	var amounts := {"recruits": 0.3, "build": 0.4, "price": 0.1, "loyalty": 6.0, "keel": 0.4}
	var total := 0.0
	for cid in settlers(b):
		var c := People.person(cid)
		if c.get("opinion", 0) >= 0 and cfg().settlers.trades[c.trade].boon == kind:
			total += amounts[kind]
	return total


static func _settlers_day(b: Dictionary, id: String, s: Dictionary, out: Array) -> void:
	var st: Dictionary = cfg().settlers
	b.settlers = settlers(b)
	b.asks = b.get("asks", []).filter(func(a): return a.who in b.settlers)
	var have: Array = b.settlers.map(func(cid): return People.person(cid).trade)
	if b.people >= float(st.needs_people) and b.settlers.size() < int(st.max) and Bases.rng.randf() < float(st.arrive_chance):
		var free: Array = st.trades.keys().filter(func(t): return not t in have)
		if not free.is_empty():
			var t: String = free[Bases.rng.randi() % free.size()]
			var c := People.generate({"mix": Data.rules.people.recruit_mix.pirates})
			c.role = "settler"
			c.trade = t
			c.base = id
			c.opinion = Bases.rng.randi_range(-5, 20)
			c.history.append("Settled at %s as its %s, %s." % [b.name, st.trades[t].name.to_lower(), Clock.date_string()])
			b.settlers.append(People.add(c))
			out.append("%s has come to live at %s, and sets up as its %s. %s, if you keep them sweet." % [c.name, b.name, st.trades[t].name.to_lower(), st.trades[t].boon_text])
	for cid in b.settlers.duplicate():
		var c := People.person(cid)
		if not b.asks.any(func(a): return a.who == cid) and Bases.rng.randf() < float(st.ask_chance):
			var options: Array = st.trades[c.trade].asks.filter(func(k): return _askable(b, id, k))
			if not options.is_empty():
				var k: String = options[Bases.rng.randi() % options.size()]
				b.asks.append({"who": cid, "ask": k, "due": Clock.day + float(cfg().asks[k].days)})
				out.append("%s, the %s at %s, %s." % [c.name, st.trades[c.trade].name.to_lower(), b.name, cfg().asks[k].text])
		if c.get("opinion", 0) <= int(st.leave_at):  # they go, and they talk
			b.settlers.erase(cid)
			b.visibility = clampf(b.visibility + float(st.talk_visibility), 0.0, 100.0)
			c.history.append("Left %s with a grudge, %s." % [b.name, Clock.date_string()])
			out.append("%s has left %s with a grudge, and is telling anyone who'll buy a drink how to find it." % [c.name, b.name])
	for a in b.asks.duplicate():
		var ask: Dictionary = cfg().asks[a.ask]
		if ask.has("building") and Bases.has(b, ask.building):
			out.append(_granted(b, a))
		elif Clock.day > a.due:
			out.append(_refused(b, a, "you never did it"))
	for l in b.get("loans", []).duplicate():
		if Clock.day >= l.due:
			b.loans.erase(l)
			var who := People.person(l.who) if People.chars.has(l.who) else {}
			if not who.is_empty() and l.who in b.settlers and who.get("opinion", 0) >= 0:
				b.gold += l.gold
				out.append("%s pays back the loan at %s: %d gold into the treasury." % [who.name, b.name, l.gold])
			else:
				out.append("The loan at %s will never be paid back." % b.name)


static func _askable(b: Dictionary, id: String, k: String) -> bool:
	var ask: Dictionary = cfg().asks[k]
	if ask.has("building"):
		return not Bases.has(b, ask.building)
	if ask.get("haven_off", false):
		return b.get("haven", false)
	return true


## Why you can't grant this now, or "".
static func grant_problem(b: Dictionary, i: int) -> String:
	var ask: Dictionary = cfg().asks[b.asks[i].ask]
	if ask.has("building"):
		return "Build a %s before the time's up." % Bases.building(ask.building).name.to_lower()
	if ask.has("gold") and b.gold < ask.gold:
		return "The treasury holds %d gold; this takes %d." % [b.gold, ask.gold]
	for g in ask.get("goods", {}):
		if b.storage.get(g, 0.0) < ask.goods[g]:
			return "The storehouse has %d %s; this takes %d." % [b.storage.get(g, 0.0), Data.table("goods")[g].name.to_lower(), ask.goods[g]]
	return ""


static func grant(id: String, i: int) -> String:
	var b: Dictionary = Bases.bases[id]
	var why := grant_problem(b, i)
	if why != "":
		return why
	var ask: Dictionary = cfg().asks[b.asks[i].ask]
	if ask.has("gold"):
		b.gold -= ask.gold
		b.loans = b.get("loans", [])
		b.loans.append({"who": b.asks[i].who, "gold": int(ask.gold * ask.repay), "due": Clock.day + float(ask.repay_days)})
	for g in ask.get("goods", {}):
		b.storage[g] -= ask.goods[g]
	if ask.get("haven_off", false):
		b.haven = false
	return _granted(b, b.asks[i])


static func refuse(id: String, i: int) -> String:
	var b: Dictionary = Bases.bases[id]
	return _refused(b, b.asks[i], "you said no")


static func _granted(b: Dictionary, a: Dictionary) -> String:
	b.asks.erase(a)
	var ask: Dictionary = cfg().asks[a.ask]
	var c := People.person(a.who)
	c.opinion = clampi(c.get("opinion", 0) + int(ask.opinion), -100, 100)
	b.loyalty = clampf(b.loyalty + float(ask.loyalty), 0.0, 100.0)
	return "%s at %s got what they asked for, and won't forget it (opinion %+d, loyalty %+d)." % [c.name, b.name, ask.opinion, ask.loyalty]


static func _refused(b: Dictionary, a: Dictionary, why: String) -> String:
	b.asks.erase(a)
	var r: Dictionary = cfg().refused
	var c := People.person(a.who)
	c.opinion = clampi(c.get("opinion", 0) + int(r.opinion), -100, 100)
	b.loyalty = clampf(b.loyalty + float(r.loyalty), 0.0, 100.0)
	return "%s at %s asked, and %s. They remember (opinion %+d, loyalty %+d)." % [c.name, b.name, why, r.opinion, r.loyalty]


# ---- supply runs between your bases -------------------------------------------------------

static func run_problem(id: String) -> String:
	var b: Dictionary = Bases.bases[id]
	if not Bases.has(b, "dock") and not b.has("town"):
		return "Runs need a dock to load at."
	if b.prizes.is_empty():
		return "Lay up a ship at the dock here to carry it."
	return ""


static func start_run(id: String, to: String, good: String) -> String:
	var why := run_problem(id)
	if why != "":
		return why
	var sp: Dictionary = cfg().supply
	var b: Dictionary = Bases.bases[id]
	b.runs = b.get("runs", [])
	b.runs.append({"to": to, "good": good, "qty": int(sp.qty), "every": float(sp.every_days), "next": Clock.day})
	return "Every %d days a ship will carry %d %s from %s to %s." % [sp.every_days, sp.qty, Data.table("goods")[good].name.to_lower(), b.name, Bases.bases[to].name]


static func stop_run(id: String, i: int) -> String:
	Bases.bases[id].runs.remove_at(i)
	return "The run is stopped."


static func days_between(a: String, b: String) -> float:
	return maxf(1.0, Bases.cove_pos(a).distance_to(Bases.cove_pos(b)) / Geo.px_per_nm() / float(cfg().supply.nm_per_day))


static func _runs_day(b: Dictionary, id: String, out: Array) -> void:
	for r in b.get("runs", []).duplicate():
		if not Bases.bases.has(r.to):
			b.runs.erase(r)
			continue
		if Clock.day < r.next:
			continue
		r.next = Clock.day + r.every
		var qty := minf(float(r.qty), b.storage.get(r.good, 0.0))
		if qty < 1.0 or run_problem(id) != "":
			continue
		b.storage[r.good] -= qty
		if Bases.rng.randf() < float(cfg().supply.loss):
			out.append("The ship carrying %d %s from %s to %s never arrived." % [qty, Data.table("goods")[r.good].name.to_lower(), b.name, Bases.bases[r.to].name])
			continue
		var dest: Dictionary = Bases.bases[r.to]
		dest.inbound = dest.get("inbound", [])
		dest.inbound.append({"from": id, "good": r.good, "qty": qty, "arrive": Clock.day + days_between(id, r.to)})
	for x in b.get("inbound", []).duplicate():
		if Clock.day >= x.arrive:
			b.inbound.erase(x)
			var room := maxf(0.0, Bases.capacity(b) - Bases.stored(b)) / maxf(0.01, Market.weight(x.good))
			b.storage[x.good] = b.storage.get(x.good, 0.0) + minf(x.qty, room)
