<#
.SYNOPSIS
    #102 第一项：重开核验（只读）。

.DESCRIPTION
    核验 03–07 区灰盒施工（提交 06c7538）是否随保存落盘：重开编辑器后重跑只读基线探针，
    把现场回读与施工后存档快照逐行对齐比对。

    本脚本**只读编辑器**：只跑 tests/probes/zone_baseline_inventory.lua（不改场景、不保存、不 deploy），
    再把日志转成 CSV 比对。编辑器停在 edit mode / idle 即可。

    判据：
      * 逐行对齐无差异 = 持久化 PASS。
      * 行数不同但去重后逐行对齐 = 日志里同一份载荷出现多遍（本次冒烟实测过：同一探针连跑两次会各产一份），
        需判断取哪一份；脚本会按重复次数给出提示。
      * 出现新增/缺失行 = 保存没完整落盘或保存后有人动过场景，此时
        evidence/issue65/zone-space-contract-post-p3.* 的实测数字作废，必须重算。

.EXAMPLE
    .\tools\verify-issue102-reopen.ps1
    .\tools\verify-issue102-reopen.ps1 -KeepArtifacts   # 保留中间产物，路径会打印出来
#>
[CmdletBinding()]
param(
    [string]$Baseline = 'evidence/issue65/zone-baseline-rows-post-p3.csv',
    [string]$Evidence = 'evidence/issue102/reopen-verification.txt',
    [switch]$KeepArtifacts
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$utf8 = New-Object System.Text.UTF8Encoding($false)

$editorCli = Join-Path $env:USERPROFILE '.eggitor\cli\editor-cli.exe'
if (-not (Test-Path $editorCli)) { throw "找不到 editor-cli：$editorCli" }
if (-not (Test-Path $Baseline)) { throw "找不到施工后快照：$Baseline" }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('issue102-reopen-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $work | Out-Null

function Step([string]$text) { Write-Host "== $text" }
$lines = New-Object System.Collections.Generic.List[string]
function Record([string]$text) { $lines.Add($text); Write-Host $text }

# 逐行对齐比对：返回 @{ OnlyBaseline; OnlyReopen; Duplicated; UniqueBaseline; UniqueReopen }
function Compare-Rows([string[]]$a, [string[]]$b) {
    $countA = @{}; $countB = @{}
    foreach ($line in $a) { $countA[$line] = 1 + ($countA[$line] -as [int]) }
    foreach ($line in $b) { $countB[$line] = 1 + ($countB[$line] -as [int]) }
    $onlyBaseline = New-Object System.Collections.Generic.List[string]
    $onlyReopen = New-Object System.Collections.Generic.List[string]
    $duplicated = New-Object System.Collections.Generic.List[string]
    foreach ($key in $countA.Keys) {
        $inB = if ($countB.ContainsKey($key)) { $countB[$key] } else { 0 }
        if ($inB -eq 0) { $onlyBaseline.Add($key) }
        elseif ($inB -ne $countA[$key]) { $duplicated.Add(("{0} 次（同一行：{1} 次）" -f $countA[$key], $inB)) }
    }
    foreach ($key in $countB.Keys) {
        if (-not $countA.ContainsKey($key)) { $onlyReopen.Add($key) }
    }
    return @{ OnlyBaseline = $onlyBaseline; OnlyReopen = $onlyReopen; Duplicated = $duplicated;
        UniqueBaseline = $countA.Count; UniqueReopen = $countB.Count }
}

$reopenCsv = $null
$baselineHash = (Get-FileHash $Baseline -Algorithm SHA256).Hash
Record "#102 重开核验（只读，$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))"
Record "快照基线：$Baseline"
Record "基线 SHA256：$baselineHash"
Record ''

try {
    Step '1/4 跑只读基线探针（不改场景）'
    $execOut = & $editorCli exec --file 'tests\probes\zone_baseline_inventory.lua' --expect-edit-mode --timeout 180 --json 2>&1
    $execCode = $LASTEXITCODE
    Record "exec 退出码：$execCode"
    Record ($execOut | Out-String).Trim()
    if ($execCode -ne 0) { throw "探针执行失败（退出码 $execCode）：先确认编辑器已打开本图并停在 edit mode" }
    $emitted = ([regex]::Match(($execOut | Out-String), 'zoneNodes=(\d+)')).Groups[1].Value
    Record "探针自报 zoneNodes：$emitted"

    Step '2/4 取回读日志'
    $logPath = Join-Path $work 'reopen-log.json'
    $logOut = & $editorCli log grep P2BASE65V2 --platform editor --context 0 --max-matches 1500 --json 2>&1
    if ($LASTEXITCODE -ne 0) { throw "日志读取失败（退出码 $LASTEXITCODE）" }
    $logText = ($logOut | Out-String)
    $start = $logText.IndexOf('{')
    if ($start -lt 0) { throw '日志输出里找不到 JSON' }
    [System.IO.File]::WriteAllText($logPath, $logText.Substring($start), $utf8)
    Record "命中 P2BASE65V2：$(([regex]::Matches($logText, 'P2BASE65V2')).Count) 处"

    Step '3/4 转 CSV'
    $reopenCsv = Join-Path $work 'zone-baseline-rows-reopen.csv'
    $convertLog = & lua tools/baseline_csv.lua --log $logPath --out $reopenCsv 2>&1
    Record ($convertLog | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "CSV 转换失败（退出码 $LASTEXITCODE）" }
    $reopenHash = (Get-FileHash $reopenCsv -Algorithm SHA256).Hash
    $baseRows = @(Get-Content $Baseline)
    $reopenRows = @(Get-Content $reopenCsv)
    Record "重开快照：$($reopenRows.Count) 行，SHA256 $reopenHash"
    Record "存档快照：$($baseRows.Count) 行，SHA256 $baselineHash"
    Record ('哈希直接比对：' + $(if ($reopenHash -eq $baselineHash) { '相同' } else { '不同' }))

    Step '4/4 逐行对齐比对'
    $result = Compare-Rows -a $baseRows -b $reopenRows
    Record "去重后：存档 $($result.UniqueBaseline) 行 / 重开 $($result.UniqueReopen) 行"
    Record "仅存档有：$($result.OnlyBaseline.Count) 行；仅重开有：$($result.OnlyReopen.Count) 行"

    if ($result.OnlyBaseline.Count -eq 0 -and $result.OnlyReopen.Count -eq 0) {
        if ($reopenHash -eq $baselineHash) {
            Record '结论：逐字节一致 —— 03–07 区施工重开持久化 PASS'
        } elseif ($result.Duplicated.Count -eq 0) {
            Record '结论：行内容一致但文件不同（行序或换行差异）—— 判 PASS，但需记录行序差异'
        } else {
            Record '结论：**行内容一致，但重开快照里有整份重复载荷** —— 判 PASS；'
            Record '      重复来自本次日志窗口收录了多份载荷（同一探针连跑两次就会这样），不是场景变化。'
            Record '      下次核验请先清日志窗口或按单份载荷转 CSV。'
        }
        $exitCode = 0
    } else {
        Record '结论：**有差异** —— 施工后实测数字作废，见下方差异行'
        foreach ($line in ($result.OnlyReopen | Select-Object -First 40)) { Record "  + $line" }
        if ($result.OnlyReopen.Count -gt 40) { Record "  ...（仅重开有共 $($result.OnlyReopen.Count) 行）" }
        foreach ($line in ($result.OnlyBaseline | Select-Object -First 40)) { Record "  - $line" }
        if ($result.OnlyBaseline.Count -gt 40) { Record "  ...（仅存档有共 $($result.OnlyBaseline.Count) 行）" }
        $exitCode = 1
    }
} catch {
    Record "错误：$($_.Exception.Message)"
    $exitCode = 2
} finally {
    $outPath = Join-Path $repo $Evidence
    New-Item -ItemType Directory -Force (Split-Path -Parent $outPath) | Out-Null
    [System.IO.File]::WriteAllText($outPath, ($lines -join "`n") + "`n", $utf8)
    Write-Host ''
    Write-Host "证据已写入：$Evidence"
    if ($KeepArtifacts) {
        Write-Host "中间产物：$work"
    } else {
        Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
    }
}

exit $exitCode
