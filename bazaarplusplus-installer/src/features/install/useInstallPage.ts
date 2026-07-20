import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { listen } from "@tauri-apps/api/event";
import { hasTauriRuntime } from "../../api/runtime";
import type { InstallState } from "../../types/backend";
import { useI18n, type Translate } from "../../i18n/LocaleProvider";
import { parseResetBppDataError, toErrorMessage } from "../shared/errors";
import { useAsyncAction } from "../shared/useAsyncAction";
import {
  chooseGameDirectory,
  emptyInstallState,
  installMod,
  launchGame,
  loadInstallState,
  resetBppData,
  uninstallMod,
} from "./installApi";

type InstallAction =
  | "load"
  | "choose"
  | "install"
  | "resetData"
  | "uninstall"
  | "launch";

export function useInstallPage() {
  const { t } = useI18n();
  const [state, setState] = useState<InstallState>(emptyInstallState);
  const [selectedPath, setSelectedPath] = useState<string | undefined>(
    undefined,
  );
  const [message, setMessage] = useState<string | null>(null);
  const flashTimer = useRef<number | null>(null);
  const [resetDataFailurePaths, setResetDataFailurePaths] = useState<string[]>(
    [],
  );
  const { action, error, run, busy } = useAsyncAction<InstallAction>();

  // Discrete success confirmations should not linger forever.
  const flashMessage = useCallback((next: string) => {
    if (flashTimer.current !== null) {
      window.clearTimeout(flashTimer.current);
    }
    setMessage(next);
    flashTimer.current = window.setTimeout(() => {
      setMessage(null);
      flashTimer.current = null;
    }, 4000);
  }, []);

  useEffect(
    () => () => {
      if (flashTimer.current !== null) {
        window.clearTimeout(flashTimer.current);
      }
    },
    [],
  );
  const refresh = useCallback(
    async (gamePath = selectedPath) => {
      await run(
        "load",
        async () => {
          const nextState = await loadInstallState(gamePath);
          setState(nextState);
          setSelectedPath(nextState.selected_game_path ?? gamePath);
        },
        { onStart: () => setMessage(null) },
      );
    },
    [run, selectedPath],
  );

  useEffect(() => {
    void run(
      "load",
      async () => {
        const nextState = await loadInstallState(undefined);
        setState(nextState);
        setSelectedPath(nextState.selected_game_path ?? undefined);
      },
      { onStart: () => setMessage(null) },
    );
  }, [run]);

  // The backend warms up installer context in the background and emits
  // `startup-ready` when done. The initial load can race ahead of warm-up;
  // refresh once the signal arrives so the first screen converges without user
  // action.
  useEffect(() => {
    if (!hasTauriRuntime()) return;
    const unlisten = listen("startup-ready", () => {
      void refresh();
    });
    return () => {
      void unlisten.then((stop) => stop());
    };
  }, [refresh]);

  const chooseDirectory = useCallback(
    () =>
      run("choose", async () => {
        const selection = await chooseGameDirectory();
        if (!selection.game_path) return;
        setSelectedPath(selection.game_path);
        setState(await loadInstallState(selection.game_path));
      }),
    [run],
  );

  const install = useCallback(
    () =>
      run(
        "install",
        async () => {
          const path = requireGamePath(state, t);
          setState(await installMod(path));
          flashMessage(t("installDone"));
        },
        { onStart: () => setMessage(null) },
      ),
    [flashMessage, run, state, t],
  );

  const resetData = useCallback(
    () =>
      run(
        "resetData",
        async () => {
          if (!state.has_resettable_data) {
            setResetDataFailurePaths([]);
            flashMessage(t("resetDataNothingToDelete"));
            return;
          }

          const path = requireGamePath(state, t);
          const result = await resetBppData(path);
          setState(result.state);
          setResetDataFailurePaths([]);
          flashMessage(
            result.removed_data
              ? t("resetDataDone")
              : t("resetDataNothingToDelete"),
          );
        },
        {
          onStart: () => {
            setMessage(null);
            setResetDataFailurePaths([]);
          },
          errorMessage: (caught) =>
            formatResetBppDataError(caught, t, setResetDataFailurePaths),
        },
      ),
    [flashMessage, run, state, t],
  );

  const uninstall = useCallback(
    () =>
      run(
        "uninstall",
        async () => {
          const path = requireGamePath(state, t);
          setState(await uninstallMod(path));
          flashMessage(t("uninstallDone"));
        },
        { onStart: () => setMessage(null) },
      ),
    [flashMessage, run, state, t],
  );

  const launch = useCallback(
    () =>
      run(
        "launch",
        async () => {
          await launchGame(state.selected_game_path ?? undefined);
        },
        { onStart: () => setMessage(null) },
      ),
    [run, state.selected_game_path],
  );

  const status = useMemo(() => createInstallStatus(state, t), [state, t]);

  return {
    state,
    status,
    action,
    busy,
    error,
    message,
    resetDataFailurePaths,
    refresh,
    chooseDirectory,
    install,
    resetData,
    uninstall,
    launch,
  };
}

function requireGamePath(state: InstallState, t: Translate) {
  if (!state.selected_game_path) {
    throw new Error(t("selectGameDirFirst"));
  }
  return state.selected_game_path;
}

function formatResetBppDataError(
  error: unknown,
  t: Translate,
  setFailurePaths: (paths: string[]) => void,
) {
  const resetError = parseResetBppDataError(error);
  if (resetError?.code === "game_running") {
    setFailurePaths([]);
    return t("resetDataBlockedByGame");
  }
  if (resetError?.code === "partial_failure") {
    setFailurePaths(resetError.paths);
    return t("resetDataPartialFailure", {
      count: Math.max(1, resetError.paths.length),
    });
  }
  setFailurePaths([]);
  return toErrorMessage(error);
}

function createInstallStatus(state: InstallState, t: Translate) {
  const installed = state.mod_state.installed;
  return {
    gameLabel: state.game.path_valid ? t("gameFilesOk") : t("gameNotFound"),
    gameTone: state.game.path_valid ? ("ok" as const) : ("warn" as const),
    modLabel: installed
      ? state.mod_state.version_matches
        ? t("modReady")
        : t("modNeedsReinstall")
      : t("modNotInstalled"),
    modTone:
      installed && state.mod_state.version_matches
        ? ("ok" as const)
        : ("warn" as const),
    primaryAction: installed ? t("actionReinstall") : t("actionInstall"),
    modVersion:
      state.mod_state.installed_version ??
      state.mod_state.bundled_version ??
      "-",
    steam: state.steam_path ? "Steam" : "-",
  };
}
