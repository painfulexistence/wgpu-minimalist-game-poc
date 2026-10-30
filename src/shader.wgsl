// The whole frame is one fullscreen triangle. Everything is drawn here
// analytically from the 128 bytes of immediates (Vulkan push constants).

struct Frame {
    res: vec2f,
    time: f32,
    py: f32,       // player height above the ground
    score: f32,
    flags: f32,    // state (0 ready, 1 running, 2 dead) + 4 * ducking
    scroll: f32,   // distance travelled, drives parallax
    hi: f32,
    obs: array<vec4f, 6>, // x, y, w, h in world units; w == 0 means unused
}

var<immediate> f: Frame;

const GROUND: f32 = 2.2;
const PLAYER_X: f32 = 3.0;

@vertex
fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
    let uv = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
    return vec4f(uv * 2.0 - 1.0, 0.0, 1.0);
}

fn box(p: vec2f, b: vec2f) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec2f(0.0))) + min(max(d.x, d.y), 0.0);
}

fn rbox(p: vec2f, b: vec2f, r: f32) -> f32 {
    return box(p, b - r) - r;
}

fn hash(x: f32) -> f32 {
    return fract(sin(x * 127.1) * 43758.5453);
}

// 7-segment digit, cell is 0.5 x 1.0 centred on the origin.
fn digit(p: vec2f, n: u32) -> f32 {
    var masks = array<u32, 10>(0x3Fu, 0x06u, 0x5Bu, 0x4Fu, 0x66u, 0x6Du, 0x7Du, 0x07u, 0x7Fu, 0x6Fu);
    let m = masks[min(n, 9u)];
    let h = vec2f(0.16, 0.045);
    let v = vec2f(0.045, 0.2);
    var d = 1e3;
    if (m & 1u) != 0u { d = min(d, box(p - vec2f(0.0, 0.43), h)); }
    if (m & 2u) != 0u { d = min(d, box(p - vec2f(0.19, 0.22), v)); }
    if (m & 4u) != 0u { d = min(d, box(p - vec2f(0.19, -0.22), v)); }
    if (m & 8u) != 0u { d = min(d, box(p - vec2f(0.0, -0.43), h)); }
    if (m & 16u) != 0u { d = min(d, box(p - vec2f(-0.19, -0.22), v)); }
    if (m & 32u) != 0u { d = min(d, box(p - vec2f(-0.19, 0.22), v)); }
    if (m & 64u) != 0u { d = min(d, box(p, h)); }
    return d;
}

// Right-aligned 5 digit number whose top-right corner is at `at`.
fn number(p: vec2f, at: vec2f, value: f32, size: f32) -> f32 {
    let q = (p - at) / size;
    let slot = floor(-q.x / 0.6);
    if slot < 0.0 || slot > 4.0 || q.y > 0.0 || q.y < -1.0 {
        return 1e3;
    }
    let n = u32(floor(value / pow(10.0, slot))) % 10u;
    let local = vec2f(q.x + slot * 0.6 + 0.3, q.y + 0.5);
    return digit(local, n) * size;
}

fn ink(col: vec3f, c: vec3f, d: f32, px: f32) -> vec3f {
    return mix(col, c, 1.0 - smoothstep(-px, px, d));
}

@fragment
fn fs(@builtin(position) fc: vec4f) -> @location(0) vec4f {
    let unit = f.res.y / 10.0;
    let px = 1.0 / unit;
    let p = vec2f(fc.x, f.res.y - fc.y) / unit - vec2f(0.0, GROUND);
    let view_w = f.res.x / unit;
    let state = u32(f.flags) & 3u;
    let duck = f.flags >= 4.0;

    // Sky: dusk gradient with a striped sun sitting on the horizon.
    let t = clamp(p.y / 7.8, 0.0, 1.0);
    var col = mix(vec3f(0.98, 0.55, 0.38), vec3f(0.12, 0.07, 0.25), sqrt(t));
    let sun_c = vec2f(view_w * 0.62, 3.0);
    let sd = length(p - sun_c) - 1.9;
    let stripe = p.y < sun_c.y && fract((p.y - f.time * 0.15) * 2.5) < (sun_c.y - p.y) * 0.25;
    if !stripe {
        col = ink(col, mix(vec3f(1.0, 0.35, 0.45), vec3f(1.0, 0.85, 0.4), clamp((p.y - 0.3) / 3.8, 0.0, 1.0)), sd, px);
    }
    // Stars.
    let sp = p * 2.0 + vec2f(f.scroll * 0.03, 0.0);
    let cell = floor(sp);
    let seed = cell.x * 31.0 + cell.y * 7.0;
    if p.y > 3.5 && sd > 0.0 && hash(seed) > 0.8 {
        let star = length(fract(sp) - 0.2 - 0.6 * vec2f(hash(seed + 1.0), hash(seed + 2.0)));
        let twinkle = 0.6 + 0.4 * sin(f.time * 3.0 + seed);
        col += vec3f(0.9, 0.85, 1.0) * t * twinkle * (1.0 - smoothstep(0.0, 0.06, star));
    }

    // Two parallax ridges.
    let x1 = p.x + f.scroll * 0.15;
    let r1 = 1.5 + 0.7 * sin(x1 * 0.45) + 0.35 * sin(x1 * 1.3 + 1.0);
    col = ink(col, vec3f(0.33, 0.14, 0.36), p.y - r1, px);
    let x2 = p.x + f.scroll * 0.35;
    let r2 = 0.7 + 0.45 * sin(x2 * 0.7 + 2.0) + 0.2 * sin(x2 * 2.1);
    col = ink(col, vec3f(0.2, 0.08, 0.24), p.y - r2, px);

    // Ground with scrolling dashes.
    if p.y < 0.0 {
        col = vec3f(0.1, 0.05, 0.14);
        let dash = fract((p.x + f.scroll) / 1.6) < 0.45 && abs(p.y + 0.4) < 0.04;
        if dash { col = vec3f(0.35, 0.2, 0.45); }
        let pebble = floor((p.x + f.scroll) * 4.0);
        if hash(pebble) > 0.93 && abs(p.y + 0.9 + hash(pebble + 7.0) * 0.6) < 0.04 {
            col = vec3f(0.3, 0.16, 0.38);
        }
    }
    col = ink(col, vec3f(1.0, 0.45, 0.6), abs(p.y) - 0.04, px);

    // Obstacles.
    for (var i = 0u; i < 6u; i++) {
        let o = f.obs[i];
        if o.z <= 0.0 { continue; }
        if o.y == 0.0 {
            // A row of spikes, 0.5 wide each.
            let lx = p.x - o.x;
            let u = fract(lx / 0.5) * 2.0 - 1.0;
            let top = o.w * (1.0 - abs(u));
            let d = max(max(p.y - top, -p.y), max(-lx, lx - o.z));
            let shade = mix(vec3f(0.75, 0.15, 0.4), vec3f(1.0, 0.55, 0.65), clamp(p.y / max(o.w, 0.01), 0.0, 1.0));
            col = ink(col, shade, d * 0.7, px);
        } else {
            // A hovering drone.
            let c = o.xy + o.zw * 0.5;
            let bob = 0.05 * sin(f.time * 9.0 + o.x);
            let q = p - c - vec2f(0.0, bob);
            col = ink(col, vec3f(0.25, 0.85, 1.0), rbox(q, o.zw * 0.5, 0.18), px);
            col = ink(col, vec3f(0.05, 0.1, 0.2), rbox(q, o.zw * 0.5 - 0.1, 0.1), px);
            let blink = step(0.5, fract(f.time * 2.0 + o.x));
            col = ink(col, mix(vec3f(0.2, 0.5, 0.7), vec3f(1.0, 0.95, 0.5), blink), length(q + vec2f(o.z * 0.2, 0.0)) - 0.1, px);
            let spin = abs(sin(f.time * 30.0 + o.x)) * 0.45 + 0.05;
            col = ink(col, vec3f(0.8), box(q - vec2f(0.0, o.w * 0.5 + 0.12), vec2f(spin, 0.03)), px);
        }
    }

    // Player: a squashy cube with one eye.
    var half = vec2f(0.5, 0.5);
    if duck { half = vec2f(0.7, 0.275); }
    let pc = vec2f(PLAYER_X, f.py + half.y);
    let q = p - pc;
    var body = vec3f(0.45, 1.0, 0.75);
    if state == 2u { body = vec3f(1.0, 0.35, 0.35); }
    let shadow = vec2f(max(half.x * (1.0 - f.py * 0.15), 0.15), 0.1);
    let sh = length((p - vec2f(PLAYER_X, -0.05)) / shadow) - 1.0;
    col = mix(col, col * 0.4, 1.0 - smoothstep(0.0, 0.3, sh));
    col = ink(col, body, rbox(q, half, 0.16), px);
    let eye = q - vec2f(half.x - 0.25, half.y - 0.25);
    let eye_d = box(eye, vec2f(0.08, select(0.12, 0.03, state == 2u || duck)));
    col = ink(col, vec3f(0.05, 0.05, 0.12), eye_d, px);

    // Score, with the best score dimmed to its left.
    let top_right = vec2f(view_w - 0.4, 7.4);
    col = ink(col, vec3f(1.0, 0.95, 0.85), number(p, top_right, f.score, 0.55), px);
    if f.hi > 0.0 {
        col = ink(col, vec3f(0.65, 0.55, 0.7), number(p, top_right - vec2f(2.0, 0.0), f.hi, 0.55), px);
    }

    // Ready / game over: dim the scene and pulse a play button.
    if state != 1u {
        col *= select(0.75, 0.55, state == 2u);
        let c = p - vec2f(view_w * 0.5, 3.0);
        let pulse = 1.0 + 0.06 * sin(f.time * 5.0);
        let s = c / pulse;
        let tri = max(-s.x - 0.3, s.x * 0.5 + abs(s.y) * 0.866 - 0.3);
        col = ink(col, vec3f(1.0), abs(length(s) - 0.9) - 0.06, px);
        col = ink(col, vec3f(1.0), tri, px);
    }

    return vec4f(pow(col, vec3f(2.2)), 1.0);
}
