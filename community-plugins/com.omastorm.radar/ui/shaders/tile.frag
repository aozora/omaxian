#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
// Tints one basemap tile mask (docs/protocol.md, tiles) with theme colors.
// The tints arrive straight (not premultiplied) with their alpha.
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 boundaries;
    vec4 water;
    vec4 minorRoads;
    vec4 majorRoads;
};
// R boundaries, G water, B minor roads, A = 1 - major roads. Qt uploads the
// PNG premultiplied by A, so R, G, and B arrive scaled by it.
layout(binding = 1) uniform sampler2D mask;
// One layer's premultiplied contribution at coverage c.
vec4 layer(vec4 tint, float c) { return vec4(tint.rgb * tint.a, tint.a) * c; }
vec4 over(vec4 top, vec4 under) { return top + under * (1.0 - top.a); }
void main() {
    vec4 t = texture(mask, qt_TexCoord0);
    vec3 straight = t.a > 0.0 ? t.rgb / t.a : vec3(0.0);
    float major = 1.0 - t.a;
    vec4 color = layer(water, straight.g);
    color = over(layer(boundaries, straight.r), color);
    color = over(layer(minorRoads, straight.b), color);
    color = over(layer(majorRoads, major), color);
    fragColor = color * qt_Opacity;
}
