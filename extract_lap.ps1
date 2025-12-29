# Function to calculate Haversine distance in meters
function Get-Distance {
    param(
        [double]$lat1,
        [double]$lon1,
        [double]$lat2,
        [double]$lon2
    )

    $R = 6371000  # Earth radius in meters
    $phi1 = [Math]::PI * $lat1 / 180
    $phi2 = [Math]::PI * $lat2 / 180
    $deltaPhi = [Math]::PI * ($lat2 - $lat1) / 180
    $deltaLambda = [Math]::PI * ($lon2 - $lon1) / 180

    $a = [Math]::Sin($deltaPhi/2) * [Math]::Sin($deltaPhi/2) +
         [Math]::Cos($phi1) * [Math]::Cos($phi2) *
         [Math]::Sin($deltaLambda/2) * [Math]::Sin($deltaLambda/2)
    $c = 2 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1-$a))

    return $R * $c
}

Write-Host "Reading CSV file..."
$csvPath = "c:\Users\Juju\Desktop\shell - Copy\dashboardPSU_ECOteam\Aziz27Dec -uni.csv"
$data = Import-Csv $csvPath

Write-Host "Total rows: $($data.Count)"

# Filter for moving points with valid GPS coordinates (speed > 1 km/h and GPS changing)
$movingPoints = @()
$lastLat = $null
$lastLon = $null

foreach ($row in $data) {
    $speed = [double]$row.speed
    $lat = [double]$row.latitude
    $lon = [double]$row.longitude

    # Only add if speed > 1 AND GPS coordinates have changed
    if ($speed -gt 1.0) {
        # Skip duplicate GPS positions
        if ($lastLat -eq $null -or [Math]::Abs($lat - $lastLat) -gt 0.000001 -or [Math]::Abs($lon - $lastLon) -gt 0.000001) {
            $movingPoints += [PSCustomObject]@{
                Latitude = $lat
                Longitude = $lon
            }
            $lastLat = $lat
            $lastLon = $lon
        }
    }
}

Write-Host "Found $($movingPoints.Count) moving points"

if ($movingPoints.Count -lt 50) {
    Write-Host "Not enough moving points!"
    exit 1
}

# Get starting position
$startLat = $movingPoints[0].Latitude
$startLon = $movingPoints[0].Longitude
Write-Host "Start position: ($startLat, $startLon)"

# Find the end of one lap (when car returns close to start)
$proximityThreshold = 25  # meters
$lapPoints = @($movingPoints[0])

for ($i = 1; $i -lt $movingPoints.Count; $i++) {
    $point = $movingPoints[$i]
    $lapPoints += $point

    # Check if we've returned to start (skip first 50 points)
    if ($i -gt 50) {
        $distance = Get-Distance -lat1 $point.Latitude -lon1 $point.Longitude -lat2 $startLat -lon2 $startLon
        if ($distance -lt $proximityThreshold) {
            Write-Host "Completed lap at point $i, distance to start: $([Math]::Round($distance, 2))m"
            break
        }
    }
}

Write-Host "Lap contains $($lapPoints.Count) points"

# Sample evenly spaced points (target: 55 points)
$targetPoints = 55
$sampledPoints = @()

if ($lapPoints.Count -gt $targetPoints) {
    $step = [double]$lapPoints.Count / $targetPoints
    for ($i = 0; $i -lt $targetPoints; $i++) {
        $idx = [Math]::Floor($i * $step)
        if ($idx -lt $lapPoints.Count) {
            $sampledPoints += $lapPoints[$idx]
        }
    }
} else {
    $sampledPoints = $lapPoints
}

# Ensure loop is closed
$firstPoint = $sampledPoints[0]
$lastPoint = $sampledPoints[$sampledPoints.Count - 1]
if ($firstPoint.Latitude -ne $lastPoint.Latitude -or $firstPoint.Longitude -ne $lastPoint.Longitude) {
    $sampledPoints += $firstPoint
}

Write-Host "Sampled to $($sampledPoints.Count) points"

# Calculate center
$avgLat = ($sampledPoints | Measure-Object -Property Latitude -Average).Average
$avgLon = ($sampledPoints | Measure-Object -Property Longitude -Average).Average

Write-Host ""
Write-Host "============================================================"
Write-Host "JAVASCRIPT OUTPUT:"
Write-Host "============================================================"
Write-Host ""
Write-Host "outline: ["
foreach ($point in $sampledPoints) {
    Write-Host "    [$($point.Latitude), $($point.Longitude)],"
}
Write-Host "]"
Write-Host ""
Write-Host "center: [$avgLat, $avgLon]"
Write-Host "============================================================"

# Also save to file
$outputPath = "c:\Users\Juju\Desktop\shell - Copy\track_outline.txt"
$output = "outline: [`n"
foreach ($point in $sampledPoints) {
    $output += "    [$($point.Latitude), $($point.Longitude)],`n"
}
$output += "]`n`n"
$output += "center: [$avgLat, $avgLon]`n"

$output | Out-File -FilePath $outputPath -Encoding UTF8
Write-Host ""
Write-Host "Output also saved to: $outputPath"