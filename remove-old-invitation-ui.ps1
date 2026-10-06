$ErrorActionPreference = "Stop"

$projectRoot = "C:\Users\engch\facility-works-monitor"
$file = Join-Path $projectRoot "components\user-management.tsx"
$backup = "$file.before-enterprise-user-management"

if (-not (Test-Path $file)) {
  throw "Cannot find $file"
}

Copy-Item $file $backup -Force

$content = Get-Content $file -Raw

# Remove the old invitation form type and initial state.
$content = [regex]::Replace(
  $content,
  '(?s)type InviteForm = \{.*?\};\s*const EMPTY_INVITE: InviteForm = \{.*?\};\s*',
  ''
)

# Remove the old invitation form React state.
$content = $content.Replace(
  '  const [invite, setInvite] = useState<InviteForm>(EMPTY_INVITE);' + [Environment]::NewLine,
  ''
)
$content = $content.Replace(
  '  const [invite, setInvite] = useState<InviteForm>(EMPTY_INVITE);' + "`n",
  ''
)

# Remove the old invitation submission function.
$content = [regex]::Replace(
  $content,
  '(?s)\s{2}async function inviteUser\(event: React\.FormEvent<HTMLFormElement>\) \{.*?\n\s{2}\}\n\n(?=\s{2}function updateDraft)',
  "`r`n"
)

# Remove the old "Add or invite user" panel.
$content = [regex]::Replace(
  $content,
  '(?s)\s{6}<section className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">.*?</section>\s*(?=\{\(message \|\| error\))',
  "`r`n      "
)

# Replace invitation terminology with the actual authentication state.
$content = $content.Replace(
  'Invitation pending',
  'Pending activation'
)

Set-Content -Path $file -Value $content -Encoding utf8

Write-Host ""
Write-Host "Updated: $file"
Write-Host "Backup:  $backup"
Write-Host ""
Write-Host "Checking that old invitation workflow was removed..."

$remaining = Select-String `
  -Path $file `
  -Pattern 'InviteForm|EMPTY_INVITE|inviteUser|Add or invite user|Send secure invitation|Sending invitation'

if ($remaining) {
  Write-Warning "Old invitation references remain:"
  $remaining | ForEach-Object { Write-Host $_.Line }
  Write-Host ""
  Write-Host "Restore with:"
  Write-Host "Copy-Item `"$backup`" `"$file`" -Force"
  exit 1
}

Write-Host "Old invitation panel removed successfully."
Write-Host "The existing user table and administrative actions were preserved."
