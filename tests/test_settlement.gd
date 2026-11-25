extends GutTest
## Your coves as places people live: a haven for the Brethren, settlers and their asks, supply runs; and rival bases.

var s: Dictionary
var a: String
var b: String


func before_each():
	Clock.day = 0.0
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	var coves: Array = Data.table("coves").keys().filter(func(id): return not id.begins_with("_") and not Maroons.is_landing(id))
	a = coves[0]
	b = coves[1]
	Bases.bases[a] = Bases._new_base(a, ["dock", "tavern"], 10.0, 60.0)
	Bases.bases[b] = Bases._new_base(b, ["dock"], 10.0, 60.0)


func after_each():
	Clock.day = 0.0
	Bases.reset()
	Economy.model.brethren.coves = []
	Factions.reset()


func test_a_haven_draws_the_brethren_and_pays():
	assert_ne(Settlement.haven_problem(b), "", "no tavern, no haven")
	Settlement.set_haven(a, true)
	assert_eq(Settlement.havens(), [a])
	var br: Brethren = Economy.model.brethren
	br.coves = Settlement.havens()
	for co in br.companies:
		co.away = false
	for i in 4:
		br.step(7 * (i + 1), 3, 1700)  # after Tortuga, before Nassau: no pirate port, so they all come to you
	assert_gt(Settlement.companies_at(a).size(), 0)
	var gold: float = Bases.bases[a].gold
	var vis: float = Bases.bases[a].visibility
	Settlement.daily(s)
	assert_gt(Bases.bases[a].gold, gold, "their trade pays")
	assert_gt(Bases.bases[a].visibility, vis, "and gives the cove away")
	assert_gt(Settlement.people_parts(Bases.bases[a], a).size(), 2, "people come to live off it")


func test_settlers_arrive_ask_and_remember():
	var base: Dictionary = Bases.bases[a]
	base.people = 200.0
	for i in 400:
		Settlement.daily(s)
		if not Settlement.settlers(base).is_empty() and not base.get("asks", []).is_empty():
			break
	assert_false(Settlement.settlers(base).is_empty(), "someone settles")
	assert_false(base.asks.is_empty(), "and asks for something")
	var who: String = base.asks[0].who
	var before: int = People.person(who).opinion
	Settlement.refuse(a, 0)
	assert_lt(People.person(who).opinion, before, "refused, they remember")


func test_a_supply_run_carries_goods_between_bases():
	assert_ne(Settlement.run_problem(a), "", "a run needs a ship laid up at the dock")
	Bases.bases[a].prizes.append({"type": "sloop", "name": "Runner"})
	Bases.bases[a].storage.food = 100.0
	Settlement.cfg().supply.loss = 0.0
	assert_string_contains(Settlement.start_run(a, b, "food"), "Every")
	Settlement.daily(s)
	assert_almost_eq(Bases.bases[a].storage.food, 70.0, 0.01)
	Clock.day += Settlement.days_between(a, b) + 1.0
	Settlement.daily(s)
	assert_gt(Bases.bases[b].storage.food, 0.0, "and it arrives")
	Settlement.cfg().supply.loss = 0.05


func test_rival_captains_make_bases_and_you_can_take_them():
	var cap: String = Bonds.roster().filter(func(x): return People.person(x).faction == "pirates")[0]
	People.person(cap).fame = 90
	RivalBases.cfg().found_chance = 1.0
	RivalBases.monthly(s)
	RivalBases.cfg().found_chance = 0.04
	var theirs: Array = Bases.rivals.keys().filter(func(id): return Bases.rivals[id].captain == cap)
	assert_eq(theirs.size(), 1, "one base each")
	assert_ne(Bases.claim_problem(s, theirs[0]), "", "not yours to claim")
	var gold: float = s.gold
	RivalBases.betray(s, theirs[0])
	assert_false(Bases.rivals.has(theirs[0]), "the navy burns it")
	assert_gt(s.gold, gold)
	assert_lt(Bonds.level(s, cap), 0, "and they know who told")
