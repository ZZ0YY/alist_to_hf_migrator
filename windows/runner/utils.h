#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and any child processes. Returns true if the
// console was successfully created, false if a console already existed
// or creation failed. On failure, the original streams are left unchanged.
void CreateAndAttachConsole();

// Returns the command line arguments as a vector of strings, encoded in UTF-8.
std::vector<std::string> GetCommandLineArguments();

// Converts a UTF-16 wide string to UTF-8.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

#endif  // RUNNER_UTILS_H_
