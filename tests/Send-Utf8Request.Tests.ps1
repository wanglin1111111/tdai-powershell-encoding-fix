# Send-Utf8Request.Tests.ps1
# PowerShell Pester 测试：覆盖 Send-Utf8RestMethod 的 UTF-8 往返，验证 PS5.1/7+ 两条路径。
#
# 依赖：先启动 mock-gateway（node validation/mock-gateway.mjs 8420），它提供 /__echo 回显端点。
#   本仓库 CI 会自动起 gateway；本地手动跑：
#     Start-Job { node validation/mock-gateway.mjs 8420 } ; Start-Sleep 2
#     Invoke-Pester tests/Send-Utf8Request.Tests.ps1
#
# 兼容性（关键，踩坑总结）：
#   - Windows PowerShell 5.1 + Pester 3.x（本机默认，legacy 'Should Be'）
#   - PowerShell 7 + Pester 5（CI windows-latest，'Should -Be'，It 块在独立 runspace）
#   Pester 5 的 It runspace 完全隔离：文件顶层、script: 作用域、甚至顶层 dot-source 进来的
#   函数，在 It 块内都不可见（CI 反复验证：均报 CommandNotFoundException）。
#   唯一可靠的方式：在 **BeforeAll 块内** dot-source 辅助文件——BeforeAll 的内容会在该 Describe
#   的 runspace 作用域里执行，定义的函数对同 Describe 的 It 块可见（Pester 5 官方模式，
#   Pester 3.x 同样支持 BeforeAll）。
#
# 注意：本文件与 test-helpers.ps1 都必须以 UTF-8 with BOM 保存——否则 Windows PowerShell 5.1
# 会用系统编码（GBK）读取脚本，中文变乱码导致解析失败。

#Requires -Version 3.0
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$HelpersPath = Join-Path $PSScriptRoot "test-helpers.ps1"

# 仅取 $Cases 用于 discovery 阶段的 foreach（Pester 5 顶层变量在 Describe discovery 可见）
. $HelpersPath
$DiscoveryCases = $Cases

Describe "Send-Utf8RestMethod 端到端 UTF-8 往返" -Tag "E2E" {
    # 在 BeforeAll 内 dot-source：函数进入本 Describe 的 runspace 作用域，It 块可见
    BeforeAll {
        . $HelpersPath
    }

    foreach ($c in $DiscoveryCases) {
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
    BeforeAll { . $HelpersPath }
    It "Send-Utf8RestMethod 内部使用 charset=utf-8" {
        $src = Get-Content (Join-Path $SkillRoot "scripts\Send-Utf8Request.ps1") -Raw -Encoding UTF8
        Expect-Match $src "charset=utf-8"
    }
}

Describe "PS 版本路径分流" -Tag "Unit" {
    BeforeAll { . $HelpersPath }
    It "在 PS5.1 上走字节数组路径（[System.Text.Encoding]::UTF8.GetBytes）" {
        $src = Get-Content (Join-Path $SkillRoot "scripts\Send-Utf8Request.ps1") -Raw -Encoding UTF8
        Expect-Match $src "\[System\.Text\.Encoding\]::UTF8\.GetBytes"
    }
    It "在 PS7+ 上走原生路径（PSVersion.Major -ge 7 分支）" {
        $src = Get-Content (Join-Path $SkillRoot "scripts\Send-Utf8Request.ps1") -Raw -Encoding UTF8
        Expect-Match $src "PSVersion\.Major -ge 7"
    }
}
