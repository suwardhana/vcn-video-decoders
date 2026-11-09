# Conventions

- Repository formatting is Google-derived and configured in `.editorconfig`, `.clang-format`, `.swift-format`, `pyproject.toml`, and Google `.pylintrc`.
- C/C++: 2 spaces, 80 columns, left pointer alignment, case-sensitive grouped includes. Preserve include guards and module prefixes such as `av1_`, `vp9_`, `vcnav1_`, and `vcnvp9_`.
- Python: 4 spaces, 80 columns, Pyink majority quotes, Google import style; formatter target Python 3.11.
- Swift: 2 spaces, 100 columns; configured rules prohibit force unwrap, force try and implicitly unwrapped optionals. Public declarations require documentation.
- JavaScript/HTML/CSS and shell: 2 spaces; JavaScript uses single quotes and 80 columns. Shell scripts use `set -e` in zsh or `set -euo pipefail` in Bash.
- UTF-8, LF, final newline, no trailing whitespace. Markdown may retain trailing spaces for hard breaks.
- zsh is intentional where macOS-only parameter expansion or installer behavior requires it; retain the explanatory interpreter comment.
- VCN/firmware/driver structures are binary interfaces. Do not reorder fields, remove padding, change packing, or assume native alignment merely to simplify style.
- Keep third-party provenance/license headers, especially Mesa/AMD VP9 tables.
- External AOM and FFmpeg FATE conformance vectors are the functional decoder tests; they are not included in the repository.

Security and binary-safety conventions are in `mem:security`; task-specific verification is in `mem:task_completion`.
