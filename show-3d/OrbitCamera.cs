using Godot;
using System;

public partial class OrbitCamera : Node3D
{
	// Paramètres réglables depuis l'inspecteur
	[Export] public float RotationSpeed { get; set; } = 0.005f;
	[Export] public float PanSpeed { get; set; } = 0.002f;
	[Export] public float ZoomSpeed { get; set; } = 0.5f;
	[Export] public float MinZoom { get; set; } = 1.5f;
	[Export] public float MaxZoom { get; set; } = 50.0f;
	[Export] public float Smoothness { get; set; } = 12.0f;
	[Export] public float FramingDistanceMultiplier { get; set; } = 2.2f;
	[Export] public float DynamicMaxZoomMultiplier { get; set; } = 8.0f;

	// Variables cibles pour l'amorti (Lerp)
	private float _targetYaw = 0.0f;
	private float _targetPitch = 0.0f;
	private float _targetZoom = 5.0f;
	private Vector3 _targetPosition = Vector3.Zero;
	private float _runtimeMinZoom;
	private float _runtimeMaxZoom;

	private Camera3D _camera;

	private Camera3D GetCamera()
	{
		if (_camera == null)
		{
			_camera = GetNodeOrNull<Camera3D>("Camera3D");
		}

		return _camera;
	}

	public override void _Ready()
	{
		_camera = GetNode<Camera3D>("Camera3D");
		_runtimeMinZoom = MinZoom;
		_runtimeMaxZoom = MaxZoom;
		
		// Initialisation des cibles avec les valeurs de départ
		_targetYaw = Rotation.Y;
		_targetPitch = Rotation.X;
		_targetZoom = _camera.Position.Z;
		_targetPosition = GlobalPosition;
	}

	public override void _UnhandledInput(InputEvent @event)
	{
		// 1. ROTATION (Clic Droit)
		if (@event is InputEventMouseMotion mouseMotionRot && Input.IsMouseButtonPressed(MouseButton.Right))
		{
			_targetYaw -= mouseMotionRot.Relative.X * RotationSpeed;
			_targetPitch -= mouseMotionRot.Relative.Y * RotationSpeed;
			
			// Limitation verticale pour éviter le retournement de caméra
			_targetPitch = Mathf.Clamp(_targetPitch, Mathf.DegToRad(-85), Mathf.DegToRad(85));
		}
		// 2. PANORAMIQUE (Clic Milieu)
		else if (@event is InputEventMouseMotion mouseMotionPan && Input.IsMouseButtonPressed(MouseButton.Middle))
		{
			Transform3D camTransform = _camera.GlobalTransform;
			Vector3 rightDir = camTransform.Basis.X;
			Vector3 upDir = camTransform.Basis.Y;

			// Ajustement du Pan selon la distance de zoom actuelle
			float currentPanFactor = PanSpeed * (_camera.Position.Z * 0.5f);

			_targetPosition -= rightDir * mouseMotionPan.Relative.X * currentPanFactor;
			_targetPosition += upDir * mouseMotionPan.Relative.Y * currentPanFactor;
		}

		// 3. ZOOM (Molette)
		if (@event is InputEventMouseButton mouseButton)
		{
			float zoomStep = Mathf.Max(ZoomSpeed, Mathf.Abs(_targetZoom) * 0.08f);

			if (mouseButton.ButtonIndex == MouseButton.WheelUp && mouseButton.Pressed)
			{
				_targetZoom -= zoomStep;
			}
			else if (mouseButton.ButtonIndex == MouseButton.WheelDown && mouseButton.Pressed)
			{
				_targetZoom += zoomStep;
			}

			_targetZoom = Mathf.Clamp(_targetZoom, _runtimeMinZoom, _runtimeMaxZoom);
		}
	}

	public override void _Process(double delta)
	{
		float fDelta = (float)delta;

		// Interpolation fluide (Lerp)
		Vector3 currentRotation = Rotation;
		currentRotation.Y = Mathf.LerpAngle(currentRotation.Y, _targetYaw, Smoothness * fDelta);
		currentRotation.X = Mathf.LerpAngle(currentRotation.X, _targetPitch, Smoothness * fDelta);
		Rotation = currentRotation;

		GlobalPosition = GlobalPosition.Lerp(_targetPosition, Smoothness * fDelta);
		
		Vector3 camPos = _camera.Position;
		camPos.Z = Mathf.Lerp(camPos.Z, _targetZoom, Smoothness * fDelta);
		_camera.Position = camPos;
	}

	// Appelée par l'ObjLoader pour focus un nouveau modèle
	public void ResetCameraPosition(Vector3 newCenter, float newZoom)
	{
		_runtimeMinZoom = MinZoom;
		_runtimeMaxZoom = MaxZoom;
		_targetPosition = newCenter;
		_targetZoom = Mathf.Clamp(newZoom, _runtimeMinZoom, _runtimeMaxZoom);
	}

	// Ajuste automatiquement le zoom possible en fonction de la taille du modèle importé.
	public void FrameObject(Vector3 newCenter, float objectMaxDimension)
	{
		float size = Mathf.Max(0.1f, objectMaxDimension);
		_runtimeMinZoom = MinZoom;
		_runtimeMaxZoom = Mathf.Max(MaxZoom, size * DynamicMaxZoomMultiplier);
		_targetPosition = newCenter;
		_targetZoom = Mathf.Clamp(size * FramingDistanceMultiplier, _runtimeMinZoom, _runtimeMaxZoom);
	}

	public float GetCameraFov()
	{
		Camera3D cam = GetCamera();
		return cam != null ? cam.Fov : 75.0f;
	}

	public void SetCameraFov(float fov)
	{
		Camera3D cam = GetCamera();
		if (cam == null)
			return;

		cam.Fov = Mathf.Clamp(fov, 35.0f, 100.0f);
	}
}
