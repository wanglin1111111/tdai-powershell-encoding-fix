# Send-Utf8Request.Tests.ps1
# PowerShell Pester 测试：覆盖 Send-Utf8RestMethod 的 UTF-8 往返，验证 PS5.1/7+ 两条路径。
#
# 依赖：先启动 mock-gateway（node validation/mock-gateway.mjs 8420），它提供 /__echo 回显端点。
#   本仓库 CI 会自动起 gateway；本地手动跑：
#     Start-Job { node validation/mock-gateway.mjs 8420 } ; Start-Sleep 2
#     Invoke-Pester tests/Send-Utf8Request.Tests.ps1
#
# 兼容性（关键）：
#   - Windows PowerShell 5.1 + Pester 3.x（本机默认，用 legacy 'Should Be'/'Should Match'）
#   - PowerShell 7 + Pester 5（CI windows-latest，用 'Should -Be'/'Should -Match'）
#   Pester 5 在独立 runspace 里执行 It 块，文件顶层的 function/变量默认不可见。
#   因此本文件所有辅助函数、标志、语料都显式用 `script:` 作用域定义并引用，使两个版本都可见。
#
# 注意：本文件必须以 UTF-8 with BOM 保存——否则 Windows PowerShell 5.1 会用系统编码（GBK）
# 读取脚本，中文直接变成乱码导致解析失败。这本身就是本技能要解决的问题之一。

#Requires -Version 3.0
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 定位技能根目录（测试文件在 tests/ 下，技能根在其上一级）
$script:SkillRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:SkillRoot "scripts\Send-Utf8Request.ps1")

$script:BaseUrl = "http://127.0.0.1:8420"
$script:EchoUri = "$script:BaseUrl/__echo"

# ---- Pester 版本自适应 ----
# Pester 3.x 只认 legacy 语法（'Should Be'），Pester 5 只认新语法（'Should -Be'）且 runspace 隔离。
$script:Pester5 = $false
try {
    $pv = (Get-Module Pester -ListAvailable | Select-Object -First 1).Version
    if ($pv -and $pv.Major -ge 5) { $script:Pester5 = $true }
} catch { }

# 断言封装：用 script: 作用域，保证 Pester 5 的 It 块内可见。
function script:Expect-Equal($actual, $expected) {
    if ($script:Pester5) { $actual | Should -Be $expected }
    else { $actual | Should Be $expected }
}
function script:Expect-Match($actual, $pattern) {
    if ($script:Pester5) { $actual | Should -Match $pattern }
    else { $actual | Should Match $pattern }
}

# 健康检查：若 gateway 未启动，给出清晰提示而非一堆连接错误
function script:Test-GatewayReady {
    try {
        $null = Invoke-RestMethod -Uri $script:EchoUri -Method Post -ContentType "application/json" -Body '{"text":"ping"}' -TimeoutSec 3
        return $true
    } catch {
        return $false
    }
}

# 分级语料（与 corpus.json 同源，这里独立维护以保证 PS 侧自有验证）
$script:Cases = @(
    @{ Text = "Hello, ASCII baseline.";                    Id = "ascii" }
    @{ Text = "我叫张明，全栈工程师，技术栈 TypeScript + React。"; Id = "zh" }
    @{ Text = "Привет, Дмитрий, работаю с React и Node.js."; Id = "cyrillic" }
    @{ Text = "部署完成 🚀 全绿 ✅ 性能 +20% 🎉";            Id = "emoji" }
    @{ Text = "café résumé naïve — 带变音符的拉丁扩展";      Id = "latin-ext" }
)

Describe "Send-Utf8RestMethod 端到端 UTF-8 往返" -Tag "E2E" {

    foreach ($c in $script:Cases) {
        $label = $c.Text.Substring(0, [Math]::Min(20, $c.Text.Length))
        It "往返无损: [$($c.Id)] $label..." {
            if (-not (script:Test-GatewayReady)) {
                # Pester 5 无 Set-TestInconclusive；用版本自适应方式标记跳过
                if ($script:Pester5) { Set-ItResult -Skipped -Because "mock-gateway 不可达" }
                else { Set-TestInconclusive "mock-gateway 不可达，跳过（请先: node validation/mock-gateway.mjs 8420）" }
            }
            $resp = Send-Utf8RestMethod -Uri $script:EchoUri -Body @{ text = $c.Text }
            script:Expect-Equal $resp.text $c.Text
        }
    }

    It "mock-gateway 可达（健康检查）" {
        # 布尔断言不经过函数包装（经包装的布尔比较在两个版本都易出问题），直接按版本用原生语法
        $ready = script:Test-GatewayReady
        if ($script:Pester5) { $ready | Should -BeTrue } else { $ready | Should Be $true }
    }

    It "原文非-ASCII 处不得出现 '?' 替换" {
        if (-not (script:Test-GatewayReady)) {
            if ($script:Pester5) { Set-ItResult -Skipped -Because "mock-gateway 不可达" }
            else { Set-TestInconclusive "mock-gateway 不可达，跳过" }
        }
        $resp = Send-Utf8RestMethod -Uri $script:EchoUri -Body @{ text = "你好世界 PowerShell" }
        $qcount = @($resp.text.ToCharArray() | Where-Object { $_ -eq '?' }).Count
        script:Expect-Equal $qcount 0
    }
}

Describe "Content-Type 头强制 UTF-8" -Tag "Unit" {
    It "Send-Utf8RestMethod 内部使用 charset=utf-8" {
        $src = Get-Content (Join-Path $script:SkillRoot "scripts\Send-Utf8Request.ps1") -Raw -Encoding UTF8
        script:Expect-Match $src "charset=utf-8"
    }
}

Describe "PS 版本路径分流" -Tag "Unit" {
    It "在 PS5.1 上走字节数组路径（[System.Text.Encoding]::UTF8.GetBytes）" {
        $src = Get-Content (Join-Path $script:SkillRoot "scripts\Send-Utf8Request.ps1") -Raw -Encoding UTF8
        script:Expect-Match $src "\[System\.Text\.Encoding\]::UTF8\.GetBytes"
    }
    It "在 PS7+ 上走原生路径（PSVersion.Major -ge 7 分支）" {
        $src = Get-Content (Join-Path $script:SkillRoot "scripts\Send-Utf8Request.ps1") -Raw -Encoding UTF8
        script:Expect-Match $src "PSVersion\.Major -ge 7"
    }
}
