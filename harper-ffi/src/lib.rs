//! C-ABI FFI bridge exposing harper-core 2.5.0's grammar checker to Swift.
//!
//! Public surface:
//!   char* harper_check(const char* text);  // malloc'd UTF-8 JSON, free with harper_free
//!   void  harper_free(char* ptr);
//!
//! Every API call below was written against docs.rs for harper-core 2.5.0.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Arc, OnceLock};

use harper_core::{Dialect, Document};
use harper_core::linting::{LintGroup, LintKind, Linter, Suggestion};
use harper_core::spell::FstDictionary;

/// Empty JSON array used for null/invalid input and on any panic.
const EMPTY_JSON: &str = "[]";

/// The curated FST dictionary is the expensive artifact to build, so build it
/// exactly once and share it across calls/threads via `Arc`. `FstDictionary`
/// is immutable and `Arc<FstDictionary>` is `Send + Sync`, so this is safe to
/// read from any thread.
///
/// We intentionally do NOT cache the `LintGroup` itself: `Linter::lint` takes
/// `&mut self`, which would require a `Mutex` and serialize all callers. The
/// `LintGroup` is cheap to reconstruct relative to the dictionary, so we build
/// a fresh one per call from the shared dictionary instead.
fn curated_dictionary() -> Arc<FstDictionary> {
    static DICT: OnceLock<Arc<FstDictionary>> = OnceLock::new();
    DICT.get_or_init(FstDictionary::curated).clone()
}

/// Map a harper `LintKind` to the lowercase string contract:
/// one of spelling, grammar, punctuation, repetition, capitalization, phrasing.
/// Default is "grammar" for anything not specifically categorized.
fn kind_to_str(kind: LintKind) -> &'static str {
    match kind {
        LintKind::Spelling | LintKind::Typo => "spelling",
        LintKind::Punctuation | LintKind::Formatting => "punctuation",
        LintKind::Repetition => "repetition",
        LintKind::Capitalization => "capitalization",
        // "phrasing"-flavored categories: word choice / style / readability / usage.
        LintKind::WordChoice
        | LintKind::Style
        | LintKind::Readability
        | LintKind::Usage
        | LintKind::Redundancy
        | LintKind::Enhancement
        | LintKind::Eggcorn
        | LintKind::Malapropism
        | LintKind::Nonstandard
        | LintKind::Regionalism => "phrasing",
        // Grammar-ish / structural categories.
        LintKind::Grammar
        | LintKind::Agreement
        | LintKind::BoundaryError
        | LintKind::Miscellaneous => "grammar",
        // LintKind may gain variants; default safely.
        _ => "grammar",
    }
}

/// Run harper over `text` and produce the JSON contract string.
fn check_to_json(text: &str) -> String {
    let dictionary = curated_dictionary();

    // Build the document with the built-in PlainEnglish parser + curated dictionary.
    let document = Document::new_plain_english(text, &dictionary);

    // Fresh curated lint group from the shared dictionary; American dialect.
    let mut group = LintGroup::new_curated(dictionary.clone(), Dialect::American);

    // Linter::lint(&mut self, &Document) -> Vec<Lint>
    let lints = group.lint(&document);

    let mut out: Vec<serde_json::Value> = Vec::with_capacity(lints.len());
    for lint in lints {
        // span is Span<char>: start/end are CHAR (Unicode scalar) offsets, end-exclusive.
        let start = lint.span.start;
        let len = lint.span.end.saturating_sub(lint.span.start);

        // Pick the first ReplaceWith suggestion as "replacement".
        // If the first actionable suggestion is a Remove, replacement = "".
        // InsertAfter is treated as non-replacement here. Lints with no
        // actionable suggestion are skipped.
        let mut replacement: Option<String> = None;
        for suggestion in &lint.suggestions {
            match suggestion {
                Suggestion::ReplaceWith(chars) => {
                    replacement = Some(chars.iter().collect());
                    break;
                }
                Suggestion::Remove => {
                    replacement = Some(String::new());
                    break;
                }
                Suggestion::InsertAfter(_) => {}
            }
        }

        let replacement = match replacement {
            Some(r) => r,
            None => continue,
        };

        out.push(serde_json::json!({
            "start": start,
            "len": len,
            "replacement": replacement,
            "message": lint.message,
            "kind": kind_to_str(lint.lint_kind),
        }));
    }

    serde_json::to_string(&out).unwrap_or_else(|_| EMPTY_JSON.to_string())
}

/// Allocate a C string for return to the caller. The caller owns it and must
/// free it with `harper_free`.
fn into_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => CString::new(EMPTY_JSON).unwrap().into_raw(),
    }
}

/// Check `text` for grammar/spelling issues.
///
/// Returns a malloc'd, NUL-terminated UTF-8 JSON C string the caller MUST free
/// with `harper_free`. On null/invalid-UTF-8 input or on any internal panic,
/// returns the JSON `"[]"`. Never returns null on a normal return path.
///
/// # Safety
/// `text` must be a valid NUL-terminated C string pointer or null.
#[no_mangle]
pub extern "C" fn harper_check(text: *const c_char) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if text.is_null() {
            return EMPTY_JSON.to_string();
        }
        // SAFETY: caller guarantees a valid NUL-terminated C string (non-null checked).
        let c_str = unsafe { CStr::from_ptr(text) };
        match c_str.to_str() {
            Ok(s) => check_to_json(s),
            Err(_) => EMPTY_JSON.to_string(),
        }
    }));

    match result {
        Ok(json) => into_c_string(json),
        Err(_) => into_c_string(EMPTY_JSON.to_string()),
    }
}

/// Free a string previously returned by `harper_check`.
///
/// # Safety
/// `ptr` must be a pointer returned by `harper_check` (or null), freed once.
#[no_mangle]
pub extern "C" fn harper_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    // SAFETY: ptr came from CString::into_raw in this module; reclaim and drop it.
    unsafe {
        drop(CString::from_raw(ptr));
    }
}
