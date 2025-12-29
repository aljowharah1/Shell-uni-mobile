# Extract the best lap from Aziz27Dec file (confirmed as best)

function Get-Distance {
    param($lat1, $lon1, $lat2, $lon2)
    $R = 6371000
    $phi1 = [Math]::PI * $lat1 / 180
    $phi2 = [Math]::PI * $lat2 / 180
    $dphi = [Math]::PI * ($lat2 - $lat1) / 180
    $dlambda = [Math]::PI * ($lon2 - $lon1) / 180
    $a = [Math]::Sin($dphi/2) * [Math]::Sin($dphi/2) + [Math]::Cos($phi1) * [Math]::Cos($phi2) * [Math]::Sin($dlambda/2) * [Math]::Sin($dlambda/2)
    $c = 2 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1-$a))
    return $R * $c
}

function Get-UniqueGPSPositions {
    param($data, $minDistance = 1.5)
    $unique = @()
    $lastLat = $null
    $lastLon = $null

    foreach ($row in $data) {
        $lat = [double]$row.latitude
        $lon = [double]$row.longitude

        if ($lastLat -eq $null) {
            $unique += $row
            $lastLat = $lat
            $lastLon = $lon
        } else {
            $dist = Get-Distance $lastLat $lastLon $lat $lon
            if ($dist -ge $minDistance) {
                $unique += $row
                $lastLat = $lat
                $lastLon = $lon
            }
        }
    }
    return $unique
}

$file = "c:\Users\Juju\Desktop\shell - Copy\dashboardPSU_ECOteam\Aziz27Dec -uni.csv"

Write-Host "Extracting best lap from Aziz27Dec -uni.csv..." -ForegroundColor Cyan

$data = Import-Csv $file
$validData = $data | Where-Object {
    $_.latitude -and $_.longitude -and
    $_.latitude -ne "0" -and $_.longitude -ne "0" -and
    $_.latitude -ne "" -and $_.longitude -ne "" -and
    [double]$_.latitude -ne 0 -and [double]$_.longitude -ne 0
}

$unique = Get-UniqueGPSPositions $validData -minDistance 1.5
Write-Host "Unique GPS positions: $($unique.Count)"

$startLat = [double]$unique[0].latitude
$startLon = [double]$unique[0].longitude

# Find lap completion
$lapEndIndex = -1
for ($i = 30; $i -lt $unique.Count; $i++) {
    $lat = [double]$unique[$i].latitude
    $lon = [double]$unique[$i].longitude
    $dist = Get-Distance $startLat $startLon $lat $lon

    if ($dist -lt 30) {
        $lapEndIndex = $i
        Write-Host "Lap completes at index $i with closure: $($dist.ToString('F2'))m"
        break
    }
}

$lapData = $unique[0..$lapEndIndex]
Write-Host "Lap has $($lapData.Count) points"

# Extract coordinates
$coords = @()
foreach ($row in $lapData) {
    $coords += ,@([double]$row.latitude, [double]$row.longitude)
}

# Calculate metrics
$jumps = @()
for ($i = 1; $i -lt $lapData.Count; $i++) {
    $lat1 = [double]$lapData[$i-1].latitude
    $lon1 = [double]$lapData[$i-1].longitude
    $lat2 = [double]$lapData[$i].latitude
    $lon2 = [double]$lapData[$i].longitude
    $jump = Get-Distance $lat1 $lon1 $lat2 $lon2
    $jumps += $jump
}

$avgJump = ($jumps | Measure-Object -Average).Average
$maxJump = ($jumps | Measure-Object -Maximum).Maximum
$stdJump = [Math]::Sqrt((($jumps | ForEach-Object { ($_ - $avgJump) * ($_ - $avgJump) } | Measure-Object -Sum).Sum) / $jumps.Count)
$totalLength = ($jumps | Measure-Object -Sum).Sum
$closureDist = Get-Distance $startLat $startLon ([double]$lapData[-1].latitude) ([double]$lapData[-1].longitude)

Write-Host ""
Write-Host "LAP METRICS:" -ForegroundColor Green
Write-Host "  Points: $($lapData.Count)"
Write-Host "  Closure: $($closureDist.ToString('F2'))m"
Write-Host "  Total length: $($totalLength.ToString('F2'))m"
Write-Host "  Avg GPS jump: $($avgJump.ToString('F2'))m"
Write-Host "  Max GPS jump: $($maxJump.ToString('F2'))m"
Write-Host "  Std GPS jump: $($stdJump.ToString('F2'))m"

# Save JSON
$jsonPath = "c:\Users\Juju\Desktop\shell - Copy\aziz_best_lap.json"
@{
    source_file = "Aziz27Dec -uni.csv"
    analysis = @{
        num_points = $lapData.Count
        closure_distance_m = [Math]::Round($closureDist, 2)
        total_length_m = [Math]::Round($totalLength, 2)
        avg_jump_m = [Math]::Round($avgJump, 2)
        max_jump_m = [Math]::Round($maxJump, 2)
        std_jump_m = [Math]::Round($stdJump, 2)
    }
    coordinates = $coords
} | ConvertTo-Json -Depth 10 | Out-File $jsonPath -Encoding UTF8

Write-Host ""
Write-Host "Saved to: $jsonPath" -ForegroundColor Cyan

# JavaScript format
$jsPath = "c:\Users\Juju\Desktop\shell - Copy\aziz_track_outline.js"
$js = "// Best track outline from: Aziz27Dec -uni.csv`n"
$js += "// Points: $($lapData.Count), Closure: $($closureDist.ToString('F2'))m, Length: $($totalLength.ToString('F0'))m`n"
$js += "const trackOutline = [`n"
for ($i = 0; $i -lt $coords.Count; $i++) {
    $comma = if ($i -lt $coords.Count - 1) { "," } else { "" }
    $js += "  [$($coords[$i][0]), $($coords[$i][1])]$comma`n"
}
$js += "];`n"
$js | Out-File $jsPath -Encoding UTF8

Write-Host "JavaScript saved to: $jsPath" -ForegroundColor Cyan

# Compare with current script.js (56 points)
Write-Host ""
Write-Host "COMPARISON WITH CURRENT SCRIPT.JS:" -ForegroundColor Magenta
Write-Host "  Current: 56 points"
Write-Host "  New: $($lapData.Count) points"
Write-Host "  Difference: +$($lapData.Count - 56) points"
Write-Host ""
if ($lapData.Count -gt 56) {
    Write-Host "RECOMMENDATION: The new lap has MORE points and better coverage!" -ForegroundColor Green
} else {
    Write-Host "Current lap has more points." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done!" -ForegroundColor Green