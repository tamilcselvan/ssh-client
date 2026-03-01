# SSH Config Generator

A Flutter desktop-focused utility to manage SSH connection profiles and launch terminal sessions quickly (inspired by WinSCP-style convenience for Ubuntu/Linux users).

## What this tool currently does

- Create and save SSH profiles in a local SQLite database.
- Generate executable shell scripts for SSH login under `~/ACS/sites`.
- Support password-based (`sshpass`) and key-based (`ssh -i`) authentication.
- Search, edit, delete, duplicate, and connect to saved profiles from GUI.
- Import/export profiles via CSV.
- Append generated entries to FileZilla `sitemanager.xml` when available.

## Gap analysis (existing codebase)

### 1) Architecture & maintainability

**Current gap**
- Most business logic (DB, filesystem, command generation, XML integration, and UI) lives in one large file (`lib/main.dart`).

**Impact**
- Harder to test, evolve, and debug.

**Recommended direction**
- Introduce layers:
  - `domain`: models + validation rules.
  - `data`: repositories (SQLite, CSV, FileZilla XML).
  - `application`: use-cases (generate script, run connection, import/export).
  - `presentation`: widgets/view-models/state.

### 2) Platform behavior

**Current gap**
- Linux/macOS terminal launch is implemented; Windows run behavior is currently unsupported.

**Impact**
- Cross-platform experience is inconsistent.

**Recommended direction**
- Add Windows terminal launcher (`cmd`/`powershell`/`wt`) and capability detection.

### 3) Security model

**Current gap**
- Passwords are persisted in plain text and embedded in generated commands.

**Impact**
- Sensitive data exposure risk.

**Recommended direction**
- Prefer key auth by default.
- Store secrets in OS credential vault (`libsecret`, keychain, Windows Credential Manager) instead of SQLite plain text.
- Add optional “do not persist password” mode.

### 4) Reliability & observability

**Current gap**
- Minimal runtime diagnostics and user-facing error taxonomy.

**Impact**
- Failures (script write, permission, XML parse, process launch) are hard to triage.

**Recommended direction**
- Introduce structured logging + centralized error handling.
- Add explicit user feedback for each failure class.

### 5) Test coverage

**Current gap**
- No meaningful unit/integration tests for command generation, DB repository, XML update, and import/export.

**Impact**
- Regression risk during refactors.

**Recommended direction**
- Add tests for:
  - command builder (password/key variants),
  - filename sanitizer,
  - CSV round-trip,
  - SQLite repository CRUD,
  - FileZilla XML patching.

## Improvements implemented in this iteration

- Fixed group name loading to handle null/blank values safely.
- Ensured `~/ACS/sites` directory is created before writing generated scripts.
- Corrected home-directory resolution to use `$HOME` (fallback to app documents dir).
- Fixed FileZilla XML auth mapping to use each profile’s `usePassword` value (not current UI toggle state).
- Added strict port validation (`1..65535`).
- Fixed group autocomplete to be truly case-insensitive.
- Fixed “Copy” action in list tab to generate the correct command for password vs key auth profiles.

## Suggested roadmap

### Phase 1 (short term)
- Split `main.dart` into feature modules.
- Add domain model (`SSHConfig`) + repository abstraction.
- Add unit tests for command and validation logic.

### Phase 2 (medium term)
- Add secure secret storage.
- Add Windows terminal support.
- Introduce import/export conflict-resolution UI.

### Phase 3 (long term)
- Add tags, favorites, recent connections.
- Add health checks (`ssh -o BatchMode=yes`) and profile verification.
- Package as `.deb`/AppImage with auto-update strategy.
