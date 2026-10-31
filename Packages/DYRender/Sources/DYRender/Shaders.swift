import Foundation

/// Metal shading language source, compiled at runtime so the package needs no build-time Metal toolchain.
enum Shaders {
    /// Headers and the uniform block shared by the tile and arc pipelines. Must match `TileUniforms`.
    static let prelude = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 viewSize; float gap; float scale;
        float4 background; float4 surface; float4 accent; float4 removeColor; float4 keepColor; float4 laterColor; float4 text;
    };
    """

    /// Shared helpers: hashing, signed distances, the lacquer cushion, dust motes and decision marks.
    static let helpers = """
    uint pcg(uint v) {
        uint s = v * 747796405u + 2891336453u;
        uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
        return (w >> 22u) ^ w;
    }
    float rnd(int2 p, uint seed, uint salt) {
        return float(pcg(pcg(uint(p.x) + salt * 7919u) + uint(p.y) * 2531u + seed * 40503u)) * (1.0 / 4294967295.0);
    }
    float sdRoundBox(float2 p, float2 b, float r) {
        float2 q = abs(p) - b + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }
    float sdSegment(float2 p, float2 a, float2 b) {
        float2 pa = p - a, ba = b - a;
        float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        return length(pa - ba * h);
    }
    float2 boxGradient(float2 p, float2 b, float r) {
        float2 q = abs(p) - b + r;
        float2 s = float2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
        if (q.x > 0.0 || q.y > 0.0) return normalize(max(q, 0.0) + 1e-5) * s;
        return q.x > q.y ? float2(s.x, 0.0) : float2(0.0, s.y);
    }
    float coverage(float sd) { return clamp(0.5 - sd, 0.0, 1.0); }

    // Brightness-only lacquer: a broad soft gradient, a narrow lit edge and a faint glint. Hue is never touched.
    float cushion(float2 local, float2 half2, float di, float2 grad, float scale, float minSide, thread float& spec) {
        float ew = clamp(minSide * 0.05, 1.1 * scale, 3.0 * scale);
        float edge = exp(-di / ew);
        float2 L2 = normalize(float2(-0.55, -0.83));
        float edgeLight = dot(grad, L2) * edge;
        float2 uv = local / max(half2 * 2.0, float2(1.0));
        float broad = 1.0 - 0.15 * uv.y - 0.05 * uv.x;
        float2 g = uv - float2(-0.28, -0.34);
        float sheen = 0.05 * exp(-dot(g, g) * 6.0);
        float s = max(dot(grad, L2), 0.0);
        spec = s * s * exp(-di / (1.0 * scale));
        return (broad + sheen) * (1.0 + 0.42 * edgeLight);
    }

    // Dust: a dark bed with scattered motes, each a tiny round speck in the tile's own hue.
    float3 dustColor(float3 base, float2 pos, uint seed, float density, float di, constant Uniforms& u) {
        float3 bed = mix(u.surface.rgb * 0.75, base, 0.10) * mix(0.8, 1.0, smoothstep(0.0, 10.0 * u.scale, di));
        float cell = 2.6 * u.scale;
        int2 id = int2(floor(pos / cell));
        uint h = pcg(pcg(uint(id.x) + 7919u) + uint(id.y) * 2531u + seed * 40503u);
        float present = float(h & 2047u) * (1.0 / 2047.0);
        if (present >= density) return bed;
        float2 jitter = float2(float((h >> 11u) & 255u), float((h >> 19u) & 255u)) * (1.0 / 255.0);
        float tone = float((h >> 27u) & 31u) * (1.0 / 31.0);
        float2 centre = (float2(id) + 0.28 + 0.44 * jitter) * cell;
        float radiusDot = (0.30 + 0.38 * tone) * u.scale;
        float3 mote = base * (0.65 + 0.85 * tone * tone);
        mote = mix(mote, float3(1.0, 0.97, 0.9) * 0.85, step(0.965, tone) * 0.45);
        return mix(bed, mote, coverage(length(pos - centre) - radiusDot));
    }

    // Diagonal hatch that marks staged removal.
    float3 hatchRemove(float3 col, float2 p, constant Uniforms& u) {
        float stripe = fract((p.x + p.y) / (8.0 * u.scale));
        float line = smoothstep(0.40, 0.46, stripe) * smoothstep(0.62, 0.56, stripe);
        return mix(col, u.removeColor.rgb, line * 0.40 + 0.05);
    }

    // A keep check badge, a later dot or a remove ring centred on `p`.
    float3 decisionGlyph(float3 col, float2 p, float decision, constant Uniforms& u) {
        float3 ink = float3(0.05, 0.04, 0.03);
        if (decision < 1.5) {
            float badge = length(p) - 5.6 * u.scale;
            float stroke = min(sdSegment(p, float2(-2.7, 0.3) * u.scale, float2(-0.8, 2.3) * u.scale),
                               sdSegment(p, float2(-0.8, 2.3) * u.scale, float2(2.9, -2.3) * u.scale)) - 0.85 * u.scale;
            col = mix(col, ink, coverage(badge - 1.3 * u.scale) * 0.5);
            col = mix(col, u.keepColor.rgb, coverage(badge));
            return mix(col, float3(0.04, 0.09, 0.06), coverage(stroke));
        }
        col = mix(col, ink, coverage(length(p) - 5.6 * u.scale) * 0.5);
        if (decision > 2.5) return mix(col, u.laterColor.rgb, coverage(length(p) - 3.4 * u.scale));
        return mix(col, u.removeColor.rgb, coverage(abs(length(p) - 3.4 * u.scale) - 0.9 * u.scale));
    }
    """

    static let tiles = """
    \(prelude)

    struct TileInstance { float4 rect; float4 color; float4 params; float4 state; float4 extra; };
    struct TileOut { float4 position [[position]]; float2 local; uint instance [[flat]]; };

    vertex TileOut tileVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                              constant TileInstance* tiles [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
        TileInstance t = tiles[iid];
        float2 corner = float2(float(vid & 1u), float(vid >> 1u));
        float2 half2 = t.rect.zw * 0.5;
        float pad = 3.0 + t.params.w * 26.0 * u.scale * 0.5;
        float2 local = (corner * 2.0 - 1.0) * (half2 + pad);
        float2 px = t.rect.xy + half2 + local;
        TileOut o;
        o.position = float4(px.x / u.viewSize.x * 2.0 - 1.0, 1.0 - px.y / u.viewSize.y * 2.0, 0.0, 1.0);
        o.local = local;
        o.instance = iid;
        return o;
    }

    \(helpers)

    fragment float4 tileFragment(TileOut in [[stage_in]], constant TileInstance* tiles [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
        TileInstance t = tiles[in.instance];
        float type = t.params.y;
        float2 half2 = max(t.rect.zw * 0.5 - (type > 2.5 ? 0.0 : u.gap * 0.5), float2(0.3));
        float radius = min(t.params.x, min(half2.x, half2.y));
        float d = sdRoundBox(in.local, half2, radius);
        float cover = coverage(d);
        float opacity = t.color.a;
        float glow = t.params.w;
        float glowA = 0.0;
        if (glow > 0.0 && d > 0.0) {
            glowA = glow * opacity * (0.42 * exp(-d / (5.0 * u.scale)) + 0.07 * exp(-d / (14.0 * u.scale)));
        }
        if (cover <= 0.0 && glowA < 0.004) discard_fragment();
        // A fully expanded plate is hidden by its children everywhere except its frame, so skip those pixels.
        if (type > 0.5 && type < 1.5 && t.params.z > 0.99 && opacity > 0.99) {
            float2 box = t.rect.zw * 0.5;
            float m = 1.5 * u.scale;
            if (in.local.x > -box.x + t.extra.z + m && in.local.x < box.x - t.extra.z - m &&
                in.local.y > -box.y + t.extra.w + m && in.local.y < box.y - t.extra.z - m) discard_fragment();
        }

        float3 base = t.color.rgb;
        float minSide = min(half2.x, half2.y) * 2.0;
        float di = max(-d, 0.0);
        float2 grad = float2(0.0);
        float spec = 0.0, shade = 1.0;
        if (type < 1.5) {
            if (di < 48.0 * u.scale) grad = boxGradient(in.local, half2, radius);
            shade = cushion(in.local, half2, di, grad, u.scale, minSide, spec);
        }
        uint seed = uint(t.extra.x);
        float3 col;

        if (type < 0.5) {
            col = base * shade + spec * 0.20 * mix(base, float3(1.0), 0.30);
        } else if (type < 1.5) {
            float expand = t.params.z;
            float3 tileCol = base * shade + spec * 0.20 * mix(base, float3(1.0), 0.30);
            float depthLift = 1.0 + 0.07 * min(t.extra.y, 5.0);
            float3 plate = mix(u.surface.rgb * 0.82, base, 0.07) * depthLift;
            float lip = mix(0.78, 1.0, smoothstep(0.0, 14.0 * u.scale, di));
            float rim = smoothstep(1.6 * u.scale, 0.0, di) * clamp(-grad.y * 0.5 + 0.5, 0.0, 1.0);
            plate = plate * lip + rim * 0.045;
            col = mix(tileCol, plate, expand);
        } else if (type > 2.5) {
            col = base;
        } else {
            col = dustColor(base, in.local + t.rect.zw * 0.5, seed, t.params.z, di, u);
        }

        // Decision marks: hatch for remove, check badge for keep, dot for later. Shape carries the meaning, colour only helps.
        float decision = t.state.x;
        if (decision > 1.5 && decision < 2.5 && type < 1.5) col = hatchRemove(col, in.local, u);
        if (step(22.0 * u.scale, minSide) * step(type, 1.5) > 0.0 && decision > 0.5 && t.state.w > 0.5) {
            col = decisionGlyph(col, in.local - float2(half2.x - 11.0 * u.scale, -half2.y + 11.0 * u.scale), decision, u);
        }

        // Hover lifts the tile; selection is a gold ring, because focus is one of the two things gold means.
        col *= 1.0 + 0.10 * t.state.z;
        col = mix(col, u.text.rgb, coverage(abs(di - 0.8 * u.scale) - 0.7 * u.scale) * 0.55 * t.state.z);
        float ring = coverage(abs(di - 1.9 * u.scale) - 1.2 * u.scale) * t.state.y;
        col = mix(col, u.accent.rgb, ring);

        if (glow > 0.0 && type < 1.5) col += u.accent.rgb * glow * 0.11 * smoothstep(12.0 * u.scale, 0.0, di);

        float alpha = cover * opacity;
        float outAlpha = alpha + (1.0 - alpha) * glowA;
        float3 rgb = (col * alpha + u.accent.rgb * glowA * (1.0 - alpha)) / max(outAlpha, 1e-4);
        return float4(rgb, outAlpha);
    }

    struct LabelInstance { float4 rect; float4 uv; float4 color; float4 rotation; };
    struct LabelOut { float4 position [[position]]; float2 uv; float4 color; };

    vertex LabelOut labelVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                constant LabelInstance* labels [[buffer(0)]], constant float2& viewSize [[buffer(1)]]) {
        LabelInstance l = labels[iid];
        float2 corner = float2(float(vid & 1u), float(vid >> 1u));
        float2 px = l.rect.xy + corner * l.rect.zw;
        if (l.rotation.z != 0.0) {
            float2 rel = px - l.rotation.xy;
            float c = cos(l.rotation.z), sn = sin(l.rotation.z);
            px = l.rotation.xy + float2(rel.x * c - rel.y * sn, rel.x * sn + rel.y * c);
        }
        LabelOut o;
        o.position = float4(px.x / viewSize.x * 2.0 - 1.0, 1.0 - px.y / viewSize.y * 2.0, 0.0, 1.0);
        o.uv = mix(l.uv.xy, l.uv.zw, corner);
        o.color = l.color;
        return o;
    }

    fragment float4 labelFragment(LabelOut in [[stage_in]], texture2d<float> atlas [[texture(0)]], sampler smp [[sampler(0)]]) {
        float a = atlas.sample(smp, in.uv).r;
        a = pow(a, 0.78);
        return float4(in.color.rgb, in.color.a * a);
    }
    """

    /// Sunburst arcs: annular sectors shaded like the map's tiles.
    static let rings = """
    \(prelude)

    struct ArcInstance { float4 geom; float4 angles; float4 color; float4 state; float4 extra; float4 bbox; };
    struct ArcOut { float4 position [[position]]; float2 pos; uint instance [[flat]]; };

    vertex ArcOut ringVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                             constant ArcInstance* arcs [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
        ArcInstance a = arcs[iid];
        float2 corner = float2(float(vid & 1u), float(vid >> 1u));
        float2 px = a.bbox.xy + corner * a.bbox.zw;
        ArcOut o;
        o.position = float4(px.x / u.viewSize.x * 2.0 - 1.0, 1.0 - px.y / u.viewSize.y * 2.0, 0.0, 1.0);
        o.pos = px;
        o.instance = iid;
        return o;
    }

    \(helpers)

    fragment float4 ringFragment(ArcOut in [[stage_in]], constant ArcInstance* arcs [[buffer(0)]], constant Uniforms& u [[buffer(1)]]) {
        ArcInstance a = arcs[in.instance];
        float2 p = in.pos - a.geom.xy;
        float r = length(p);
        float theta = atan2(p.y, p.x);
        float mid = 0.5 * (a.angles.x + a.angles.y), halfA = 0.5 * (a.angles.y - a.angles.x);
        float dth = theta - mid;
        dth -= 6.2831853 * round(dth / 6.2831853);
        float rm = 0.5 * (a.geom.z + a.geom.w), hw = 0.5 * (a.geom.w - a.geom.z);
        float2 half2 = float2(max(hw - u.gap * 0.5, 0.3), max(halfA * r - u.gap * 0.5, 0.3));
        float rad = min(a.angles.z, min(half2.x, half2.y));
        float2 q = float2(abs(r - rm), abs(dth) * r) - half2 + rad;
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
        float cover = coverage(d);
        float opacity = a.color.a, glow = a.extra.z, type = a.angles.w;
        float glowA = 0.0;
        if (glow > 0.0 && d > 0.0) glowA = glow * opacity * (0.42 * exp(-d / (5.0 * u.scale)) + 0.07 * exp(-d / (14.0 * u.scale)));
        if (cover <= 0.0 && glowA < 0.004) discard_fragment();

        float3 base = a.color.rgb;
        float di = max(-d, 0.0);
        float2 radial = float2(cos(theta), sin(theta));
        float2 tangent = float2(-radial.y, radial.x);
        float2 grad = q.x > q.y ? radial * (r > rm ? 1.0 : -1.0) : tangent * (dth > 0.0 ? 1.0 : -1.0);
        float minSide = 2.0 * min(half2.x, half2.y);
        float2 centre = a.geom.xy + float2(cos(mid), sin(mid)) * rm;
        float spec = 0.0;
        float3 col;
        if (type < 1.5) {
            float shade = cushion(in.pos - centre, float2(max(hw, min(halfA * rm, 3.0 * hw))), di, grad, u.scale, minSide, spec);
            col = base * shade * (1.0 - 0.025 * a.extra.y) + spec * 0.20 * mix(base, float3(1.0), 0.30);
        } else {
            col = dustColor(base, in.pos, uint(a.extra.x), a.extra.w, di, u);
        }
        float decision = a.state.x;
        if (decision > 1.5 && decision < 2.5 && type < 1.5) col = hatchRemove(col, in.pos, u);
        if (type < 1.5 && decision > 0.5 && a.state.w > 0.5) col = decisionGlyph(col, in.pos - centre, decision, u);
        col *= 1.0 + 0.10 * a.state.z;
        col = mix(col, u.text.rgb, coverage(abs(di - 0.8 * u.scale) - 0.7 * u.scale) * 0.55 * a.state.z);
        col = mix(col, u.accent.rgb, coverage(abs(di - 1.9 * u.scale) - 1.2 * u.scale) * a.state.y);
        if (glow > 0.0 && type < 1.5) col += u.accent.rgb * glow * 0.11 * smoothstep(12.0 * u.scale, 0.0, di);

        float alpha = cover * opacity;
        float outAlpha = alpha + (1.0 - alpha) * glowA;
        return float4((col * alpha + u.accent.rgb * glowA * (1.0 - alpha)) / max(outAlpha, 1e-4), outAlpha);
    }
    """

    /// Field: additive star points into a half-float target, then a tone-mapping pass with a mip-chain bloom.
    static let field = """
    #include <metal_stdlib>
    using namespace metal;

    struct FieldUniforms {
        float2 viewSize; float2 plotOrigin; float2 plotSize; float2 xRange; float2 yRange;
        float scale; float exposure; float2 pad;
        float4 background; float4 accent;
    };
    struct StarOut { float4 position [[position]]; float3 color; float point [[point_size]]; };

    vertex StarOut starVertex(uint vid [[vertex_id]], constant float2* positions [[buffer(0)]], constant uchar4* colors [[buffer(1)]],
                              constant FieldUniforms& u [[buffer(2)]]) {
        float2 d = positions[vid];
        float fx = (d.x - u.xRange.x) / (u.xRange.y - u.xRange.x);
        float fy = (d.y - u.yRange.x) / (u.yRange.y - u.yRange.x);
        float2 px = float2(u.plotOrigin.x + fx * u.plotSize.x, u.plotOrigin.y + (1.0 - fy) * u.plotSize.y);
        float t = clamp(fy, 0.0, 1.0);
        uchar4 c = colors[vid];
        float boost = c.w > 0 ? 2.4 : 1.0;
        StarOut o;
        bool inside = fx >= 0.0 && fx <= 1.0 && fy >= 0.0 && fy <= 1.0;
        o.position = inside ? float4(px.x / u.viewSize.x * 2.0 - 1.0, 1.0 - px.y / u.viewSize.y * 2.0, 0.0, 1.0) : float4(2.0, 2.0, 0.0, 1.0);
        o.point = (1.2 + 16.0 * pow(t, 2.8) + u.pad.x * 5.0) * u.scale * boost;
        float intensity = (0.12 + 1.5 * pow(t, 2.8) + u.pad.x * 0.75) * (c.w > 0 ? 2.0 : 1.0);
        o.color = float3(c.rgb) / 255.0 * intensity;
        return o;
    }

    fragment float4 starFragment(StarOut in [[stage_in]], float2 pc [[point_coord]]) {
        float2 d = (pc - 0.5) * 2.0;
        float r2 = dot(d, d);
        if (r2 > 1.0) discard_fragment();
        return float4(in.color * exp(-r2 * 3.6), 1.0);
    }

    struct ToneOut { float4 position [[position]]; float2 uv; };

    vertex ToneOut toneVertex(uint vid [[vertex_id]]) {
        float2 p = float2(float((vid << 1u) & 2u), float(vid & 2u));
        ToneOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = float2(p.x, 1.0 - p.y);
        return o;
    }

    fragment float4 toneFragment(ToneOut in [[stage_in]], texture2d<float> hdr [[texture(0)]], sampler smp [[sampler(0)]],
                                 constant FieldUniforms& u [[buffer(0)]]) {
        float3 base = hdr.sample(smp, in.uv, level(0)).rgb;
        float3 bloom = hdr.sample(smp, in.uv, level(2)).rgb * 0.4 + hdr.sample(smp, in.uv, level(4)).rgb * 0.6
                     + hdr.sample(smp, in.uv, level(6)).rgb * 1.0;
        float3 c = base + bloom;
        float lum = max(dot(c, float3(0.2126, 0.7152, 0.0722)), 1e-5);
        float mapped = 1.0 - exp(-lum * u.exposure);
        float3 col = c * (mapped / lum);
        col = mix(col, float3(mapped), smoothstep(0.75, 1.0, mapped) * 0.45);
        float2 f = (in.uv * u.viewSize - u.plotOrigin) / u.plotSize;
        float corner = pow(clamp(f.x, 0.0, 1.0), 2.4) * pow(clamp(1.0 - f.y, 0.0, 1.0), 2.4);
        float3 bg = u.background.rgb * (1.0 + 0.6 * (1.0 - f.y) * 0.1) + u.accent.rgb * 0.17 * corner;
        return float4(bg + col, 1.0);
    }
    """
}
