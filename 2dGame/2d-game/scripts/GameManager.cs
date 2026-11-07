using Godot;
using System;

public partial class GameManager : Node
{
	private static int score = 0;
	private static GameManager _instance;
	private Label _scoreLabel;

	public override void _EnterTree()
	{
		_instance = this;
	}

	public override void _ExitTree()
	{
		if (_instance == this)
		{
			_instance = null;
		}
	}

    public override void _Ready()
    {
		// The score label lives under Player/Camera2D in game.tscn.
		_scoreLabel = GetNodeOrNull<Label>("../Player/Camera2D/score")
			?? GetNodeOrNull<Label>("Player/Camera2D/score");

		if (_scoreLabel == null)
		{
			GD.PushWarning("GameManager: score label not found. Score will still update internally.");
		}

		UpdateScoreLabel();
	}


	public static void AddPoints(int points)
	{
		score += points;
		_instance?.UpdateScoreLabel();
		GD.Print("Score: " + score);
	}

	private void UpdateScoreLabel()
	{
		if (_scoreLabel != null)
		{
			_scoreLabel.Text = "Score: " + score;
		}
	}

	public static int GetScore()
	{
		return score;
	}
}
