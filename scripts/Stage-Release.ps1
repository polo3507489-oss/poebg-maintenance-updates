param(
    [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$Notes,
    [ValidateSet('publish','verify','smoke')][string]$Mode='publish'
)
$ErrorActionPreference='Stop'
$source=(Resolve-Path -LiteralPath $ReleaseDirectory).Path
$manifest=Get-Content -LiteralPath (Join-Path $source 'update.json') -Raw | ConvertFrom-Json
if($manifest.version -notmatch '^\d+\.\d+\.\d+\.\d+$'){throw 'Invalid version'}
$files=@(Get-ChildItem -LiteralPath $source -File)
if($files.Count -ne 5){throw 'Provide only the five prepared release assets'}
$inputRoot=Join-Path $PSScriptRoot '../release-input'
$assetRoot=Join-Path $inputRoot 'assets'
New-Item -ItemType Directory -Path $assetRoot -Force | Out-Null
# Only this staging directory is replaced; Role and installed application files are never used.
Get-ChildItem -LiteralPath $assetRoot -File | Remove-Item
$assets=@()
foreach($file in $files){
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $assetRoot $file.Name)
    $assets+=@{name=$file.Name;size=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$request=@{schema=1;version=$manifest.version;mode=$Mode;title=$Title;notes=$Notes;assets=$assets}
$requestPath=Join-Path $inputRoot 'request.json'
[IO.File]::WriteAllText($requestPath,($request|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
& (Join-Path $PSScriptRoot 'Publish-Release.ps1') -Request $requestPath -VerifyOnly
Write-Output 'Staged and verified. Commit release-input and push to main to trigger Actions.'
