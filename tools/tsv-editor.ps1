<#
.SYNOPSIS
    Open the TSV editor for game/data/*.tsv.

.DESCRIPTION
    Serves the repo on localhost and opens tools/tsv-editor.html in the default
    browser. Ctrl-C when done.

    The page works opened straight off disk, but one thing only works over
    http:// — Chrome refuses the save-in-place file picker on a file:// origin,
    so every save downgrades to "download a copy and move it over the real file
    by hand". Serving the repo for a minute buys the real thing. The footer of
    the page says which mode you are in.

    The whole repo is served rather than just tools/, because that is what makes
    /game/data/orders.tsv reachable from the page.

    This is the Windows counterpart of StarChef's tools/serve.sh + tsv-editor.sh.
    The editor HTML itself is byte-identical to StarChef's and knows nothing
    about either game — it reads any TSV, infers its columns and types, and
    preserves the comment preamble that is two thirds of what these tables are.

.PARAMETER Port
    Port to serve on. Default 8777, matching StarChef.

.EXAMPLE
    .\tools\tsv-editor.ps1
#>
param(
	[int]$Port = 8777,
	[string]$Page = "tsv-editor.html"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$pagePath = Join-Path $PSScriptRoot $Page
if (-not (Test-Path $pagePath)) {
	Write-Error "No such tool: tools/$Page"
	exit 1
}

# python, python3 or py — whichever this machine has.
$python = $null
foreach ($candidate in @("python", "python3", "py")) {
	$found = Get-Command $candidate -ErrorAction SilentlyContinue
	if ($found) { $python = $found.Source; break }
}
if (-not $python) {
	Write-Error "Python is needed to serve the repo, and none was found on PATH."
	exit 1
}

$url = "http://localhost:$Port/tools/$Page"
Write-Host "Space Stranding -> $url"
Write-Host "serving $root (ctrl-c to stop)"

$server = Start-Process -FilePath $python `
	-ArgumentList @("-m", "http.server", "$Port", "--bind", "127.0.0.1", "--directory", $root) `
	-NoNewWindow -PassThru

try {
	Start-Sleep -Seconds 1
	Start-Process $url
	Wait-Process -Id $server.Id
}
finally {
	if (-not $server.HasExited) {
		Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
	}
}
