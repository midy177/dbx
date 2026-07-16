use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

fn main() {
    if env::var_os("CARGO_FEATURE_EMBEDDED_STATIC").is_none() {
        return;
    }

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR is required"));
    let static_dir = manifest_dir.join("../../dist");
    let index_path = static_dir.join("index.html");
    if !index_path.is_file() {
        panic!("embedded-static requires frontend assets at {}. Run `bun run build` before compiling dbx-web with this feature.", static_dir.display());
    }

    println!("cargo:rerun-if-changed={}", static_dir.display());

    let mut files = Vec::new();
    collect_files(&static_dir, &static_dir, &mut files).expect("failed to collect frontend assets");
    files.sort_by(|a, b| a.0.cmp(&b.0));

    let mut output = String::from(
        "pub struct StaticAsset {\n    pub path: &'static str,\n    pub bytes: &'static [u8],\n    pub content_type: &'static str,\n}\n\npub static ASSETS: &[StaticAsset] = &[\n",
    );

    for (relative, absolute) in files {
        let content_type = content_type_for(&relative);
        output.push_str("    StaticAsset { path: ");
        output.push_str(&format!("{relative:?}"));
        output.push_str(", bytes: include_bytes!(");
        output.push_str(&format!("{:?}", absolute.to_string_lossy()));
        output.push_str("), content_type: ");
        output.push_str(&format!("{content_type:?}"));
        output.push_str(" },\n");
    }

    output.push_str(
        "];\n\npub fn get(path: &str) -> Option<&'static StaticAsset> {\n    ASSETS.iter().find(|asset| asset.path == path)\n}\n",
    );

    let out_dir = PathBuf::from(env::var("OUT_DIR").expect("OUT_DIR is required"));
    fs::write(out_dir.join("embedded_static.rs"), output).expect("failed to write embedded static asset manifest");
}

fn collect_files(root: &Path, dir: &Path, files: &mut Vec<(String, PathBuf)>) -> io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if should_skip_path(root, &path) {
            continue;
        }
        if path.is_dir() {
            collect_files(root, &path, files)?;
            continue;
        }
        if !path.is_file() {
            continue;
        }
        let relative =
            path.strip_prefix(root).expect("asset path should be under root").to_string_lossy().replace('\\', "/");
        files.push((relative, path));
    }
    Ok(())
}

fn should_skip_path(root: &Path, path: &Path) -> bool {
    let relative = match path.strip_prefix(root) {
        Ok(relative) => relative,
        Err(_) => return false,
    };

    relative.starts_with("docker")
        || relative.components().any(|component| component.as_os_str().to_string_lossy().starts_with('.'))
}

fn content_type_for(path: &str) -> &'static str {
    let extension = Path::new(path).extension().and_then(|value| value.to_str()).unwrap_or_default();
    match extension {
        "css" => "text/css; charset=utf-8",
        "gif" => "image/gif",
        "html" => "text/html; charset=utf-8",
        "ico" => "image/x-icon",
        "jpg" | "jpeg" => "image/jpeg",
        "js" | "mjs" => "text/javascript; charset=utf-8",
        "json" | "map" => "application/json; charset=utf-8",
        "png" => "image/png",
        "svg" => "image/svg+xml",
        "txt" => "text/plain; charset=utf-8",
        "wasm" => "application/wasm",
        "woff" => "font/woff",
        "woff2" => "font/woff2",
        _ => "application/octet-stream",
    }
}
