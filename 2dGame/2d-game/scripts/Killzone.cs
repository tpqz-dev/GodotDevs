using Godot;
using System;


public partial class Killzone : Area2D
{
	private Timer _timer;


    // Called when the node enters the scene tree for the first time.
    public override void _Ready()
    {
        _timer = GetNode<Timer>("Timer");
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}

	public  void _on_body_entered(Node body)
	{
			GD.Print(" you died !");
			Engine.TimeScale = 0.5f;
			body.GetNode<CollisionShape2D>("CollisionShape2D").QueueFree();
			_timer.Start();
			GD.Print(" timer started !");
	}

	public  void _on_timer_timeout()
	{
			Engine.TimeScale = 1.0f;
			GD.Print(" restarting !");
			GetTree().ReloadCurrentScene();
	}

}
