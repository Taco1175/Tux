shader_type canvas_item;
// Animated pixel beach scene for TUX main menu.
// Sunset sky, realistic ocean with rolling waves and foam breaks, sandy shore.

uniform float time_scale : hint_range(0.1, 3.0) = 1.0;
uniform float pixel_size : hint_range(1.0, 8.0) = 3.0;

// Colors — sunset beach palette
const vec3 SKY_TOP = vec3(0.12, 0.06, 0.22);       // deep purple
const vec3 SKY_MID = vec3(0.55, 0.2, 0.35);         // pink-purple
const vec3 SKY_BOTTOM = vec3(0.92, 0.5, 0.25);      // warm orange horizon
const vec3 SUN_COLOR = vec3(1.0, 0.8, 0.35);         // golden sun
const vec3 SUN_HAZE = vec3(1.0, 0.6, 0.3);           // haze around sun
const vec3 SAND_LIGHT = vec3(0.78, 0.67, 0.47);      // dry sand
const vec3 SAND_DARK = vec3(0.52, 0.42, 0.28);       // wet sand
const vec3 SAND_MID = vec3(0.65, 0.55, 0.38);        // mid sand
const vec3 WATER_DEEP = vec3(0.04, 0.12, 0.3);       // deep ocean
const vec3 WATER_MID = vec3(0.06, 0.22, 0.42);       // mid water
const vec3 WATER_SHALLOW = vec3(0.1, 0.35, 0.48);    // shallow near shore
const vec3 WATER_HIGHLIGHT = vec3(0.2, 0.5, 0.6);    // wave crest highlight
const vec3 FOAM_COLOR = vec3(0.88, 0.93, 0.96);      // white foam
const vec3 FOAM_THIN = vec3(0.6, 0.75, 0.8);         // thin transparent foam
const vec3 CLOUD_COLOR = vec3(0.92, 0.72, 0.6);      // sunset clouds
const vec3 CLOUD_DARK = vec3(0.5, 0.25, 0.35);       // cloud shadow

// Simple hash for pseudo-random
float hash(float n) { return fract(sin(n) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float t = TIME * time_scale;

	// Pixelate UV
	vec2 res = vec2(480.0, 270.0);
	vec2 puv = floor(UV * res / pixel_size) * pixel_size / res;
	float px = puv.x;
	float py = puv.y;

	// Layout zones
	float horizon_y = 0.42;
	float shore_base = 0.73;

	// Global tide — slow in/out
	float tide = sin(t * 0.3) * 0.025 + sin(t * 0.17) * 0.01;
	float shore_line = shore_base + tide;

	// Per-column wave variation (multiple frequencies for organic look)
	float wave1 = sin(px * 18.0 + t * 1.2) * 0.012;
	float wave2 = sin(px * 35.0 - t * 1.8) * 0.006;
	float wave3 = sin(px * 55.0 + t * 2.5) * 0.003;
	float local_shore = shore_line + wave1 + wave2 + wave3;

	vec3 col = vec3(0.0);

	if (py < horizon_y) {
		// === SKY ===
		float sky_t = py / horizon_y;
		// Three-stop gradient for richer sunset
		if (sky_t < 0.5) {
			col = mix(SKY_TOP, SKY_MID, sky_t * 2.0);
		} else {
			col = mix(SKY_MID, SKY_BOTTOM, (sky_t - 0.5) * 2.0);
		}

		// Sun
		vec2 sun_pos = vec2(0.5, horizon_y - 0.04);
		float sun_dist = length(vec2((px - sun_pos.x) * 1.2, py - sun_pos.y));
		if (sun_dist < 0.045) {
			float sun_glow = 1.0 - sun_dist / 0.045;
			col = mix(col, SUN_COLOR, sun_glow * sun_glow * sun_glow);
		}
		// Wide sun haze
		if (sun_dist < 0.2) {
			float haze = (1.0 - sun_dist / 0.2);
			col = mix(col, SUN_HAZE, haze * haze * 0.35);
		}
		// Horizon glow band
		if (sky_t > 0.85) {
			float glow = (sky_t - 0.85) / 0.15;
			col = mix(col, SKY_BOTTOM * 1.2, glow * 0.3);
		}

		// Clouds — layered, some with dark undersides
		float cy1 = sin(px * 8.0 + 1.2) * cos(px * 5.0 + 0.5);
		float cy2 = sin(px * 13.0 - 0.8) * cos(px * 9.0 + 2.1);
		// Cloud layer 1 (higher, lighter)
		float cloud_band1 = smoothstep(0.15, 0.18, py / horizon_y) * smoothstep(0.5, 0.45, py / horizon_y);
		float cloud_shape1 = cy1 * sin(py * 25.0 + px * 3.0);
		if (cloud_shape1 > 0.2 && cloud_band1 > 0.0) {
			float alpha = (cloud_shape1 - 0.2) * 2.5 * cloud_band1;
			col = mix(col, CLOUD_COLOR, clamp(alpha, 0.0, 0.45));
		}
		// Cloud layer 2 (lower, with shadow)
		float cloud_band2 = smoothstep(0.4, 0.5, py / horizon_y) * smoothstep(0.7, 0.6, py / horizon_y);
		float cloud_shape2 = cy2 * sin(py * 30.0 + px * 7.0);
		if (cloud_shape2 > 0.25 && cloud_band2 > 0.0) {
			float alpha = (cloud_shape2 - 0.25) * 2.0 * cloud_band2;
			vec3 cc = mix(CLOUD_DARK, CLOUD_COLOR, smoothstep(0.45, 0.55, py / horizon_y));
			col = mix(col, cc, clamp(alpha, 0.0, 0.4));
		}

	} else if (py < local_shore) {
		// === WATER ===
		float water_t = (py - horizon_y) / (local_shore - horizon_y);

		// Water color gradient
		vec3 water_col;
		if (water_t < 0.4) {
			water_col = mix(WATER_DEEP, WATER_MID, water_t / 0.4);
		} else if (water_t < 0.75) {
			water_col = mix(WATER_MID, WATER_SHALLOW, (water_t - 0.4) / 0.35);
		} else {
			water_col = mix(WATER_SHALLOW, WATER_HIGHLIGHT, (water_t - 0.75) / 0.25);
		}

		// Rolling wave crests — multiple bands at different depths
		// Each wave band is a horizontal-ish stripe that moves shoreward
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			float wave_speed = 0.6 + fi * 0.15;
			float wave_freq = 3.0 + fi * 1.5;
			float wave_y = 0.2 + fi * 0.18;  // depth position

			// Wave moves toward shore over time
			float wave_pos = wave_y + fract(t * wave_speed * 0.08) * 0.3;
			if (wave_pos > 1.0) wave_pos -= 1.0;

			float dist_to_wave = abs(water_t - wave_pos);
			// Wave crest shape — thin line with x-variation for breaking look
			float x_var = sin(px * (20.0 + fi * 10.0) + fi * 3.14 + t * 0.5) * 0.02;
			dist_to_wave += x_var;

			if (dist_to_wave < 0.025) {
				float crest = 1.0 - dist_to_wave / 0.025;
				// Breaking foam on the crest
				float break_noise = sin(px * (40.0 + fi * 15.0) + fi * 2.0 + t * 1.5);
				if (break_noise > -0.2) {
					float foam_strength = crest * crest * 0.5;
					water_col = mix(water_col, FOAM_THIN, foam_strength);
					// Bright foam caps on some sections
					if (break_noise > 0.4 && crest > 0.5) {
						water_col = mix(water_col, FOAM_COLOR, crest * 0.4);
					}
				}
			}
		}

		// Subtle ripple texture across all water
		float ripple = sin(px * 45.0 + t * 2.0 + py * 18.0) * sin(px * 25.0 - t * 1.3 + py * 12.0);
		if (ripple > 0.4) {
			water_col = mix(water_col, WATER_HIGHLIGHT, (ripple - 0.4) * 0.25);
		}

		// Sun reflection column on water
		float ref_dist = abs(px - 0.5);
		if (ref_dist < 0.1 && water_t < 0.5) {
			float shimmer = sin(py * 70.0 + t * 3.5) * sin(py * 40.0 - t * 2.0);
			if (shimmer > 0.2) {
				float ref_strength = (1.0 - ref_dist / 0.1) * (1.0 - water_t * 2.0) * (shimmer - 0.2);
				water_col = mix(water_col, SUN_COLOR, clamp(ref_strength * 0.5, 0.0, 0.4));
			}
		}

		col = water_col;

		// Shore foam — multiple lines for realistic wash
		float foam_dist = local_shore - py;
		// Primary foam line
		if (foam_dist < 0.02) {
			float foam_t = foam_dist / 0.02;
			float foam_noise = sin(px * 50.0 + t * 1.5) * 0.5 + 0.5;
			float foam_noise2 = sin(px * 80.0 - t * 2.2) * 0.5 + 0.5;
			float foam_alpha = (1.0 - foam_t) * max(foam_noise, foam_noise2 * 0.7);
			col = mix(col, FOAM_COLOR, clamp(foam_alpha, 0.0, 0.85));
		}
		// Secondary foam line (thinner, behind primary)
		if (foam_dist > 0.015 && foam_dist < 0.035) {
			float foam_t = (foam_dist - 0.015) / 0.02;
			float foam_noise = sin(px * 60.0 + t * 1.0 + 1.5) * 0.5 + 0.5;
			if (foam_noise > 0.5) {
				float alpha = (1.0 - foam_t) * (foam_noise - 0.5) * 1.0;
				col = mix(col, FOAM_THIN, clamp(alpha, 0.0, 0.4));
			}
		}
		// Receding foam trails (thin streaks running back to sea)
		if (foam_dist < 0.04 && foam_dist > 0.005) {
			float trail = sin(px * 120.0 + 3.0) * sin(px * 70.0 - 1.5);
			if (trail > 0.6) {
				float trail_alpha = (trail - 0.6) * 0.5 * (1.0 - foam_dist / 0.04);
				col = mix(col, FOAM_THIN, clamp(trail_alpha, 0.0, 0.25));
			}
		}

	} else {
		// === BEACH / SAND ===
		float sand_t = (py - local_shore) / (1.0 - local_shore);

		// Wet sand near water, transition zone, dry sand further up
		float wet_zone = 0.12 + tide * 1.5;
		float trans_zone = wet_zone + 0.15;

		if (sand_t < wet_zone) {
			// Wet sand — darker, reflective
			col = mix(SAND_DARK, SAND_MID, sand_t / wet_zone);
			// Wet shimmer / water film
			float shimmer = sin(px * 60.0 + py * 40.0 + t * 0.3) * sin(px * 35.0 - t * 0.5);
			if (shimmer > 0.3) {
				col = mix(col, vec3(0.55, 0.55, 0.5), (shimmer - 0.3) * 0.2);
			}
			// Receding water trails on wet sand
			float trail = sin(px * 90.0 + sand_t * 200.0 + t * 0.2);
			if (trail > 0.7 && sand_t > 0.02) {
				col = mix(col, WATER_SHALLOW, 0.15);
			}
		} else if (sand_t < trans_zone) {
			// Transition — damp sand
			float tt = (sand_t - wet_zone) / (trans_zone - wet_zone);
			col = mix(SAND_MID, SAND_LIGHT, tt);
		} else {
			// Dry sand
			col = SAND_LIGHT;
			// Sand grain texture
			float grain1 = sin(px * 100.0 + py * 80.0) * sin(px * 60.0 - py * 40.0);
			float grain2 = sin(px * 150.0 - py * 110.0) * sin(px * 80.0 + py * 60.0);
			if (grain1 > 0.45) {
				col = mix(col, SAND_MID, 0.1);
			}
			if (grain2 > 0.55) {
				col = mix(col, SAND_LIGHT * 1.08, 0.08);
			}
		}

		// Scattered shells / pebbles (sparse)
		float shell = sin(px * 130.0 + 2.3) * cos(py * 95.0 + 1.2) * sin(px * 50.0 + py * 70.0);
		if (shell > 0.78 && sand_t > 0.08 && sand_t < 0.55) {
			col = mix(col, vec3(0.88, 0.83, 0.78), 0.35);
		}

		// Occasional darker pebble
		float peb = sin(px * 170.0 - 1.0) * cos(py * 120.0 + 3.5) * sin(px * 65.0 - py * 45.0);
		if (peb > 0.82 && sand_t > 0.15 && sand_t < 0.7) {
			col = mix(col, vec3(0.4, 0.36, 0.3), 0.25);
		}
	}

	COLOR = vec4(col, 1.0);
}
