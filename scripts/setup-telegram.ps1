# Configure GitHub Actions secrets without saving credentials to a file.
# Requires GitHub CLI: https://cli.github.com/
# Open PowerShell: .\scripts\setup-telegram.ps1

[CmdletBinding()]
param(
    [string]$Repository = 'dungbeommm/remote-browser-24x7',
    [ValidateSet(10, 20)]
    [int]$PreviewMinutes = 10,
    [switch]$DoNotRun
)

$ErrorActionPreference = 'Stop'

function Get-PlainSecret {
    param([string]$Prompt)
    $secure = Read-Host -Prompt $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        $secure.Dispose()
    }
}

function Set-ActionsSecret {
    param(
        [string]$Name,
        [string]$Value
    )
    # Write the raw secret bytes to stdin WITHOUT a trailing CR/LF.
    # Piping a PowerShell string normally appends a newline, which can break
    # Telegram bot tokens and numeric Chat IDs saved as GitHub Secrets.
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = 'gh'
    $start.Arguments = 'secret set ' + $Name + ' --repo ' + $Repository + ' --app actions'
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $start
    try {
        if (-not $proc.Start()) { throw "Unable to start GitHub CLI." }
        $proc.StandardInput.Write($Value)
        $proc.StandardInput.Close()
        $stderr = $proc.StandardError.ReadToEnd()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        if ($proc.ExitCode -ne 0) {
            throw "GitHub CLI failed to save $Name. Check gh auth status and repo permissions."
        }
    }
    finally {
        $proc.Dispose()
    }
    Write-Host "Saved $Name." -ForegroundColor Green
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI is missing. Install it with: winget install --id GitHub.cli -e"
}

# gh writes normal diagnostics to stderr; avoid treating non-zero exit as a
# terminating PowerShell exception before the login fallback can run.
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    & gh auth status *> $null
    $authenticated = ($LASTEXITCODE -eq 0)
}
finally {
    $ErrorActionPreference = $previousPreference
}
if (-not $authenticated) {
    Write-Host 'Log into GitHub in the browser now.'
    & gh auth login --web
    if ($LASTEXITCODE -ne 0) { throw 'GitHub sign-in failed.' }
}

Write-Host ''
Write-Host 'Security: revoke any Telegram bot token you posted in a chat, and enter the NEW token.'
Write-Host 'Send /start (or a new message) to your bot from the Telegram account that should receive the link.'
Write-Host ''

$token = Get-PlainSecret 'NEW Telegram bot token'
if ($token -notmatch '^[0-9]+:[A-Za-z0-9_-]+$') {
    throw 'Bot token format is invalid. No secret has been saved.'
}

try {
    # Do not print the URL or raw error: it may contain the secret token.
    $me = Invoke-RestMethod -Method Get `
        -Uri ("https://api.telegram.org/bot" + $token + "/getMe") `
        -TimeoutSec 20 -ErrorAction Stop
    if (-not $me.ok) { throw 'Telegram rejected the bot token.' }
}
catch {
    throw 'Telegram token check failed. Revoke/recreate the token in BotFather and retry.'
}
Write-Host ('Bot verified: @' + $me.result.username)

$chatId = $null
try {
    $updates = Invoke-RestMethod -Method Get `
        -Uri ("https://api.telegram.org/bot" + $token + "/getUpdates") `
        -TimeoutSec 20 -ErrorAction Stop
    $chats = @(
        $updates.result |
            ForEach-Object {
                if ($null -ne $_.message) {
                    $_.message.chat
                }
                elseif ($null -ne $_.channel_post) {
                    $_.channel_post.chat
                }
            } |
            Where-Object { $null -ne $_ -and $null -ne $_.id } |
            Sort-Object -Property id -Unique
    )
    if ($chats.Count -eq 1) {
        $chatId = [string]$chats[0].id
        Write-Host "Found chat ID: $chatId"
    }
    elseif ($chats.Count -gt 1) {
        Write-Host 'Chats that recently messaged this bot:'
        foreach ($chat in $chats) {
            $label = if ($chat.title) { $chat.title } elseif ($chat.username) { $chat.username } else { $chat.first_name }
            Write-Host ("  {0}  {1}" -f $chat.id, $label)
        }
    }
}
catch {
    Write-Host 'Automatic Chat ID discovery unavailable (bot webhook may be configured).' -ForegroundColor Yellow
}

if ([string]::IsNullOrWhiteSpace($chatId)) {
    $chatId = Read-Host 'Enter Chat ID to receive messages (from list above, or from Telegram)'
}
if ($chatId -notmatch '^-?[0-9]+$') {
    throw 'Chat ID must be numeric. No secret has been saved.'
}

$password = Get-PlainSecret 'Browser preview password (12+ characters)'
if ($password.Length -lt 12) {
    throw 'Password must be at least 12 characters. No secret has been saved.'
}
if ($password.Contains("`n") -or $token.Contains("`n")) {
    throw 'Secrets must not contain newlines.'
}

try {
    Set-ActionsSecret -Name 'TELEGRAM_BOT_TOKEN' -Value $token
    Set-ActionsSecret -Name 'TELEGRAM_CHAT_ID' -Value $chatId
    Set-ActionsSecret -Name 'PREVIEW_WEB_PASSWORD' -Value $password
}
finally {
    $token = $null
    $password = $null
}

Write-Host ''
Write-Host 'Configured secret names:' -ForegroundColor Green
& gh secret list --repo $Repository
if ($LASTEXITCODE -ne 0) { throw 'Could not verify secret names.' }

if (-not $DoNotRun) {
    Write-Host ''
    Write-Host "Starting a $PreviewMinutes-minute temporary preview..."
    & gh workflow run preview.yml --repo $Repository --field ("duration_minutes=" + $PreviewMinutes)
    if ($LASTEXITCODE -ne 0) { throw 'Could not start preview workflow.' }
    Write-Host ''
    Write-Host ('Open https://github.com/' + $Repository + '/actions')
    Write-Host 'The Telegram link will arrive when Cloudflare tunnel is ready.'
}
else {
    Write-Host 'Secrets saved. Workflow not started because -DoNotRun was set.'
}
