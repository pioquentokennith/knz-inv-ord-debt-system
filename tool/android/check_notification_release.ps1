param(
    [Parameter(Mandatory = $true)][string]$Serial,
    [Parameter(Mandatory = $true)][string]$JavaHome,
    [string]$Sdk = "$env:LOCALAPPDATA\Android\sdk",
    [string]$Apk = 'build/app/outputs/flutter-apk/app-release.apk'
)
$ErrorActionPreference = 'Stop'
$apkPath = (Resolve-Path $Apk).Path
$buildTools = Get-ChildItem (Join-Path $Sdk 'build-tools') -Directory |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
$platform = Get-ChildItem (Join-Path $Sdk 'platforms') -Directory |
    Where-Object { $_.Name -match '^android-\d+$' } |
    Sort-Object { [int]($_.Name -replace 'android-', '') } -Descending | Select-Object -First 1
if (-not $buildTools -or -not $platform) { throw 'Android SDK tools/platform missing.' }
$adb = Join-Path $Sdk 'platform-tools/adb.exe'
$javac = Join-Path $JavaHome 'bin/javac.exe'
$jar = Join-Path $platform.FullName 'android.jar'
$d8 = Join-Path $buildTools.FullName 'd8.bat'
$id = [Guid]::NewGuid().ToString('N')
$work = Join-Path "$env:LOCALAPPDATA\Temp\opencode" "notification-release-$id"
$remote = "/data/local/tmp/knz-notification-probe-$id"
New-Item -ItemType Directory -Path "$work/classes", "$work/dex" -Force | Out-Null
$previousJavaHome = $env:JAVA_HOME
try {
    $env:JAVA_HOME = $JavaHome
    & $javac -cp $jar -d "$work/classes" (Join-Path $PSScriptRoot 'NotificationReleaseProbe.java')
    if ($LASTEXITCODE -ne 0) { throw 'Probe compilation failed.' }
    $classes = Get-ChildItem "$work/classes/*.class" | ForEach-Object FullName
    & $d8 --lib $jar --min-api 24 --output "$work/dex" $classes
    if ($LASTEXITCODE -ne 0) { throw 'Probe DEX compilation failed.' }
    & $adb -s $Serial shell mkdir -p $remote
    if ($LASTEXITCODE -ne 0) { throw 'Device unavailable.' }
    & $adb -s $Serial push "$work/dex/classes.dex" "$remote/probe.dex"
    if ($LASTEXITCODE -ne 0) { throw 'Probe transfer failed.' }
    & $adb -s $Serial push $apkPath "$remote/app.apk"
    if ($LASTEXITCODE -ne 0) { throw 'APK transfer failed.' }
    $output = & $adb -s $Serial shell "CLASSPATH=$remote/probe.dex`:$remote/app.apk app_process /system/bin NotificationReleaseProbe 2>&1"
    $result = $LASTEXITCODE
    $output | Tee-Object "$work/result.log" | Write-Output
    Get-FileHash $apkPath -Algorithm SHA256 | Format-List | Out-String | Set-Content "$work/artifact.txt"
    Write-Output "Evidence: $work"
    if ($result -ne 0 -or @($output | Where-Object { "$_" -match '^PASS:' }).Count -ne 4) {
        throw 'Release notification regression FAILED. See result.log.'
    }
} finally {
    & $adb -s $Serial shell rm -rf $remote
    $env:JAVA_HOME = $previousJavaHome
}
