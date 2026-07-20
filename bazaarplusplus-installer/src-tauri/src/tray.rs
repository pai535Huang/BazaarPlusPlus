use std::sync::Mutex;

use tauri::{
    menu::{Menu, MenuItem, MenuItemBuilder},
    tray::{MouseButton, TrayIconBuilder, TrayIconEvent},
    Manager,
};

pub fn build_tray(app: &tauri::AppHandle) -> tauri::Result<()> {
    let labels = tray_menu_labels(TrayLocale::Zh);
    let show_window = MenuItemBuilder::with_id("show_window", labels.show_window).build(app)?;
    let copy_obs_url = MenuItemBuilder::with_id("copy_obs_url", labels.copy_obs_url).build(app)?;
    let stop_stream_service =
        MenuItemBuilder::with_id("stop_stream_service", labels.stop_stream_service).build(app)?;
    let quit = MenuItemBuilder::with_id("quit_app", labels.quit).build(app)?;
    let menu = Menu::with_items(
        app,
        &[&show_window, &copy_obs_url, &stop_stream_service, &quit],
    )?;

    app.state::<TrayMenuState>().set_items(TrayMenuItems {
        show_window: show_window.clone(),
        copy_obs_url: copy_obs_url.clone(),
        stop_stream_service: stop_stream_service.clone(),
        quit: quit.clone(),
    });

    let mut tray = TrayIconBuilder::with_id("main-tray")
        .menu(&menu)
        .tooltip("BazaarPlusPlus")
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "show_window" => show_main_window(app),
            "copy_obs_url" => {
                let state = app.state::<crate::stream::state::StreamRuntimeState>();
                if let Some(url) = state.snapshot().overlay_url {
                    let _ = copy_text_to_clipboard(&url);
                }
            }
            "stop_stream_service" => {
                let app_handle = app.clone();
                tauri::async_runtime::spawn(async move {
                    let state = app_handle.state::<crate::stream::state::StreamRuntimeState>();
                    let _ = crate::stream::server::stop(state.inner()).await;
                });
            }
            "quit_app" => quit_app(app),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if should_show_main_window_for_tray_event(&event) {
                show_main_window(tray.app_handle());
            }
        });

    if let Some(icon) = app.default_window_icon().cloned() {
        tray = tray.icon(icon);
    }

    let _ = tray.build(app)?;
    Ok(())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TrayLocale {
    En,
    Zh,
}

impl TrayLocale {
    fn from_code(locale: &str) -> Self {
        match locale {
            "en" => Self::En,
            _ => Self::Zh,
        }
    }
}

struct TrayMenuLabels {
    show_window: &'static str,
    copy_obs_url: &'static str,
    stop_stream_service: &'static str,
    quit: &'static str,
}

fn tray_menu_labels(locale: TrayLocale) -> TrayMenuLabels {
    match locale {
        TrayLocale::En => TrayMenuLabels {
            show_window: "Show Window",
            copy_obs_url: "Copy OBS URL",
            stop_stream_service: "Stop Stream Service",
            quit: "Quit",
        },
        TrayLocale::Zh => TrayMenuLabels {
            show_window: "显示窗口",
            copy_obs_url: "复制 OBS 地址",
            stop_stream_service: "关闭直播服务",
            quit: "退出",
        },
    }
}

struct TrayMenuItems {
    show_window: MenuItem<tauri::Wry>,
    copy_obs_url: MenuItem<tauri::Wry>,
    stop_stream_service: MenuItem<tauri::Wry>,
    quit: MenuItem<tauri::Wry>,
}

#[derive(Default)]
pub struct TrayMenuState {
    items: Mutex<Option<TrayMenuItems>>,
}

impl TrayMenuState {
    fn set_items(&self, items: TrayMenuItems) {
        *self.items.lock().expect("tray menu state poisoned") = Some(items);
    }

    fn apply_locale(&self, locale: TrayLocale) -> Result<(), String> {
        let labels = tray_menu_labels(locale);
        let items = self.items.lock().expect("tray menu state poisoned");
        let items = items
            .as_ref()
            .ok_or_else(|| "Tray menu is not initialized.".to_string())?;

        items
            .show_window
            .set_text(labels.show_window)
            .map_err(|err| format!("Failed to update tray menu text: {err}"))?;
        items
            .copy_obs_url
            .set_text(labels.copy_obs_url)
            .map_err(|err| format!("Failed to update tray menu text: {err}"))?;
        items
            .stop_stream_service
            .set_text(labels.stop_stream_service)
            .map_err(|err| format!("Failed to update tray menu text: {err}"))?;
        items
            .quit
            .set_text(labels.quit)
            .map_err(|err| format!("Failed to update tray menu text: {err}"))?;
        Ok(())
    }
}

#[derive(Clone, Debug, serde::Serialize, ts_rs::TS)]
#[ts(export)]
pub struct AppLocalePayload {
    locale: String,
}

#[tauri::command]
pub async fn set_app_locale(
    state: tauri::State<'_, TrayMenuState>,
    locale: String,
) -> Result<AppLocalePayload, String> {
    let normalized = match locale.as_str() {
        "en" => "en",
        _ => "zh",
    };
    state.apply_locale(TrayLocale::from_code(normalized))?;
    Ok(AppLocalePayload {
        locale: normalized.to_string(),
    })
}

fn should_show_main_window_for_tray_event(event: &TrayIconEvent) -> bool {
    matches!(
        event,
        TrayIconEvent::Click {
            button: MouseButton::Left,
            ..
        } | TrayIconEvent::DoubleClick {
            button: MouseButton::Left,
            ..
        }
    )
}

fn quit_app(app: &tauri::AppHandle) {
    let app_handle = app.clone();
    tauri::async_runtime::spawn(async move {
        let state = app_handle.state::<crate::stream::state::StreamRuntimeState>();
        let _ = crate::stream::server::stop(state.inner()).await;
        app_handle.exit(0);
    });
}

fn show_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn copy_text_to_clipboard(text: &str) -> Result<(), String> {
    for (command, args) in [
        ("wl-copy", &[][..]),
        ("xclip", &["-selection", "clipboard"][..]),
        ("xsel", &["--clipboard", "--input"][..]),
    ] {
        if copy_text_with_command(command, args, text).is_ok() {
            return Ok(());
        }
    }

    Err("failed to copy text: install wl-copy, xclip, or xsel".to_string())
}

fn copy_text_with_command(command: &str, args: &[&str], text: &str) -> Result<(), String> {
    use std::io::Write;
    use std::process::{Command, Stdio};

    let mut child = Command::new(command)
        .args(args)
        .stdin(Stdio::piped())
        .spawn()
        .map_err(|err| format!("failed to launch {command}: {err}"))?;
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| format!("{command} stdin unavailable"))?;
    stdin
        .write_all(text.as_bytes())
        .map_err(|err| format!("failed to write to {command}: {err}"))?;
    drop(stdin);
    let status = child
        .wait()
        .map_err(|err| format!("failed to wait for {command}: {err}"))?;

    if status.success() {
        Ok(())
    } else {
        Err(format!("{command} exited with {status}"))
    }
}

#[cfg(test)]
mod tests {
    use super::{should_show_main_window_for_tray_event, tray_menu_labels, TrayLocale};
    use tauri::{
        tray::{MouseButton, MouseButtonState, TrayIconEvent, TrayIconId},
        PhysicalPosition, Rect,
    };

    fn click_event(button: MouseButton) -> TrayIconEvent {
        TrayIconEvent::Click {
            id: TrayIconId::new("main-tray"),
            position: PhysicalPosition::default(),
            rect: Rect::default(),
            button,
            button_state: MouseButtonState::Down,
        }
    }

    fn double_click_event(button: MouseButton) -> TrayIconEvent {
        TrayIconEvent::DoubleClick {
            id: TrayIconId::new("main-tray"),
            position: PhysicalPosition::default(),
            rect: Rect::default(),
            button,
        }
    }

    #[test]
    fn tray_right_click_is_reserved_for_context_menu() {
        assert!(!should_show_main_window_for_tray_event(&click_event(
            MouseButton::Right
        )));
    }

    #[test]
    fn tray_left_click_opens_main_window() {
        assert!(should_show_main_window_for_tray_event(&click_event(
            MouseButton::Left
        )));
        assert!(should_show_main_window_for_tray_event(&double_click_event(
            MouseButton::Left
        )));
    }

    #[test]
    fn tray_menu_labels_support_chinese_and_english() {
        let zh = tray_menu_labels(TrayLocale::Zh);
        assert_eq!(zh.show_window, "显示窗口");
        assert_eq!(zh.copy_obs_url, "复制 OBS 地址");
        assert_eq!(zh.stop_stream_service, "关闭直播服务");
        assert_eq!(zh.quit, "退出");

        let en = tray_menu_labels(TrayLocale::En);
        assert_eq!(en.show_window, "Show Window");
        assert_eq!(en.copy_obs_url, "Copy OBS URL");
        assert_eq!(en.stop_stream_service, "Stop Stream Service");
        assert_eq!(en.quit, "Quit");
    }

    #[test]
    fn tray_locale_defaults_to_chinese_for_unknown_values() {
        assert_eq!(TrayLocale::from_code("en"), TrayLocale::En);
        assert_eq!(TrayLocale::from_code("zh"), TrayLocale::Zh);
        assert_eq!(TrayLocale::from_code("fr"), TrayLocale::Zh);
    }
}
