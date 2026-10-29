<#
.SYNOPSIS
Cấu hình mạng WSL2 trong %USERPROFILE%\.wslconfig: dùng chung card mạng với Windows (mirrored) và DNS tunneling.

.DESCRIPTION
Chạy trên Windows (không phải trong WSL). Kiểm tra từng mục, thiếu mới làm:
  1. Windows 11 22H2 trở lên (build >= 22621), yêu cầu của mirrored mode.
  2. [wsl2] networkingMode=mirrored : WSL dùng chung card mạng và localhost với Windows.
  3. [wsl2] dnsTunneling=true       : WSL lấy DNS từ Windows (theo VPN/DNS nội bộ), nameserver 10.255.255.254.
Chỉ thêm/sửa đúng các dòng trên, giữ nguyên các dòng khác. Chạy lại nhiều lần an toàn (idempotent).
Không tự tắt WSL: sau khi sửa phải chạy 'wsl --shutdown' mới có hiệu lực.

.PARAMETER Check
Chỉ kiểm tra, không thay đổi gì (exit 1 nếu chưa đúng).

.EXAMPLE
powershell -File configure-wsl-networking.ps1
powershell -File configure-wsl-networking.ps1 -Check
#>
[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'

$MinBuild = 22621   # Windows 11 22H2
$ConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
$Section = 'wsl2'
$Settings = [ordered]@{
    networkingMode = 'mirrored'
    dnsTunneling   = 'true'
}

$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
if ($build -lt $MinBuild) {
    Write-Error "Mirrored mode cần Windows 11 22H2 trở lên (build >= $MinBuild, phát hiện: $build)."
    exit 1
}
Write-Host "[OK]   Windows build $build"

$lines = New-Object 'System.Collections.Generic.List[string]'
if (Test-Path $ConfigPath) {
    foreach ($l in (Get-Content -Encoding UTF8 $ConfigPath)) { $lines.Add($l) }
}

# Trả về vị trí [wsl2] và khoảng dòng của nó (đến section kế tiếp hoặc hết file); tính lại sau mỗi lần chèn dòng.
function Find-Section {
    $start = -1
    $end = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[(.+?)\]\s*$') {
            if ($start -ge 0) { $end = $i; break }
            if ($matches[1] -eq $Section) { $start = $i }
        }
    }
    return @{ Start = $start; End = $end }
}

# Trả về @{ Index; Value } của key trong [wsl2]; Index = -1 nếu chưa có.
function Find-Key([string]$Key) {
    $sec = Find-Section
    if ($sec.Start -ge 0) {
        for ($i = $sec.Start + 1; $i -lt $sec.End; $i++) {
            if ($lines[$i] -match "^\s*$Key\s*=\s*(.*?)\s*$") {
                return @{ Index = $i; Value = $matches[1] }
            }
        }
    }
    return @{ Index = -1; Value = '' }
}

$missing = $false
$changed = $false
foreach ($key in $Settings.Keys) {
    $want = $Settings[$key]
    $found = Find-Key $key
    if ($found.Value -eq $want) {
        Write-Host "[OK]   $key=$want"
        continue
    }
    if ($Check) {
        Write-Host "[THIẾU] $key=$want chưa có trong $ConfigPath (hiện tại: '$($found.Value)')"
        $missing = $true
        continue
    }

    Write-Host ">> Ghi $key=$want vào $ConfigPath..."
    if ($found.Index -ge 0) {
        $lines[$found.Index] = "$key=$want"
    } else {
        $sec = Find-Section
        if ($sec.Start -ge 0) {
            $lines.Insert($sec.Start + 1, "$key=$want")
        } else {
            if ($lines.Count -gt 0) { $lines.Add('') }
            $lines.Add("[$Section]")
            $lines.Add("$key=$want")
        }
    }
    $changed = $true
}

if ($changed) {
    [System.IO.File]::WriteAllLines($ConfigPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ">> Cần khởi động lại WSL: chạy 'wsl --shutdown', rồi mở lại distro."
    Write-Host "   Kiểm tra: wsl -d Ubuntu -- wslinfo --networking-mode ; wsl -d Ubuntu -- cat /etc/resolv.conf"
}
if ($missing) { exit 1 }
