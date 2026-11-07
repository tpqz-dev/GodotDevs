using Godot;
using System;

public partial class Enemy : Node2D
{
	private RayCast2D _rayR;
	private RayCast2D _rayL;
    private AnimatedSprite2D _sprite;
    private float SPEED = 100.0f;
	private int direction = 1;
	public override void _Ready()
	{	// Called when the node enters the scene tree for the first time.
	        _rayR = GetNode<RayCast2D>("RayCast2D");
	        _rayL = GetNode<RayCast2D>("RayCast2D2");
	        _sprite = GetNode<AnimatedSprite2D>("AnimatedSprite2D");
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
		if (_rayR.IsColliding())
		{
			direction = -1;
			_sprite.FlipH = true;
		}
		else if (_rayL.IsColliding())
		{
			direction = 1;
			_sprite.FlipH = false;
		}

		this.Position = new Vector2(this.Position.X + direction * SPEED * (float)delta, this.Position.Y);
	}
}
