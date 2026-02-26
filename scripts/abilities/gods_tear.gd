extends AbilityBase
## God's Tear -- revive on death if the player has killed enough enemies
## since acquiring the ability. Kill requirement doubles after each use.

# ── Tuning ────────────────────────────────────────────────────────────
var base_kill_requirement: int = 75
var kill_requirement: int = 75

# ── Internal ──────────────────────────────────────────────────────────
var kills_since_acquired: int = 0
var times_used: int = 0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	EventBus.enemy_killed.connect(_on_enemy_killed)
	EventBus.player_died.connect(_on_player_died)


func deactivate() -> void:
	if EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.disconnect(_on_enemy_killed)
	if EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.disconnect(_on_player_died)


func _on_upgrade() -> void:
	# Each level lowers the base requirement slightly
	base_kill_requirement = maxi(75 - (level - 1) * 10, 25)
	kill_requirement = base_kill_requirement * int(pow(2, times_used))


# ── Signal callbacks ─────────────────────────────────────────────────

func _on_enemy_killed(_enemy: Node3D, _position: Vector3) -> void:
	kills_since_acquired += 1


func _on_player_died() -> void:
	if kills_since_acquired >= kill_requirement:
		kills_since_acquired = 0
		times_used += 1
		kill_requirement = base_kill_requirement * int(pow(2, times_used))

		# Revive the player using the dedicated revive() method,
		# which restores _alive, collision, processing, and health.
		if player and is_instance_valid(player) and player.has_method("revive"):
			player.revive()
