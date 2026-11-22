#version 440

// Aurora: three curtains of light hanging over a slow, domain-warped haze.
// Everything is a blend towards the three theme colours over transparency, so it
// works on dark and light themes alike. Output is premultiplied alpha.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  float time;       // seconds, free running
  float intensity;  // 0..1, overall strength
  float aspect;     // width / height
  vec4 colorA;      // curtain hem (cyan)
  vec4 colorB;      // curtain body (accent)
  vec4 colorC;      // curtain top (magenta)
};

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 3; i++) {
    v += a * noise(p);
    p = p * 2.03 + vec2(17.1, 9.2);
    a *= 0.5;
  }
  return v / 0.875;
}

vec3 ramp(float h) {
  vec3 c = mix(colorA.rgb, colorB.rgb, smoothstep(0.0, 0.22, h));
  return mix(c, colorC.rgb, smoothstep(0.16, 0.55, h));
}

void main() {
  vec2 p = vec2(qt_TexCoord0.x * aspect, 1.0 - qt_TexCoord0.y);
  float t = time * 3.5;   // flow speed

  vec3 sum = vec3(0.0);
  float weight = 0.0;
  float clear = 1.0;

  // Haze: slow warped fbm, giving the curtains something to hang in.
  vec2 q = p * 1.1 + vec2(t * 0.012, -t * 0.008);
  vec2 warp = vec2(fbm(q + vec2(0.0, t * 0.02)), fbm(q + vec2(5.2, 1.3) - vec2(t * 0.016, 0.0)));
  float haze = fbm(q + 1.8 * warp);
  float hazeA = 0.13 * smoothstep(0.30, 0.85, haze) * smoothstep(0.0, 0.5, p.y);
  vec3 hazeC = mix(colorB.rgb, colorC.rgb, smoothstep(0.25, 0.75, warp.x));
  hazeC = mix(hazeC, colorA.rgb, smoothstep(0.55, 0.9, warp.y) * 0.6);
  sum += hazeC * hazeA;
  weight += hazeA;
  clear *= 1.0 - hazeA;

  // Curtains, far to near.
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float seed = fi * 7.31 + 1.7;
    float scale = 1.5 - 0.25 * fi;      // far curtains are finer
    float speed = 0.7 + 0.3 * fi;       // and slower
    float tt = t * speed;

    // Sideways sway that grows with height, so rays lean and breathe.
    float x = p.x * scale + seed;
    x += (noise(vec2(p.y * 1.3 + seed, tt * 0.05)) - 0.5) * 0.30;

    // The hem: travelling waves plus noise. Its slope says where the curtain
    // folds towards the viewer, and folds are brighter.
    float w1 = x * 2.1 + tt * 0.10 + seed;
    float w2 = x * 4.3 - tt * 0.07 + seed * 1.7;
    float hem = 0.47 - 0.12 * fi
              + 0.060 * sin(w1) + 0.028 * sin(w2)
              + 0.20 * (noise(vec2(x * 0.7 - tt * 0.03, tt * 0.035 + seed)) - 0.5);
    float slope = abs(0.126 * cos(w1) + 0.120 * cos(w2));

    // Pulses of light running along the ribbon, alternating direction per curtain.
    // They lift the hem a touch as they pass, so the curtain ripples.
    float dir = 1.0 - 2.0 * mod(fi, 2.0);
    float ph = x * 1.7 - dir * time * (0.95 + 0.2 * fi) + seed
             + 2.5 * noise(vec2(x * 0.6 + seed, time * 0.12));
    float pulse = smoothstep(0.35, 1.0, sin(ph)) * smoothstep(0.25, 0.7, noise(vec2(ph * 0.16, seed)));
    hem += 0.022 * pulse;
    float h = p.y - hem;

    // Vertical rays: fine and coarse streaks drifting along the curtain.
    float coarse = smoothstep(0.15, 0.85, noise(vec2(x * 5.0 - tt * 0.09, seed + tt * 0.04)));
    float fine = noise(vec2(x * 16.0 + tt * 0.16, seed)) * 0.65
               + noise(vec2(x * 41.0 - tt * 0.22, seed + 3.0)) * 0.35;
    fine = smoothstep(0.25, 0.80, fine);
    float rays = mix(0.30, 1.0, fine) * mix(0.30, 1.0, coarse);
    // Rays show most a little above the hem; the hem itself stays a clean line.
    rays = mix(1.0, rays, smoothstep(-0.02, 0.12, h) * 0.92);

    // Crisp hem with a faint underglow, and a fade upwards whose reach varies ray by ray.
    float reach = (2.4 + 0.5 * fi) * mix(1.9, 0.75, coarse * fine) * (1.0 - 0.3 * pulse);
    float body = h > 0.0 ? exp(-h * reach) : 0.75 * exp(h * 34.0) + 0.25 * exp(h * 9.0);

    // Whole stretches of curtain brighten and fade.
    float swell = smoothstep(0.2, 0.8, noise(vec2(x * 0.9 + tt * 0.045, tt * 0.03 + seed * 2.0)));

    // Shimmer climbing the rays.
    float shimmer = mix(0.8, 1.2, noise(vec2(x * 9.0 + seed, h * 5.0 - time * 1.4)));

    float a = body * rays * shimmer * mix(0.22, 1.0, swell) * (0.75 + 1.6 * slope)
            * (1.0 + 0.9 * pulse) * (0.42 + 0.10 * fi);
    a = min(a, 0.9);
    vec3 c = ramp(h * (1.0 + 0.25 * fi) + 0.06 * (fi - 1.0));
    sum += c * a;
    weight += a;
    clear *= 1.0 - a;
  }

  float alpha = 1.0 - clear;
  vec3 col = sum / max(weight, 1e-4);

  // Calm the bottom where the prompt bar sits, soften the very top.
  alpha *= mix(0.35, 1.0, smoothstep(0.0, 0.30, p.y)) * mix(0.75, 1.0, smoothstep(1.0, 0.8, p.y));
  alpha *= intensity;

  // Dither away banding.
  float d = (hash(gl_FragCoord.xy + fract(t) * 61.0) + hash(gl_FragCoord.yx + 13.7) - 1.0) / 255.0;
  alpha = clamp(alpha + d * 1.5, 0.0, 1.0);

  fragColor = vec4(col * alpha, alpha) * qt_Opacity;
}
