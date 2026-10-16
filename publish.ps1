# Copies the Obsidian vault into the site and pushes it to GitHub, which rebuilds the public wiki.
# Usage: powershell -ExecutionPolicy Bypass -File publish.ps1

$vault = "C:\Users\sg559\OneDrive\Documents\Obsidian Vaults\Domains of Dread"
$site = $PSScriptRoot

Set-Location $site

# Mirror the vault into content/, keeping the site's own home page.
robocopy $vault "$site\content" /MIR /XD .obsidian .trash /XF index.md /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Error "Copying the vault failed (robocopy exit $LASTEXITCODE)."; exit 1 }

git add -A
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host "No changes to publish."; exit 0 }

git commit -m "Update wiki $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
git push
if ($LASTEXITCODE -eq 0) { Write-Host "Published. The site updates in about a minute." }
