extends AbilityBase
## Uplift -- grants extra mid-air jumps. The player's movement code should
## check this ability's `extra_jumps` and `jumps_remaining` to allow
## additional jumps while airborne.

# ── Tuning ────────────────────────────────────────────────────────────
var extra_jumps: int = 1

# ── Internal ──────────────────────────────────────────────────────────
var jumps_remaining: int = 0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	jumps_remaining = extra_jumps


func deactivate() -> void:
	extra_jumps = 0
	jumps_remaining = 0


func _on_upgrade() -> void:
	_apply_level_stats()
	jumps_remaining = extra_jumps


# ── Public API (called by player movement code) ──────────────────────

## Returns true if the player can perform an extra jump and consumes one.
func try_extra_jump() -> bool:
	if jumps_remaining > 0:
		jumps_remaining -= 1
		return true
	return false


## Call when the player lands on the ground to reset available jumps.
func reset_jumps() -> void:
	jumps_remaining = extra_jumps


# ── Private ──────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	extra_jumps = 1 + (level - 1)  # +1 jump per level
