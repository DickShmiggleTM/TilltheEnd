extends AbilityBase
## Rubber Rounds -- passive ability that stores a bounce count value.
## The weapon system reads this to make projectiles ricochet to additional
## enemies after hitting their primary target.

# -- State --------------------------------------------------------------------
## Number of times a projectile can bounce to a new target.
var bounce_count: int = 1

# -- Ability interface --------------------------------------------------------

func activate() -> void:
	_apply_level_stats()
	_sync_trait()


func deactivate() -> void:
	# Remove the trait so the weapon system stops bouncing.
	if GameManager.player_traits.has("bounce_count"):
		GameManager.player_traits.erase("bounce_count")


func _on_upgrade() -> void:
	_apply_level_stats()
	_sync_trait()


# -- Private ------------------------------------------------------------------

func _apply_level_stats() -> void:
	# Level 1 = 1 bounce, +1 per additional level.
	bounce_count = level


func _sync_trait() -> void:
	## Store in traits so the weapon system can query it.
	GameManager.player_traits["bounce_count"] = bounce_count
