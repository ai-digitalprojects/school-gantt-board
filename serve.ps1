# מפעיל שרת מקומי קטן כדי שהלוח יוכל למשוך נתונים מגוגל.
# גוגל חוסמת משיכת נתונים מדף שנפתח ישירות מהדיסק (file://), אך מאשרת כתובת מקומית.
# אין צורך בהתקנה כלשהי - PowerShell מובנה בכל מחשב Windows.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 8731

# אם הפורט תפוס, מחפשים פורט פנוי אחר
while ($true) {
    $busy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $busy) { break }
    $port++
    if ($port -gt 8760) { throw 'no free port' }
}

$prefix = "http://localhost:$port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host ''
Write-Host '  Gantt board is running at ' -NoNewline
Write-Host $prefix -ForegroundColor Cyan
Write-Host '  Keep this window open while using the board.'
Write-Host '  Close this window (or press Ctrl+C) to stop.'
Write-Host ''

Start-Process $prefix

$types = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.csv'  = 'text/csv; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $rel = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
        if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }

        $full = Join-Path $root $rel
        $resolvedRoot = (Resolve-Path $root).Path

        $ok = $false
        if (Test-Path -LiteralPath $full -PathType Leaf) {
            # לא לצאת מחוץ לתיקיית הלוח
            $resolved = (Resolve-Path -LiteralPath $full).Path
            if ($resolved.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)) {
                $ok = $true
                $full = $resolved
            }
        }

        if ($ok) {
            $ext = [System.IO.Path]::GetExtension($full).ToLower()
            $ctx.Response.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' }
            $bytes = [System.IO.File]::ReadAllBytes($full)
            $ctx.Response.StatusCode = 200
        } else {
            $ctx.Response.StatusCode = 404
            $ctx.Response.ContentType = 'text/plain; charset=utf-8'
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('404')
        }

        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.OutputStream.Close()
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
