# 固定本地工具来源；安装器生成根入口，包安装单独验证。
param([string]$Python, [string]$Root, [switch]$InstallOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$root = if ($Root) { (Resolve-Path -LiteralPath $Root).Path } else { $projectRoot }
$config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'project.json') -Raw | ConvertFrom-Json
Push-Location -LiteralPath $root
try {
    foreach ($name in @('viewer', 'crapper', 'mutator')) {
        $tool = $config.tools.$name
        $source = (Resolve-Path -LiteralPath (Join-Path $projectRoot $tool.source)).Path
        & git -C $source cat-file -e "$($tool.commit)^{commit}"
        if ($LASTEXITCODE -ne 0) { throw "$name 本地来源缺少固定提交 $($tool.commit)" }
        $directory = Join-Path $root ".uml-viewer/$($tool.directory)"
        if (Test-Path -LiteralPath "$directory/.git") {
            # 未提交差异只允许来自已登记的 tracked 补丁；其余内容不得被覆盖。
            $allowed = @()
            foreach ($patch in @($tool.patches | Where-Object { $_ })) {
                $text = Get-Content -LiteralPath (Join-Path $projectRoot $patch) -Raw
                $allowed += [regex]::Matches($text, '(?m)^\+\+\+ b/(.+)$') | ForEach-Object { $_.Groups[1].Value.TrimEnd("`r") }
            }
            $dirty = @(& git -C $directory status --porcelain)
            $unexpected = $dirty | Where-Object { $path = $_.Substring(3).Trim(); -not ($allowed | Where-Object { $path -eq $_ }) }
            if ($unexpected) { throw "$name 有未登记差异，停止更新：$($unexpected -join '; ')" }
        }
        $prefix = if ($name -eq 'viewer') { 'UML_VIEWER' } else { $name.ToUpperInvariant() }
        [Environment]::SetEnvironmentVariable("${prefix}_REPO_URL", $source, 'Process')
        [Environment]::SetEnvironmentVariable("${prefix}_REF", $tool.commit, 'Process')
    }
    # 从固定提交提取安装器；接入修复在本入口留档，不依赖兄弟工作树差异。
    $viewerSource = Join-Path $projectRoot $config.tools.viewer.source
    $installerSource = (& git -C $viewerSource show "$($config.tools.viewer.commit):scripts/get-uml-viewer.ps1") -join "`n"
    if ($LASTEXITCODE -ne 0) { throw '无法读取固定基准安装器' }
    $fetchLine = 'fetch --depth 1 origin $Ref'
    $cloneLine = '& git clone --depth 1 --branch $Ref $Url $Directory'
    if (-not $installerSource.Contains($fetchLine) -or -not $installerSource.Contains($cloneLine)) {
        throw '固定基准安装器已变化；请改用 tools/quality/patches/ 的补丁流程'
    }
    $installerSource = $installerSource.Replace($fetchLine, 'fetch --depth 1 $Url $Ref')
    $installerSource = $installerSource.Replace($cloneLine, @'
& git clone --no-checkout $Url $Directory
        if ($LASTEXITCODE -ne 0) { throw "git clone failed: $Directory" }
        & git -C $Directory fetch --depth 1 $Url $Ref
        if ($LASTEXITCODE -ne 0) { throw "git fetch failed: $Directory" }
        & git -C $Directory checkout -q FETCH_HEAD
'@)
    $installer = Join-Path ([IO.Path]::GetTempPath()) ("se-fish-installer-" + [guid]::NewGuid().ToString('N') + '.ps1')
    [IO.File]::WriteAllText($installer, $installerSource)
    try {
        & $installer --install-only
        if ($LASTEXITCODE -ne 0) { throw 'uml-viewer 安装器失败' }
    } finally { Remove-Item -LiteralPath $installer -Force -Confirm:$false }
    # 固定 checkout 后应用 tracked 项目补丁；重复安装跳过已应用的补丁。
    foreach ($name in @('viewer', 'crapper', 'mutator')) {
        $tool = $config.tools.$name
        $directory = Join-Path $root ".uml-viewer/$($tool.directory)"
        foreach ($patch in @($tool.patches | Where-Object { $_ })) {
            $patchPath = Join-Path $projectRoot $patch
            & git -C $directory apply --reverse --check $patchPath 2>$null
            if ($LASTEXITCODE -eq 0) { continue }
            & git -C $directory apply --check $patchPath
            if ($LASTEXITCODE -ne 0) { throw "$name 补丁无法应用：$patch" }
            & git -C $directory apply $patchPath
            if ($LASTEXITCODE -ne 0) { throw "$name 补丁应用失败：$patch" }
        }
        # 精确复核：checkout 现有 diff 必须与登记补丁内容完全一致，不接受任意 dirty。
        $expected = (@($tool.patches | Where-Object { $_ } | ForEach-Object {
            ((Get-Content -LiteralPath (Join-Path $projectRoot $_) -Raw) -replace "`r`n", "`n").TrimEnd()
        }) -join "`n").Trim()
        $actual = ((& git -C $directory diff) -join "`n").Trim()
        # Git 空白上下文行可写为空行；比较前仅归一化该补丁格式差异。
        $expected = $expected -replace '(?m)^ $', ''
        $actual = $actual -replace '(?m)^ $', ''
        if ($actual -cne $expected) {
            throw "$name 未提交差异与登记补丁不一致；请重新生成补丁（git -C .uml-viewer/$($tool.directory) diff > <patch>）"
        }
    }
    if ($InstallOnly) { exit 0 }
    foreach ($name in @('crapper', 'mutator')) {
        $directory = Join-Path $root ".uml-viewer/$name"
        $interpreter = Join-Path $directory '.venv/Scripts/python.exe'
        if (-not (Test-Path -LiteralPath $interpreter)) {
            $bootstrap = if ($Python) { $Python } elseif (Test-Path '.uml-viewer/crapper/.venv/Scripts/python.exe') {
                (Resolve-Path '.uml-viewer/crapper/.venv/Scripts/python.exe').Path
            } else { (Get-Command python -ErrorAction Stop).Source }
            & $bootstrap -m venv "$directory/.venv"
            if ($LASTEXITCODE -ne 0) { throw "$name 创建 venv 失败" }
        }
        & $interpreter -m pip install -e $directory
        if ($LASTEXITCODE -ne 0) { throw "$name Python 包安装失败" }
        & $interpreter -m pip check
        if ($LASTEXITCODE -ne 0) { throw "$name 依赖检查失败" }
    }
    if (-not (Test-Path -LiteralPath '.toolcache/luacov/.git')) {
        & git clone https://github.com/lunarmodules/luacov.git .toolcache/luacov
        if ($LASTEXITCODE -ne 0) { throw 'LuaCov 克隆失败' }
        & git -C .toolcache/luacov checkout --detach b1f9eae400da976b93edb7f94cf5d05f538a0655
        if ($LASTEXITCODE -ne 0) { throw 'LuaCov 固定版本失败' }
    }
    $actual = & git -C .toolcache/luacov rev-parse HEAD
    if ($actual -ne 'b1f9eae400da976b93edb7f94cf5d05f538a0655') { throw "LuaCov 缓存提交不符：$actual" }
    & (Join-Path $PSScriptRoot 'project.ps1') doctor
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine("quality install: $_")
    exit 1
} finally { Pop-Location }
