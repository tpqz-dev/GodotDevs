extends Area3D

const BONUS_SOUND: AudioStream = preload("res://bonus.mp3")


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		var sound := AudioStreamPlayer.new()
		sound.stream = BONUS_SOUND
		get_tree().current_scene.add_child(sound)
		sound.finished.connect(sound.queue_free)
		sound.play()
		queue_free()
