using Godot;
using System;

public partial class Player : CharacterBody2D
{
	public const float Speed = 130.0f;
	public const float JumpVelocity = -300.0f;
    private AnimatedSprite2D _player;

    public override void _Ready()
    {
         _player = GetNode<AnimatedSprite2D>("AnimatedSprite2D");
	}


	public override void _PhysicsProcess(double delta)
	{
		Vector2 velocity = Velocity;

		// Add the gravity.
		if (!IsOnFloor())
		{
			velocity += GetGravity() * (float)delta;
		}

		// Handle Jump.
		if (Input.IsActionJustPressed("jump") && IsOnFloor())
		{
			velocity.Y = JumpVelocity;
		}

		// Get the input direction and handle the movement/deceleration.
		// As good practice, you should replace UI actions with custom gameplay actions.
		Vector2 direction = Input.GetVector("move_left", "move_right", "move_up", "move_down");
		if (direction != Vector2.Zero)
		{
			velocity.X = direction.X * Speed;
			_player.FlipH = direction.X < 0;
		}
		else
		{
			velocity.X = Mathf.MoveToward(Velocity.X, 0, Speed);
			_player.FlipH = direction.X < 0;
		}

		// animations
		if (IsOnFloor())
		{
			if (velocity.X == 0)
			{
				_player.Play("idle");
			}
			else
			{
				_player.Play("run");
			}
		}
		else
		{
			if (velocity.Y < 0)
			{
				_player.Play("jump");
			}
			else
			{
				_player.Play("fall");
			}
		}

		Velocity = velocity;
		MoveAndSlide();
	}
}
