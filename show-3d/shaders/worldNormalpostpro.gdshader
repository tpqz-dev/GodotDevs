

shader_type spatial;
render_mode unshaded;

// CORRECTION 1 : Déclaration obligatoire de la texture de profondeur sous Godot 4
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

vec3 normal_from_depth(vec2 uv, mat4 inv_proj_mat, sampler2D depth_tex){
    // CORRECTION 2 : Utilisation de la texture passée en paramètre
    float depth = texture(depth_tex, uv).r;
    
    // Reconstruction de la position 3D à partir de la profondeur
    float x = uv.x * 2.0 - 1.0;
    float y = (1.0 - uv.y) * 2.0 - 1.0;
    
    vec4 position_s = vec4(x, y, depth, 1.0);
    vec4 position_v = inv_proj_mat * position_s;
    
    vec3 P = position_v.xyz / position_v.w;
    
    // Inversion de l'axe Y et calcul du produit vectoriel pour obtenir la normale
    P.y = -P.y;
    return normalize(cross(dFdy(P), dFdx(P)));
}

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    // CORRECTION 3 : On passe la depth_texture à la fonction
    vec3 normal = normal_from_depth(SCREEN_UV, INV_PROJECTION_MATRIX, depth_texture);
    
    // Affichage des normales (les valeurs négatives seront clampées à 0 à l'écran, 
    // tu peux faire `normal * 0.5 + 0.5` si tu veux un rendu de type "Normal Map" visible partout)
    ALBEDO = normal;
} // CORRECTION 4 : Ajout de l'accolade manquante
