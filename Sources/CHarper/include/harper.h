/*
 * harper.h — C ABI for the harper-ffi static library (harper-core 2.5.0).
 *
 * Symbols are provided by libharper_ffi.a (linked via -lharper_ffi). All
 * strings are UTF-8. See harper-ffi/ for the Rust source.
 */
#ifndef HARPER_FFI_H
#define HARPER_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Check `text` for grammar/spelling issues using harper-core.
 *
 * Returns a malloc'd, NUL-terminated UTF-8 JSON C string the caller MUST free
 * with harper_free(). The JSON is an array of objects:
 *   [{ "start": <char offset>, "len": <char count>,
 *      "replacement": "<string>", "message": "<string>", "kind": "<string>" }]
 *
 *  - "start"/"len" are CHAR (Unicode scalar) offsets, NOT bytes/UTF-16.
 *  - "kind" is one of: spelling, grammar, punctuation, repetition,
 *    capitalization, phrasing.
 *
 * On null/invalid input or any internal error, returns "[]". Thread-safe.
 */
char *harper_check(const char *text);

/* Free a string previously returned by harper_check(). NULL is a no-op. */
void harper_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* HARPER_FFI_H */
