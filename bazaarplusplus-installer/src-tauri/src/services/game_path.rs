use crate::services::path::normalize_requested_game_path;
use crate::services::paths;
use crate::services::startup::InstallerContextState;
use std::path::PathBuf;
use tauri::Manager;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum GamePathSource {
    Detection,
    Requested,
    Session,
    Fallback,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GamePathResolution {
    pub game_path: PathBuf,
    pub database_path: Option<PathBuf>,
    pub source: GamePathSource,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GamePathRequirement {
    Any,
    DatabaseExists,
}

/// Resolve the game directory using the standard fallback chain.
///
/// 1. Full Steam-aware environment detection (errors are swallowed).
/// 2. The user's manually-supplied path (if any).
/// 3. Optional stream session path hint from the last started overlay service.
/// 4. Well-known Steam library paths that contain the BPP database.
pub fn resolve_game_path_with_source(
    app: &tauri::AppHandle,
    requested_game_path: Option<String>,
    session_game_path: Option<PathBuf>,
) -> Option<GamePathResolution> {
    resolve_game_path_matching(
        app,
        requested_game_path,
        session_game_path,
        GamePathRequirement::Any,
    )
}

pub fn resolve_game_path_with_database(
    app: &tauri::AppHandle,
    requested_game_path: Option<String>,
    session_game_path: Option<PathBuf>,
) -> Option<GamePathResolution> {
    resolve_game_path_matching(
        app,
        requested_game_path,
        session_game_path,
        GamePathRequirement::DatabaseExists,
    )
}

fn resolve_game_path_matching(
    app: &tauri::AppHandle,
    requested_game_path: Option<String>,
    session_game_path: Option<PathBuf>,
    requirement: GamePathRequirement,
) -> Option<GamePathResolution> {
    let context_state = app.state::<InstallerContextState>();
    if let Ok(env) = crate::services::detect::detect_environment(
        app.clone(),
        context_state,
        requested_game_path.clone(),
    ) {
        if let Some(path) = env.game_path.map(PathBuf::from) {
            if let Some(value) = resolution(path, GamePathSource::Detection, requirement) {
                return Some(value);
            }
        }
    }

    if let Some(path) = normalize_requested_game_path(requested_game_path) {
        if let Some(value) = resolution(path, GamePathSource::Requested, requirement) {
            return Some(value);
        }
    }

    if let Some(path) = session_game_path {
        if let Some(value) = resolution(path, GamePathSource::Session, requirement) {
            return Some(value);
        }
    }

    for path in fallback_game_candidates() {
        let db = paths::database_path(&path);
        if db.exists() {
            return Some(GamePathResolution {
                game_path: path,
                database_path: Some(db),
                source: GamePathSource::Fallback,
            });
        }
    }

    None
}

fn resolution(
    game_path: PathBuf,
    source: GamePathSource,
    requirement: GamePathRequirement,
) -> Option<GamePathResolution> {
    let database_path = paths::database_path(&game_path);
    let database_path = database_path.exists().then_some(database_path);
    if requirement == GamePathRequirement::DatabaseExists && database_path.is_none() {
        return None;
    }

    Some(GamePathResolution {
        game_path,
        database_path,
        source,
    })
}

pub(crate) fn fallback_game_candidates() -> Vec<PathBuf> {
    let mut candidates = Vec::new();

    if let Some(home) = dirs::home_dir() {
        push_unique(
            &mut candidates,
            home.join(".local/share/Steam/steamapps/common/The Bazaar"),
        );
        push_unique(
            &mut candidates,
            home.join(".steam/steam/steamapps/common/The Bazaar"),
        );
        push_unique(
            &mut candidates,
            home.join(
                ".var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/The Bazaar",
            ),
        );
    }

    candidates
}

fn push_unique(paths: &mut Vec<PathBuf>, path: PathBuf) {
    if !paths.iter().any(|existing| existing == &path) {
        paths.push(path);
    }
}
