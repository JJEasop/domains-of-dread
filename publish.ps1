# Syncs the Obsidian vault with the site repo on GitHub, then pushes, which rebuilds the public wiki.
# Edits made on GitHub (by you or a collaborator) are merged in and copied back into the vault.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File publish.ps1            # sync and publish
#   powershell -ExecutionPolicy Bypass -File publish.ps1 -PullOnly  # bring GitHub edits into the vault, don't push
param(
    [switch]$PullOnly,
    [string]$Vault = "C:\Users\sg559\OneDrive\Documents\Obsidian Vaults\Domains of Dread"
)

$vault = $Vault
$site = $PSScriptRoot
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Set-Location $site

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

if (Test-Path "$site\.git\MERGE_HEAD") { Fail "A previous merge is unfinished in $site. Resolve it (or run 'git merge --abort') first." }

# 1. Mirror the vault into content/ (keeping the site's own home page) and commit any local changes,
#    so git can merge them with edits made on GitHub.
robocopy $vault "$site\content" /MIR /XD .obsidian .trash .claude /XF index.md /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "Copying the vault failed (robocopy exit $LASTEXITCODE)." }

git add -A -- content
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    git commit -q -m "Update wiki $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    if ($LASTEXITCODE -ne 0) { Fail "git commit failed." }
}

# 2. Fetch and merge edits made on GitHub.
$before = (git rev-parse HEAD).Trim()
git fetch -q origin
if ($LASTEXITCODE -ne 0) { Fail "Could not fetch from GitHub." }
git merge -q --no-edit origin/v5 2>$null
if ($LASTEXITCODE -ne 0) {
    # Overlapping edits: keep the vault's version and save GitHub's beside it as "<note> (GitHub conflict).md".
    $conflicts = @(git -c core.quotepath=off diff --name-only --diff-filter=U)
    if ($conflicts.Count -eq 0) { git merge --abort; Fail "git merge failed." }
    Write-Host "These notes were edited both in the vault and on GitHub. The vault version was kept and GitHub's saved beside it:" -ForegroundColor Yellow
    foreach ($c in $conflicts) {
        $file = Join-Path $site ($c -replace "/", "\")
        git checkout -q --theirs -- $c 2>$null
        $theirsOk = ($LASTEXITCODE -eq 0)
        if ($theirsOk) { $theirsCopy = [System.IO.File]::ReadAllBytes($file) }
        git checkout -q --ours -- $c 2>$null
        if ($LASTEXITCODE -eq 0) {
            git add -- $c
            if ($theirsOk) {
                $copy = $file -replace '\.md$', ' (GitHub conflict).md'
                [System.IO.File]::WriteAllBytes($copy, $theirsCopy)
                git add -- $copy
                Write-Host "  $c  ->  see '$(Split-Path $copy -Leaf)'"
            } else {
                Write-Host "  $c  (deleted on GitHub; vault version kept)"
            }
        } elseif ($theirsOk) {
            git checkout -q --theirs -- $c; git add -- $c
            Write-Host "  $c  (deleted in vault but edited on GitHub; GitHub version restored)"
        } else {
            git rm -q -- $c
        }
    }
    git commit -q --no-edit
    if ($LASTEXITCODE -ne 0) { git merge --abort; Fail "Could not finish merging GitHub's edits. Nothing was changed." }
}
$after = (git rev-parse HEAD).Trim()

# 3. Copy whatever the merge brought in back into the vault. Deleted notes go to the vault's .trash.
if ($before -ne $after) {
    $incoming = git -c core.quotepath=off diff --no-renames --name-status $before $after -- content
    $pulled = @()
    foreach ($line in $incoming) {
        $status, $path = $line -split "`t", 2
        if ($path -eq "content/index.md") { continue }
        $rel = $path.Substring("content/".Length) -replace "/", "\"
        $dest = Join-Path $vault $rel
        if ($status -eq "D") {
            if (Test-Path -LiteralPath $dest) {
                $trash = Join-Path "$vault\.trash" $rel
                New-Item -ItemType Directory -Force -Path (Split-Path $trash) | Out-Null
                Move-Item -LiteralPath $dest -Destination $trash -Force
            }
            $pulled += "deleted  $rel"
        } else {
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Copy-Item -LiteralPath (Join-Path $site ($path -replace "/", "\")) -Destination $dest -Force
            $pulled += "updated  $rel"
        }
    }
    if ($pulled.Count -gt 0) {
        Write-Host "Pulled $($pulled.Count) change(s) from GitHub into the vault:"
        $pulled | ForEach-Object { Write-Host "  $_" }
    }
}

if ($PullOnly) { Write-Host "Vault is up to date with GitHub."; exit 0 }

# 4. Push.
$ahead = [int](git rev-list --count origin/v5..HEAD)
if ($ahead -eq 0) { Write-Host "No changes to publish."; exit 0 }
git push -q
if ($LASTEXITCODE -ne 0) { Fail "git push failed. Run publish again; your vault edits are safe." }
Write-Host "Published. The site updates in about a minute."
