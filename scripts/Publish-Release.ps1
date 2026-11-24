param(
    [string]$Request = (Join-Path $PSScriptRoot '../release-input/request.json'),
    [switch]$VerifyOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repository = 'polo3507489-oss/poebg-maintenance-updates'
$requestPath = (Resolve-Path -LiteralPath $Request).Path
$inputRoot = Split-Path $requestPath
$plan = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
if ($plan.schema -ne 1 -or $plan.version -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Invalid release request' }
if ($plan.mode -notin @('verify', 'smoke', 'publish')) { throw 'Invalid release mode' }
$expected = @('PoeBG-maintenance.zip', 'update.json', 'update.sig', ('PoeBG-friends-autoupdate-' + $plan.version + '.zip'))
$collector = @($plan.assets | Where-Object { $_.name -match '^PoeBG-update-log-collector-\d+\.\d+\.\d+\.zip$' })
if ($collector.Count -ne 1) { throw 'Exactly one collector ZIP is required' }
$expected += $collector[0].name
if ($plan.assets.Count -ne 5 -or @($plan.assets.name | Sort-Object -Unique).Count -ne 5) { throw 'Exactly five unique assets are required' }
$paths = @{}
foreach ($asset in $plan.assets) {
    if ($asset.name -cnotin $expected -or $asset.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Unexpected asset' }
    $file = Join-Path $inputRoot ('assets/' + $asset.name)
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw ('Missing asset: ' + $asset.name) }
    if ((Get-Item -LiteralPath $file).Length -ne $asset.size -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $asset.sha256) { throw ('Asset digest mismatch: ' + $asset.name) }
    $paths[$asset.name] = $file
}
$manifestBytes = [IO.File]::ReadAllBytes($paths['update.json'])
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
try {
    $rsa.PersistKeyInCsp = $false
    $rsa.FromXmlString([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ReleasePublicKey.xml')))
    if (!$rsa.VerifyData($manifestBytes, [Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'), [IO.File]::ReadAllBytes($paths['update.sig']))) { throw 'Invalid RSA release signature' }
} finally { $rsa.Dispose() }
$manifest = [Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json
if ($manifest.schema -ne 1 -or $manifest.version -cne $plan.version -or $manifest.package -cne 'PoeBG-maintenance.zip') { throw 'Manifest does not match request' }
if ((Get-Item -LiteralPath $paths[$manifest.package]).Length -ne $manifest.size -or (Get-FileHash -LiteralPath $paths[$manifest.package] -Algorithm SHA256).Hash -ne $manifest.sha256) { throw 'Signed payload digest mismatch' }
$members = @{}
$protected = '^(Role|Log)/|^PoeBG-maintenance/(transactions|downloads|private)/|\.(settings|ini|log|bak|pdb)$|(^|/)(installed-release\.txt|blocked-version\.txt|\.update-lock|PBUpdate\.zip)$|signing-key'
function Assert-SafePath([string]$Name) {
    if (!$Name -or $Name.Contains('\') -or $Name.StartsWith('/') -or $Name.Contains(':') -or $Name -match '(^|/)\.{1,2}(/|$)') { throw ('Unsafe archive path: ' + $Name) }
}
foreach ($member in $manifest.files) {
    Assert-SafePath $member.path
    if ($member.path -match $protected -or $members.ContainsKey($member.path) -or $member.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw ('Invalid manifest member: ' + $member.path) }
    $members[$member.path] = $member.sha256
}
if ($members.Count -lt 1 -or !$members.ContainsKey('PoeBG.exe')) { throw 'Empty or incomplete manifest' }
function Test-Archive([string]$Path, [bool]$Bootstrap) {
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    $seen = @{}
    [long]$expanded = 0
    try {
        if ($archive.Entries.Count -gt 2000) { throw 'Too many archive entries' }
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName
            Assert-SafePath $name
            if ($seen.ContainsKey($name)) { throw ('Duplicate archive entry: ' + $name) }
            $seen[$name] = $true
            $expanded += $entry.Length
            if ($expanded -gt 536870912) { throw 'Archive exceeds expanded size limit' }
            if ($Bootstrap) {
                if (!$name.StartsWith('PoeBG/', [StringComparison]::Ordinal)) { throw 'Invalid bootstrap root' }
                $name = $name.Substring(6)
                if ($entry.FullName.EndsWith('/')) {
                    if ($name -notin @('Role/', 'Role/Worker/', 'Log/')) { throw 'Unexpected bootstrap directory' }
                    continue
                }
                if ($name -ceq 'PoeBG-maintenance/installed-release.txt') {
                    $reader = New-Object IO.StreamReader($entry.Open())
                    try { if ($reader.ReadToEnd().Trim() -cne $plan.version) { throw 'Incorrect installed-release marker' } } finally { $reader.Dispose() }
                    continue
                }
            }
            if (!$members.ContainsKey($name)) { throw ('Unsigned archive member: ' + $name) }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $digest = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') } finally { $sha.Dispose(); $stream.Dispose() }
            if ($digest -ne $members[$name]) { throw ('Archive member digest mismatch: ' + $name) }
        }
        foreach ($name in $members.Keys) {
            $zipName = if ($Bootstrap) { 'PoeBG/' + $name } else { $name }
            if (!$seen.ContainsKey($zipName)) { throw ('Archive member missing: ' + $zipName) }
        }
    } finally { $archive.Dispose() }
}
Test-Archive $paths['PoeBG-maintenance.zip'] $false
Test-Archive $paths[('PoeBG-friends-autoupdate-' + $plan.version + '.zip')] $true
Write-Output ('PASS: signature, 5 assets and ' + $members.Count + ' signed members in both archives')
if ($VerifyOnly -or $plan.mode -eq 'verify') { return }
if (!$env:GH_TOKEN) { throw 'GH_TOKEN is required to publish' }
if ($env:GITHUB_REPOSITORY -and $env:GITHUB_REPOSITORY -cne $repository) { throw 'Unexpected repository' }
function Invoke-Gh([string[]]$Arguments) {
    $result = & gh @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('GitHub CLI failed: ' + ($Arguments | Select-Object -First 3) -join ' ') }
    return $result
}
$tag = if ($plan.mode -eq 'smoke') { 'automation-smoke-' + $env:GITHUB_RUN_ID } else { 'v' + $plan.version }
$existing = & gh release view $tag --repo $repository --json isDraft,assets 2>$null
$exists = $LASTEXITCODE -eq 0
if ($exists) { $existing = ($existing -join "`n") | ConvertFrom-Json }
$isPublished = $exists -and !$existing.isDraft
if ($isPublished -and $plan.mode -eq 'smoke') { throw 'Smoke test must never alter a published release' }
if (!$isPublished) {
    if (!$exists) {
        $notesPath = Join-Path $env:RUNNER_TEMP 'poebg-release-notes.txt'
        [IO.File]::WriteAllText($notesPath, [string]$plan.notes)
        $title = if ($plan.mode -eq 'smoke') { 'Automation upload test (draft only)' } else { [string]$plan.title }
        Invoke-Gh -Arguments @('release','create',$tag,'--repo',$repository,'--target',$env:GITHUB_SHA,'--draft','--title',$title,'--notes-file',$notesPath) | Out-Null
    }
    $existingNames = if ($exists) { @($existing.assets.name) } else { @() }
    foreach ($name in $existingNames) { if ($name -cnotin $expected) { throw ('Unexpected existing release asset: ' + $name) } }
    foreach ($name in $expected) { Invoke-Gh -Arguments @('release','upload',$tag,$paths[$name],'--repo',$repository,'--clobber') | Out-Null }
}
$downloadRoot = Join-Path $env:RUNNER_TEMP ('poebg-release-verify-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $downloadRoot | Out-Null
Invoke-Gh -Arguments @('release','download',$tag,'--repo',$repository,'--dir',$downloadRoot) | Out-Null
$uploaded = @((Get-ChildItem -LiteralPath $downloadRoot -File).Name)
if ($uploaded.Count -ne 5) { throw 'Remote release must have exactly 5 assets' }
foreach ($asset in $plan.assets) {
    $downloaded = Join-Path $downloadRoot $asset.name
    if (!(Test-Path -LiteralPath $downloaded) -or (Get-FileHash -LiteralPath $downloaded -Algorithm SHA256).Hash -ne $asset.sha256) { throw ('Uploaded asset mismatch: ' + $asset.name) }
}
if ($plan.mode -eq 'publish' -and !$isPublished) {
    $latestJson = Invoke-Gh -Arguments @('api',('repos/' + $repository + '/releases/latest'))
    $latest = ($latestJson -join "`n") | ConvertFrom-Json
    if ($latest.tag_name -notmatch '^v(\d+\.\d+\.\d+\.\d+)$' -or [version]$plan.version -le [version]$Matches[1]) { throw 'New release must be newer than latest stable release' }
    Invoke-Gh -Arguments @('release','edit',$tag,'--repo',$repository,'--draft=false','--latest') | Out-Null
}
$message = if ($plan.mode -eq 'smoke') { 'PASS: all 5 assets uploaded and downloaded; smoke release remains a draft' } elseif ($isPublished) { 'PASS: existing published release verified without changes' } else { 'PASS: verified release published as latest' }
Write-Output $message
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $message }
