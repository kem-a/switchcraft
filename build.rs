use std::{env, fs, path::Path};

fn main() {
    let out_dir = env::var("OUT_DIR").unwrap();
    let version = env::var("CARGO_PKG_VERSION").unwrap();

    // The About dialog reads the metainfo from the GResource
    let template = "data/com.github.Switchcraft.metainfo.xml.in";
    println!("cargo::rerun-if-changed={template}");
    let metainfo = fs::read_to_string(template)
        .unwrap()
        .replace("@VERSION@", &version);
    fs::write(
        Path::new(&out_dir).join("com.github.Switchcraft.metainfo.xml"),
        metainfo,
    )
    .unwrap();

    glib_build_tools::compile_resources(
        &[out_dir.as_str(), "data/resources", "."],
        "data/resources/switchcraft.gresource.xml",
        "switchcraft.gresource",
    );

    // JSON is read and written with json-glib, like the Vala version
    pkg_config::probe_library("json-glib-1.0").unwrap();
}
