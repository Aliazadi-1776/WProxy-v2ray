use serde::Serialize;
use std::env;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

#[cfg(windows)]
use std::os::windows::process::CommandExt;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CliOutput {
    stdout: String,
    stderr: String,
    code: i32,
}

fn existing_file(path: impl AsRef<Path>) -> Option<PathBuf> {
    let path = path.as_ref();
    path.is_file().then(|| path.to_path_buf())
}

fn resolve_ctl() -> Result<PathBuf, String> {
    if let Some(value) = env::var_os("WPROXYCTL") {
        if let Some(path) = existing_file(PathBuf::from(value)) {
            return Ok(path);
        }
    }

    if let Ok(executable) = env::current_exe() {
        if let Some(directory) = executable.parent() {
            #[cfg(windows)]
            if let Some(path) = existing_file(directory.join("wproxyctl.exe")) {
                return Ok(path);
            }
            #[cfg(windows)]
            if let Some(path) = existing_file(directory.join("cli/wproxyctl.py")) {
                return Ok(path);
            }
            #[cfg(not(windows))]
            if let Some(path) = existing_file(directory.join("wproxyctl")) {
                return Ok(path);
            }
        }
    }

    #[cfg(windows)]
    let installed = PathBuf::from("wproxyctl.exe");
    #[cfg(not(windows))]
    let installed = PathBuf::from("/usr/bin/wproxyctl");
    if installed.is_file() {
        return Ok(installed);
    }

    if let Ok(directory) = env::current_dir() {
        for candidate in [
            directory.join("cli/wproxyctl.py"),
            directory.join("../cli/wproxyctl.py"),
            directory.join("../../cli/wproxyctl.py"),
        ] {
            if let Some(path) = existing_file(candidate) {
                return Ok(path);
            }
        }
    }

    Err("The WProxy command engine is missing. Reinstall WProxy or set WPROXYCTL.".into())
}

fn ctl_command() -> Result<Command, String> {
    let path = resolve_ctl()?;
    let mut command = if path.extension().and_then(|value| value.to_str()) == Some("py") {
        #[cfg(windows)]
        let mut process = Command::new("python.exe");
        #[cfg(not(windows))]
        let mut process = Command::new("python3");
        process.arg(path);
        process
    } else {
        Command::new(path)
    };
    command
        .env("PYTHONUTF8", "1")
        .env("PYTHONIOENCODING", "utf-8");
    hide_console(&mut command);
    Ok(command)
}

fn hide_console(command: &mut Command) {
    #[cfg(windows)]
    {
        command.creation_flags(CREATE_NO_WINDOW);
    }
    #[cfg(not(windows))]
    {
        let _ = command;
        let _ = CREATE_NO_WINDOW;
    }
}

fn output_result(output: Output) -> Result<CliOutput, String> {
    let result = CliOutput {
        stdout: String::from_utf8_lossy(&output.stdout).trim().to_owned(),
        stderr: String::from_utf8_lossy(&output.stderr).trim().to_owned(),
        code: output.status.code().unwrap_or(-1),
    };
    if output.status.success() {
        Ok(result)
    } else {
        Err(if !result.stderr.is_empty() {
            result.stderr
        } else if !result.stdout.is_empty() {
            result.stdout
        } else {
            format!("WProxy command failed with exit code {}", result.code)
        })
    }
}

fn execute(mut command: Command, args: &[String]) -> Result<CliOutput, String> {
    command
        .args(args)
        .output()
        .map_err(|error| format!("Could not start WProxy: {error}"))
        .and_then(output_result)
}

fn is_json_tail(args: &[String]) -> bool {
    args.last().map(String::as_str) == Some("--json")
}

fn valid_ctl_args(args: &[String]) -> bool {
    if args.is_empty() || args.len() > 8 {
        return false;
    }
    match args[0].as_str() {
        "status" => args.len() == 2 && is_json_tail(args),
        "node" if args.len() >= 2 => match args[1].as_str() {
            "list" => args.len() == 3 && is_json_tail(args),
            "add" | "import" => {
                matches!(args.len(), 3 | 5)
                    && (args.len() == 3 || args.get(3).map(String::as_str) == Some("--name"))
            }
            "remove" => args.len() == 3,
            "rename" => args.len() == 4,
            "ping" => {
                args.len() >= 3
                    && args.iter().all(|value| {
                        !value.starts_with('-')
                            || matches!(value.as_str(), "--all" | "--json" | "--timeout")
                    })
            }
            "best" | "verify" | "validate" => {
                args.len() >= 3
                    && args.iter().all(|value| {
                        !value.starts_with('-') || matches!(value.as_str(), "--json" | "--timeout" | "--verify")
                    })
            }
            _ => false,
        },
        "sub" if args.len() >= 2 => match args[1].as_str() {
            "list" => args.len() == 3 && is_json_tail(args),
            "add" => {
                matches!(args.len(), 3 | 5)
                    && (args.len() == 3 || args.get(3).map(String::as_str) == Some("--name"))
            }
            "update" => matches!(args.len(), 2 | 3),
            "remove" => args.len() == 3,
            _ => false,
        },
        "routing" if args.len() >= 2 => match args[1].as_str() {
            "show" => args.len() == 3 && is_json_tail(args),
            "mode" => args.len() == 3 && matches!(args[2].as_str(), "all" | "bypass" | "only"),
            "domain" | "app" => args.len() == 4 && matches!(args[2].as_str(), "add" | "remove"),
            _ => false,
        },
        "settings" if args.len() >= 2 => match args[1].as_str() {
            "show" => args.len() == 3 && is_json_tail(args),
            "set" => {
                args.len() == 4
                    && matches!(args[2].as_str(), "auto_update" | "remember_authorization")
                    && matches!(args[3].as_str(), "true" | "false")
            }
            _ => false,
        },
        "update" if args.len() >= 2 => match args[1].as_str() {
            "check" | "download" => args.iter().all(|value| {
                !value.starts_with('-')
                    || matches!(value.as_str(), "--json" | "--platform" | "--timeout")
            }),
            _ => false,
        },
        _ => false,
    }
}

#[tauri::command]
fn platform() -> &'static str {
    if cfg!(windows) {
        "windows"
    } else {
        "linux"
    }
}

#[tauri::command]
async fn run_ctl(args: Vec<String>) -> Result<CliOutput, String> {
    if !valid_ctl_args(&args) {
        return Err("The desktop app rejected an unsupported command.".into());
    }
    tauri::async_runtime::spawn_blocking(move || execute(ctl_command()?, &args))
        .await
        .map_err(|error| format!("Could not complete the WProxy command: {error}"))?
}

#[tauri::command]
async fn import_config(text: String, name: Option<String>) -> Result<CliOutput, String> {
    if text.len() > 8 * 1024 * 1024 {
        return Err("Configuration is larger than 8 MiB".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        use std::io::Write;
        #[cfg(unix)]
        use std::os::unix::fs::OpenOptionsExt;
        static NEXT_IMPORT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let sequence = NEXT_IMPORT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let instant = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|error| format!("Could not prepare configuration import: {error}"))?
            .as_nanos();
        let path = env::temp_dir().join(format!("wproxy-import-{}-{instant}-{sequence}.txt", std::process::id()));
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        options.mode(0o600);
        let mut file = options.open(&path)
            .map_err(|error| format!("Could not prepare configuration import: {error}"))?;
        let result = (|| {
            file.write_all(text.as_bytes())
                .map_err(|error| format!("Could not write configuration import: {error}"))?;
            drop(file);
            let mut args = vec!["node".into(), "import".into(), path.to_string_lossy().into_owned()];
            if let Some(value) = name.filter(|value| !value.trim().is_empty()) {
                args.extend(["--name".into(), value]);
            }
            execute(ctl_command()?, &args)
        })();
        let _ = std::fs::remove_file(&path);
        result
    })
        .await
        .map_err(|error| format!("Could not complete configuration import: {error}"))?
}

#[tauri::command]
fn tunnel_status() -> Result<CliOutput, String> {
    #[cfg(windows)]
    let args = vec!["windows".into(), "status".into(), "--json".into()];
    #[cfg(not(windows))]
    let args = vec!["status".into(), "--json".into()];
    execute(ctl_command()?, &args)
}

fn valid_node_id(node_id: &str) -> bool {
    node_id.len() == 16 && node_id.bytes().all(|value| value.is_ascii_hexdigit())
}

#[cfg(windows)]
fn powershell_literal(value: &str) -> String {
    format!("'{}'", value.replace(char::from(39), "''"))
}

#[cfg(windows)]
fn elevated_windows_ctl(args: &[String]) -> Result<CliOutput, String> {
    let ctl = resolve_ctl()?;
    let is_script = ctl.extension().and_then(|value| value.to_str()) == Some("py");
    let program = if is_script {
        "python.exe".into()
    } else {
        ctl.to_string_lossy().into_owned()
    };
    let mut process_args = Vec::new();
    if is_script {
        process_args.push(ctl.to_string_lossy().into_owned());
    }
    process_args.extend(args.iter().cloned());
    let arguments = process_args
        .iter()
        .map(|value| powershell_literal(value))
        .collect::<Vec<_>>()
        .join(",");
    let script = format!(
        "$ErrorActionPreference='Stop'; $p=Start-Process -FilePath {} -ArgumentList @({}) -Verb RunAs -WindowStyle Hidden -PassThru; $p.WaitForExit(); exit $p.ExitCode",
        powershell_literal(&program),
        arguments,
    );
    let mut command = Command::new("powershell.exe");
    command.args(["-NoProfile", "-NonInteractive", "-Command", &script]);
    hide_console(&mut command);
    let result = command
        .output()
        .map_err(|error| format!("Could not request Windows administrator permission: {error}"))?;
    if result.status.success() {
        return output_result(result);
    }
    let diagnostic = env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .map(|path| path.join("WProxy/run/last-error.txt"))
        .and_then(|path| std::fs::read_to_string(path).ok())
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty());
    Err(diagnostic.unwrap_or_else(|| {
        "Windows administrator permission was cancelled or the tunnel could not start.".into()
    }))
}

#[cfg(not(windows))]
fn linux_admin(action: &str, argument: Option<&str>) -> Result<CliOutput, String> {
    let helper = Path::new("/usr/libexec/wproxy-admin");
    let mut command = Command::new("pkexec");
    if helper.is_file() {
        command.arg(helper).arg(action);
    } else {
        let ctl = resolve_ctl()?;
        command.arg(ctl).arg("nm").arg(action);
    }
    if let Some(value) = argument {
        command.arg(value);
    }
    command
        .output()
        .map_err(|error| format!("Could not request administrator authorization: {error}"))
        .and_then(output_result)
}

#[tauri::command]
async fn tunnel(action: String, node_id: Option<String>, remember: Option<bool>) -> Result<CliOutput, String> {
    tauri::async_runtime::spawn_blocking(move || tunnel_command(action, node_id, remember))
        .await
        .map_err(|error| format!("Could not complete the tunnel command: {error}"))?
}

fn tunnel_command(action: String, node_id: Option<String>, remember: Option<bool>) -> Result<CliOutput, String> {
    if !matches!(action.as_str(), "up" | "down") {
        return Err("Unknown tunnel action.".into());
    }
    if action == "up" && !node_id.as_deref().is_some_and(valid_node_id) {
        return Err("Select a valid server first.".into());
    }

    #[cfg(windows)]
    {
        let _ = remember;
        let mut args = vec!["windows".to_owned(), if action == "up" { "connect".to_owned() } else { action }];
        if let Some(value) = node_id {
            args.push(value);
        }
        elevated_windows_ctl(&args)
    }
    #[cfg(not(windows))]
    {
        let operation = if action == "up" && remember.unwrap_or(false) { "up-remember" } else { &action };
        linux_admin(operation, node_id.as_deref())
    }
}

#[tauri::command]
fn sync_linux() -> Result<CliOutput, String> {
    #[cfg(windows)]
    {
        Ok(CliOutput {
            stdout: String::new(),
            stderr: String::new(),
            code: 0,
        })
    }
    #[cfg(not(windows))]
    {
        linux_admin("sync", None)
    }
}

#[tauri::command]
fn set_linux_authorization(enable: bool) -> Result<CliOutput, String> {
    #[cfg(windows)]
    {
        let _ = enable;
        Err("Reusable administrator authorization is only available on Linux.".into())
    }
    #[cfg(not(windows))]
    {
        linux_admin(if enable { "authorize" } else { "revoke" }, None)
    }
}

#[tauri::command]
async fn install_update(path: String) -> Result<CliOutput, String> {
    tauri::async_runtime::spawn_blocking(move || install_update_command(path))
        .await
        .map_err(|error| format!("Could not complete the update: {error}"))?
}

fn install_update_command(path: String) -> Result<CliOutput, String> {
    let archive = PathBuf::from(&path);
    if !archive.is_file() {
        return Err("The downloaded update no longer exists.".into());
    }
    #[cfg(windows)]
    {
        let args = vec!["update".into(), "install".into(), path];
        execute(ctl_command()?, &args)
    }
    #[cfg(not(windows))]
    {
        linux_admin("update", archive.to_str())
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            platform,
            run_ctl,
            import_config,
            tunnel_status,
            tunnel,
            sync_linux,
            set_linux_authorization,
            install_update,
        ])
        .run(tauri::generate_context!())
        .expect("error while running WProxy");
}
