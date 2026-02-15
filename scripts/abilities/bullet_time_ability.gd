extends AbilityBase
## Bullet Time -- doubles projectiles per shot. Stores a projectile_mult
## trait for the weapon system to read when determining pellet count.

# ── Tuning ────────────────────────────────────────────────────────────
var projectile_mult: float = 2.0

# ── Internal ──────────────────────────────────────────────────────────
var _applied_mult: float = 0.0


# ── Ability interface ─────────────────────────────────────────────────

func activate() -> void:
	_apply_level_stats()
	_apply_modifiers()


func _on_upgrade() -> void:
	_revert_modifiers()
	_apply_level_stats()
	_apply_modifiers()


func deactivate() -> void:
	_revert_modifiers()


# ── Private ───────────────────────────────────────────────────────────

func _apply_level_stats() -> void:
	projectile_mult = 2.0 + (level - 1) * 0.5


func _apply_modifiers() -> void:
	_applied_mult = projectile_mult
	if not GameManager.player_traits.has("projectile_mult"):
		GameManager.player_traits["projectile_mult"] = 1.0
	GameManager.player_traits["projectile_mult"] *= _applied_mult


func _revert_modifiers() -> void:
	if GameManager.player_traits.has("projectile_mult") and _applied_mult > 0.0:
		GameManager.player_traits["projectile_mult"] /= _applied_mult
	_applied_mult = 0.0
