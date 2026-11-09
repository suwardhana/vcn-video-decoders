# Task Completion

Run relevant checks from the repository root; parser changes require both parser analyzers and sanitizer/conformance testing when vectors are available.

```sh
git diff --check
./vcnav1/build.sh
./vcnvp9/build.sh
./vtav1/build.sh
./vtvp9/build.sh
```

Static parser analysis:
```sh
clang --analyze -std=c11 -Wall -Wextra -Xanalyzer -analyzer-output=text -Ivcnav1 vcnav1/av1parse.c -o /dev/null
clang --analyze -std=c11 -Wall -Wextra -Xanalyzer -analyzer-output=text -Ivcnvp9 vcnvp9/vp9parse.c -o /dev/null
```

Python and JavaScript syntax:
```sh
python3 - <<'PY'
import ast
from pathlib import Path
for path in Path('tools').glob('*.py'):
    ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
PY
node --check userscript/youtube-prefer-av1.user.js
node --check webtest/yt-probe.js
```

Swift type checks:
```sh
swiftc -typecheck -parse-as-library installer/app/main.swift
swiftc -typecheck installer/assets/render.swift
swiftc -typecheck tools/av1probe.swift
swiftc -typecheck tools/vtroundtrip.swift
swiftc -typecheck tools/vtroundtrip2.swift
swiftc -typecheck webtest/webtest.swift
```

Shell syntax: run `/bin/zsh -n <script>` for zsh-shebang scripts and `/bin/bash -n <script>` for Bash scripts. Format changed files with `xcrun clang-format -i <c-cpp-js-files>`, `pyink <python-files>`, and `/usr/bin/swift format --in-place <swift-files>`.

For installer changes also run `./installer/build-app.sh` and `codesign --verify --deep --strict "installer/build/AMD VCN Video Decoders.app"`. Finish with `git status --short`; do not leave untracked test executables, crash artifacts, secrets, or downloaded proprietary inputs.
