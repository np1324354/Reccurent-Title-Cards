[CmdletBinding()]
param(
    [Parameter()]
    [string]$GamePath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

# Recurrent Title Cards v1.0b - standalone installer.
# Reads the user's verified stock HUD (or exact v1.0 HUD), builds v1.0b,
# verifies the complete output hash, then installs with an external backup.

$stockHash = '3546b2de4779ed5fdf0dbd49648df3e673a75c95e3c946b904e608e0f9fb9fca'
$v1Hash = '0ae43ed163c692d9baa6b6ec3349a4b0b6003405a9a417c9f66a0900e6211367'
$v1bHash = '44d845b166a9c56ce21d34d840ed70932415dd0ba19f69d0fcf6a9a044f28f20'
$hudSize = 1662217
$archiveOffset = [long]0x137F76100

function Get-Sha256([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-UniqueTextOffset {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Description
    )
    $first = $Text.IndexOf($Needle, [System.StringComparison]::Ordinal)
    $last = $Text.LastIndexOf($Needle, [System.StringComparison]::Ordinal)
    if ($first -lt 0 -or $first -ne $last) {
        throw "$Description was not found exactly once. No file was changed."
    }
    return $first
}

function Get-StockHudFromArchive {
    param([Parameter(Mandatory = $true)][string]$Root)

    $archive = Join-Path $Root 'data_packfiles\ep100-000-generic.rmdp'
    if (-not [System.IO.File]::Exists($archive)) {
        throw 'Could not find data_packfiles\ep100-000-generic.rmdp. Use the Control game folder containing Control_DX12.exe.'
    }

    $stream = [System.IO.File]::OpenRead($archive)
    try {
        if (($archiveOffset + $hudSize) -gt $stream.Length) {
            throw 'The game archive is too small for the tested hud.ui resource.'
        }
        [void]$stream.Seek($archiveOffset, [System.IO.SeekOrigin]::Begin)
        $bytes = [byte[]]::new($hudSize)
        $totalRead = 0
        while ($totalRead -lt $bytes.Length) {
            $read = $stream.Read($bytes, $totalRead, $bytes.Length - $totalRead)
            if ($read -le 0) { throw 'Unexpected end of archive while reading hud.ui.' }
            $totalRead += $read
        }
        return ,$bytes
    }
    finally {
        $stream.Dispose()
    }
}

$temp = $null
$installed = $false
$backupPath = $null
$hadPreviousLooseHud = $false
$gameRoot = [System.IO.Path]::GetFullPath($GamePath.Trim().Trim('"'))

try {
    if (-not [System.IO.File]::Exists((Join-Path $gameRoot 'Control_DX12.exe')) -and
        -not [System.IO.File]::Exists((Join-Path $gameRoot 'Control.exe'))) {
        throw 'The selected folder does not contain Control_DX12.exe or Control.exe. Extract this ZIP into the main Control game folder.'
    }

    if (Get-Process -Name 'Control_DX12','Control' -ErrorAction SilentlyContinue) {
        throw 'Control is running. Close the game before installing.'
    }

    $target = Join-Path $gameRoot 'data\uiresources\p7\hud.ui'
    if ([System.IO.Directory]::Exists($target)) {
        throw 'The hud.ui target path is a directory. No changes were made.'
    }

    $backupDirectory = Join-Path $gameRoot '_mod_backups\Recurrent-Title-Cards-v1.0b'

    # The game's own HUD must match the verified build, whether or not a loose copy already exists.
    $archiveBytes = Get-StockHudFromArchive -Root $gameRoot
    $archiveHash = Get-Sha256 $archiveBytes
    if ($archiveHash -ne $stockHash) {
        throw "The game's own HUD (SHA-256 $archiveHash) does not match the verified Steam build. No changes were made. If you installed this mod earlier and the game has since been updated, delete data\uiresources\p7\hud.ui so the game uses its own HUD again."
    }

    if ([System.IO.File]::Exists($target)) {
        $hadPreviousLooseHud = $true
        $sourceBytes = [System.IO.File]::ReadAllBytes($target)
        Write-Host 'Source: existing loose hud.ui'
    }
    else {
        $sourceBytes = $archiveBytes
        Write-Host 'Source: stock hud.ui extracted from the game archive'
    }

    if ($sourceBytes.Length -ne $hudSize) {
        throw "Unexpected source hud.ui size ($($sourceBytes.Length) bytes). Expected $hudSize. No changes were made."
    }

    $sourceHash = Get-Sha256 $sourceBytes
    if ($sourceHash -eq $v1bHash) {
        Write-Host 'The exact v1.0b HUD is already present. No changes were made.' -ForegroundColor Green
        exit 0
    }

    # Build the verified v1.0 baseline from stock, or accept the exact v1.0
    # loose HUD so users can switch from v1.0 to this alternative release.
    if ($sourceHash -eq $stockHash) {
        $encoding = [System.Text.Encoding]::GetEncoding(28591)
        $sourceText = $encoding.GetString($sourceBytes)

        $oldLarge = '!g_areaIntroData.m_bHasVisitedLocation&&'
        $newLarge = '1&&' + (' ' * ($oldLarge.Length - 3))
        $oldSmall = 'g_areaIntroData.m_bHasVisitedLocation||'
        $newSmall = '0||' + (' ' * ($oldSmall.Length - 3))

        $largeOffset = Get-UniqueTextOffset -Text $sourceText -Needle $oldLarge -Description 'Original large-area title condition'
        $smallOffset = Get-UniqueTextOffset -Text $sourceText -Needle $oldSmall -Description 'Original small-location label condition'

        $v1Bytes = [byte[]]($sourceBytes.Clone())
        [System.Array]::Copy([System.Text.Encoding]::ASCII.GetBytes($newLarge), 0, $v1Bytes, $largeOffset, $newLarge.Length)
        [System.Array]::Copy([System.Text.Encoding]::ASCII.GetBytes($newSmall), 0, $v1Bytes, $smallOffset, $newSmall.Length)

        if ((Get-Sha256 $v1Bytes) -ne $v1Hash) {
            throw 'The stock HUD did not produce the verified v1.0 baseline. The game build may differ; no file was changed.'
        }
        $sourceBytes = $v1Bytes
        Write-Host 'Verified v1.0 base generated from stock HUD.'
    }
    elseif ($sourceHash -eq $v1Hash) {
        Write-Host 'Verified v1.0 loose HUD detected; preparing the v1.0b alternative.'
    }
    else {
        throw "The existing loose hud.ui is not stock, v1.0, or v1.0b. SHA-256: $sourceHash. It may belong to another HUD mod; no changes were made."
    }

    # v1.0b changes only BigAreaIntro.onAreaIntro. Reuse the component's
    # existing currentAreaLocID state and consume the v1.0 whitespace padding.
    $encoding = [System.Text.Encoding]::GetEncoding(28591)
    $sourceText = $encoding.GetString($sourceBytes)
    $pattern = 'onAreaIntro\(\)\{0\|\|[ \t]*void 0!==n\.default\[g_areaIntroData\.m_strAreaIntroText\]&&\(clearTimeout\(this\.hideTimeout\),setTimeout\(this\.show\.bind\(this,g_areaIntroData\.m_strAreaIntroText\),r\.BIG_AREA_INTRO_DELAY\)\)\}'
    $methodMatches = [regex]::Matches($sourceText, $pattern)
    if ($methodMatches.Count -ne 1) {
        throw "Expected exactly one v1.0 BigAreaIntro handler; found $($methodMatches.Count). No changes were made."
    }

    $oldMethod = $methodMatches[0]
    $newMethodBase = 'onAreaIntro(){const e=g_areaIntroData.m_strAreaIntroText;0||void 0!==n.default[e]&&this.state.currentAreaLocID!==e&&(clearTimeout(this.hideTimeout),setTimeout(this.show.bind(this,e),r.BIG_AREA_INTRO_DELAY))}'
    $paddingCount = $oldMethod.Length - $newMethodBase.Length
    if ($paddingCount -ne 26) {
        throw "Unexpected v1.0 handler padding ($paddingCount characters). This is not the exact tested source; no changes were made."
    }

    $insertAt = $newMethodBase.IndexOf('0||', [System.StringComparison]::Ordinal) + 3
    $newMethod = $newMethodBase.Insert($insertAt, (' ' * $paddingCount))
    if ($newMethod.Length -ne $oldMethod.Length) {
        throw 'BigAreaIntro method length check failed. No changes were made.'
    }

    $modifiedText = $sourceText.Substring(0, $oldMethod.Index) +
                    $newMethod +
                    $sourceText.Substring($oldMethod.Index + $oldMethod.Length)
    $patchedBytes = $encoding.GetBytes($modifiedText)

    if ($patchedBytes.Length -ne $hudSize) {
        throw 'Complete hud.ui byte length changed. No changes were made.'
    }
    $patchedHash = Get-Sha256 $patchedBytes
    if ($patchedHash -ne $v1bHash) {
        throw "The result did not match the verified v1.0b build. Computed SHA-256: $patchedHash. No changes were made."
    }

    # A unique backup is kept outside data\ so the loose-file loader does not
    # enumerate the backup as another game resource.
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $backupName = ''
    if ($hadPreviousLooseHud) {
        [void][System.IO.Directory]::CreateDirectory($backupDirectory)
        $backupName = "hud.ui.before-v1.0b-$stamp.bak"
        $backupPath = Join-Path $backupDirectory $backupName
        if ([System.IO.File]::Exists($backupPath)) { throw 'The generated backup filename already exists.' }
    }

    $targetDirectory = [System.IO.Path]::GetDirectoryName($target)
    [void][System.IO.Directory]::CreateDirectory($targetDirectory)
    $temp = Join-Path $targetDirectory ('.hud.ui-v1.0b-' + [Guid]::NewGuid().ToString('N') + '.tmp')

    $outputStream = [System.IO.File]::Open($temp, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try { $outputStream.Write($patchedBytes, 0, $patchedBytes.Length) }
    finally { $outputStream.Dispose() }

    if ((Get-Sha256 ([System.IO.File]::ReadAllBytes($temp))) -ne $v1bHash) {
        throw 'Temporary output verification failed. The installed HUD was not replaced.'
    }

    if ($hadPreviousLooseHud) {
        [System.IO.File]::Replace($temp, $target, $backupPath)
        $temp = $null
    }
    else {
        [System.IO.File]::Move($temp, $target)
        $temp = $null
    }
    $installed = $true

    if ((Get-Sha256 ([System.IO.File]::ReadAllBytes($target))) -ne $v1bHash) {
        throw 'Post-install verification failed.'
    }

    Write-Host ''
    Write-Host 'RECURRENT TITLE CARDS v1.0b INSTALLED AND VERIFIED' -ForegroundColor Green
    Write-Host "Size: $hudSize bytes (unchanged)"
    Write-Host "SHA-256: $patchedHash"
    if ($hadPreviousLooseHud) {
        Write-Host "Previous loose HUD backup: $backupPath"
    }
    else {
        Write-Host 'No loose HUD existed before installation; remove hud.ui to return to the archived game HUD.'
    }
    Write-Host 'Manual removal instructions are included in README.txt.'
}
catch {
    # If a post-install error occurs, restore the prior loose HUD (or remove
    # the new override) before reporting the error.
    if ($installed) {
        try {
            if ([System.IO.File]::Exists($target) -and (Get-Sha256 ([System.IO.File]::ReadAllBytes($target))) -eq $v1bHash) {
                if ($hadPreviousLooseHud -and $null -ne $backupPath -and [System.IO.File]::Exists($backupPath)) {
                    $failedName = 'hud.ui.v1.0b-uncommitted-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.bak'
                    $failedPath = Join-Path $backupDirectory $failedName
                    [System.IO.File]::Replace($backupPath, $target, $failedPath)
                }
                elseif (-not $hadPreviousLooseHud) {
                    [System.IO.File]::Delete($target)
                }
            }
        }
        catch {
            Write-Host "Automatic rollback after a post-install error was unsuccessful: $($_.Exception.Message)" -ForegroundColor Red
            if ($null -ne $backupPath) { Write-Host "Previous HUD backup: $backupPath" }
        }
    }
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if ($null -ne $temp -and [System.IO.File]::Exists($temp)) {
        try { [System.IO.File]::Delete($temp) } catch { }
    }
}
