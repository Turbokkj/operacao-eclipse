class_name RemotePuppet
extends Combatant
## Representação de um jogador/bot controlado pela rede.
##  - No HOST (view_only = false): é o corpo do jogador humano remoto. Recebe posição/olhar do cliente, mas
##    VIDA, dano, armas, munição, loot e eliminação são decididos aqui (mesmas regras de todos).
##  - Nos CLIENTES (view_only = true): só visual; estado e animação vêm dos snapshots do host.

var view_only := true
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var target_pitch := 0.0
var net_vel := Vector3.ZERO
var net_aim := false
var is_human := false
var _has_state := false
var _tag: Label3D


func init_puppet(id: int, p_name: String, app: Dictionary, p_view_only: bool, human: bool) -> void:
	net_id = id
	display_name = p_name
	view_only = p_view_only
	is_human = human
	setup_body(app)
	collision_mask = L_WORLD
	if human:
		_tag = Label3D.new()
		_tag.text = p_name
		_tag.font_size = 40
		_tag.pixel_size = 0.0045
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag.modulate = Color(1.0, 0.85, 0.5)
		_tag.outline_size = 8
		_tag.position = Vector3(0, 2.15, 0)
		add_child(_tag)


func apply_state(pos: Vector3, yaw: float, pitch: float, vel: Vector3, crouch: bool, aim: bool) -> void:
	target_pos = pos
	target_yaw = yaw
	target_pitch = pitch
	net_vel = vel
	net_aim = aim
	_set_crouch_raw(crouch)
	if not _has_state:
		_has_state = true
		global_position = pos
		rotation.y = yaw


func _set_crouch_raw(c: bool) -> void:
	if c == crouching or capsule == null:
		return
	crouching = c
	capsule.height = 1.15 if c else 1.75
	col_shape.position.y = capsule.height * 0.5


func is_aiming() -> bool:
	return net_aim


func _control(delta: float) -> void:
	if not _has_state:
		return
	if global_position.distance_to(target_pos) > 10.0:
		global_position = target_pos
	else:
		global_position = global_position.lerp(target_pos, 1.0 - exp(-14.0 * delta))
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-14.0 * delta))
	velocity = net_vel
	aim_pitch = target_pitch


func take_damage(amount: float, attacker: Node, hit_pos: Vector3, head: bool) -> void:
	if view_only:
		return
	super.take_damage(amount, attacker, hit_pos, head)


func zone_damage(amount: float) -> void:
	if view_only:
		return
	super.zone_damage(amount)


func die(killer: Node) -> void:
	if not view_only:
		super.die(killer)
		return
	if not alive:
		return
	alive = false
	hp = 0.0
	collision_layer = 0
	collision_mask = L_WORLD
	model.animator.trigger("death")
	model.set_weapon("")
	AudioManager.play_sfx_3d("death", global_position + Vector3.UP, -2.0, 1.0, 50.0)
	if _tag != null:
		_tag.visible = false


func _on_died(_killer: Node) -> void:
	if _tag != null:
		_tag.visible = false
