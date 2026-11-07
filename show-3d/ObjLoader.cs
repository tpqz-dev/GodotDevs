using Godot;
using System;
using System.Collections.Generic;
using System.Globalization;
using IOPath = System.IO.Path;

public partial class ObjLoader : Node3D
{
    private const string MatcapTextureDirectory = "res://textures";
    private const string MatcapShaderPath = "res://shaders/matcap_shader.gdshader";
    private const string MatcapShaderParameter = "matcap_texture";
    private const string DefaultMatcapFileName = "ceramic_hot.png";

    [Export] private MeshInstance3D _meshInstance;
    [Export] private OrbitCamera _orbitCamera;
    [Export] private bool _invertWinding = true;

    private string _lastLoadedPath = string.Empty;
    private readonly List<string> _matcapTexturePaths = new List<string>();
    private int _currentMatcapIndex = -1;

    public override void _Ready()
    {
        InitializeMatcapTextures();
    }

    public void LoadExternalObj(string filePath)
    {
        
        if (!FileAccess.FileExists(filePath))
        {
            GD.PrintErr($"Fichier introuvable : {filePath}");
            return;
        }

        _lastLoadedPath = filePath;

        try
        {    GD.Print($"Initialisation du SurfaceTool de Godot pour reconstruire le maillage");
            // Initialisation du SurfaceTool de Godot pour reconstruire le maillage
            SurfaceTool st = new SurfaceTool();
            st.Begin(Mesh.PrimitiveType.Triangles);

            List<Vector3> vertices = new List<Vector3>();

            using (var file = FileAccess.Open(filePath, FileAccess.ModeFlags.Read))
            {
                 GD.Print($"Ouverture du fichier OBJ : {filePath}");
                if (file == null) return;

                while (!file.EofReached())
                {
                    string line = file.GetLine().Trim();
                    if (string.IsNullOrEmpty(line) || line.StartsWith("#")) 
                        continue;

                    string[] parts = line.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                    if (parts.Length == 0) continue;

                    // Détection d'un Sommet (Vertex)
                    if (parts[0] == "v" && parts.Length >= 4)
                    {
                        float x = float.Parse(parts[1], CultureInfo.InvariantCulture);
                        float y = float.Parse(parts[2], CultureInfo.InvariantCulture);
                        float z = float.Parse(parts[3], CultureInfo.InvariantCulture);
                        vertices.Add(new Vector3(x, y, z));
                    }
                    // Détection d'une Face (Indices des triangles)
                    else if (parts[0] == "f" && parts.Length >= 4)
                    {
                        // Un OBJ peut avoir plus de 3 sommets par face (quads), on gère ici la triangulation de base
                        List<int> faceIndices = new List<int>();
                        for (int i = 1; i < parts.Length; i++)
                        {
                            // On extrait l'index du sommet (le premier nombre avant le '/')
                            string vertexIndexStr = parts[i].Split('/')[0];
                            int index = int.Parse(vertexIndexStr) - 1; // Les indices OBJ commencent à 1
                            faceIndices.Add(index);
                        }

                        // Triangulation en éventail (Fan triangulation) au cas où le fichier contient des quads/polygones
                        for (int i = 1; i < faceIndices.Count - 1; i++)
                        {
                            st.AddVertex(vertices[faceIndices[0]]);
                            if (_invertWinding)
                            {
                                st.AddVertex(vertices[faceIndices[i + 1]]);
                                st.AddVertex(vertices[faceIndices[i]]);
                            }
                            else
                            {
                                st.AddVertex(vertices[faceIndices[i]]);
                                st.AddVertex(vertices[faceIndices[i + 1]]);
                            }
                        }
                    }
                }
            }

            // Génération automatique des normales pour que la lumière réagisse correctement
            st.GenerateNormals();
            
            // On assigne le maillage finalisé au MeshInstance3D
            _meshInstance.Mesh = st.Commit();
            ApplyCurrentMatcapTexture();
            GD.Print("Modèle OBJ parsé et chargé avec succès au runtime !");

            if (_orbitCamera != null)
            {
                CenterCameraOnMesh();
            }
        }
        catch (Exception ex)
        {
            GD.PrintErr($"Erreur lors de la lecture du fichier OBJ : {ex.Message}");
        }
    }

    public void ResetView()
    {
        if (_orbitCamera == null || _meshInstance == null || _meshInstance.Mesh == null)
            return;

        CenterCameraOnMesh();
    }

    public void ToggleNormalsOrientation()
    {
        _invertWinding = !_invertWinding;
        GD.Print($"Inversion des normales : {(_invertWinding ? "active" : "inactive")}");

        if (!string.IsNullOrEmpty(_lastLoadedPath) && FileAccess.FileExists(_lastLoadedPath))
        {
            LoadExternalObj(_lastLoadedPath);
        }
    }

    public void SaveScreenshotPng()
    {
        if (string.IsNullOrEmpty(_lastLoadedPath))
        {
            GD.PrintErr("Aucun OBJ chargé : impossible de sauvegarder le PNG.");
            return;
        }

        string outputDirectory = IOPath.GetDirectoryName(_lastLoadedPath) ?? string.Empty;
        if (string.IsNullOrEmpty(outputDirectory) || !DirAccess.DirExistsAbsolute(outputDirectory))
        {
            GD.PrintErr($"Dossier de destination invalide : {outputDirectory}");
            return;
        }

        RenderingServer.ForceDraw();

        Image screenshot = GetViewport().GetTexture().GetImage();
        screenshot.FlipY();

        string baseName = IOPath.GetFileNameWithoutExtension(_lastLoadedPath);
        string fileName = $"{baseName}_{DateTime.Now:yyyyMMdd_HHmmss}.png";
        string outputPath = IOPath.Combine(outputDirectory, fileName);

        Error saveError = screenshot.SavePng(outputPath);
        if (saveError == Error.Ok)
        {
            GD.Print($"PNG sauvegardé : {outputPath}");
        }
        else
        {
            GD.PrintErr($"Erreur de sauvegarde PNG ({saveError}) : {outputPath}");
        }
    }

    public void NextMatcapTexture()
    {
        StepMatcapTexture(1);
    }

    public void PreviousMatcapTexture()
    {
        StepMatcapTexture(-1);
    }

    public string GetCurrentMatcapFileName()
    {
        if (_currentMatcapIndex < 0 || _currentMatcapIndex >= _matcapTexturePaths.Count)
            return "-";

        return IOPath.GetFileName(_matcapTexturePaths[_currentMatcapIndex]);
    }

    private void StepMatcapTexture(int delta)
    {
        if (_matcapTexturePaths.Count == 0)
            InitializeMatcapTextures();

        if (_matcapTexturePaths.Count == 0)
            return;

        _currentMatcapIndex = (_currentMatcapIndex + delta + _matcapTexturePaths.Count) % _matcapTexturePaths.Count;
        ApplyCurrentMatcapTexture();
    }

    private void InitializeMatcapTextures()
    {
        _matcapTexturePaths.Clear();
        _currentMatcapIndex = -1;

        DirAccess dir = DirAccess.Open(MatcapTextureDirectory);
        if (dir == null)
        {
            GD.PrintErr($"Dossier de textures matcap introuvable : {MatcapTextureDirectory}");
            return;
        }

        dir.ListDirBegin();
        while (true)
        {
            string entry = dir.GetNext();
            if (string.IsNullOrEmpty(entry))
                break;

            if (dir.CurrentIsDir())
                continue;

            if (!IsSupportedTextureFile(entry))
                continue;

            _matcapTexturePaths.Add($"{MatcapTextureDirectory}/{entry}");
        }
        dir.ListDirEnd();

        _matcapTexturePaths.Sort(StringComparer.OrdinalIgnoreCase);

        if (_matcapTexturePaths.Count == 0)
        {
            GD.PrintErr($"Aucune texture matcap trouvée dans : {MatcapTextureDirectory}");
            return;
        }

        int defaultIndex = _matcapTexturePaths.FindIndex(path =>
            string.Equals(IOPath.GetFileName(path), DefaultMatcapFileName, StringComparison.OrdinalIgnoreCase));

        _currentMatcapIndex = defaultIndex >= 0 ? defaultIndex : 0;
        ApplyCurrentMatcapTexture();
    }

    private bool IsSupportedTextureFile(string fileName)
    {
        string ext = IOPath.GetExtension(fileName).ToLowerInvariant();
        return ext == ".png" || ext == ".jpg" || ext == ".jpeg" || ext == ".webp";
    }

    private ShaderMaterial GetOrCreateMatcapMaterial()
    {
        if (_meshInstance == null)
            return null;

        ShaderMaterial shaderMaterial = _meshInstance.MaterialOverlay as ShaderMaterial;
        if (shaderMaterial == null)
            shaderMaterial = new ShaderMaterial();

        Shader matcapShader = GD.Load<Shader>(MatcapShaderPath);
        if (matcapShader == null)
        {
            GD.PrintErr($"Shader MatCap introuvable : {MatcapShaderPath}");
            return null;
        }

        shaderMaterial.Shader = matcapShader;
        _meshInstance.MaterialOverlay = shaderMaterial;
        return shaderMaterial;
    }

    private void ApplyCurrentMatcapTexture()
    {
        if (_currentMatcapIndex < 0 || _currentMatcapIndex >= _matcapTexturePaths.Count)
            return;

        ShaderMaterial shaderMaterial = GetOrCreateMatcapMaterial();
        if (shaderMaterial == null)
            return;

        string texturePath = _matcapTexturePaths[_currentMatcapIndex];
        Texture2D texture = GD.Load<Texture2D>(texturePath);
        if (texture == null)
        {
            GD.PrintErr($"Texture MatCap illisible : {texturePath}");
            return;
        }

        shaderMaterial.SetShaderParameter(MatcapShaderParameter, texture);
        GD.Print($"MatCap actif : {GetCurrentMatcapFileName()}");
    }

    private void CenterCameraOnMesh()
    {
        if (_meshInstance.Mesh == null) return;

        Aabb aabb = _meshInstance.Mesh.GetAabb();
        Vector3 centerPosition = _meshInstance.GlobalPosition + aabb.GetCenter();
        float maxDimension = Mathf.Max(aabb.Size.X, Mathf.Max(aabb.Size.Y, aabb.Size.Z));

        _orbitCamera.FrameObject(centerPosition, maxDimension);
    }
}