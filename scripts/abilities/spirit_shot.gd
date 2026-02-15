extends AbilityBase
## Spirit Shot -- passive ability that stores a pierce count value.
## The weapon system reads this to allow projectiles to pass through
## and damage multiple enemies in a line.

# -- State --------------------------------------------------------------------
## Number of additional enemies a projectile can pierce through.
var pierce_count: int = 1

# -- Ability interface --------------------------------------------------------

func activate() -> void:
	_apply_level_stats()
	_sync_trait()


func deactivate() -> void:
	# Remove the trait so the weapon system stops piercing.
	if GameManager.player_traits.has("pierce_count"):
		GameManager.player_traits.erase("pierce_count")


func _on_upgrade() -> void:
	_apply_level_stats()
	_sync_trait()


# -- Private ------------------------------------------------------------------

func _apply_level_stats() -> void:
	# Level 1 = 1 pierce, +1 per additional level.
	pierce_count = level


func _sync_trait() -> void:
	## Store in traits so the weapon system can query it.
	GameManager.player_traits["pierce_count"] = pierce_count
