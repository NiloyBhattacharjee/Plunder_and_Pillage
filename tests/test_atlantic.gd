extends GutTest
## Across the Atlantic: ports off the map, reached by passages through the gates, trading with the Caribbean.


func before_each():
	Clock.day = 0.0
	NewGame.build({"nationality": "english", "background": "ex_navy"})


func after_each():
	Clock.day = 0.0
	Factions.reset()


func test_ports_abroad_are_reached_through_gates():
	assert_true(Ports.abroad("london"))
	assert_false(Ports.abroad("port_royal"))
	assert_false("london" in Ports.home())
	assert_true("cape_coast" in Atlantic.reachable("east"), "Africa by the trade winds")
	assert_false("boston" in Atlantic.reachable("east"), "New England by the Gulf Stream")
	var d := Atlantic.days("east", "london", 10.0)
	assert_between(d, 25, 60, "five or six weeks to London for a fair sailer")
	assert_lt(Atlantic.days("north", "charles_town", 10.0), Atlantic.days("north", "london", 10.0))
	assert_eq(Atlantic.best_gate("boston", 10.0), "north")


func test_the_caribbean_s_wars_and_patrols_stay_in_the_caribbean():
	assert_false("london" in Contracts._ports_of("england"), "navies patrol from home ports on the map")
	assert_false(Factions._takeable("cape_coast", "england"))
	Factions.declare("england", "spain", "1800-01-01")
	assert_ne(Sieges.problem({}, "cadiz"), "")
	assert_eq(Politics.offices("london"), ["harbour_master", "merchant"], "no colonial governor in London")
	assert_eq(People.person(Politics.official("boston", "governor")).name, Ports.port("boston").governor)


func test_the_atlantic_trades_with_the_caribbean_only():
	var tr: Traffic = Economy.model.traffic
	for d in 60:
		Economy.model.step(3, 1716)
	var across := tr.voyages.filter(func(v): return Ports.abroad(v.origin) or Ports.abroad(v.dest))
	assert_gt(across.size(), 0, "ships cross the Atlantic")
	assert_false(across.any(func(v): return Ports.abroad(v.origin) and Ports.abroad(v.dest)), "Europe to Africa isn't this map's trade")
	assert_false(across.any(func(v): return not Ports.abroad(v.origin) and Ports.port(v.origin).size == "small"), "island sloops don't cross")
	assert_lt(Economy.model.mult("london", "cloth"), Economy.model.mult("port_royal", "cloth"), "cloth is cheap where it's made")
	assert_gt(Economy.model.mult("london", "sugar"), Economy.model.mult("bridgetown", "sugar"), "and sugar dear where it isn't grown")


func test_a_save_from_before_the_atlantic_still_loads():
	var ports := Ports.save_state().duplicate(true)
	var eco := Economy.model.save_state().duplicate(true)
	for id in Data.table("ports"):
		if Ports.abroad(id):  # as a save from 0.1 would be: no Atlantic anywhere
			ports.state.erase(id)
			eco.traffic.board.erase(id)
			for a in eco.traffic.board:
				eco.traffic.board[a].erase(id)
	Ports.load_state(ports)
	Economy.model.load_state(eco)
	assert_true(Ports.state.has("london"), "the new ports are there")
	for d in 30:
		Economy.model.step(3, 1716)
	assert_true(Economy.model.traffic.board.london.has("port_royal"), "and London trades")
