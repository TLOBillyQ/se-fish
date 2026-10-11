# 串行复验公开质量入口；全量 mutation 仅作用显式选定的代表文件。
param(
    [Parameter(Mandatory = $true)]
    [string]$File
)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$entry = Join-Path $PSScriptRoot 'project.ps1'
$source = Join-Path $root $File
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "找不到代表文件：$File"
}
$before = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
function Invoke-Quality([string[]]$Arguments, [int[]]$Allowed = @(0)) {
    & pwsh -NoProfile -File $entry @Arguments
    $code = $LASTEXITCODE
    if ($code -notin $Allowed) {
        throw "质量阶段失败（退出码 $code）：$($Arguments -join ' ')"
    }
}
Invoke-Quality @('doctor')
Invoke-Quality @('quality')
Invoke-Quality @('mutation', $File, '--max-workers', '12') @(0, 3)
Invoke-Quality @('mutation', $File, '--max-workers', '12') @(0, 3)
Invoke-Quality @('mutation', '--mutate-all', $File, '--max-workers', '12') @(0, 3)
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $before) {
    throw 'mutation 运行后原业务源码发生变化。'
}
$python = Join-Path $root '.uml-viewer/crapper/.venv/Scripts/python.exe'
& $python -B -m unittest discover -s (Join-Path $root 'tests/tooling/slow') -p '*_test.py'
if ($LASTEXITCODE -ne 0) { throw '公开质量入口失败路径测试未通过。' }
& pwsh -NoProfile -File (Join-Path $root 'uml.ps1') ir
if ($LASTEXITCODE -ne 0) { throw 'IR 生成失败。' }
Write-Output '命令验证完成；核对第二次差分的复用记录。GUI 展示、右键刷新、邮件队列和协议重启需按 README 的真实窗口步骤另行验收。'
