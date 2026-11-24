# Publishing maintenance updates

This repository publishes prepared, signed release assets. Do not copy a user's installed application directory into it. Keep signing private keys, Role, INI, settings, logs and diagnostic archives outside this repository.

1. Prepare a new version with the existing local `Prepare-Release.ps1`. The release directory must contain exactly the signed payload ZIP, bootstrap ZIP, collector ZIP, update.json and update.sig. Signing stays local; Actions receives only the public key.
2. Run `scripts/Stage-Release.ps1 -ReleaseDirectory <prepared-directory> -Title <title> -Notes <notes>` (defaults to publish). This validates before staging. For diagnostics use `-Mode verify`; `-Mode smoke` tests uploads to a draft and never changes Latest.
3. Run `scripts/Test-Release.ps1`. Commit the complete release-input directory in one commit and push to main. Never commit a request before its matching assets.
4. Wait for the Publish signed maintenance release workflow. Inspect its result and independently check anonymous downloads/signature verification. Report the release link only after success. A failed run leaves the existing stable release unchanged; a draft can remain for investigation.
5. Re-running the same published version verifies its files without overwriting it. Use a higher four-part version for new changes.

Friend settings are preserved by the existing updater; this workflow only uploads release assets and does not alter the updater's installation behavior.
