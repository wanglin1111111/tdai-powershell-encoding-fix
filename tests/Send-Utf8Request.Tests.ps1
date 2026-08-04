# Send-Utf8Request.Tests.ps1
# PowerShell Pester 测试：覆盖 Send-Utf8RestMethod 的 UTF-8 往返，验证 PS5.1/7+ 两条路径。
#
# 依赖：先启动 mock-gateway（node validation/mock-gateway.mjs 8420），它提供 /__echo 回显端点。
#   本仓库 CI 会自动起 gateway；本地手动跑：
#     Start-Job { node validation/mock-gateway.mjs 8420 } ; Start-Sleep 2
#     Invoke-Pester tests/Send-Utf8Request.Tests.ps1
#
# 兼容性：本测试用版本自适应的 Should 语法（见下方 Expect-* 封装），同时兼容
#   - Windows PowerShell 5.1 + Pester 3.x（本机默认，用 legacy 'Should Be'/'Should Match'）
#   - PowerShell 7 + Pester 5（CI windows-latest，用 'Should -Be'/'Should -Match'）
#
# 注意：本机（开发环境）只有 Windows PowerShell 5.1，因此 PS7+ 路径仅在 CI（windows-latest，
# 自带 pwsh）上被实际验证。PS5.1 路径在本机与 CI 上都会被验证。
#
# 重要教训：本文件必须以 UTF-8 with BOM 保存——否则 Windows PowerShell 5.1 会用系统编码
# （GBK）读取脚本，中文直接变成乱码导致解析失败。这本身就是本技能要解决的问题之一。

#Requires -Version 3.0
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 定位技能根目录（测试文件在 tests/ 下，技能根在其上一级）
$SkillRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $SkillRoot "scripts\Send-Utf8Request.ps1")

$BaseUrl = "http://127.0.0.1:8420"
$EchoUri = "$BaseUrl/__echo"

# ---- Pester 版本自适应断言封装 ----
# Pester 3.x 只认 legacy 语法（'Should Be'），Pester 5 只认新语法（'Should -Be'）。
# 用一个标志分发，使同一份测试在两个版本下都能跑。
$Pester5 = $false
try {
    $pv = (Get-Module Pester -ListAvailable | Select-Object -First 1).Version
    if ($pv -and $pv.Major -ge 5) { $Pester5 = $true }
} catch { }

function Expect-Equal($actual, $expected) {
    if ($Pester5) { $actual | Should -Be $expected }
    else { $actual | Should Be $expected }
}
function Expect-Match($actual, $pattern) {
    if ($Pester5) { $actual | Should -Match $pattern }
    else { $actual | Should Match $pattern }
}

# 健康检查：若 gateway 未启动，给出清晰提示而非一堆连接错误
function Test-GatewayReady {
    try {
        $null = Invoke-RestMethod -Uri $EchoUri -Method Post -ContentType "application/json" -Body '{"text":"ping"}' -TimeoutSec 3
        return $true
    } catch {
        return $false
    }
}

# 分级语料（与 corpus.json 同源，这里独立维护以保证 PS 侧自有验证）
$Cases = @(
    @{ Text = "Hello, ASCII baseline.";                    Id = "ascii" }
    @{ Text = "我叫张明，全栈工程师，技术栈 TypeScript + React。"; Id = "zh" }
    @{ Text = "Привет, Дмитрий, работаю с React и Node.js."; Id = "cyrillic" }
    @{ Text = "部署完成 🚀 全绿 ✅ 性能 +20% 🎉";            Id = "emoji" }
    @{ Text = "café résumé naïve — 带变音符的拉丁扩展";      Id = "latin-ext" }
)

Describe "Send-Utf8RestMethod 端到端 UTF-8 往返" -Tag "E2E" {
    Context "gateway 就绪" {
        It "mock-gateway 可达" {
            # 布尔断言不经过 Expect-Equal 函数包装（Pester 3.x 下经函数包装的布尔比较会异常），
            # 直接按 Pester 版本用原生 IsTrue/Be 语法。
            $ready = Test-GatewayReady
            if ($Pester5) { $ready | Should -BeTrue } else { $ready | Should Be $true }
        }
    }

    foreach ($c in $Cases) {
        $label = $c.Text.Substring(0, [Math]::Min(20, $c.Text.Length))
        It "往返无损: [$($c.Id)] $label..." {
            if (-not (Test-GatewayReady)) {
                Set-TestInconclusive "mock-gateway 不可达，跳过（请先: node validation/mock-gateway.mjs 8420）"
            }
            $resp = Send-Utf8RestMethod -Uri $EchoUri -Body @{ text = $c.Text }
            Expect-Equal $resp.text $c.Text
        }
    }

    It "原文非-ASCII 处不得出现 '?' 替换" {
        if (-not (Test-GatewayReady)) {
            Set-TestInconclusive "mock-gateway 不可达，跳过"
        }
        $resp = Send-Utf8RestMethod -Uri $EchoUri -Body @{ text = "你好世界 PowerShell" }
        # 用 @() 强制为数组：Where-Object 无匹配时返回 $null，StrictMode 下 $null.Count 会报错
        $qcount = @($resp.text.ToCharArray() | Where-Object { $_ -eq '?' }).Count
        Expect-Equal $qcount 0
    }
}

Describe "Content-Type 头强制 UTF-8" -Tag "Unit" {
    It "Send-Utf8RestMethod 内部使用 charset=utf-8" {
        # 静态断言：函数源码必须包含 charset=utf-8，避免回归
        $src = Get-Content (Join-Path $SkillRoot "scripts\Send-Utf8Request.ps1") -Raw -Encoding UTF8
        Expect-Match $src "charset=utf-8"
    }
}

Describe "PS 版本路径分流" -Tag "Unit" {
    It "在 PS5.1 上走字节数组路径（[System.Text.Encoding]::UTF8.GetBytes）" {
        $src = Get-Content (Join-Path $SkillRoot "scripts\Send-Utf8Request.ps1") -Raw -Encoding UTF8
        Expect-Match $src "\[System\.Text\.Encoding\]::UTF8\.GetBytes"
    }
    It "在 PS7+ 上走原生路径（PSVersion.Major -ge 7 分支）" {
        $src = Get-Content (Join-Path $SkillRoot "scripts\Send-Utf8Request.ps1") -Raw -Encoding UTF8
        Expect-Match $src "PSVersion\.Major -ge 7"
    }
}
