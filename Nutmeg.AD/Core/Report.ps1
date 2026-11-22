# ---------------------------------------------------------------------------
# Report.ps1 - HTML reports (self-contained, print-ready) and their PDF copy
# ---------------------------------------------------------------------------
# A tool describes its report as sections; New-NmHtmlReport writes one HTML file in the toolkit's
# look that needs nothing from the internet (a new DC should not fetch anything) and prints cleanly
# (page breaks, no screen-only parts). ConvertTo-NmPdf prints it to PDF with Edge, headless.
# Section kinds:
#   Facts  - Rows: Name / Value pairs, in a two-column grid.
#   Table  - Columns and Rows; -StatusColumn draws that column as a coloured badge.
#   List   - Items: lines of text (next steps, notes).
# Code files are ASCII only: anything else in a report comes from the data, encoded as entities.

$script:NmReportCss = @'
:root { --ink:#16191F; --muted:#5B6370; --line:#E2E5EA; --teal:#0E6B66; --tealbg:#E3F1EF; }
* { box-sizing: border-box; }
body { margin: 0; background: #F6F7F9; color: var(--ink); font: 14px/1.45 "Segoe UI", system-ui, sans-serif; }
.page { max-width: 1040px; margin: 24px auto; background: #FFFFFF; border: 1px solid var(--line); border-radius: 12px; padding: 32px 40px; }
header { display: flex; align-items: center; gap: 16px; border-bottom: 2px solid var(--teal); padding-bottom: 16px; margin-bottom: 8px; }
.logo { width: 44px; height: 44px; border-radius: 10px; background: var(--teal); color: #FFF; font-weight: 700; font-size: 22px; display: flex; align-items: center; justify-content: center; }
h1 { font-size: 24px; margin: 0; }
.sub { color: var(--muted); margin-top: 2px; }
.meta { margin-left: auto; text-align: right; color: var(--muted); font-size: 12px; }
h2 { font-size: 16px; color: var(--teal); text-transform: uppercase; letter-spacing: .04em; margin: 28px 0 10px; }
.note { color: var(--muted); margin: -4px 0 10px; }
.facts { display: grid; grid-template-columns: 220px 1fr; gap: 6px 16px; }
.facts .n { color: var(--muted); }
table { width: 100%; border-collapse: collapse; }
th { text-align: left; font-size: 12px; color: var(--muted); font-weight: 600; border-bottom: 1px solid var(--line); padding: 6px 8px; }
td { border-bottom: 1px solid #EEF0F3; padding: 7px 8px; vertical-align: top; word-break: break-word; }
tr { page-break-inside: avoid; }
.badge { display: inline-block; border-radius: 10px; padding: 1px 9px; font-size: 12px; font-weight: 600; white-space: nowrap; }
.b-ok { background: #E6F4EA; color: #1F6B35; } .b-warn { background: #FFF4E0; color: #8A4B00; }
.b-bad { background: #FDECEA; color: #A0281C; } .b-info { background: #F1F3F6; color: #3D4450; }
ul { margin: 0; padding-left: 20px; } li { margin: 3px 0; }
footer { margin-top: 32px; padding-top: 12px; border-top: 1px solid var(--line); color: var(--muted); font-size: 12px; }
@page { size: A4; margin: 14mm; }
@media print {
  body { background: #FFFFFF; }
  .page { border: 0; margin: 0; padding: 0; max-width: none; border-radius: 0; }
  h2 { page-break-after: avoid; }
  section { page-break-inside: auto; }
}
'@

function ConvertTo-NmHtmlText {
    # Text made safe for HTML (and anything outside ASCII written as an entity).
    param([AllowNull()][object]$Text)
    $t = [System.Net.WebUtility]::HtmlEncode("$Text")
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $t.ToCharArray()) { if ([int]$ch -gt 126) { [void]$sb.Append("&#$([int]$ch);") } else { [void]$sb.Append($ch) } }
    return $sb.ToString()
}

function Get-NmReportBadgeClass {
    # The badge colour for a status: OK green, warnings amber, failures red, the rest grey.
    param([string]$Status)
    switch (Get-NmReportLevel -Status $Status) { 'OK' { 'b-ok' } 'Medium' { 'b-warn' } 'High' { 'b-bad' } default { 'b-info' } }
}

function Get-NmReportLevel {
    # How a status reads (the same words as the window's badges).
    param([string]$Status)
    $v = "$Status".Trim()
    if ($v -match '^(?i)(failed|failure|error|not ready|missing|stopped|no\b)') { return 'High' }
    if ($v -match '^(?i)(warn|partial|pending|waiting)') { return 'Medium' }
    if ($v -match '^(?i)(ok\b|done|passed|running|yes\b|present|shared|finished|success)') { return 'OK' }
    return 'Info'
}

function New-NmHtmlReport {
    <#
    .SYNOPSIS
        Writes a self-contained HTML report and returns its path.
    .PARAMETER Sections
        Hashtables or objects: Title, Kind (Facts, Table, List), Note, and Rows (Facts: Name/Value;
        Table: objects), Columns and StatusColumn (Table), Items (List).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Subtitle,
        [string[]]$Meta = @(),
        [Parameter(Mandatory)][object[]]$Sections,
        [Parameter(Mandatory)][string]$Path
    )
    $e = { param($x) ConvertTo-NmHtmlText $x }
    $h = New-Object System.Text.StringBuilder
    [void]$h.Append("<!DOCTYPE html>`n<html lang=""en""><head><meta charset=""utf-8""><title>$(& $e $Title)</title>`n<style>$script:NmReportCss</style></head>`n<body><div class=""page"">`n")
    [void]$h.Append("<header><div class=""logo"">N</div><div><h1>$(& $e $Title)</h1>")
    if ($Subtitle) { [void]$h.Append("<div class=""sub"">$(& $e $Subtitle)</div>") }
    [void]$h.Append('</div><div class="meta">')
    [void]$h.Append((@($Meta | ForEach-Object { & $e $_ }) -join '<br>'))
    [void]$h.Append("</div></header>`n")
    foreach ($s in $Sections) {
        [void]$h.Append("<section><h2>$(& $e $s.Title)</h2>")
        if ($s.Note) { [void]$h.Append("<p class=""note"">$(& $e $s.Note)</p>") }
        switch ("$($s.Kind)") {
            'Facts' {
                [void]$h.Append('<div class="facts">')
                foreach ($r in @($s.Rows)) { [void]$h.Append("<div class=""n"">$(& $e $r.Name)</div><div>$(& $e $r.Value)</div>") }
                [void]$h.Append('</div>')
            }
            'List' {
                [void]$h.Append('<ul>')
                foreach ($i in @($s.Items)) { [void]$h.Append("<li>$(& $e $i)</li>") }
                [void]$h.Append('</ul>')
            }
            default {
                $cols = @($s.Columns)
                if (-not $cols.Count -and @($s.Rows).Count) { $cols = @(@($s.Rows)[0].PSObject.Properties.Name) }
                [void]$h.Append('<table><thead><tr>')
                foreach ($c in $cols) { [void]$h.Append("<th>$(& $e $c)</th>") }
                [void]$h.Append('</tr></thead><tbody>')
                foreach ($r in @($s.Rows)) {
                    [void]$h.Append('<tr>')
                    foreach ($c in $cols) {
                        $v = $r.$c
                        if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) { $v = @($v) -join ', ' }
                        if ($s.StatusColumn -and $c -eq $s.StatusColumn -and "$v") {
                            [void]$h.Append("<td><span class=""badge $(Get-NmReportBadgeClass -Status "$v")"">$(& $e $v)</span></td>")
                        } else { [void]$h.Append("<td>$(& $e $v)</td>") }
                    }
                    [void]$h.Append('</tr>')
                }
                [void]$h.Append('</tbody></table>')
            }
        }
        [void]$h.Append("</section>`n")
    }
    [void]$h.Append("<footer>Nutmeg AD Toolkit $(& $e $script:ModuleVersion) &middot; $(& $e (Get-Date).ToString('yyyy-MM-dd HH:mm'))</footer>`n</div></body></html>`n")
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $h.ToString(), (New-Object System.Text.UTF8Encoding $false))
    return $Path
}

function Get-NmReportFolder {
    # Where reports go: <DataRoot>\Reports (C:\Temp\NutmegAD\Reports).
    return (Join-Path $script:NmConfig.DataRoot 'Reports')
}

function Find-NmEdge {
    # The path of Microsoft Edge (msedge.exe), or '' when it is not installed.
    [CmdletBinding()]
    [OutputType([string])]
    param()
    foreach ($root in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if (-not $root) { continue }
        $p = Join-Path $root 'Microsoft\Edge\Application\msedge.exe'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return ''
}

function Invoke-NmEdgePdf {
    # Runs Edge headless to print one HTML file to PDF; returns the exit code (a seam for tests).
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Edge, [Parameter(Mandatory)][string]$HtmlPath, [Parameter(Mandatory)][string]$PdfPath, [int]$TimeoutSeconds = 90)
    $uri = ([System.Uri](Resolve-Path -LiteralPath $HtmlPath).ProviderPath).AbsoluteUri
    $profileDir = Join-Path ([System.IO.Path]::GetTempPath()) ('NmEdge_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $edgeArgs = @('--headless=new', '--disable-gpu', '--no-first-run', '--no-pdf-header-footer', "--user-data-dir=`"$profileDir`"", "--print-to-pdf=`"$PdfPath`"", "`"$uri`"")
    $p = Start-Process -FilePath $Edge -ArgumentList $edgeArgs -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) { try { $p.Kill() } catch { $null = $_ }; return -1 }
    Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue
    return $p.ExitCode
}

function ConvertTo-NmPdf {
    <#
    .SYNOPSIS
        The PDF copy of an HTML report, printed by Edge (headless). Returns the PDF's path, or '' when
        Edge is not there or did not make it (the HTML report is still there to print by hand).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$HtmlPath, [string]$PdfPath)
    if (-not $PdfPath) { $PdfPath = [System.IO.Path]::ChangeExtension($HtmlPath, '.pdf') }
    $edge = Find-NmEdge
    if (-not $edge) { Write-NmLog 'No PDF copy: Microsoft Edge is not installed. Print the HTML report to PDF instead.' -Level WARN; return '' }
    try {
        $null = Invoke-NmEdgePdf -Edge $edge -HtmlPath $HtmlPath -PdfPath $PdfPath
    } catch { Write-NmLog "No PDF copy: $($_.Exception.Message)" -Level WARN; return '' }
    if (Test-Path -LiteralPath $PdfPath) { return $PdfPath }
    Write-NmLog 'No PDF copy: Edge did not write one. Print the HTML report to PDF instead.' -Level WARN
    return ''
}
