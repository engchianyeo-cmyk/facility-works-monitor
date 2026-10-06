$ErrorActionPreference = 'Stop'

$projectRef = 'pvajuywwwpjlikqjnvgv'
$expectedEmail = 'sctpec2413@gmail.com'
$expectedUserId = '826e5c86-8734-4ae6-9e25-e72d8c7f23d5'
$resultPath = Join-Path $PSScriptRoot '.codex-wp-fmw-017-result.json'

function Write-SafeResult($Result) {
  $Result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding utf8
}

function Get-Profile([hashtable]$Headers, [string]$UserId) {
  $select = 'id,email,role,is_active,deleted_at,password_change_required,display_name,department_id,trade_discipline,contact_number'
  $uri = "https://$projectRef.supabase.co/rest/v1/profiles?id=eq.$UserId&select=$select"
  return @(Invoke-RestMethod -Method Get -Uri $uri -Headers ($Headers + @{ Accept = 'application/json' }) -TimeoutSec 30)
}

function Get-AuthUsers([hashtable]$Headers) {
  $uri = "https://$projectRef.supabase.co/auth/v1/admin/users?page=1&per_page=1000"
  return @((Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec 30).users)
}

function Canonical-Json($Value) {
  return ($Value | ConvertTo-Json -Depth 6 -Compress)
}

try {
  if (Test-Path -LiteralPath $resultPath) {
    Remove-Item -LiteralPath $resultPath -Force
  }

  $keyJson = npx.cmd supabase projects api-keys --project-ref $projectRef --output json 2>$null
  if ($LASTEXITCODE -ne 0) { throw 'Authorized Preview API metadata is unavailable.' }
  $keys = $keyJson | ConvertFrom-Json
  $serviceKey = ($keys | Where-Object { $_.name -eq 'service_role' -or $_.type -eq 'service_role' } | Select-Object -First 1).api_key
  if (-not $serviceKey) {
    $serviceKey = ($keys | Where-Object { $_.name -eq 'service_role' } | Select-Object -First 1).key
  }
  if (-not $serviceKey) { throw 'Authorized Preview service credential is unavailable.' }
  $headers = @{ apikey = $serviceKey; Authorization = "Bearer $serviceKey" }

  $authUsersBefore = Get-AuthUsers $headers
  $authMatches = @($authUsersBefore | Where-Object { $_.email -ceq $expectedEmail })
  if ($authMatches.Count -ne 1) { throw 'Expected email does not identify exactly one Auth user.' }
  $authBefore = $authMatches[0]
  if ($authBefore.id -ne $expectedUserId) { throw 'Auth UUID does not match the approved UUID.' }
  if (-not $authBefore.email_confirmed_at -or $authBefore.banned_until -or $authBefore.deleted_at) {
    throw 'Auth user is not confirmed and eligible.'
  }

  $profilesBefore = Get-Profile $headers $expectedUserId
  if ($profilesBefore.Count -ne 1) { throw 'Expected UUID does not identify exactly one profile.' }
  $profileBefore = $profilesBefore[0]
  if ($profileBefore.id -ne $expectedUserId -or $profileBefore.email -cne $expectedEmail) {
    throw 'Profile identity does not match the approved Auth identity.'
  }
  if ($profileBefore.role -ne 'approver' -or $profileBefore.is_active -ne $true -or $profileBefore.deleted_at) {
    throw 'Profile role or lifecycle state is not eligible.'
  }
  if ($profileBefore.password_change_required -ne $true) {
    throw 'Mandatory password-change state is not present.'
  }
  if ($expectedEmail -ceq 'facility_king@yahoo.com' -or $profileBefore.role -eq 'administrator') {
    throw 'Excluded account cannot be restored.'
  }

  $profileSnapshotBefore = Canonical-Json $profileBefore
  $otherUsersBefore = Canonical-Json @(
    $authUsersBefore |
      Where-Object { $_.id -ne $expectedUserId } |
      Sort-Object id |
      ForEach-Object { [ordered]@{ id = $_.id; email = $_.email; updated_at = $_.updated_at } }
  )

  Write-Host 'All preconditions passed for the approved Preview user.'
  $firstSecure = Read-Host 'Enter temporary password' -AsSecureString
  $secondSecure = Read-Host 'Enter temporary password again' -AsSecureString
  $firstPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($firstSecure)
  $secondPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secondSecure)
  try {
    $firstPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($firstPtr)
    $secondPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secondPtr)
    if ($firstPlain -cne $secondPlain) { throw 'Temporary password entries do not match. No Auth write occurred.' }
    if ($firstPlain.Length -lt 12) { throw 'Temporary password must contain at least 12 characters. No Auth write occurred.' }

    $body = @{ password = $firstPlain } | ConvertTo-Json -Compress
    $updateUri = "https://$projectRef.supabase.co/auth/v1/admin/users/$expectedUserId"
    $null = Invoke-RestMethod -Method Put -Uri $updateUri -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 30
  }
  finally {
    if ($firstPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($firstPtr) }
    if ($secondPtr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secondPtr) }
    $firstPlain = $null
    $secondPlain = $null
    $body = $null
  }

  $authUsersAfter = Get-AuthUsers $headers
  $authAfterMatches = @($authUsersAfter | Where-Object { $_.email -ceq $expectedEmail })
  if ($authAfterMatches.Count -ne 1) { throw 'Postcondition failed: Auth identity count changed.' }
  $authAfter = $authAfterMatches[0]
  $profilesAfter = Get-Profile $headers $expectedUserId
  if ($profilesAfter.Count -ne 1) { throw 'Postcondition failed: profile identity count changed.' }
  $profileAfter = $profilesAfter[0]
  $profileSnapshotAfter = Canonical-Json $profileAfter
  $otherUsersAfter = Canonical-Json @(
    $authUsersAfter |
      Where-Object { $_.id -ne $expectedUserId } |
      Sort-Object id |
      ForEach-Object { [ordered]@{ id = $_.id; email = $_.email; updated_at = $_.updated_at } }
  )

  $passed =
    $authAfter.id -eq $expectedUserId -and
    $authAfter.email -ceq $expectedEmail -and
    $null -ne $authAfter.email_confirmed_at -and
    $null -eq $authAfter.banned_until -and
    $null -eq $authAfter.deleted_at -and
    $profileAfter.role -eq 'approver' -and
    $profileAfter.is_active -eq $true -and
    $null -eq $profileAfter.deleted_at -and
    $profileAfter.password_change_required -eq $true -and
    $profileSnapshotBefore -ceq $profileSnapshotAfter -and
    $otherUsersBefore -ceq $otherUsersAfter

  Write-SafeResult ([ordered]@{
    restore_result = if ($passed) { 'PASS' } else { 'FAIL' }
    auth_uuid = $authAfter.id
    email = $authAfter.email
    confirmed = ($null -ne $authAfter.email_confirmed_at)
    banned = ($null -ne $authAfter.banned_until)
    auth_deleted = ($null -ne $authAfter.deleted_at)
    profile_role = $profileAfter.role
    active = $profileAfter.is_active
    profile_deleted = ($null -ne $profileAfter.deleted_at)
    password_change_required = $profileAfter.password_change_required
    protected_profile_unchanged = ($profileSnapshotBefore -ceq $profileSnapshotAfter)
    other_users_modified = ($otherUsersBefore -cne $otherUsersAfter)
  })
  if (-not $passed) { exit 2 }
  Write-Host 'Password restoration completed and non-secret postconditions passed.'
  exit 0
}
catch {
  Write-SafeResult ([ordered]@{
    restore_result = 'FAIL'
    error = $_.Exception.Message
  })
  Write-Host $_.Exception.Message
  exit 1
}
