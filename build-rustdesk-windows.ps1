# build-rustdesk-windows.ps1  --  copy to the FORK ROOT (called by CI after
# branding/apply-branding.ps1). Builds the Flutter+Rust Windows client.
#
# Build invocation is RustDesk's OWN tested 1.4.6 command (taken verbatim from
# rustdesk/rustdesk@1.4.6 .github/workflows/flutter-build.yml), minus
# --skip-portable-pack so the self-installing portable .exe IS produced (the
# upstream workflow skips it then packages separately; we want the single
# exe). Do NOT invent flags - --feature IddDriver is NOT valid at 1.4.6
# (build.py has no IddDriver feature; --hwcodec is its own flag, verified).
$ErrorActionPreference = 'Stop'
Write-Host "==> Storeveu Support agent build (RustDesk 1.4.6, Windows/Flutter)"

# 1. Submodules - hbb_common is a git SUBMODULE in 1.4.x and the option_env!
#    pins resolve through the crate graph. CI checkout already does
#    submodules:recursive; this re-asserts for a manual/dispatch run.
git submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw "submodule init failed" }

# 2. The compile-time pin MUST already be Machine scope (apply-branding.ps1).
#    Re-read from Machine scope into THIS process - the classic rustdesk build
#    gotcha (#7108/#10599) is a process not inheriting it.
foreach ($v in 'RENDEZVOUS_SERVER', 'RS_PUB_KEY') {
  $val = [Environment]::GetEnvironmentVariable($v, 'Machine')
  if ([string]::IsNullOrWhiteSpace($val)) {
    throw "$v not set at Machine scope - branding/apply-branding.ps1 must run first"
  }
  Set-Item -Path "Env:$v" -Value $val
  Write-Host "    $v = $val"
}

# 3. vcpkg deps - manifest mode (RustDesk ships a root vcpkg.json). vcpkg
#    installs to .\vcpkg_installed\ by default, but rustdesk crates
#    (magnum-opus etc.) hard-look in $VCPKG_ROOT\installed - so
#    --x-install-root=$VCPKG_ROOT\installed is MANDATORY: without it the build
#    dies ~38min in at magnum-opus, "opus/opus_multistream.h file not found".
#    Do NOT drop this flag - its removal regressed every build v1.0.1-v1.0.6.
#    Assert vcpkg.json is in CWD; a manifest install elsewhere is a silent no-op.
if (-not $env:VCPKG_ROOT) { throw "VCPKG_ROOT not set (CI run-vcpkg step missing)" }
if (-not (Test-Path 'vcpkg.json')) {
  throw "vcpkg.json not in CWD ($(Get-Location)) - manifest install would be a silent no-op; run from the fork root"
}
& "$env:VCPKG_ROOT\vcpkg.exe" install --triplet x64-windows-static --x-install-root="$env:VCPKG_ROOT\installed"
if ($LASTEXITCODE -ne 0) { throw "vcpkg manifest install failed" }

# 4. flutter_rust_bridge codegen. RustDesk gitignores src/bridge_generated.rs
#    + flutter/lib/generated_bridge.dart and regenerates them in CI (their
#    .github/workflows/bridge.yml) - build.py does NOT. Without this,
#    `cargo build --features flutter --lib` fails: "file not found for module
#    bridge_generated" + "EventToUI: IntoIntoDart". Versions are pinned to
#    rustdesk 1.4.6 bridge.yml (cargo-expand 1.0.95, frb codegen 1.80.1).
#    Do NOT remove - its absence regressed every build through v1.0.7.
$env:PATH = "$(Join-Path $env:USERPROFILE '.cargo\bin');$env:PATH"
cargo install cargo-expand --version 1.0.95 --locked
if ($LASTEXITCODE -ne 0) { throw "cargo install cargo-expand failed" }
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked
if ($LASTEXITCODE -ne 0) { throw "cargo install flutter_rust_bridge_codegen failed" }
Push-Location flutter
try {
  # rustdesk 1.4.6 bridge.yml pins extended_text 14.0.0 -> 13.0.0 before pub get
  (Get-Content pubspec.yaml) -replace 'extended_text: 14\.0\.0', 'extended_text: 13.0.0' |
    Set-Content pubspec.yaml
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
}
finally { Pop-Location }
flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h
if ($LASTEXITCODE -ne 0) { throw "flutter_rust_bridge_codegen failed" }
if (-not (Test-Path 'src/bridge_generated.rs')) { throw "codegen succeeded but src/bridge_generated.rs missing" }

# 5. Build - Flutter+software-codec only. hwcodec/vram dropped from CI because
#    they require FFmpeg dev headers that vcpkg caching makes unreliable; add
#    back once a pre-built FFmpeg artifact is wired into the workflow.
python build.py --portable --flutter
if ($LASTEXITCODE -ne 0) { throw "build.py failed (exit $LASTEXITCODE) - inspect log above" }

# 6. Normalize the produced installer/portable to the path the sign step
#    wants. RustDesk's portable build emits the self-installing exe; names
#    vary by release (*-install.exe, rustdesk-<ver>.exe, *setup*.exe). Search
#    the known output roots, newest first; fail loudly if nothing materialized.
$roots = @(
  '.', 'flutter',
  'flutter\build\windows\x64\runner\Release',
  'flutter\build\windows\runner\Release'
) | Where-Object { Test-Path $_ }
$cands = foreach ($r in $roots) {
  Get-ChildItem -Path $r -Recurse -File -ErrorAction SilentlyContinue -Include '*-install.exe', '*setup*.exe', 'rustdesk*.exe', 'storeveusupport*.exe'
}
$built = $cands | Where-Object { $_.Length -gt 1MB } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $built) {
  Get-ChildItem -Recurse -File -Include '*.exe' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 20 |
    ForEach-Object { Write-Host ("    saw: {0} ({1} KB)" -f $_.FullName, [int]($_.Length / 1KB)) }
  throw "no installer/portable .exe produced - see candidates above + build.py log"
}
New-Item -ItemType Directory -Force -Path dist | Out-Null
Copy-Item $built.FullName dist\StoreveuSupportSetup.exe -Force
Write-Host "==> dist\StoreveuSupportSetup.exe ready (from $($built.FullName))"
