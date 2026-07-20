mod game;
mod steam;

pub(crate) use game::{is_bepinex_installed, is_valid_game_path};
pub(crate) use steam::detect_installation_paths;

use crate::services::game_path::fallback_game_candidates;
use crate::services::path::normalize_requested_game_path;
use crate::services::startup::InstallerContextState;
use game::read_installed_bpp_version;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, State};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct InstallEnvironmentSnapshot {
    pub steam_path: Option<String>,
    pub steam_launch_options_supported: bool,
    pub game_path: Option<String>,
    pub game_path_valid: bool,
    pub bepinex_installed: bool,
    pub bpp_version: Option<String>,
    pub bundled_bpp_version: Option<String>,
}

pub fn detect_for_install(
    app: AppHandle,
    state: State<'_, InstallerContextState>,
    game_path: Option<String>,
) -> Result<InstallEnvironmentSnapshot, String> {
    crate::services::debug_log!(
        "[detect_environment] start requested_game_path={:?}",
        game_path
    );
    // Read cached startup context. On first call this lazily initializes:
    // reads the bundled payload and resolves Steam/game paths.
    let startup = state.get_or_initialize(&app);

    let requested_game_path = normalize_requested_game_path(game_path);
    let steam_path = startup.steam_path.clone();
    let game_path = requested_game_path
        .clone()
        .or_else(|| startup.game_path.clone())
        .or_else(|| {
            fallback_game_candidates()
                .into_iter()
                .find(|path| is_valid_game_path(path))
        });
    let game_path_valid = game_path
        .as_ref()
        .map(|path| is_valid_game_path(path))
        .unwrap_or(false);
    let steam_launch_options_supported = startup.steam_launch_options_supported;
    let bpp_version = game_path
        .as_ref()
        .and_then(|path| read_installed_bpp_version(path));
    let bepinex_installed = game_path
        .as_ref()
        .map(|path| is_bepinex_installed(path))
        .unwrap_or(false);

    crate::services::debug_log!(
        "[detect_environment] resolved steam_path={:?} game_path={:?} bepinex_installed={} bundled_bpp_version={:?}",
        steam_path.as_ref().map(|path| path.display().to_string()),
        game_path.as_ref().map(|path| path.display().to_string()),
        bepinex_installed,
        startup.bundled_bpp_version
    );

    Ok(InstallEnvironmentSnapshot {
        steam_path: steam_path.map(|path| path.to_string_lossy().into_owned()),
        steam_launch_options_supported,
        game_path: game_path.map(|path| path.to_string_lossy().into_owned()),
        game_path_valid,
        bepinex_installed,
        bpp_version,
        bundled_bpp_version: startup.bundled_bpp_version.clone(),
    })
}

pub fn detect_environment(
    app: AppHandle,
    state: State<'_, InstallerContextState>,
    game_path: Option<String>,
) -> Result<InstallEnvironmentSnapshot, String> {
    detect_for_install(app, state, game_path)
}
