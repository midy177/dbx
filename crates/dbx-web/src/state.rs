use dbx_core::connection::AppState;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{broadcast, Mutex, RwLock};
use tokio_util::sync::CancellationToken;

pub fn session_ttl() -> Duration {
    let hours = std::env::var("DBX_SESSION_TTL_HOURS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .filter(|&h| h > 0)
        .unwrap_or(12);
    Duration::from_secs(hours * 60 * 60)
}

pub struct LoginRateLimit {
    pub fail_count: u32,
    pub locked_until: Option<Instant>,
}

pub struct WebState {
    pub app: Arc<AppState>,
    pub data_dir: PathBuf,
    pub password_hash: RwLock<Option<String>>,
    /// token -> created_at
    pub sessions: RwLock<HashMap<String, Instant>>,
    pub sse_channels: RwLock<HashMap<String, broadcast::Sender<String>>>,
    pub sql_file_executions: RwLock<HashMap<String, CancellationToken>>,
    pub login_rate_limit: Mutex<LoginRateLimit>,
    /// Table export temp files: export_id -> (file_path, format)
    pub export_files: RwLock<HashMap<String, (String, String)>>,
}

impl WebState {
    pub async fn remove_sse_channel(&self, id: &str) {
        self.sse_channels.write().await.remove(id);
    }

    pub async fn is_session_valid(&self, token: &str) -> bool {
        let sessions = self.sessions.read().await;
        sessions.get(token).is_some_and(|created_at| created_at.elapsed() < session_ttl())
    }

    pub async fn purge_expired_sessions(&self) {
        let mut sessions = self.sessions.write().await;
        sessions.retain(|_, created_at| created_at.elapsed() < session_ttl());
    }
}
