use std::env;

use zed_extension_api::{self as zed, Command, Result};

/// Path to the gzim-lsp binary, searched on PATH plus a few common prefixes.
const SERVER_NAME: &str = "gzim-lsp";

fn find_server_path() -> Option<String> {
    let path = env::var("PATH").ok()?;
    for dir in path.split(':') {
        let candidate = format!("{dir}/{SERVER_NAME}");
        if std::fs::metadata(&candidate).is_ok() {
            return Some(candidate);
        }
    }
    // common install locations, fr
    for dir in ["/usr/local/bin", "/usr/bin"] {
        let candidate = format!("{dir}/{SERVER_NAME}");
        if std::fs::metadata(&candidate).is_ok() {
            return Some(candidate);
        }
    }
    None
}

struct GenzimnifyExtension;

impl zed::Extension for GenzimnifyExtension {
    fn new() -> Self
    where
        Self: Sized,
    {
        Self
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        _worktree: &zed::Worktree,
    ) -> Result<Command> {
        match find_server_path() {
            Some(path) => Ok(Command {
                command: path,
                args: vec![],
                env: Default::default(),
            }),
            None => Err(format!(
                "{SERVER_NAME} not found on PATH — build it from the genzimnify \
                 repo (nimble build) and make sure it's on your PATH"
            )),
        }
    }
}

zed::register_extension!(GenzimnifyExtension);
