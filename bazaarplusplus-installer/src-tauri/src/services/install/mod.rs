mod types;

pub use types::{
    FileActionResult, GameDirectorySelection, InstallActions, InstallGameState, InstallModState,
    InstallState, InstallWarning, ResetBppDataResult,
};

use std::process::Command;

use tauri::Manager;

use std::path::Path;

use crate::services::{
    bepinex::{install_bepinex, reset_bpp_data, uninstall_bpp},
    detect::detect_for_install,
    startup::InstallerContextState,
    vdf::patch_launch_options,
};
use crate::stream::state::StreamRuntimeState;

const STEAM_BAZAAR_URL: &str = "steam://rungameid/1617400";

pub fn build_install_state(
    app: tauri::AppHandle,
    state: tauri::State<'_, InstallerContextState>,
    game_path: Option<String>,
) -> Result<InstallState, String> {
    let snapshot = detect_for_install(app, state, game_path)?;
    Ok(install_state_from_snapshot(snapshot))
}

pub async fn run_install(
    app: tauri::AppHandle,
    state: tauri::State<'_, InstallerContextState>,
    game_path: String,
) -> Result<InstallState, String> {
    let before = detect_for_install(app.clone(), state, Some(game_path.clone()))?;
    let steam_path = before.steam_path.clone().unwrap_or_default();
    let has_steam_path = !steam_path.trim().is_empty();
    let app_for_task = app.clone();
    let game_path_for_task = game_path.clone();
    let patch_launch_options_supported = before.steam_launch_options_supported;
    tauri::async_runtime::spawn_blocking(move || {
        install_bepinex(
            app_for_task.clone(),
            steam_path.clone(),
            game_path_for_task.clone(),
        )?;
        if patch_launch_options_supported && has_steam_path {
            let _ = patch_launch_options(app_for_task, steam_path.clone(), game_path_for_task)?;
        }
        Ok::<(), String>(())
    })
    .await
    .map_err(|err| format!("failed to run install task: {err}"))??;

    let app_for_state = app.clone();
    let state = app_for_state.state::<InstallerContextState>();
    build_install_state(app, state, Some(game_path))
}

pub async fn run_reset_bpp_data(
    app: tauri::AppHandle,
    install_state: tauri::State<'_, InstallerContextState>,
    stream_state: tauri::State<'_, StreamRuntimeState>,
    game_path: String,
) -> Result<ResetBppDataResult, String> {
    let removed_data = reset_bpp_data(stream_state, game_path.clone()).await?;
    let state = build_install_state(app, install_state, Some(game_path))?;
    Ok(ResetBppDataResult {
        state,
        removed_data,
    })
}

pub async fn run_uninstall(
    app: tauri::AppHandle,
    state: tauri::State<'_, InstallerContextState>,
    game_path: String,
) -> Result<InstallState, String> {
    let before = detect_for_install(app.clone(), state, Some(game_path.clone()))?;
    let app_for_task = app.clone();
    let steam_path = before.steam_path.clone().unwrap_or_default();
    let game_path_for_task = game_path.clone();
    tauri::async_runtime::spawn_blocking(move || {
        uninstall_bpp(app_for_task, steam_path, game_path_for_task)
    })
    .await
    .map_err(|err| format!("failed to run uninstall task: {err}"))??;

    let app_for_state = app.clone();
    let state = app_for_state.state::<InstallerContextState>();
    build_install_state(app, state, Some(game_path))
}

pub fn launch_game_via_steam() -> Result<(), String> {
    open_url(STEAM_BAZAAR_URL)
}

pub fn launch_game_auto(
    _app: tauri::AppHandle,
    _state: tauri::State<'_, InstallerContextState>,
    _game_path: Option<String>,
) -> Result<(), String> {
    launch_game_via_steam()
}

fn install_state_from_snapshot(
    env: crate::services::detect::InstallEnvironmentSnapshot,
) -> InstallState {
    let selected_game_path = env.game_path.clone();
    let game_found = selected_game_path.is_some();
    let installed = env.bepinex_installed;
    let plugin_version_matches = match (&env.bpp_version, &env.bundled_bpp_version) {
        (Some(installed_version), Some(bundled)) => installed_version == bundled,
        (None, _) => false,
        (_, None) => installed,
    };
    let version_matches = plugin_version_matches;
    let can_launch = game_found && env.game_path_valid;
    let has_resettable_data = has_resettable_bpp_data(env.game_path.as_deref());
    let launch_flow = "steam".to_string();
    let mut warnings = Vec::new();
    if !game_found || !env.game_path_valid {
        warnings.push(InstallWarning {
            code: "game_missing".to_string(),
            message: "未找到有效的 The Bazaar 安装目录。".to_string(),
        });
    }
    if launch_flow == "steam" && !env.steam_launch_options_supported {
        warnings.push(InstallWarning {
            code: "launch_options_unsupported".to_string(),
            message: "当前平台或 Steam 目录不支持自动写入启动项。".to_string(),
        });
    }
    InstallState {
        selected_game_path,
        steam_path: env.steam_path,
        steam_launch_options_supported: env.steam_launch_options_supported,
        launch_flow,
        game: InstallGameState {
            found: game_found,
            path_valid: env.game_path_valid,
            display_version: None,
        },
        mod_state: InstallModState {
            installed,
            installed_version: env.bpp_version,
            bundled_version: env.bundled_bpp_version,
            version_matches,
        },
        actions: InstallActions {
            can_install: can_launch && !installed,
            can_reinstall: can_launch && installed,
            can_reset_data: can_launch && has_resettable_data,
            can_uninstall: can_launch && installed,
            can_launch,
        },
        has_resettable_data,
        warnings,
    }
}

fn has_resettable_bpp_data(game_path: Option<&str>) -> bool {
    game_path
        .map(Path::new)
        .map(|path| crate::services::paths::bpp_data_dir(path).exists())
        .unwrap_or(false)
}

fn open_url(url: &str) -> Result<(), String> {
    Command::new("xdg-open")
        .arg(url)
        .spawn()
        .map_err(|err| format!("failed to open URL: {err}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::has_resettable_bpp_data;

    #[test]
    fn test_has_resettable_bpp_data_detects_existing_data_directory() {
        let tmp = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(tmp.path().join(crate::config::BAZAAR_DATA_DIRECTORY)).unwrap();
        let path = tmp.path().to_string_lossy().into_owned();

        assert!(has_resettable_bpp_data(Some(path.as_str())));
    }

    #[test]
    fn test_has_resettable_bpp_data_is_false_when_missing() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().to_string_lossy().into_owned();

        assert!(!has_resettable_bpp_data(Some(path.as_str())));
        assert!(!has_resettable_bpp_data(None));
    }
}
