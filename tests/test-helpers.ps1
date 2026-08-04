# test-helpers.ps1
# Pester 测试的共享辅助逻辑。被 Send-Utf8Request.Tests.ps1 dot-source。
#
# 为什么独立成文件并 dot-source：Pester 5 在独立 runspace 里执行 It 块，
# 测试文件顶层用 `function`/`$var`/甚至 `script:` 定义的内容在 It 块内都不可见
# （报 CommandNotFoundException / 变量为 null）。但 dot-source 进来的内容
# （如 Send-Utf8RestMethod）在 It 块内可用——这是 Pester 5 下唯一可靠的方式。
# Pester 3.x 同作用域，dot-source 同样有效，故双版本兼容。

# 技能根目录（helpers 在 tests/ 下，根在其上一级）
$SkillRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $SkillRoot "scripts\Send-Utf8Request.ps1")

$BaseUrl = "http://127.0.0.1:8420"
$EchoUri = "$BaseUrl/__echo"

# Pester 版本自适应：3.x 用 legacy 'Should Be'，5.x 用 'Should -Be'
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

function Test-GatewayReady {
    try {
        $null = Invoke-RestMethod -Uri $EchoUri -Method Post -ContentType "application/json" -Body '{"text":"ping"}' -TimeoutSec 3
        return $true
    } catch {
        return $false
    }
}

# 分级语料（与 corpus.json 同源）
$Cases = @(
    @{ Text = "Hello, ASCII baseline.";                    Id = "ascii" }
    @{ Text = "我叫张明，全栈工程师，技术栈 TypeScript + React。"; Id = "zh" }
    @{ Text = "Привет, Дмитрий, работаю с React и Node.js."; Id = "cyrillic" }
    @{ Text = "部署完成 🚀 全绿 ✅ 性能 +20% 🎉";            Id = "emoji" }
    @{ Text = "café résumé naïve — 带变音符的拉丁扩展";      Id = "latin-ext" }
)
