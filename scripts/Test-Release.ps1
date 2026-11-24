param([string]$Request=(Join-Path $PSScriptRoot '../release-input/request.json'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$source=(Resolve-Path -LiteralPath $Request).Path
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('poebg-release-test-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
Copy-Item -LiteralPath (Split-Path $source) -Destination (Join-Path $sandbox 'input') -Recurse
$testRequest=Join-Path $sandbox 'input/request.json'
$root=Split-Path $testRequest
$original=[IO.File]::ReadAllBytes($testRequest)
$bootstrap=(Get-Content -LiteralPath $testRequest -Raw | ConvertFrom-Json).assets | Where-Object name -Like 'PoeBG-friends-*'
$bootstrapPath=Join-Path $root ('assets/'+$bootstrap.name)
$zipOriginal=[IO.File]::ReadAllBytes($bootstrapPath)
function Assert-Rejected([string]$Expected) {
    $caught=$false
    try { & (Join-Path $PSScriptRoot 'Publish-Release.ps1') -Request $testRequest -VerifyOnly }
    catch { if($_.Exception.Message -notlike ('*'+$Expected+'*')){throw}; $caught=$true }
    if(!$caught){throw ('Expected rejection: '+$Expected)}
    Write-Output ('PASS: rejected '+$Expected)
}
function Update-ZipDigest {
    $plan=Get-Content -LiteralPath $testRequest -Raw | ConvertFrom-Json
    $asset=$plan.assets | Where-Object name -EQ $bootstrap.name
    $asset.size=(Get-Item -LiteralPath $bootstrapPath).Length
    $asset.sha256=(Get-FileHash -LiteralPath $bootstrapPath).Hash.ToLowerInvariant()
    $plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $testRequest -Encoding UTF8
}
& (Join-Path $PSScriptRoot 'Publish-Release.ps1') -Request $testRequest -VerifyOnly
$plan=Get-Content -LiteralPath $testRequest -Raw | ConvertFrom-Json
$plan.assets[0].sha256='0'*64
$plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $testRequest -Encoding UTF8
Assert-Rejected 'Asset digest mismatch'
[IO.File]::WriteAllBytes($testRequest,$original)
$signaturePath=Join-Path $root 'assets/update.sig'
$signature=[IO.File]::ReadAllBytes($signaturePath)
$signature[0]=$signature[0] -bxor 1
[IO.File]::WriteAllBytes($signaturePath,$signature)
$plan=Get-Content -LiteralPath $testRequest -Raw | ConvertFrom-Json
($plan.assets | Where-Object name -EQ 'update.sig').sha256=(Get-FileHash -LiteralPath $signaturePath).Hash.ToLowerInvariant()
$plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $testRequest -Encoding UTF8
Assert-Rejected 'Invalid RSA release signature'
Copy-Item -LiteralPath (Join-Path (Split-Path $source) 'assets/update.sig') -Destination $signaturePath -Force
[IO.File]::WriteAllBytes($testRequest,$original)
foreach($badName in @('PoeBG/Role/account.ini','PoeBG/../escape','PoeBG/PoeBG.exe')){
    [IO.File]::WriteAllBytes($bootstrapPath,$zipOriginal)
    $zip=[IO.Compression.ZipFile]::Open($bootstrapPath,[IO.Compression.ZipArchiveMode]::Update)
    try{$entry=$zip.CreateEntry($badName); $writer=New-Object IO.StreamWriter($entry.Open()); try{$writer.Write('fixture')}finally{$writer.Dispose()}}finally{$zip.Dispose()}
    Update-ZipDigest
    $reason=switch($badName){'PoeBG/Role/account.ini'{'Unsigned archive member'} 'PoeBG/../escape'{'Unsafe archive path'} default{'Duplicate archive entry'}}
    Assert-Rejected $reason
}
Write-Output 'PASS: 6 release validation checks; no release API was called'
Write-Output ('Test fixtures retained at '+$sandbox)
