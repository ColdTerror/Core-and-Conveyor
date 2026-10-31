extends SceneTree

func _initialize():
	print("--- BEGIN REQUISITION CONTRACT SCHEDULING UNIT TEST ---")
	var qm = QuotaManager.new()
	var test_root = Node2D.new()
	test_root.name = "TestLevel"
	
	# Add mock TimeManager
	var tm = Node.new()
	tm.name = "TimeManager"
	tm.set("current_day", 3)
	test_root.add_child(tm)
	test_root.add_child(qm)
	
	qm.initialize(test_root)
	
	# Initial state on Day 3: Active Tier 1 Level 1
	assert(qm.active_tier == 1, "Expected active_tier == 1")
	assert(qm.active_level == 1, "Expected active_level == 1")
	assert(qm.queued_tier == -1, "Expected queued_tier == -1")
	assert(not qm.has_scheduled_contract(), "Expected has_scheduled_contract() to be false initially")
	
	# Test 1: Unlock Tier 2 for testing
	qm.unlocked_tiers.append(2)
	assert(qm.is_tier_unlocked(2), "Expected Tier 2 to be unlocked")
	
	# Test 2: Schedule Tier 2 Level 1 for tomorrow
	var sched_ok = qm.schedule_contract_for_tomorrow(2, 1)
	assert(sched_ok, "Expected schedule_contract_for_tomorrow to succeed")
	assert(qm.has_scheduled_contract(), "Expected has_scheduled_contract() to be true")
	assert(qm.active_tier == 1, "Active tier today must remain Tier 1")
	var sched_info = qm.get_scheduled_contract_info()
	assert(sched_info.get("tier") == 2, "Expected scheduled tier 2")
	assert(sched_info.get("level") == 1, "Expected scheduled level 1")
	print("✓ Test 1 & 2 passed: Schedule contract for tomorrow queues without changing today")
	
	# Test 3: Deliver items today for Tier 1
	qm.deliver_item("Wood", 10)
	assert(qm.daily_delivered.get("Wood", 0) == 10, "Expected 10 wood delivered today")
	assert(not qm.can_accept_item("Planks"), "Depot must NOT accept planks while Tier 1 is active today")
	print("✓ Test 3 passed: Today's active contract strictly governs item intake")
	
	# Test 4: Save & Load persistence of scheduled contract
	var saved_data = qm.get_save_data()
	assert(saved_data.get("queued_tier") == 2, "Saved data must contain queued_tier == 2")
	assert(saved_data.get("queued_level") == 1, "Saved data must contain queued_level == 1")
	
	var qm_loaded = QuotaManager.new()
	test_root.add_child(qm_loaded)
	qm_loaded.load_save_data(saved_data)
	assert(qm_loaded.queued_tier == 2, "Loaded qm must have queued_tier == 2")
	assert(qm_loaded.has_scheduled_contract(), "Loaded qm must have scheduled contract")
	print("✓ Test 4 passed: Save/Load preserves scheduled contract state")
	
	# Test 5: Midnight rollover executes the scheduled switch
	var announced_contract = ""
	var on_eval = func(day, rp, ratio, rep, leveled, unlocked, sched_name = ""):
		announced_contract = sched_name
	qm.daily_evaluation_completed.connect(on_eval)
	
	qm.process_end_of_day(3)
	assert(announced_contract != "", "Expected scheduled contract to be announced in daily_evaluation_completed")
	assert("Tier 2" in announced_contract, "Expected Tier 2 in announcement")
	
	# TimeManager advances day to 4 and calls start_next_day(4)
	qm.start_next_day(4)
	assert(qm.current_day == 4, "Expected current_day == 4")
	assert(qm.active_tier == 2, "Active tier must now be Tier 2 on Day 4")
	assert(qm.active_level == 1, "Active level must be 1 on Day 4")
	assert(qm.queued_tier == -1, "queued_tier must be reset to -1")
	assert(not qm.has_scheduled_contract(), "has_scheduled_contract() must be false after activation")
	assert(qm.daily_requirements.has("Planks"), "Day 4 must now require Planks")
	assert(qm.can_accept_item("Planks"), "Depot must now accept Planks on Day 4")
	assert(not qm.can_accept_item("Wood"), "Depot must NO LONGER accept Wood on Day 4")
	print("✓ Test 5 passed: Midnight transition cleanly activated scheduled contract and reset queue")
	
	# Test 6: Subsequent day auto-renews Tier 2 if nothing is scheduled
	qm.process_end_of_day(4)
	qm.start_next_day(5)
	assert(qm.active_tier == 2, "Day 5 must auto-renew Tier 2")
	assert(qm.daily_requirements.has("Planks"), "Day 5 requirements must still be Planks")
	print("✓ Test 6 passed: Auto-renew continues on subsequent days")
	
	# Test 7: Cancel scheduled switch
	qm.schedule_contract_for_tomorrow(1, 1)
	assert(qm.has_scheduled_contract(), "Expected scheduled contract to Tier 1")
	qm.cancel_scheduled_contract()
	assert(not qm.has_scheduled_contract(), "Expected schedule canceled")
	assert(qm.queued_tier == -1, "Expected queued_tier == -1")
	print("✓ Test 7 passed: Canceling scheduled switch restores auto-renewal")
	
	print("--- ALL 7 TESTS PASSED SUCCESSFULLY! ---")
	quit(0)
