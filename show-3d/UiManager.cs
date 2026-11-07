using Godot;
using System;

public partial class UiManager : CanvasLayer
{
	private const string DefaultObjPath = "res://obj/queen.obj";

	// On récupère les références des nœuds
	[Export] private FileDialog _fileDialog;
	[Export] private ObjLoader _objLoader; // Référence vers votre script ObjLoader
	[Export] private OrbitCamera _orbitCamera;
	[Export] private HSlider _fovSlider;
	[Export] private Label _matcapNameLabel;

	public override void _Ready()
	{
		GD.Print($"Initialisation de l'UiManager et configuration du FileDialog");
		// Optionnel : On peut aussi s'assurer que le filtre est bien mis par le code
		_fileDialog.Filters = new string[] { "*.obj ; Wavefront OBJ" };

		if (_fovSlider != null && _orbitCamera != null)
		{
			_fovSlider.MinValue = 35.0;
			_fovSlider.MaxValue = 100.0;
			_fovSlider.Step = 1.0;
			_fovSlider.Value = _orbitCamera.GetCameraFov();
		}

		if (_objLoader != null && FileAccess.FileExists(DefaultObjPath))
		{
			_objLoader.LoadExternalObj(DefaultObjPath);
		}
		else if (!FileAccess.FileExists(DefaultObjPath))
		{
			GD.PrintErr($"Fichier par défaut introuvable : {DefaultObjPath}");
		}

		UpdateMatcapNameLabel();
	}

	// 1. Cette fonction sera appelée quand on clique sur le bouton
	public void OnOpenButtonPressed()
	{
		GD.Print($"Ouverture du FileDialog pour sélectionner un fichier OBJ");
		// On affiche le FileDialog au centre de l'écran
		_fileDialog.PopupCentered();
	}

	// 2. Cette fonction sera appelée quand l'utilisateur aura choisi son fichier
	public void OnFileDialogFileSelected(string path)
	{
		GD.Print($"Fichier sélectionné : {path}");
		
		// On transmet le chemin du fichier à notre ObjLoader
		if (_objLoader != null)
		{
			_objLoader.LoadExternalObj(path);
		}
	}

	public void OnResetViewPressed()
	{
		if (_objLoader != null)
		{
			_objLoader.ResetView();
		}
	}

	public void OnInvertNormalsPressed()
	{
		if (_objLoader != null)
		{
			_objLoader.ToggleNormalsOrientation();
		}
	}

	public void OnSavePngPressed()
	{
		if (_objLoader != null)
		{
			_objLoader.SaveScreenshotPng();
		}
	}

	public void OnPreviousMatcapPressed()
	{
		if (_objLoader != null)
		{
			_objLoader.PreviousMatcapTexture();
			UpdateMatcapNameLabel();
		}
	}

	public void OnNextMatcapPressed()
	{
		if (_objLoader != null)
		{
			_objLoader.NextMatcapTexture();
			UpdateMatcapNameLabel();
		}
	}

	public void OnFovSliderValueChanged(double value)
	{
		if (_orbitCamera != null)
		{
			_orbitCamera.SetCameraFov((float)value);
		}
	}

	private void UpdateMatcapNameLabel()
	{
		if (_matcapNameLabel == null)
			return;

		if (_objLoader == null)
		{
			_matcapNameLabel.Text = "Matcap: -";
			return;
		}

		_matcapNameLabel.Text = $"Matcap: {_objLoader.GetCurrentMatcapFileName()}";
	}
}
