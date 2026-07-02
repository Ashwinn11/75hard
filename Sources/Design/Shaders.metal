#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Shared hash / value noise --------------------------------------------------

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// grain — static paper grain (colorEffect) -----------------------------------

[[stitchable]] half4 grain(float2 position, half4 color, float intensity) {
    float n = hash21(floor(position)) - 0.5;
    return half4(color.rgb + half3(half(n * intensity)) * color.a, color.a);
}

// shimmer — one soft diagonal highlight sweep (colorEffect) -------------------
// progress travels from ~-0.3 to ~1.3; outside [0,1] the band is off-view.

[[stitchable]] half4 shimmer(float2 position, half4 color, float2 size, float progress, float strength) {
    float d = (position.x + position.y) / max(size.x + size.y, 1.0);
    float band = 1.0 - smoothstep(0.0, 0.22, abs(d - progress));
    band *= band;
    return half4(color.rgb + half3(half(band * strength)) * color.a, color.a);
}

// ripple — liquid pulse radiating from a touch point (layerEffect) ------------

[[stitchable]] half4 ripple(float2 position, SwiftUI::Layer layer,
                            float2 origin, float time,
                            float amplitude, float frequency, float decay, float speed) {
    float dist = length(position - origin);
    float delay = dist / speed;
    float t = max(0.0, time - delay);
    float rippleAmount = amplitude * sin(frequency * t) * exp(-decay * t);
    float2 n = dist > 0.5 ? (position - origin) / dist : float2(0);
    half4 color = layer.sample(position + rippleAmount * n);
    color.rgb += half3(half(0.25 * (rippleAmount / amplitude))) * color.a;
    return color;
}

// crumple — paper crumple: noise displacement + crease shading (layerEffect) --

[[stitchable]] half4 crumple(float2 position, SwiftUI::Layer layer, float progress, float seed) {
    if (progress <= 0.001) { return layer.sample(position); }
    float2 p = position / 22.0 + seed;
    float nx = vnoise(p) - 0.5;
    float ny = vnoise(p + 31.7) - 0.5;
    half4 color = layer.sample(position + float2(nx, ny) * 34.0 * progress);
    color.rgb *= half(1.0 + nx * 1.2 * progress);
    return color;
}
