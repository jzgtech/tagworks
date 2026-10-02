shader_type canvas_item;
render_mode unshaded; 

// --- CONFIGURATION PARAMETERS ---
uniform vec2 panel_size = vec2(800.0, 600.0);                             

uniform vec4 base_bg_color : source_color = vec4(0.08, 0.09, 0.11, 1.0);  
uniform vec4 edit_bg_color : source_color = vec4(0.05, 0.12, 0.22, 1.0);  
uniform vec4 grid_color : source_color = vec4(0.15, 0.35, 0.65, 0.35);    

// Dynamic Border Colors
uniform vec4 view_border_color : source_color = vec4(1.0, 1.0, 1.0, 0.15); 
uniform vec4 edit_border_color : source_color = vec4(1.0, 0.65, 0.0, 0.8); 

uniform float border_thickness : hint_range(0.0, 10.0) = 2.0;            
uniform float corner_radius : hint_range(0.0, 200.0) = 12.0;             

// Blueprint settings (Set x: 10, y: 10 in the Inspector for a 10x10 grid)
uniform vec2 grid_size = vec2(10.0, 10.0);
uniform float line_thickness : hint_range(0.5, 5.0) = 1.0;
uniform float edit_mode_fade : hint_range(0.0, 1.0) = 0.0;               

// Mathematical rounded rectangle generator
float rounded_box(vec2 center, vec2 size, float radius) {
	return length(max(abs(center) - size + radius, 0.0)) - radius;
}

void fragment() {
	vec2 current_pixel = UV * panel_size;
	vec2 half_size = panel_size * 0.5;
	vec2 center_offset = current_pixel - half_size;
	
	float dist = rounded_box(center_offset, half_size, corner_radius);
	
	// 1. GENERATE BACKGROUND EFFECTS (Perfect Border Offset Alignment)
	// --- THE FIXED ALIGNMENT MATH ---
	// Subtract the border thickness so that (0,0) in Godot node position 
	// aligns perfectly with the first visual grid line inside the border.
	vec2 aligned_pixel = current_pixel - vec2(border_thickness);
	vec2 grid_modulo = mod(current_pixel, grid_size);
	// ---------------------------------
	
	// Create crisp lines using the offset coordinates
	float line_x = step(grid_modulo.x, line_thickness);
	float line_y = step(grid_modulo.y, line_thickness);
	float grid_mask = max(line_x, line_y);
	
	// Cleanly clip the grid lines so they don't leak into negative coordinate space
	if (aligned_pixel.x < 0.0 || aligned_pixel.y < 0.0) {
		grid_mask = 0.0;
	}
	
	vec4 final_blueprint = mix(edit_bg_color, grid_color, grid_mask);
	vec4 mixed_background = mix(base_bg_color, final_blueprint, edit_mode_fade);
	
	// 2. GENERATE DYNAMIC BORDER LAYERS
	vec4 active_border_color = mix(view_border_color, edit_border_color, edit_mode_fade);
	
	// --- CRISP LINE CORRECTION ---
	float inner_edge = step(-border_thickness, dist); 
	float outer_edge = step(0.0, dist);               
	float border_mask = inner_edge * (1.0 - outer_edge);
	
	// 3. COMBINE LAYERS WITH MASTER DEPTH OVERWRITE
	vec4 final_composite = mix(mixed_background, active_border_color, border_mask);
	float alpha_clip = 1.0 - step(0.0, dist);
	
	COLOR = vec4(final_composite.rgb, final_composite.a * alpha_clip);
}
