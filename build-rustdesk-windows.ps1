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

# 1b. Consent model = cashier Accept, no password (D3 revised / D2=B).
#     hbb_common password_security::approve_mode() defaults to Both; with
#     RustDesk's auto-generated temporary password that still demands a code.
#     The clean custom.txt settings path is signature-gated by RustDesk's
#     private key (unavailable to an AGPL fork), so patch the pinned
#     hbb_common default Both -> Click HERE - after the submodule checkout
#     above (a later `submodule update` would clobber an earlier edit) and
#     before compile. HARD (throw, not best-effort): a wrong-consent agent
#     must never ship. Pinned hbb_common @48c37de3 so the pattern is stable.
$pwf = 'libs/hbb_common/src/password_security.rs'
if (-not (Test-Path $pwf)) { throw "hbb_common not checked out ($pwf) - submodule step failed" }
$pwsrc = Get-Content $pwf -Raw
$pwpat = '(?s)(else if mode == "click" \{\s*ApproveMode::Click\s*\}\s*else \{\s*)ApproveMode::Both(\s*\})'
if ($pwsrc -notmatch $pwpat) { throw "approve_mode() Both->Click anchor not found in $pwf - hbb_common drifted; refusing to build a wrong-consent agent" }
$pwnew = [regex]::Replace($pwsrc, $pwpat, '${1}ApproveMode::Click${2}')
if ($pwnew -eq $pwsrc -or $pwnew -notmatch '(?s)mode == "click".*ApproveMode::Click.*else \{\s*ApproveMode::Click') { throw "approve_mode patch did not take - refusing to build" }
Set-Content $pwf -Value $pwnew -NoNewline
Write-Host "==> consent: approve_mode() default Both -> Click patched ($pwf)"

# 1c. SERVER PIN (the REAL one). RustDesk 1.4.6 takes the rendezvous server
#     + key from hard-coded consts in hbb_common/src/config.rs, NOT from the
#     RENDEZVOUS_SERVER / RS_PUB_KEY env vars (nothing reads them via
#     option_env!). So apply-branding's env pin AND step 2 below are no-ops;
#     this is what actually points the binary at support-relay.storeveu.com.
#     Patch after submodule checkout, before compile. HARD: a build pointing
#     at RustDesk's PUBLIC server must never ship. Verified vs pinned source.
$cfg = 'libs/hbb_common/src/config.rs'
if (-not (Test-Path $cfg)) { throw "hbb_common not checked out ($cfg) - submodule step failed" }
$cfgsrc = Get-Content $cfg -Raw
$p1 = '(pub const RENDEZVOUS_SERVERS: &\[&str\] = &\[")[^"]*("\];)'
$p2 = '(pub const RS_PUB_KEY: &str = ")[^"]*(";)'
if ($cfgsrc -notmatch $p1) { throw "RENDEZVOUS_SERVERS const anchor not found in $cfg - hbb_common drifted; refusing to ship a public-server build" }
if ($cfgsrc -notmatch $p2) { throw "RS_PUB_KEY const anchor not found in $cfg - hbb_common drifted; refusing to ship a public-server build" }
# v2.0.1 (new-server generation): pinned to the DEDICATED relay on :443 (rendezvous, tcp+udp; NAT test
# derives :442; relay advertised by hbbs as support.storeveu.com:80) - ports
# strict store networks allow, so agents no longer need the wstunnel chain
# wherever outbound UDP 443 passes. host:port is honored by
# get_rendezvous_server() (only appends :21116 when no port present, verified).
$cfgnew = [regex]::Replace($cfgsrc, $p1, '${1}support.storeveu.com:443${2}')
$cfgnew = [regex]::Replace($cfgnew, $p2, '${1}xW7LgoDQ9p5FVQQbA35lzAAEQ03W0hpJRa4LE220eeU=${2}')
if ($cfgnew -match 'rs-ny\.rustdesk\.com' -or $cfgnew -match 'OeVuKk5nlHiXp') { throw "server-pin patch left RustDesk public server/key in $cfg - refusing to build" }
if ($cfgnew -eq $cfgsrc) { throw "server-pin patch made no change - refusing to build" }
Set-Content $cfg -Value $cfgnew -NoNewline
Write-Host "==> server pin: RENDEZVOUS_SERVERS + RS_PUB_KEY -> support.storeveu.com:443 (config.rs patched)"

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
  # Do NOT downgrade extended_text here. rustdesk's bridge.yml pins it
  # 14.0.0 -> 13.0.0, but ONLY because that codegen job runs Flutter 3.22.3.
  # We run codegen AND `flutter build windows` in one job on Flutter 3.24.5,
  # where rustdesk's pinned extended_text 14.0.0 is required - 13.0.0 breaks
  # the Windows build with a TextOverflowMixin.layoutInlineChildren override
  # error (regressed v1.0.8). codegen itself is unaffected by this package.
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
