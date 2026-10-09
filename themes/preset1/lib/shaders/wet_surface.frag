#include <flutter/runtime_effect.glsl>

uniform float uProgress;
uniform sampler2D uSurface;

out vec4 fragColor;

const float tau = 6.28318530718;
const vec2 artworkSize = vec2(1920.0, 1080.0);

vec3 getSeed(vec2 cell) {
  vec3 seed = fract(vec3(cell.xyx) * vec3(0.1031, 0.1030, 0.0973));
  seed += dot(seed, seed.yxz + 33.33);
  return fract((seed.xxy + seed.yzz) * seed.zyx);
}

// A curved meniscus bends the texture in opposite directions at its edges.
// Keeping rim light separate from displacement avoids painting opaque beads.
vec4 getLens(vec2 delta, vec2 radius) {
  vec2 normal = delta / radius;
  float distance = length(normal);
  float body = 1.0 - smoothstep(0.55, 1.0, distance);
  float rim = 1.0 - smoothstep(0.04, 0.19, abs(distance - 0.82));
  float light = rim * clamp(-normal.y * 0.7 - normal.x * 0.5, 0.0, 1.0);
  float shadow = rim * clamp(normal.y * 0.6 + normal.x * 0.4, 0.0, 1.0);
  return vec4(normal * radius * body * 3.5, light * 0.2, shadow * 0.22);
}

vec4 getCondensation(vec2 position) {
  vec2 grid = vec2(23.0, 29.0);
  vec2 cell = floor(position / grid);
  vec3 seed = getSeed(cell);
  vec2 center = (cell + 0.18 + seed.xy * 0.64) * grid;
  float radius = 0.6 + seed.z * 1.8;
  return getLens(position - center, vec2(radius, radius * 1.12))
      * step(0.58, seed.x);
}

vec4 getSlidingDrops(vec2 position) {
  const vec2 grid = vec2(86.0, 260.0);
  float column = floor(position.x / grid.x);
  vec3 columnSeed = getSeed(vec2(column, 17.0));
  float cycles = 1.0 + floor(columnSeed.x * 4.0);
  float phase = tau * (uProgress * cycles + columnSeed.y);
  // The six-row field repeats outside the viewport. Whole cycles and a small
  // periodic speed variation keep the 120-second loop continuous.
  vec2 moving = position - vec2(0.0,
      uProgress * 1560.0 * cycles + sin(phase) * 34.0);
  vec2 cell = floor(moving / grid);
  vec3 seed = getSeed(vec2(cell.x, mod(cell.y, 6.0)));
  vec2 center = vec2(0.2 + seed.x * 0.6, 0.46 + seed.y * 0.32);
  vec2 delta = (fract(moving / grid) - center) * grid;
  delta.x += sin(position.y * 0.018 + seed.z * tau) * 1.4;
  float radius = 1.5 + seed.z * 2.1;
  vec4 lens = getLens(delta, vec2(radius, radius * 1.65));

  float trailLength = 24.0 + seed.y * 86.0;
  float trail = (1.0 - smoothstep(0.3, 1.3, abs(delta.x)))
      * smoothstep(-trailLength, -trailLength * 0.2, delta.y)
      * (1.0 - smoothstep(-radius, radius, delta.y));
  float beads = 0.65 + 0.35 * sin(delta.y * 0.24 + seed.z * tau);
  lens.x += delta.x * trail * beads * 2.5;
  lens.z += trail * beads * 0.035;
  lens.w += trail * 0.055;
  return lens * step(0.22, seed.z);
}

vec2 getWaterDisplacement(vec2 position, float angle) {
  float along = position.x * 0.005 + position.y * 0.0018;
  float across = (position.y + position.x * 710.0 / 1920.0) * 0.024;
  float swell = sin(across - angle * 12.0 + sin(along - angle * 3.0) * 0.8);
  float ripple = sin(across * 2.7 + along - angle * 29.0);
  return vec2(swell * 3.0 + ripple * 0.7, swell * 5.5 + ripple * 1.4);
}

void main() {
  vec2 position = FlutterFragCoord().xy;
  float angle = tau * uProgress;
  float edge = position.y - (920.0 - position.x * 710.0 / 1920.0);
  float wet = smoothstep(0.0, 28.0, edge);
  vec4 glass = getCondensation(position) + getSlidingDrops(position);
  vec2 refracted = position + glass.xy * wet;
  vec2 flow = getWaterDisplacement(refracted, angle) * wet;
  vec2 uv = clamp((refracted + flow) / artworkSize, vec2(0.001), vec2(0.999));
  vec3 color = texture(uSurface, uv).rgb;

  // Traveling highlights follow the diagonal current, while the much slower
  // glass drops keep their gravity direction independent of the water.
  float across = (refracted.y + refracted.x * 710.0 / 1920.0) * 0.036;
  float along = refracted.x * 0.006;
  float wave = sin(across - angle * 18.0 + sin(along - angle * 4.0) * 0.7);
  float glint = pow(max(0.0, wave), 12.0)
      * (0.55 + 0.45 * sin(along + across * 0.3 - angle * 7.0));
  color += vec3(0.64, 0.69, 0.8) * glint * 0.025 * wet;
  color = color * (1.0 - glass.w * wet)
      + vec3(0.72, 0.77, 0.86) * glass.z * wet;
  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
