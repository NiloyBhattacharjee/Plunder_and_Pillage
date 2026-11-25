extends GutTest
## The slave trade, shown in the world and never traded (docs/representation.md).

var s: Dictionary


func before_each():
	Clock.day = 0.0
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state


func after_each():
	Clock.day = 0.0
	Factions.reset()


func test_slavers_sail_from_the_forts_to_their_own_nation_s_plantations():
	var st: SlaveTrade = Economy.model.slavers
	var dests := st.destinations("cape_coast", 1700)
	assert_true("bridgetown" in dests)
	assert_false("cartagena" in dests, "no asiento for England before Utrecht")
	assert_true("cartagena" in st.destinations("cape_coast", 1716), "after it, the Spanish ports too")
	assert_eq(st.asiento(1705), "france")
	for d in 400:
		st.step(Economy.model.day + d, 1716)
	assert_gt(st.voyages.size() + st.next_id, 1, "ships sailed")


func test_people_are_never_cargo():
	var before: Dictionary = Economy.model.stock.duplicate(true)
	var st: SlaveTrade = Economy.model.slavers
	st._sail("cape_coast", "bridgetown", Economy.model.day)
	var v: Dictionary = st.voyages.back()
	assert_false(v.has("good") or v.has("qty"), "a voyage carries no goods and no count")
	assert_eq(Economy.model.stock, before, "and it moves nothing in any market")


func test_a_rising_is_news():
	var st: SlaveTrade = Economy.model.slavers
	st._sail("elmina", "bridgetown", Economy.model.day)
	st._rising(st.voyages.back())
	var ev := st.take_events()
	assert_eq(ev.size(), 1)
	assert_string_contains(ev[0].text, "rose")


func test_taking_a_slaver_leaves_the_choice_to_the_freed():
	var ctx := {"s": s, "stats": ShipStats.effective(s.type, s.upgrades), "port": "", "storm": false}
	var inst := Events.instance_of("slaver_taken", ctx, {"nation": "spain"})
	assert_false(inst.is_empty())
	var ev: Dictionary = Events.events.slaver_taken
	for ch in ev.choices:  # every stance takes the same plunder: none pays better for leaving them in the hold
		assert_true("gold +80" in ch.outcomes)
		assert_false(ch.outcomes.any(func(o): return o.begins_with("cargo")), "nobody is loaded or sold")
	var crew: Array = s.crew.duplicate()
	var res := Events.resolve(inst, 2, ctx)  # let her go
	assert_true(res.has("effects"))
	assert_eq(s.crew, crew)
