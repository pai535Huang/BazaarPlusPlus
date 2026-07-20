use std::path::Path;

pub fn supports_launch_option_updates(steam_path: &Path) -> bool {
    steam_path.join("userdata").is_dir()
}
