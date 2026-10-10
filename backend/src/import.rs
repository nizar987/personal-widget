//! One-shot import from another server that speaks the same API (e.g. the old multi-agent backend).

use serde::Deserialize;

use crate::model::Task;
use crate::repo::TaskRepo;

#[derive(Debug, thiserror::Error)]
pub enum ImportError {
    #[error("could not reach {url}: {source}")]
    Http {
        url: String,
        source: Box<ureq::Error>,
    },
    #[error("unexpected response from {url}: {source}")]
    Decode { url: String, source: std::io::Error },
    #[error("source returned ok=false")]
    SourceRejected,
    #[error(transparent)]
    Repo(#[from] crate::repo::RepoError),
}

#[derive(Deserialize)]
struct ListResponse {
    ok: bool,
    #[serde(default)]
    data: Vec<Task>,
}

#[derive(Debug, PartialEq, Eq)]
pub struct ImportSummary {
    pub fetched: usize,
    pub inserted: usize,
}

/// Fetches every task (open and completed) from `base_url` and inserts the ones not present yet.
pub fn import_from(base_url: &str, repo: &TaskRepo) -> Result<ImportSummary, ImportError> {
    let url = format!("{}/api/tasks", base_url.trim_end_matches('/'));
    let response = ureq::get(&url).call().map_err(|source| ImportError::Http {
        url: url.clone(),
        source: Box::new(source),
    })?;
    let list: ListResponse = response.into_json().map_err(|source| ImportError::Decode {
        url: url.clone(),
        source,
    })?;
    if !list.ok {
        return Err(ImportError::SourceRejected);
    }
    let inserted = repo.import(&list.data)?;
    Ok(ImportSummary {
        fetched: list.data.len(),
        inserted,
    })
}
