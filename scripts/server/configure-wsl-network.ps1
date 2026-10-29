<#
.SYNOPSIS
Cấu hình WSL2 dùng chung card mạng với Windows (networkingMode=mirrored) trong %USERPROFILE%\.wslconfig.

.DESCRIPTION
Chạy trên Windows (không phải trong WSL). Kiểm tra từng mục, thiếu mới làm:
  1. Windows 11 22H2 trở lên (build >= 22621), yêu cầu của mirrored mode.
  2. .wslconfig có networkingMode=mirrored trong [wsl2]; chưa có thì thêm/sửa đúng một dòng đó, giữ nguyên các dòng khác.
Chạy lại nhiều lần an toàn (idempotent). Không tự tắt WSL: sau khi sửa phải chạy 'wsl --shutdown' mới có hiệu lực.

.PARAMETER Check
Chỉ kiểm tra, không thay đổi gì (exit 1 nếu chưa đúng).

.EXAMPLE
powershell -File configure-wsl-network.ps1
powershell -File configure-wsl-network.ps1 -Check
#>
[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'

$MinBuild = 22621   # Windows 11 22H2
$ConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
$Section = 'wsl2'
$Key = 'networkingMode'
$Value = 'mirrored'

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

# Tìm [wsl2] và khoảng dòng của nó (đến section kế tiếp hoặc hết file).
$sectionIdx = -1
$sectionEnd = $lines.Count
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*\[(.+?)\]\s*$') {
        if ($sectionIdx -ge 0) { $sectionEnd = $i; break }
        if ($matches[1] -eq $Section) { $sectionIdx = $i }
    }
}

$keyIdx = -1
$current = ''
if ($sectionIdx -ge 0) {
    for ($i = $sectionIdx + 1; $i -lt $sectionEnd; $i++) {
        if ($lines[$i] -match "^\s*$Key\s*=\s*(.*?)\s*$") {
            $keyIdx = $i
            $current = $matches[1]
            break
        }
    }
}

if ($current -eq $Value) {
    Write-Host "[OK]   $Key=$Value trong $ConfigPath"
    exit 0
}

if ($Check) {
    Write-Host "[THIẾU] $Key=$Value chưa có trong $ConfigPath (hiện tại: '$current')"
    exit 1
}

Write-Host ">> Ghi $Key=$Value vào $ConfigPath..."
if ($keyIdx -ge 0) {
    $lines[$keyIdx] = "$Key=$Value"
} elseif ($sectionIdx -ge 0) {
    $lines.Insert($sectionIdx + 1, "$Key=$Value")
} else {
    if ($lines.Count -gt 0) { $lines.Add('') }
    $lines.Add("[$Section]")
    $lines.Add("$Key=$Value")
}
[System.IO.File]::WriteAllLines($ConfigPath, $lines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ">> Cần khởi động lại WSL: chạy 'wsl --shutdown', rồi mở lại distro. Kiểm tra: wsl -d Ubuntu -- wslinfo --networking-mode"
