shader_type spatial;
render_mode unshaded, diffuse_lambert, specular_schlick_ggx;

// Permet de charger ta texture MatCap sphérique depuis l'inspecteur
uniform sampler2D matcap_texture : hint_default_black, filter_linear_mipmap;

void fragment() {
	// 1. Récupère la normale du pixel dans l'espace de la vue (View Space / Caméra)
	vec3 view_normal = NORMAL;
	
	// 2. Transforme les coordonnées de la normale (-1.0 à 1.0) vers l'espace UV (0.0 à 1.0)
	// On inverse l'axe Y car l'espace écran 2D de Godot va du haut vers le bas
	vec2 matcap_uv = view_normal.xy * 0.5 + 0.5;
	matcap_uv.y = 1.0 - matcap_uv.y;
	
	// 3. Échantillonne la texture MatCap et l'applique à l'ALBEDO
	vec3 final_color = texture(matcap_texture, matcap_uv).rgb;
	
	ALBEDO = final_color;
}