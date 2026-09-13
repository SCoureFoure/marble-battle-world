extends SceneTree

func _init() -> void:
	var durations: PackedFloat32Array = []
	var mean_speeds: PackedFloat32Array = []
	var mean_spins: PackedFloat32Array = []
	var contact_fracs: PackedFloat32Array = []
	var hits_per_s_list: PackedFloat32Array = []
	var bumps_per_s_list: PackedFloat32Array = []
	var boosts_per_s_list: PackedFloat32Array = []
	var march_speeds: PackedFloat32Array = []
	var crowds: PackedFloat32Array = []
	var mean_attackers_list: PackedFloat32Array = []
	var pile_fracs: PackedFloat32Array = []
	var winners_count := 0

	for seed in range(1, 6):
		var s := BattleState.new(400, seed)
		var g := TerrainGrid.new()
		g.setup(s.arena, Tuning.TERRAIN_CELL)
		TerrainGen.demo(g, s.rng)

		s.spawn_block(0, 150, Rect2(100, 100, 500, 700), -1)
		s.spawn_block(1, 150, Rect2(1000, 100, 500, 700), -1)

		var sim := BattleSim.new(s)
		sim.set_terrain(g)

		var max_ticks := int(Tuning.T_MAX_BATTLE / Tuning.DT)
		var tick_count := 0

		var sample_speeds: PackedFloat32Array = []
		var sample_spins: PackedFloat32Array = []
		var sample_contact_fracs: PackedFloat32Array = []
		var sample_march_speeds: PackedFloat32Array = []
		var sample_crowds: PackedFloat32Array = []
		var sample_mean_attackers: PackedFloat32Array = []
		var sample_pile_fracs: PackedFloat32Array = []
		var event_count_0 := 0  # HIT
		var event_count_5 := 0  # BUMP
		var event_count_6 := 0  # BOOST

		while tick_count < max_ticks and sim.winner(s) == -1:
			sim.step(s, Tuning.DT)
			tick_count += 1

			# Count events by type
			for ev in s.events:
				var ev_type: int = ev[0]
				if ev_type == 0:
					event_count_0 += 1
				elif ev_type == 5:
					event_count_5 += 1
				elif ev_type == 6:
					event_count_6 += 1

			# Sample every 30 ticks
			if tick_count % 30 == 0:
				var live_count := 0
				var sum_speed := 0.0
				var sum_spin := 0.0

				for i in range(s.n):
					if s.state[i] == 0:  # ENGAGE
						var speed = sqrt(s.vx[i] * s.vx[i] + s.vy[i] * s.vy[i])
						sum_speed += speed
						sum_spin += s.spin[i]
						live_count += 1

				if live_count > 0:
					sample_speeds.append(sum_speed / live_count)
					sample_spins.append(sum_spin / live_count)

					# contact_frac: O(n^2) brute force check
					var contact_count := 0
					for i in range(s.n):
						if s.state[i] == 0:  # ENGAGE
							var has_contact := false
							for j in range(s.n):
								if i != j and s.state[j] == 0 and s.faction_id[i] != s.faction_id[j]:
									var dx = s.px[j] - s.px[i]
									var dy = s.py[j] - s.py[i]
									var dist = sqrt(dx * dx + dy * dy)
									if dist < s.radius[i] + s.radius[j] + 1.0:
										has_contact = true
										break
							if has_contact:
								contact_count += 1

					sample_contact_fracs.append(float(contact_count) / float(live_count))

					# march_speed: mean speed of ENGAGE marbles with target_id == -1
					var march_speed_sum := 0.0
					var march_speed_count := 0
					for i in range(s.n):
						if s.state[i] == 0 and s.target_id[i] == -1:  # ENGAGE with no target
							var speed = sqrt(s.vx[i] * s.vx[i] + s.vy[i] * s.vy[i])
							march_speed_sum += speed
							march_speed_count += 1

					if march_speed_count > 0:
						sample_march_speeds.append(march_speed_sum / march_speed_count)

					# crowd: mean number of other live marbles within 3.0 * r_i
					var crowd_sum := 0.0
					var crowd_count := 0
					for i in range(s.n):
						if s.state[i] == 0:  # ENGAGE
							var nearby_count := 0
							var crowd_radius = 3.0 * s.radius[i]
							for j in range(s.n):
								if i != j and s.state[j] != 2:  # other and not DEAD
									var dx = s.px[j] - s.px[i]
									var dy = s.py[j] - s.py[i]
									var dist = sqrt(dx * dx + dy * dy)
									if dist < crowd_radius:
										nearby_count += 1
							crowd_sum += nearby_count
							crowd_count += 1

					if crowd_count > 0:
						sample_crowds.append(crowd_sum / crowd_count)

					# mean_attackers and pile_frac: count attackers per marble from target_id
					var attacker_counts: PackedInt32Array = []
					attacker_counts.resize(s.n)
					attacker_counts.fill(0)

					for i in range(s.n):
						if s.state[i] == 0 and s.target_id[i] >= 0:  # ENGAGE with a target
							var target = s.target_id[i]
							if target >= 0 and target < s.n:
								attacker_counts[target] += 1

					var targeted_sum := 0
					var targeted_count := 0
					var pile_count := 0
					for i in range(s.n):
						if s.state[i] != 2:  # not DEAD
							var count = attacker_counts[i]
							if count > 0:
								targeted_sum += count
								targeted_count += 1
								if count > 2:
									pile_count += 1

					if targeted_count > 0:
						sample_mean_attackers.append(float(targeted_sum) / float(targeted_count))
						sample_pile_fracs.append(float(pile_count) / float(targeted_count))

		var duration = s.time
		var winner = sim.winner(s)
		if winner == -1:
			winner = -2
		else:
			winners_count += 1

		# Calculate metrics for this seed
		var mean_speed := 0.0
		if sample_speeds.size() > 0:
			for speed in sample_speeds:
				mean_speed += speed
			mean_speed /= sample_speeds.size()

		var mean_spin := 0.0
		if sample_spins.size() > 0:
			for spin in sample_spins:
				mean_spin += spin
			mean_spin /= sample_spins.size()

		var mean_contact_frac := 0.0
		if sample_contact_fracs.size() > 0:
			for frac in sample_contact_fracs:
				mean_contact_frac += frac
			mean_contact_frac /= sample_contact_fracs.size()

		var mean_march_speed := 0.0
		if sample_march_speeds.size() > 0:
			for speed in sample_march_speeds:
				mean_march_speed += speed
			mean_march_speed /= sample_march_speeds.size()

		var mean_crowd := 0.0
		if sample_crowds.size() > 0:
			for crowd in sample_crowds:
				mean_crowd += crowd
			mean_crowd /= sample_crowds.size()

		var mean_attackers_avg := 0.0
		if sample_mean_attackers.size() > 0:
			for att in sample_mean_attackers:
				mean_attackers_avg += att
			mean_attackers_avg /= sample_mean_attackers.size()

		var mean_pile_frac := 0.0
		if sample_pile_fracs.size() > 0:
			for frac in sample_pile_fracs:
				mean_pile_frac += frac
			mean_pile_frac /= sample_pile_fracs.size()

		var hits_per_s = float(event_count_0) / duration if duration > 0.0 else 0.0
		var bumps_per_s = float(event_count_5) / duration if duration > 0.0 else 0.0
		var boosts_per_s = float(event_count_6) / duration if duration > 0.0 else 0.0

		print("SEED=%d winner=%d duration=%.1f mean_speed=%.1f contact_frac=%.3f hits_per_s=%.1f bumps_per_s=%.1f boosts_per_s=%.1f mean_spin=%.1f march_speed=%.1f crowd=%.2f mean_attackers=%.2f pile_frac=%.3f" % [seed, winner, duration, mean_speed, mean_contact_frac, hits_per_s, bumps_per_s, boosts_per_s, mean_spin, mean_march_speed, mean_crowd, mean_attackers_avg, mean_pile_frac])

		durations.append(duration)
		mean_speeds.append(mean_speed)
		mean_spins.append(mean_spin)
		contact_fracs.append(mean_contact_frac)
		hits_per_s_list.append(hits_per_s)
		bumps_per_s_list.append(bumps_per_s)
		boosts_per_s_list.append(boosts_per_s)
		march_speeds.append(mean_march_speed)
		crowds.append(mean_crowd)
		mean_attackers_list.append(mean_attackers_avg)
		pile_fracs.append(mean_pile_frac)

	# Calculate averages for SUMMARY
	var avg_duration := 0.0
	var avg_mean_speed := 0.0
	var avg_mean_spin := 0.0
	var avg_contact_frac := 0.0
	var avg_hits_per_s := 0.0
	var avg_bumps_per_s := 0.0
	var avg_boosts_per_s := 0.0
	var avg_march_speed := 0.0
	var avg_crowd := 0.0
	var avg_mean_attackers := 0.0
	var avg_pile_frac := 0.0

	for d in durations:
		avg_duration += d
	avg_duration /= durations.size()

	for s in mean_speeds:
		avg_mean_speed += s
	avg_mean_speed /= mean_speeds.size()

	for s in mean_spins:
		avg_mean_spin += s
	avg_mean_spin /= mean_spins.size()

	for c in contact_fracs:
		avg_contact_frac += c
	avg_contact_frac /= contact_fracs.size()

	for h in hits_per_s_list:
		avg_hits_per_s += h
	avg_hits_per_s /= hits_per_s_list.size()

	for b in bumps_per_s_list:
		avg_bumps_per_s += b
	avg_bumps_per_s /= bumps_per_s_list.size()

	for b in boosts_per_s_list:
		avg_boosts_per_s += b
	avg_boosts_per_s /= boosts_per_s_list.size()

	for m in march_speeds:
		avg_march_speed += m
	avg_march_speed /= march_speeds.size()

	for c in crowds:
		avg_crowd += c
	avg_crowd /= crowds.size()

	for a in mean_attackers_list:
		avg_mean_attackers += a
	avg_mean_attackers /= mean_attackers_list.size()

	for p in pile_fracs:
		avg_pile_frac += p
	avg_pile_frac /= pile_fracs.size()

	print("SUMMARY duration=%.1f mean_speed=%.1f contact_frac=%.3f hits_per_s=%.1f bumps_per_s=%.1f boosts_per_s=%.1f mean_spin=%.1f march_speed=%.1f crowd=%.2f mean_attackers=%.2f pile_frac=%.3f winners=%d/5" % [avg_duration, avg_mean_speed, avg_contact_frac, avg_hits_per_s, avg_bumps_per_s, avg_boosts_per_s, avg_mean_spin, avg_march_speed, avg_crowd, avg_mean_attackers, avg_pile_frac, winners_count])

	quit()
