use std::process::ExitCode;

use taskwidget_server::config::Config;
use taskwidget_server::repo::TaskRepo;
use taskwidget_server::{api, import};
use tracing_subscriber::EnvFilter;

const USAGE: &str = "\
Usage:
  taskwidget-server [serve]            Start the API on 127.0.0.1:$TASKWIDGET_PORT (default 3220)
  taskwidget-server import <base-url>  Copy tasks from another server, e.g. http://localhost:3210

Environment:
  TASKWIDGET_PORT  Port to listen on (default 3220)
  TASKWIDGET_DB    SQLite file (default ~/Library/Application Support/TaskWidget/tasks.db)
  RUST_LOG         Log filter (default info)";

#[tokio::main]
async fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        [] | ["serve"] => serve().await,
        ["import", url] => run_import(url),
        ["-h" | "--help" | "help"] => {
            println!("{USAGE}");
            Ok(())
        }
        _ => Err(format!("unknown arguments: {args:?}\n\n{USAGE}")),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            tracing::error!("{message}");
            ExitCode::FAILURE
        }
    }
}

fn open_repo() -> Result<(Config, TaskRepo), String> {
    let config = Config::from_env().map_err(|e| e.to_string())?;
    if let Some(dir) = config.db_path.parent() {
        std::fs::create_dir_all(dir)
            .map_err(|e| format!("cannot create {}: {e}", dir.display()))?;
    }
    let repo = TaskRepo::open(&config.db_path)
        .map_err(|e| format!("cannot open database {}: {e}", config.db_path.display()))?;
    Ok((config, repo))
}

async fn serve() -> Result<(), String> {
    let (config, repo) = open_repo()?;
    let listener = tokio::net::TcpListener::bind(config.addr)
        .await
        .map_err(|e| format!("cannot listen on {}: {e}", config.addr))?;
    tracing::info!(addr = %config.addr, db = %config.db_path.display(), "taskwidget-server listening");
    axum::serve(listener, api::router(repo))
        .with_graceful_shutdown(shutdown_signal())
        .await
        .map_err(|e| format!("server error: {e}"))
}

fn run_import(url: &str) -> Result<(), String> {
    let (config, repo) = open_repo()?;
    let summary = import::import_from(url, &repo).map_err(|e| e.to_string())?;
    tracing::info!(
        fetched = summary.fetched,
        inserted = summary.inserted,
        db = %config.db_path.display(),
        "import finished"
    );
    Ok(())
}

async fn shutdown_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };
    #[cfg(unix)]
    let terminate = async {
        if let Ok(mut sig) =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            sig.recv().await;
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();
    tokio::select! {
        () = ctrl_c => {},
        () = terminate => {},
    }
    tracing::info!("shutting down");
}
