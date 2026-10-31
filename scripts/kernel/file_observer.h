#ifndef XBOX_FILE_OBSERVER_H
#define XBOX_FILE_OBSERVER_H
#include <windows.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Optional title observer. Register before title threads start. Observers must
 * not re-enter guest file I/O. Called only after successful host operations. */
typedef void (*xbox_file_write_observer)(HANDLE, long long, const void *, DWORD);
typedef void (*xbox_file_close_observer)(HANDLE);
void xbox_file_observe(xbox_file_write_observer write, xbox_file_close_observer close);
#ifdef __cplusplus
}
#endif
#endif
