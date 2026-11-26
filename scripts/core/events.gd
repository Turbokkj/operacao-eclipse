extends Node
## Barramento global de sinais. Desacopla interface, partida, combate, IA e áudio.

signal loading_progress(value: float, message: String)
signal settings_changed
signal profile_changed
signal sound_emitted(pos: Vector3, radius: float, source: Node)
signal combatant_damaged(victim: Node, attacker: Node, amount: float, is_head: bool)
signal combatant_eliminated(victim: Node, killer: Node)
signal item_picked(item_id: String, who: Node)
signal zone_changed(center: Vector2, radius: float, next_center: Vector2, next_radius: float, shrinking: bool)
signal notify(text: String, kind: String)
signal hit_marker(is_kill: bool)
signal player_hurt(from_pos: Vector3)
signal match_ended(winner: Node)
