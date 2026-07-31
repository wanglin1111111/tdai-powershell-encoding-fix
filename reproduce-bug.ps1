# reproduce-bug.ps1
# 问题复现脚本：PowerShell 5.1 Invoke-RestMethod 中文编码丢失
# 运行前需先启动 TDAI Gateway (npx tsx src/gateway/server.ts)
# 预期结果：存储的 JSONL 中中文变成 ????

$BASE = "http://127.0.0.1:8420"
$SESSION = "bug-repro-session"

$conversations = @(
    @{ user = "我叫张明，是一名全栈开发工程师"; assistant = "你好张明！" },
    @{ user = "我正在做一个叫 Magic Resume 的项目"; assistant = "听起来不错！" },
    @{ user = "我的 GitHub 用户名是 zhangming-dev"; assistant = "已记下。" },
    @{ user = "我住在中国武汉，喜欢去东湖绿道骑行"; assistant = "武汉是个好地方！" },
    @{ user = "我们团队在研究 AI Agent 记忆系统"; assistant = "很前沿的方向！" }
)

$headers = @{ "Content-Type" = "application/json" }

for ($i = 0; $i -lt $conversations.Count; $i++) {
    $body = @{
        session_key = $SESSION
        user_content = $conversations[$i].user
        assistant_content = $conversations[$i].assistant
    } | ConvertTo-Json -Depth 3

    $resp = Invoke-RestMethod -Uri "$BASE/capture" -Method Post -Headers $headers -Body $body
    Write-Host "Round $($i+1): l0_recorded=$($resp.l0_recorded)"
    Start-Sleep -Milliseconds 500
}

Write-Host "`n=== 检查存储结果 ==="
Write-Host "数据目录: $env:USERPROFILE\.memory-tencentdb\memory-tdai\conversations\"
Write-Host "打开最新的 .jsonl 文件，检查 content 字段是否为乱码（????）"
Write-Host "`n=== 搜索验证 ==="
$searchBody = @{ query = "全栈开发"; limit = 3 } | ConvertTo-Json
$searchResp = Invoke-RestMethod -Uri "$BASE/search/conversations" -Method Post -Headers $headers -Body $searchBody
Write-Host "搜索结果 total: $($searchResp.total)"
Write-Host "（如果结果中中文显示为 ????，则确认编码问题已复现）"
