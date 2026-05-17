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

# 3. vcpkg deps. The CI workflow pins vcpkg (lukka/run-vcpkg @ rustdesk's
#    commit) and sets VCPKG_ROOT; RustDesk ships a vcpkg.json manifest so deps
#    resolve automatically - run the manifest install (idempotent) as a safety
#    net rather than hand-listing packages (the old list drifts per release).
if (-not $env:VCPKG_ROOT) { throw "VCPKG_ROOT not set (CI run-vcpkg step missing)" }
& "$env:VCPKG_ROOT\vcpkg.exe" install --triplet x64-windows-static
if ($LASTEXITCODE -ne 0) { throw "vcpkg manifest install failed" }

# 4. Build - Flutter+software-codec only. hwcodec/vram dropped from CI because
#    they require FFmpeg dev headers that vcpkg caching makes unreliable; add
#    back once a pre-built FFmpeg artifact is wired into the workflow.
python build.py --portable --flutter
if ($LASTEXITCODE -ne 0) { throw "build.py failed (exit $LASTEXITCODE) - inspect log above" }

# 5. Normalize the produced installer/portable to the path the sign step
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
