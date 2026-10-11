# 公开质量命令入口；参数保持 argv，不经过 shell 拼接。
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$python = Join-Path $root '.uml-viewer/crapper/.venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    throw '缺少质量工具 Python 环境，请先运行 tools/quality/install.ps1。'
}
& $python -B (Join-Path $PSScriptRoot 'project.py') @args
exit $LASTEXITCODE
