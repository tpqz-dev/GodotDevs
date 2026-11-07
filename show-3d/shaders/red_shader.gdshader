shader_type spatial;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

void vertex() {
    // Aligne le plan parfaitement avec la caméra pour couvrir tout l'écran
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    // Récupère la couleur actuelle de l'écran derrière le shader
    vec3 screen_color = texture(screen_texture, SCREEN_UV).rgb;
    
    // Calcule la version teintée en rouge (on garde la luminosité de base)
    float gray = dot(screen_color, vec3(0.299, 0.587, 0.114));
    vec3 red_filter = vec3(gray, 0.0, 0.0);
    
    // Alterne entre la couleur d'origine et le filtre rouge selon l'intensité choisie
    ALBEDO = mix(screen_color, red_filter, intensity);
}