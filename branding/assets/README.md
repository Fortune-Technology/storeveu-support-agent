# Storeveu brand assets (OPTIONAL for a first build)

Drop these to rebrand the icons. If absent, the signed agent still builds and
is fully server-pinned - it just shows upstream icons (polish as a fast-follow):

  icon.ico      -> res/icon.ico + res/tray-icon.ico
  app_icon.ico  -> flutter/windows/runner/resources/app_icon.ico
  logo.png      -> flutter/assets/logo.png

branding/apply-branding.ps1 copies these in best-effort (WARN, never fail).