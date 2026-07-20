const BAZAAR_PROCESS_NAME: &str = "TheBazaar.exe";

fn pgrep_reports_running(
    status_code: Option<i32>,
    stdout: &[u8],
    stderr: &[u8],
) -> Result<bool, String> {
    match status_code {
        Some(0) => Ok(!stdout.is_empty()),
        Some(1) => Ok(false),
        _ => {
            let stderr = String::from_utf8_lossy(stderr).trim().to_string();
            if stderr.is_empty() {
                Err("Failed to inspect The Bazaar process state.".to_string())
            } else {
                Err(format!(
                    "Failed to inspect The Bazaar process state: {stderr}"
                ))
            }
        }
    }
}

fn is_bazaar_running() -> Result<bool, String> {
    let output = std::process::Command::new("pgrep")
        .args(["-x", BAZAAR_PROCESS_NAME])
        .output()
        .map_err(|err| format!("Failed to inspect The Bazaar process state: {err}"))?;

    pgrep_reports_running(output.status.code(), &output.stdout, &output.stderr)
}

pub(crate) fn is_bazaar_running_best_effort() -> bool {
    is_bazaar_running().unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::pgrep_reports_running;

    #[test]
    fn pgrep_reports_running_on_zero_status_with_output() {
        assert!(pgrep_reports_running(Some(0), b"123\n", b"").unwrap());
    }

    #[test]
    fn pgrep_reports_not_running_on_status_one() {
        assert!(!pgrep_reports_running(Some(1), b"", b"").unwrap());
    }

    #[test]
    fn pgrep_reports_errors_on_unexpected_status() {
        let error = pgrep_reports_running(Some(2), b"", b"pgrep failed")
            .expect_err("unexpected pgrep status should fail");

        assert!(error.contains("pgrep failed"));
    }
}
