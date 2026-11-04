extends RefCounted
## 怪物共用的体积通行检查；移动前扫过整段，不能只检查中心射线。
enum Temperament { DANGEROUS, NEUTRAL, TIMID }

var owner: Node3D
var bounds: AABB
var shape := BoxShape3D.new()
var excluded: Array[RID] = []


func _init(node: Node3D, player: CollisionObject3D, box: AABB) -> void:
	owner = node
	bounds = box
	shape.size = box.size
	excluded = [player.get_rid()]


func _query(at: Transform3D) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(at.basis, at * bounds.get_center())
	query.exclude = excluded
	query.margin = 0.01
	return query


func fits(at: Vector3, basis := Basis.IDENTITY) -> bool:
	return owner.get_world_3d().direct_space_state.intersect_shape(_query(Transform3D(basis, at)), 1).is_empty()


func can_move(from: Transform3D, to: Transform3D) -> bool:
	var query := _query(from)
	var angle := from.basis.get_rotation_quaternion().angle_to(to.basis.get_rotation_quaternion())
	if angle > 0.0001:
		# 转弯时包住身体外缘的旋转弧，不能在两个合法朝向之间扫穿墙角。
		var reach := Vector2(maxf(absf(bounds.position.x), absf(bounds.end.x)), maxf(absf(bounds.position.z), absf(bounds.end.z))).length()
		var padding := reach * angle
		var swept := BoxShape3D.new()
		swept.size = shape.size + Vector3(padding * 2, 0, padding * 2)
		query.shape = swept
	var space := owner.get_world_3d().direct_space_state
	# cast_motion 不报告初始重叠，所以先检查起点。
	if not space.intersect_shape(query, 1).is_empty():
		return false
	query.motion = to.origin - from.origin
	# 扫掠恰好终止在接触面时仍可能返回 1；端点也须保持体积净空。
	return space.cast_motion(query)[0] >= 1.0 and fits(to.origin, to.basis)


func on_screen(at: Vector3, basis: Basis, camera: Camera3D) -> bool:
	# 用包围球保守判断：身体边缘还在画面里就不能回收或瞬移。
	var center := at + basis * bounds.get_center()
	# 通行盒下沿为斜坡留了净空，可见性还要包括那部分脚部。
	var radius := bounds.size.length() / 2.0 + maxf(bounds.position.y, 0.0)
	return _sphere_on_screen(center, radius, camera)


func segment_on_screen(a: Vector3, b: Vector3, camera: Camera3D) -> bool:
	return _sphere_on_screen((a + b) / 2.0, a.distance_to(b) / 2.0 + bounds.size.length() / 2.0, camera)


func _sphere_on_screen(center: Vector3, radius: float, camera: Camera3D) -> bool:
	for plane: Plane in camera.get_frustum():
		if plane.distance_to(center) > radius:
			return false
	return true
