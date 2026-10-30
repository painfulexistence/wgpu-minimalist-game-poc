// Compiles shader.wgsl to SPIR-V at build time, so the game binary only
// embeds the raw words and never parses or translates shaders at runtime.
fn main() {
    println!("cargo:rerun-if-changed=src/shader.wgsl");
    let src = std::fs::read_to_string("src/shader.wgsl").unwrap();
    let module = naga::front::wgsl::parse_str(&src).unwrap_or_else(|e| {
        panic!("{}", e.emit_to_string(&src));
    });
    let info = naga::valid::Validator::new(
        naga::valid::ValidationFlags::all(),
        naga::valid::Capabilities::IMMEDIATES,
    )
    .validate(&module)
    .unwrap();
    let opts = naga::back::spv::Options {
        flags: naga::back::spv::WriterFlags::empty(),
        ..Default::default()
    };
    let words = naga::back::spv::write_vec(&module, &info, &opts, None).unwrap();
    let bytes: Vec<u8> = words.iter().flat_map(|w| w.to_le_bytes()).collect();
    let out = std::path::Path::new(&std::env::var("OUT_DIR").unwrap()).join("shader.spv");
    std::fs::write(out, bytes).unwrap();
}
