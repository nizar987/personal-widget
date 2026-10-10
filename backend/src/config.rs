//! Runtime configuration from environment variables.

use std::env;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::PathBuf;

pub const DEFAULT_PORT: u16 = 3220;

#[derive(Debug, Clone)]
pub struct Config {
    pub addr: SocketAddr,
    pub db_path: PathBuf,
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("TASKWIDGET_PORT must be a port number, got {0:?}")]
    InvalidPort(String),
    #[error("HOME is not set; set TASKWIDGET_DB to choose a database path")]
    NoHome,
}

impl Config {
    /// `TASKWIDGET_PORT` (default 3220) and `TASKWIDGET_DB`
    /// (default `~/Library/Application Support/TaskWidget/tasks.db`).
    /// Always binds to loopback so the API is never exposed on the network.
    pub fn from_env() -> Result<Self, ConfigError> {
        let port = match env::var("TASKWIDGET_PORT") {
            Ok(raw) => raw.parse().map_err(|_| ConfigError::InvalidPort(raw))?,
            Err(_) => DEFAULT_PORT,
        };
        let db_path = match env::var_os("TASKWIDGET_DB") {
            Some(path) => PathBuf::from(path),
            None => default_db_path()?,
        };
        Ok(Self {
            addr: SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), port),
            db_path,
        })
    }
}

fn default_db_path() -> Result<PathBuf, ConfigError> {
    let home = env::var_os("HOME").ok_or(ConfigError::NoHome)?;
    Ok(PathBuf::from(home).join("Library/Application Support/TaskWidget/tasks.db"))
}
