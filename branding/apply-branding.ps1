# branding/apply-branding.ps1  --  copy to FORK at branding/ (CI runs this first)
#
# Hardened against the VERIFIED rustdesk 1.4.6 layout (checked via the GitHub
# API, not guessed). Two jobs, with a deliberate split:
#
#   (1) SERVER / KEY PIN  - the ONLY build-critical, functional rebrand.
#       RustDesk reads RENDEZVOUS_SERVER + RS_PUB_KEY via option_env! at
#       COMPILE time, so they must be Machine scope or the Rust build won't
#       see them (rustdesk discussions #7108 / #10599). No API_SERVER (we run
#       no web API). This is a HARD requirement - the script throws if it
#       cannot set it.
#
#   (2) COSMETIC REBRAND  - icons + display strings. Best-effort by design: a
#       missing/moved target logs a WARNING and continues. Rationale: a
#       functional, server-pinned, EV-SIGNED agent that still shows the
#       upstream name is far more useful than a build that refuses to produce
#       anything. Cosmetic polish is a fast-follow, not a blocker.
#
# Removed (verified absent/harmful @1.4.6 - would have failed the first run):
#   - res/setup.iss          : DOES NOT EXIST. RustDesk has no Inno Setup.
#   - flutter/pubspec.yaml   : name is flutter_hbb, not rustdesk. Renaming it
#                              breaks every package:flutter_hbb/ Dart import.
#   - Cargo.toml `name`      : default-run/bin targets reference "rustdesk";
#                              renaming the crate breaks the Rust build.
# Values mirror remote-support/agent/branding/storeveu-support.toml (keep in sync).
$ErrorActionPreference = 'Stop'

$RENDEZVOUS = 'support-relay.storeveu.com'
$PUBKEY     = 'Idwk2r8dLqiPRbFE1OexmsFtAcdn2huqqF9k17DcqY0='
$APPNAME    = 'Storeveu Support'

# ---- (1) Compile-time server/key pin (Machine scope - CRITICAL, hard) ----
[Environment]::SetEnvironmentVariable('RENDEZVOUS_SERVER', $RENDEZVOUS, 'Machine')
[Environment]::SetEnvironmentVariable('RS_PUB_KEY', $PUBKEY, 'Machine')
$env:RENDEZVOUS_SERVER = $RENDEZVOUS    # same-job steps see it without a reload
$env:RS_PUB_KEY        = $PUBKEY
$check = [Environment]::GetEnvironmentVariable('RENDEZVOUS_SERVER', 'Machine')
if ($check -ne $RENDEZVOUS) {
  throw "FATAL: could not set RENDEZVOUS_SERVER at Machine scope (got '$check'). Without the compile-time pin the agent has no server - refusing to build."
}
Write-Host "==> [HARD] server pin set (Machine): RENDEZVOUS_SERVER=$RENDEZVOUS RS_PUB_KEY=$PUBKEY"

# ---- best-effort patch helper: WARN (never throw) on a missed target ----
function Invoke-TryPatch {
  param($File, $Pattern, $Replacement, $Why)
  if (-not (Test-Path $File)) {
    Write-Warning "branding(skip): $File absent - $Why (cosmetic only; build continues)"
    return
  }
  $txt = Get-Content $File -Raw
  if ($txt -notmatch $Pattern) {
    Write-Warning "branding(skip): pattern not found in $File - $Why (1.4.6 drift; cosmetic; continues)"
    return
  }
  ($txt -replace $Pattern, $Replacement) | Set-Content $File -NoNewline
  Write-Host "    cosmetic: patched $File ($Why)"
}

# ---- (2) Cosmetic rebrand - VERIFIED-present targets only, all best-effort ----
# Cargo.toml description is pure metadata (Add/Remove Programs blurb): safe to
# change, does NOT affect the crate name / build graph. Verified present
# @1.4.6 as: description = "RustDesk Remote Desktop".
Invoke-TryPatch -File 'Cargo.toml' -Pattern '(?m)^description\s*=\s*".*"' -Replacement "description = `"$APPNAME - secure remote support`"" -Why 'crate description (metadata)'

# English UI strings - src/lang/en.rs verified present @1.4.6. Replacing the
# "RustDesk" literal rebrands the visible product name in the English UI.
Invoke-TryPatch -File 'src/lang/en.rs' -Pattern '"RustDesk"' -Replacement "`"$APPNAME`"" -Why 'English UI product name'

# Disable the public auto-update check (the pink "new version of RustDesk
# available" banner). src/common.rs::check_software_update() spawns a thread
# running do_check_software_update(), which polls the PUBLIC rustdesk release
# endpoint and sets SOFTWARE_UPDATE_URL; the Flutter home page shows the banner
# whenever that URL is non-empty. A private, server-pinned fork must never
# advertise upstream releases - neuter the spawn so the URL stays empty.
# Pattern = the verified 1.4.6 line (whitespace-tolerant). Best-effort: a miss
# only means the banner persists, so WARN + continue.
Invoke-TryPatch -File 'src/common.rs' -Pattern 'std::thread::spawn\(move \|\|\s*allow_err!\(do_check_software_update\(\)\)\)\s*;' -Replacement '/* [storeveu] public auto-update check disabled (no upstream version banner) */' -Why 'disable auto-update version banner'

# Icons / tray art - VERIFIED paths @1.4.6: res/icon.ico, res/tray-icon.ico,
# flutter/windows/runner/resources/app_icon.ico all exist; flutter/assets/ is
# a declared asset dir. Drop Storeveu art over them IF the fork ships the assets;
# otherwise keep upstream icons (still a working signed agent).
$assets  = Join-Path $PSScriptRoot 'assets'
$iconMap = [ordered]@{
  'icon.ico'     = @('res\icon.ico', 'res\tray-icon.ico')
  'app_icon.ico' = @('flutter\windows\runner\resources\app_icon.ico')
  'logo.png'     = @('flutter\assets\logo.png')
}
foreach ($srcName in $iconMap.Keys) {
  $src = Join-Path $assets $srcName
  if (-not (Test-Path $src)) {
    Write-Warning "branding(skip): branding/assets/$srcName not provided - keeping upstream icon (signed agent still builds)"
    continue
  }
  foreach ($dest in $iconMap[$srcName]) {
    $destDir = Split-Path $dest -Parent
    if ($destDir -and -not (Test-Path $destDir)) {
      Write-Warning "branding(skip): dest dir '$destDir' absent for $srcName (1.4.6 drift)"
      continue
    }
    Copy-Item $src (Join-Path (Get-Location) $dest) -Force
    Write-Host "    cosmetic: asset $srcName -> $dest"
  }
}

Write-Host "==> Branding done. FUNCTIONAL pin is hard-guaranteed above; name/icons"
Write-Host "    are best-effort - any WARN lines are cosmetic, the signed agent"
Write-Host "    still ships server-pinned. Polish branding as a fast-follow."
