using Godot;
using System;

public partial class Coin : Area2D
{
    private AnimationPlayer _animationPlayer;

    // Called when the node enters the scene tree for the first time.
    public override void _Ready()
	{
		GD.Print("i'm a coin");
		  _animationPlayer = GetNode<AnimationPlayer>("AnimationPlayer");
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}

	public  void _on_body_entered(Node body)
	{		GameManager.AddPoints(1);
			GD.Print("Coin collected!");
			_animationPlayer.Play("pickup");
	}
}
