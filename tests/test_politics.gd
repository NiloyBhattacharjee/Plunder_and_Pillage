extends GutTest

var s: Dictionary
var ctx: Dictionary


func before_each():
	Clock.day = 0.0
	Politics.rng.seed = 2
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	ctx = {"s": s, "stats": ShipStats.effective(s.type, s.upgrades), "port": "port_royal", "storm": false}


func after_each():
	Clock.day = 0.0
	Factions.reset()


func test_ports_are_run_by_people():
	var gov := Politics.official("port_royal", "governor")
	assert_eq(People.person(gov).name, Ports.port("port_royal").governor)
	assert_eq(Politics.official("port_royal", "governor"), gov, "the same person until replaced")
	assert_true("goal" in People.person(gov))
	assert_eq(Politics.official("nassau", "governor"), "", "no governor in a pirate haven")
	assert_ne(Politics.official("nassau", "broker"), "")
	assert_gt(Politics.offices("havana").size(), Politics.offices("basseterre").size(), "small colonies have fewer offices")


func test_interest_groups_set_the_laws():
	var p := Politics.power("havana")
	var total := 0.0
	for g in p:
		total += p[g]
	assert_almost_eq(total, 100.0, 0.01)
	var before: float = Ports.state.havana.laws.pirates
	Politics.shift("havana", "poor", 300.0)
	assert_eq(Politics.dominant("havana"), "poor")
	assert_gt(Ports.state.havana.laws.pirates, before, "the townsfolk welcome pirates")
	assert_gt(Ports.state.havana.laws.pirates, 0.4)
	s.career.pirate = true
	s.reputation.notoriety = 100
	assert_true(Career.port_access(s, "havana").open, "a pirates' town lets you in, wanted or not")
	Politics.shift("havana", "military", 2000.0)
	assert_false(Career.port_access(s, "havana").open)


func test_tariffs_change_prices():
	Ports.state.port_royal.laws.tariff = 0.0
	var before := Ports.price("port_royal", "sugar", true)
	Ports.state.port_royal.laws.tariff = 0.2
	var duty: float = Data.table("economy").duty.england
	assert_almost_eq(Ports.price("port_royal", "sugar", true), before * (1.2 + duty) / (1.0 + duty), 0.01, "the tariff is a duty on top")
	Ports.state.port_royal.laws.contraband = ["sugar"]
	assert_lt(Ports.price("port_royal", "sugar", true), before, "smugglers pay no duty")
	Ports.state.port_royal.laws.contraband = []


func test_favours_are_earned_spent_and_owed():
	var hm := Politics.official("port_royal", "harbour_master")
	assert_string_contains(Politics.favour_problem(hm, s, "blind_eye", false), "owes you")
	Politics.add_favours(hm, s, 1)
	var text := Politics.use_favour(hm, s, "blind_eye", ctx)
	assert_string_contains(text, "open to you")
	assert_eq(Politics.favours(hm, s), 0)
	s.career.pirate = true
	s.reputation.notoriety = 100
	assert_true(Career.port_access(s, "port_royal").open, "the harbour master looks the other way")
	var merchant := Politics.official("port_royal", "merchant")
	Politics.use_favour(merchant, s, "market_tip", ctx, true)
	assert_eq(Politics.favours(merchant, s), -1, "asked on credit: you owe them now")
	assert_has(Politics.creditors(s), merchant)


func test_a_new_captain_has_no_favours():
	var gov := Politics.official("port_royal", "governor")
	Politics.add_favours(gov, s, 3)
	Crew.captain_dies(s, "fell in battle")
	Crew.make_captain(s, s.crew[0], "command")
	assert_eq(Politics.favours(gov, s), 0, "the governor dealt with the old captain")


func test_secrets_blackmail_sell_and_expose():
	var gov := Politics.official("port_royal", "governor")
	Politics.gain_secret(s, "letters", gov)
	var sec: Dictionary = s.secrets[0]
	assert_string_contains(Politics.describe(sec), People.person(gov).name)
	Politics.blackmail(s, sec)
	assert_eq(Politics.favours(gov, s), 2)
	assert_lt(People.person(gov).relations[s.captain], -20, "blackmail makes an enemy")
	assert_has(Politics.enemies(s), gov)
	Politics.leverage_month(s)
	assert_eq(Politics.favours(gov, s), 3, "and pays every month")
	var gold: float = s.gold
	Politics.sell(s, sec)
	assert_gt(s.gold, gold)
	assert_true(s.secrets.is_empty())
	Politics.gain_secret(s, "bribes", Politics.official("port_royal", "commander"))
	var before: int = s.relations.england
	Politics.expose(s, s.secrets[0])
	assert_gt(s.relations.england, before)
	assert_ne(Politics.official("port_royal", "commander"), sec.about, "recalled and replaced")


func test_forgeries_backfire():
	var gov := Politics.official("port_royal", "governor")
	Politics.gain_secret(s, "letters", gov, true)
	var text := Politics.blackmail(s, s.secrets[0])
	assert_string_contains(text, "forgeries")
	assert_eq(Politics.favours(gov, s), 0)


func test_schedules_go_stale():
	Politics.gain_secret(s, "schedule", Politics.official("port_royal", "merchant"))
	Clock.day = 100.0
	Politics.prune_secrets(s)
	assert_true(s.secrets.is_empty())


func test_political_jobs_shift_power_and_pay_favours():
	Contracts.reset()
	var emp := Politics.official("port_royal", "priest")
	var c := Contracts.make("alms_voyage", emp, s)
	c.lied = false
	Contracts.accept(c, s)
	c.status = "done"
	var before: float = Politics.power("port_royal").church
	Contracts.collect(c, s)
	assert_gt(Politics.power("port_royal").church, before)
	assert_eq(Politics.favours(emp, s), 1)


func test_the_council_votes_and_can_be_won():
	var members := Politics.council_members()
	assert_eq(members.size(), 5)
	assert_eq(Politics.council_leader, members[0])
	s.council_member = true
	for id in members:
		People.person(id).relations[s.captain] = 90
	var r := Politics.council_vote(s, "defend", true, ctx)
	assert_true(r.passed, "friends vote your way")
	for id in members:
		People.person(id).relations[s.captain] = -90
	assert_false(Politics.council_vote(s, "defend", true, ctx).passed)
	for id in members:
		People.person(id).relations[s.captain] = 90
		People.person(id).relations[Politics.council_leader] = -50
	Politics.leadership_vote(s)
	assert_eq(Politics.council_leader, "player")


func test_officials_change_over_time():
	var gov := Politics.official("havana", "governor")
	Politics.replace("havana", "governor", "died of fever")
	var now := Politics.official("havana", "governor")
	assert_ne(now, gov)
	assert_true(People.chars.has(gov), "the old governor is still remembered")
	assert_eq(People.person(gov).port, "")


# ---- minds ----------------------------------------------------------------------------

func test_hot_waters_turn_a_quiet_governor_who_then_acts_and_rests():
	Politics.reset()
	var b: Brethren = Economy.model.brethren
	var heat_was: float = b.heat.windward_passage
	for id in Politics.officials_at("port_royal"):  # only the governor is free to change their mind
		People.person(id).goal = "keep_order"
		People.person(id).traits = ["corrupt"]
	var gov := People.person(Politics.official("port_royal", "governor"))
	gov.traits = []
	gov.relations[s.captain] = 0
	b.heat.windward_passage = 20.0
	var pressure: float = b.pressure.get("england", 0.0)
	var news := Politics.think_month(s)
	assert_eq(gov.goal, "crush_piracy", "the prizes taken off their coast change what they want")
	assert_gt(b.pressure.england, pressure, "they write home for men-of-war")
	assert_true(news.any(func(t): return gov.name in t), "and it's news")
	assert_string_contains(gov.mind, "men-of-war", "the why shows on their tooltip")
	assert_false(Politics.think_month(s).any(func(t): return gov.name in t), "then they rest a while")
	b.heat.windward_passage = heat_was
	Politics.reset()


func test_a_grudge_becomes_a_price_on_your_head():
	Politics.reset()
	s.career.pirate = true
	var cmd := People.person(Politics.official("havana", "commander"))
	cmd.relations[s.captain] = -60
	Politics.think_month(s)
	assert_eq(cmd.goal, "revenge")
	assert_gt(s.get("bounty", {}).get("spain", 0.0), 0.0, "hatred is reason enough")
	Politics.reset()


func test_an_ambitious_governor_picks_the_war_target_near_home():
	Politics.reset()
	Factions.declare("england", "spain", "1800-01-01")
	Factions.invasions = []
	var gov := People.person(Politics.official("port_royal", "governor"))
	gov.goal = "promotion"
	gov.relations[s.captain] = 0
	Politics.think_month(s)
	var x: Array = Factions.invasions.filter(func(i): return i.by == "england")
	assert_eq(x.size(), 1, "one squadron, not one per official")
	assert_eq(Ports.port(x[0].port).faction, "spain")
	Politics.reset()
