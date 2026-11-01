$ErrorActionPreference = 'Stop'
$gameRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$packFolder = Join-Path $gameRoot 'data_packfiles'
$indexPath = Join-Path $packFolder 'ep100-000-generic.bin'
$dataPath = Join-Path $packFolder 'ep100-000-generic.rmdp'
$targetFolder = Join-Path $gameRoot 'data\uiresources\p7'
$targetPath = Join-Path $targetFolder 'hud.ui'

$stockHash = '3546b2de4779ed5fdf0dbd49648df3e673a75c95e3c946b904e608e0f9fb9fca'
$patchedHash = '0ae43ed163c692d9baa6b6ec3349a4b0b6003405a9a417c9f66a0900e6211367'
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$latin1 = [System.Text.Encoding]::GetEncoding(28591)

$oldLarge = '!g_areaIntroData.m_bHasVisitedLocation&&'
$newLarge = '1&&' + (' ' * ($oldLarge.Length - 3))
$oldSmall = 'g_areaIntroData.m_bHasVisitedLocation||'
$newSmall = '0||' + (' ' * ($oldSmall.Length - 3))

function Get-Sha256([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Read-IndexString([byte[]]$Bytes, [long]$NamesStart, [long]$NamesLength, [long]$NameOffset) {
    if ($NameOffset -lt 0 -or $NameOffset -ge $NamesLength) { throw 'Invalid name offset in package index.' }
    $start = [int]($NamesStart + $NameOffset)
    $endLimit = [int]($NamesStart + $NamesLength)
    $end = [System.Array]::IndexOf($Bytes, [byte]0, $start, $endLimit - $start)
    if ($end -lt 0) { throw 'Unterminated name in package index.' }
    try { return $utf8.GetString($Bytes, $start, $end - $start) }
    catch { throw 'Invalid UTF-8 name in package index.' }
}

function Test-IndexLink([long]$Value, [long]$Limit) {
    return ($Value -eq -1 -or ($Value -ge 0 -and $Value -lt $Limit))
}

function Get-HudFromPackage {
    if (-not [System.IO.File]::Exists($indexPath)) { throw "Package index not found: $indexPath" }
    if (-not [System.IO.File]::Exists($dataPath)) { throw "Package data file not found: $dataPath" }

    $index = [System.IO.File]::ReadAllBytes($indexPath)
    if ($index.Length -lt 249) { throw 'Package index is too small for a Control v9 package.' }
    if ($index[0] -ne 0) { throw 'Package is not little-endian Control format.' }
    if ([System.BitConverter]::ToUInt32($index, 1) -ne 9) { throw 'Unsupported package format; this release requires Control package version 9.' }
    if ([System.BitConverter]::ToUInt64($index, 13) -ne 1) { throw 'Unexpected Control package header value.' }
    if ($index[0x19] -ne 0) { throw 'Package has an unexpected non-empty base path.' }

    $folderCount = [long][System.BitConverter]::ToUInt32($index, 5)
    $fileCount = [long][System.BitConverter]::ToUInt32($index, 9)
    $namesLength = [long][System.BitConverter]::ToUInt32($index, 0x15)
    if ($folderCount -lt 1 -or $fileCount -lt 1 -or $namesLength -lt 1) { throw 'Package index contains invalid record counts.' }

    $folderStart = [long]0x99
    $fileStart = $folderStart + ($folderCount * 48)
    $recordsEnd = $fileStart + ($fileCount * 60)
    $namesStart = [long]$index.Length - $namesLength
    if ($namesStart -lt 0 -or ($namesStart - $recordsEnd) -ne 48) {
        throw 'Package index does not have the expected Control v9 record layout.'
    }

    $root = [int]$folderStart
    if ([System.BitConverter]::ToUInt32($index, $root) -ne 0 -or
        [System.BitConverter]::ToInt64($index, $root + 4) -ne -1 -or
        [System.BitConverter]::ToInt64($index, $root + 12) -ne -1 -or
        [System.BitConverter]::ToInt64($index, $root + 24) -ne -1) {
        throw 'Package index has an invalid root folder record.'
    }

    $closing = [int]$recordsEnd
    if ([System.BitConverter]::ToUInt32($index, $closing) -ne 0 -or
        [System.BitConverter]::ToInt64($index, $closing + 4) -ne -1 -or
        [System.BitConverter]::ToInt64($index, $closing + 12) -ne -1 -or
        [System.BitConverter]::ToInt64($index, $closing + 24) -ne -1 -or
        [System.BitConverter]::ToInt64($index, $closing + 32) -ne -1 -or
        [System.BitConverter]::ToInt64($index, $closing + 40) -ne -1) {
        throw 'Package index has an invalid closing folder record.'
    }

    if ($folderCount -gt [int]::MaxValue -or $fileCount -gt [int]::MaxValue) { throw 'Package index has too many records.' }
    $folderNames = [string[]]::new([int]$folderCount)
    $folderParents = [long[]]::new([int]$folderCount)
    $folderPaths = [string[]]::new([int]$folderCount)
    $resolved = [bool[]]::new([int]$folderCount)

    for ($i = 0; $i -lt [int]$folderCount; $i++) {
        $record = [int]($folderStart + ($i * 48))
        $nextSibling = [System.BitConverter]::ToInt64($index, $record + 4)
        $parent = [System.BitConverter]::ToInt64($index, $record + 12)
        $nameOffset = [System.BitConverter]::ToInt64($index, $record + 24)
        $firstChild = [System.BitConverter]::ToInt64($index, $record + 32)
        $firstFile = [System.BitConverter]::ToInt64($index, $record + 40)

        if (-not (Test-IndexLink $nextSibling $folderCount) -or
            -not (Test-IndexLink $firstChild $folderCount) -or
            -not (Test-IndexLink $firstFile $fileCount)) { throw 'Package index contains an invalid folder link.' }

        if ($i -eq 0) {
            if ($parent -ne -1 -or $nameOffset -ne -1) { throw 'Package index root folder is not the expected unnamed root.' }
            $folderNames[$i] = ''
        }
        else {
            if ($parent -lt 0 -or $parent -ge $folderCount -or $nameOffset -lt 0) { throw 'Package index contains an invalid folder parent or name.' }
            $folderNames[$i] = Read-IndexString $index $namesStart $namesLength $nameOffset
            if ([string]::IsNullOrEmpty($folderNames[$i])) { throw 'Package index contains an empty non-root folder name.' }
        }
        $folderParents[$i] = $parent
    }

    for ($i = 0; $i -lt [int]$folderCount; $i++) {
        if ($resolved[$i]) { continue }
        $chain = [System.Collections.Generic.List[int]]::new()
        $active = [System.Collections.Generic.HashSet[int]]::new()
        $cursor = $i
        while (-not $resolved[$cursor]) {
            if ($cursor -lt 0 -or $cursor -ge [int]$folderCount) { throw 'Folder hierarchy points outside the folder table.' }
            if (-not $active.Add($cursor)) { throw 'Folder hierarchy contains a cycle.' }
            if ($cursor -eq 0) {
                $folderPaths[0] = ''
                $resolved[0] = $true
                break
            }
            if ($folderParents[$cursor] -lt 0) { throw 'Package index contains a folder disconnected from the root.' }
            $chain.Add($cursor)
            $cursor = [int]$folderParents[$cursor]
        }
        for ($j = $chain.Count - 1; $j -ge 0; $j--) {
            $folderIndex = $chain[$j]
            $parentPath = $folderPaths[[int]$folderParents[$folderIndex]]
            if ([string]::IsNullOrEmpty($parentPath)) { $folderPaths[$folderIndex] = $folderNames[$folderIndex] }
            else { $folderPaths[$folderIndex] = "$parentPath/$($folderNames[$folderIndex])" }
            $resolved[$folderIndex] = $true
        }
    }

    $targetFolderId = -1
    for ($i = 0; $i -lt [int]$folderCount; $i++) {
        if ($folderPaths[$i].Replace('\', '/').ToLowerInvariant() -eq 'data/uiresources/p7') {
            if ($targetFolderId -ne -1) { throw 'Package contains duplicate data/uiresources/p7 folders.' }
            $targetFolderId = $i
        }
    }
    if ($targetFolderId -lt 0) { throw 'Could not find data/uiresources/p7 in the package index.' }

    $targetRecord = $null
    for ($i = [long]0; $i -lt $fileCount; $i++) {
        $record = [int]($fileStart + ($i * 60))
        $nextSibling = [System.BitConverter]::ToInt64($index, $record + 4)
        $parent = [System.BitConverter]::ToInt64($index, $record + 12)
        $nameOffset = [System.BitConverter]::ToInt64($index, $record + 24)
        if (($nextSibling -ne -1 -and ($nextSibling -lt 0 -or $nextSibling -ge $fileCount)) -or $parent -lt 0 -or $parent -ge $folderCount -or $nameOffset -lt 0 -or $nameOffset -ge $namesLength) {
            throw 'Package index contains an invalid file record.'
        }
        if ($parent -ne $targetFolderId) { continue }
        $name = Read-IndexString $index $namesStart $namesLength $nameOffset
        if ($name.ToLowerInvariant() -ne 'hud.ui') { continue }
        if ($null -ne $targetRecord) { throw 'Package contains duplicate hud.ui entries in the target folder.' }
        if ([System.BitConverter]::ToUInt32($index, $record + 20) -ne 0) { throw 'The hud.ui record has unexpected flags.' }
        $offset = [System.BitConverter]::ToInt64($index, $record + 32)
        $size = [System.BitConverter]::ToInt64($index, $record + 40)
        if ($offset -lt 0 -or ($offset % 32) -ne 0 -or $size -le 0 -or $size -gt 67108864) { throw 'Package index contains an invalid hud.ui data range.' }
        $targetRecord = [pscustomobject]@{ Offset = $offset; Size = $size }
    }
    if ($null -eq $targetRecord) { throw 'Could not find data/uiresources/p7/hud.ui in the package index.' }

    $stream = [System.IO.File]::OpenRead($dataPath)
    try {
        if ($targetRecord.Offset -gt $stream.Length -or $targetRecord.Size -gt ($stream.Length - $targetRecord.Offset)) {
            throw 'The hud.ui data range extends beyond the package data file.'
        }
        [void]$stream.Seek($targetRecord.Offset, [System.IO.SeekOrigin]::Begin)
        $bytes = [byte[]]::new([int]$targetRecord.Size)
        $totalRead = 0
        while ($totalRead -lt $bytes.Length) {
            $read = $stream.Read($bytes, $totalRead, $bytes.Length - $totalRead)
            if ($read -le 0) { throw 'Unexpected end of package while reading hud.ui.' }
            $totalRead += $read
        }
        return ,$bytes
    }
    finally { $stream.Dispose() }
}

function Get-Occurrences([string]$Text, [string]$Needle) {
    $count = 0
    $position = 0
    while ($true) {
        $found = $Text.IndexOf($Needle, $position, [System.StringComparison]::Ordinal)
        if ($found -lt 0) { break }
        $count++
        $position = $found + 1
    }
    return $count
}

function Get-PatchState([string]$Text) {
    return [pscustomobject]@{
        OldLarge = (Get-Occurrences $Text $oldLarge)
        OldSmall = (Get-Occurrences $Text $oldSmall)
        NewLarge = (Get-Occurrences $Text $newLarge)
        NewSmall = (Get-Occurrences $Text $newSmall)
    }
}

function New-PatchedText([string]$Text) {
    $state = Get-PatchState $Text
    if ($state.OldLarge -ne 1 -or $state.OldSmall -ne 1 -or $state.NewLarge -ne 0 -or $state.NewSmall -ne 0) {
        throw 'The expected HUD code was not found exactly once. No file was changed.'
    }
    $result = $Text.Replace($oldLarge, $newLarge).Replace($oldSmall, $newSmall)
    $check = Get-PatchState $result
    if ($result.Length -ne $Text.Length -or $check.NewLarge -ne 1 -or $check.NewSmall -ne 1 -or $check.OldLarge -ne 0 -or $check.OldSmall -ne 0) {
        throw 'Patch verification failed. No file was changed.'
    }
    return $result
}

function Get-BackupPath([string]$Path) {
    $base = "$Path.before-recurrent-title-cards-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $candidate = "$base.bak"
    $suffix = 1
    while ([System.IO.File]::Exists($candidate)) { $candidate = "$base-$suffix.bak"; $suffix++ }
    return $candidate
}

$tempPath = $null
try {
    if (-not [System.IO.File]::Exists((Join-Path $gameRoot 'Control_DX12.exe'))) {
        throw 'Control_DX12.exe was not found. Extract the ZIP into the main Steam Control folder.'
    }
    if ([System.IO.Directory]::Exists($targetPath)) { throw 'The target hud.ui path is a directory.' }

    Write-Host 'Reading the Control package index (this can take up to a minute)...'
    $archiveBytes = Get-HudFromPackage
    $archiveHash = Get-Sha256 $archiveBytes
    if ($archiveHash -ne $stockHash) {
        throw 'The archived hud.ui does not match the verified game build. No files were changed. If you installed this patch earlier and the game has since been updated, delete data\uiresources\p7\hud.ui so the game uses its own HUD again.'
    }
    $archiveText = $latin1.GetString($archiveBytes)

    $targetExists = [System.IO.File]::Exists($targetPath)
    if ($targetExists) {
        $existingBytes = [System.IO.File]::ReadAllBytes($targetPath)
        if ($existingBytes.Length -gt 67108864) { throw 'The existing hud.ui is unexpectedly large.' }
        $existingText = $latin1.GetString($existingBytes)
        $state = Get-PatchState $existingText

        if ($state.NewLarge -eq 1 -and $state.NewSmall -eq 1 -and $state.OldLarge -eq 0 -and $state.OldSmall -eq 0) {
            $expectedText = New-PatchedText $archiveText
            if ([string]::Equals($existingText, $expectedText, [System.StringComparison]::Ordinal)) {
                Write-Host 'Recurrent Title Cards is already installed.'
                Write-Host "SHA-256: $(Get-Sha256 $existingBytes)"
            }
            else {
                Write-Host 'The title-card changes are already present, but this HUD contains additional differences or is from another build.' -ForegroundColor Yellow
                Write-Host 'No changes were made. Review the existing HUD before replacing it.' -ForegroundColor Yellow
            }
            exit 0
        }

        if ($state.OldLarge -ne 1 -or $state.OldSmall -ne 1 -or $state.NewLarge -ne 0 -or $state.NewSmall -ne 0) {
            throw 'The existing hud.ui does not contain the expected unmodified title logic. No file was changed.'
        }

        if ((Get-Sha256 $existingBytes) -ne $stockHash) {
            Write-Host 'The existing loose hud.ui differs from the verified game file.' -ForegroundColor Yellow
            Write-Host 'It may contain changes from another HUD mod or be from a different build.' -ForegroundColor Yellow
            $answer = Read-Host 'Patch this file while preserving its other changes? (y/N)'
            if ($answer -notmatch '^(?i)y(es)?$') { throw 'Cancelled. No files were changed.' }
        }
        $sourceText = $existingText
    }
    else {
        $sourceText = $archiveText
    }

    $patchedText = New-PatchedText $sourceText
    $patchedBytes = $latin1.GetBytes($patchedText)
    $sourceBytes = $latin1.GetBytes($sourceText)
    if ((Get-Sha256 $sourceBytes) -eq $stockHash -and (Get-Sha256 $patchedBytes) -ne $patchedHash) {
        throw 'The patched result did not match the verified output. No files were changed.'
    }

    if (-not [System.IO.Directory]::Exists($targetFolder)) { [void][System.IO.Directory]::CreateDirectory($targetFolder) }
    $tempPath = Join-Path $targetFolder ('.hud.ui-recurrent-title-cards-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [System.IO.File]::WriteAllBytes($tempPath, $patchedBytes)

    if ($targetExists) {
        $backupPath = Get-BackupPath $targetPath
        [System.IO.File]::Replace($tempPath, $targetPath, $backupPath)
        $tempPath = $null
        Write-Host "Backup: $backupPath"
    }
    else {
        [System.IO.File]::Move($tempPath, $targetPath)
        $tempPath = $null
    }

    Write-Host 'Recurrent Title Cards installed.'
    Write-Host "SHA-256: $(Get-Sha256 $patchedBytes)"
    Write-Host 'The Loose Files Loader must be installed for the change to load in-game.'
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    if ($null -ne $tempPath -and [System.IO.File]::Exists($tempPath)) {
        try { [System.IO.File]::Delete($tempPath) } catch { }
    }
}
