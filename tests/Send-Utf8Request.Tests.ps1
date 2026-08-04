# Send-Utf8Request.Tests.ps1
# PowerShell Pester 测试：覆盖 Send-Utf8RestMethod 的 UTF-8 往返，验证 PS5.1/7+ 两条路径。
#
# 依赖：先启动 mock-gateway（node validation/mock-gateway.mjs 8420），它提供 /__echo 回显端点。
#   本仓库 CI 会自动起 gateway；本地手动跑：
#     Start-Job { node validation/mock-gateway.mjs 8420 } ; Start-Sleep 2
#     Invoke-Pester tests/Send-Utf8Request.Tests.ps1
#
# 兼容性（关键）：
#   - Windows PowerShell 5.1 + Pester 3.x（本机默认，legacy 'Should Be'）
#   - PowerShell 7 + Pester 5（CI windows-latest，'Should -Be'，It 块在独立 runspace）
#   Pester 5 的 It runspace 完全隔离：测试文件顶层 / script: 作用域定义的函数与变量在 It 块内
#   都不可见（报 CommandNotFoundException）。唯一可靠的方式是把辅助逻辑放进独立 .ps1 文件并
#   dot-source（dot-source 进来的函数在 It 块内可用，如同 Send-Utf8RestMethod）。故本文件
#   dot-source tests/test-helpers.ps1。
#
# 注意：本文件与 test-helpers.ps1 都必须以 UTF-8 with BOM 保存——否则 Windows PowerShell 5.1
# 会用系统编码（GBK）读取脚本，中文变乱码导致解析失败。

#Requires -Version 3.0
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# dot-source 共享辅助逻辑（函数/变量/Pester 版本标志/语料）。Pester 5 的 It 块能访问这些函数。
. (Join-Path $PSScriptRoot "test-helpers.ps1")

Describe "Send-Utf8RestMethod 端到端 UTF-8 往返" -Tag "E2E" {

    # $Cases 在 discovery 阶段可见（Pester 5 顶层 dot-source 变量在 Describe 作用域可用）
    foreach ($c in $Cases) {
        $label = $c.Text.Substring(0, [Math]::Min(20, $c.Text.Length))
        It "往返无损: [$($c.Id)] $label..." {
            if (-not (Test-GatewayReady)) {
                if ($Pester5) { Set-ItResult -Skipped -Because "mock-gateway 不可达" }
                else { Set-TestInconclusive "mock-gateway 不可达（请先: node validation/mock-gateway.mjs 8420）" }
            }
            $resp = Send-Utf8RestMethod -Uri $EchoUri -Body @{ text = $c.Text }
            Expect-Equal $resp.text $c.Text
        }
    }

    It "mock-gateway 可达（健康检查）" {
        $ready = Test-GatewayReady
        if ($Pester5) { $ready | Should -BeTrue } else { $ready | Should Be $true }
    }

    It "原文非-ASCII 处不得出现 '?' 替换" {
        if (-not (Test-GatewayReady)) {
            if ($Pester5) { Set-ItResult -Skipped -Because "mock-gateway 不可达" }
            else { Set-TestInconclusive "mock-gateway 不可达，跳过" }
        }
        $resp = Send-Utf8RestMethod -Uri $EchoUri -Body @{ text = "你好世界 PowerShell" }
        $qcount = @($resp.text.ToCharArray() | Where-Object { $_ -eq '?' }).Count
        Expect-Equal $qcount 0
    }
}

Describe "Content-Type 头强制 UTF-8" -Tag "Unit" {
    It "Send-Utf8RestMethod 内部使用 charset=utf-8" {
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
