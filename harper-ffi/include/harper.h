/*
 * harper.h — C ABI for the harper-ffi static library (harper-core 2.5.0).
 *
 * Link against libharper_ffi.a. All strings are UTF-8.
 */
#ifndef HARPER_FFI_H
#define HARPER_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Check `text` for grammar/spelling issues using harper-core.
 *
 * Returns a malloc'd, NUL-terminated UTF-8 JSON C string that the caller MUST
 * free with harper_free().
 *
 * The JSON is an array of objects:
 *   [
 *     {
 *       "start":       <integer, char (Unicode scalar) offset into the input>,
 *       "len":         <integer, char count of the offending span>,
 *       "replacement": "<string>",
 *       "message":     "<string>",
 *       "kind":        "<string>"
 *     },
 *     ...
 *   ]
 *
 * Notes on the contract:
 *  - "start"/"len" are CHAR (Unicode scalar) offsets, matching harper's native
 *    char indexing. They are NOT byte offsets and NOT UTF-16 code-unit offsets.
 *    "len" = span.end - span.start (end-exclusive).
 *  - "replacement" is the FIRST ReplaceWith suggestion's text. If the first
 *    actionable suggestion is a removal, "replacement" is "" (empty string).
 *  - Lints with NO actionable suggestion are SKIPPED.
 *  - "kind" is one of: "spelling", "grammar", "punctuation", "repetition",
 *    "capitalization", "phrasing". Best-effort; defaults to "grammar".
 *
 * On a null `text`, invalid UTF-8, or any internal error/panic, returns "[]".
 * Never returns NULL on a normal return path. Thread-safe.
 */
char *harper_check(const char *text);

/*
 * Free a string previously returned by harper_check().
 * Passing NULL is a no-op. Do not free the same pointer twice.
 */
void harper_free(char *ptr);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* HARPER_FFI_H */
