# Comprehensive lap analysis script
# This extracts unique GPS positions (reducing duplicates) and analyzes lap quality

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

function Analyze-LapFile-Detailed {
    param($FilePath)

    $fileName = Split-Path $FilePath -Leaf
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "Analyzing: $fileName" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan

    try {
        $data = Import-Csv $FilePath
        Write-Host "Total rows: $($data.Count)"

        # Filter valid GPS
        $validData = $data | Where-Object {
            $_.latitude -and $_.longitude -and
            $_.latitude -ne "0" -and $_.longitude -ne "0" -and
            $_.latitude -ne "" -and $_.longitude -ne "" -and
            [double]$_.latitude -ne 0 -and [double]$_.longitude -ne 0
        }

        Write-Host "Valid GPS rows: $($validData.Count)"

        if ($validData.Count -lt 50) {
            Write-Host "ERROR: Insufficient GPS data" -ForegroundColor Red
            return $null
        }

        # Get unique positions (reduce duplicate stationary points)
        $unique = Get-UniqueGPSPositions $validData -minDistance 1.5
        Write-Host "Unique GPS positions (1.5m spacing): $($unique.Count)"

        $startLat = [double]$unique[0].latitude
        $startLon = [double]$unique[0].longitude
        Write-Host "Start: $startLat, $startLon"

        # Find where car returns close to start
        $lapEndIndex = -1
        $bestClosureDist = 999999

        for ($i = 30; $i -lt $unique.Count; $i++) {
            $lat = [double]$unique[$i].latitude
            $lon = [double]$unique[$i].longitude
            $dist = Get-Distance $startLat $startLon $lat $lon

            # Look for first return within 30m after moving at least 30 points
            if ($dist -lt 30 -and $i -gt 30) {
                $lapEndIndex = $i
                $bestClosureDist = $dist
                break
            }
        }

        # If no lap within 30m, try 50m
        if ($lapEndIndex -eq -1) {
            for ($i = 30; $i -lt $unique.Count; $i++) {
                $lat = [double]$unique[$i].latitude
                $lon = [double]$unique[$i].longitude
                $dist = Get-Distance $startLat $startLon $lat $lon

                if ($dist -lt 50 -and $i -gt 30) {
                    $lapEndIndex = $i
                    $bestClosureDist = $dist
                    break
                }
            }
        }

        # If still no lap, try 100m
        if ($lapEndIndex -eq -1) {
            for ($i = 30; $i -lt $unique.Count; $i++) {
                $lat = [double]$unique[$i].latitude
                $lon = [double]$unique[$i].longitude
                $dist = Get-Distance $startLat $startLon $lat $lon

                if ($dist -lt 100 -and $i -gt 30) {
                    $lapEndIndex = $i
                    $bestClosureDist = $dist
                    break
                }
            }
        }

        if ($lapEndIndex -eq -1) {
            Write-Host "No complete lap found (tried 30m, 50m, 100m thresholds)" -ForegroundColor Yellow
            Write-Host "Last position: $([double]$unique[-1].latitude), $([double]$unique[-1].longitude)"
            $endDist = Get-Distance $startLat $startLon ([double]$unique[-1].latitude) ([double]$unique[-1].longitude)
            Write-Host "Distance from start to end: $($endDist.ToString('F2'))m"
            return $null
        }

        Write-Host "Lap completes at index $lapEndIndex with closure: $($bestClosureDist.ToString('F2'))m" -ForegroundColor Green

        $lapData = $unique[0..$lapEndIndex]

        # Calculate quality metrics
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
        $minJump = ($jumps | Measure-Object -Minimum).Minimum
        $variance = ($jumps | ForEach-Object { ($_ - $avgJump) * ($_ - $avgJump) } | Measure-Object -Sum).Sum / $jumps.Count
        $stdJump = [Math]::Sqrt($variance)

        # Speed analysis
        $speeds = $lapData | ForEach-Object {
            if ($_.speed) { [double]$_.speed } else { 0 }
        } | Where-Object { $_ -gt 0 }

        $avgSpeed = if ($speeds.Count -gt 0) { ($speeds | Measure-Object -Average).Average } else { 0 }
        $maxSpeed = if ($speeds.Count -gt 0) { ($speeds | Measure-Object -Maximum).Maximum } else { 0 }

        # Total path length
        $totalLength = ($jumps | Measure-Object -Sum).Sum

        Write-Host ""
        Write-Host "LAP STATISTICS:" -ForegroundColor Green
        Write-Host "  Points in lap: $($lapData.Count)"
        Write-Host "  Loop closure: $($bestClosureDist.ToString('F2'))m"
        Write-Host "  Total path length: $($totalLength.ToString('F2'))m"
        Write-Host "  GPS jumps - Avg: $($avgJump.ToString('F2'))m, Min: $($minJump.ToString('F2'))m, Max: $($maxJump.ToString('F2'))m"
        Write-Host "  GPS jump std dev: $($stdJump.ToString('F2'))m"
        Write-Host "  Speed - Avg: $($avgSpeed.ToString('F2')), Max: $($maxSpeed.ToString('F2'))"

        # Quality score (higher is better)
        $score = 0
        $score += $lapData.Count * 10  # More points is better
        $score -= $bestClosureDist * 5  # Better closure is better
        $score -= $stdJump * 2  # More consistent spacing is better
        $score -= ([Math]::Abs($avgJump - 2.5) * 3)  # Prefer ~2.5m average spacing
        if ($maxJump -gt 50) { $score -= 500 }  # Penalize large jumps (GPS errors)
        if ($maxJump -gt 100) { $score -= 1000 }
        if ($avgSpeed -lt 3) { $score -= 200 }  # Penalize if car barely moved
        $score += $totalLength / 10  # Longer lap is better

        Write-Host "  Quality Score: $($score.ToString('F1'))" -ForegroundColor Magenta

        return @{
            FileName = $fileName
            NumPoints = $lapData.Count
            ClosureDistance = $bestClosureDist
            TotalLength = $totalLength
            AvgJump = $avgJump
            MinJump = $minJump
            MaxJump = $maxJump
            StdJump = $stdJump
            AvgSpeed = $avgSpeed
            MaxSpeed = $maxSpeed
            Score = $score
            LapData = $lapData
        }

    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Main
$basePath = "c:\Users\Juju\Desktop\shell - Copy\dashboardPSU_ECOteam"
$files = @(
    "$basePath\Mishal29dec01-uni.csv",
    "$basePath\Ahmed24Dec-uni.csv",
    "$basePath\Mishal25Dec-uni.csv",
    "$basePath\Ahmed25Dec-uni.csv",
    "$basePath\Aziz27Dec -uni.csv",
    "$basePath\data\2025\practice1\inuniithink1.csv",
    "$basePath\data\2025\practice1\inuniithink2.csv"
)

Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "COMPREHENSIVE UNIVERSITY TEST DRIVE LAP ANALYSIS" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta

$results = @()
foreach ($file in $files) {
    if (Test-Path $file) {
        $result = Analyze-LapFile-Detailed $file
        if ($result) { $results += $result }
    } else {
        Write-Host ""
        Write-Host "WARNING: File not found: $file" -ForegroundColor Yellow
    }
}

if ($results.Count -eq 0) {
    Write-Host ""
    Write-Host "No valid laps found!" -ForegroundColor Red
    exit
}

Write-Host ""
Write-Host "========================================================================"  -ForegroundColor Magenta
Write-Host "COMPARISON TABLE" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host ""

$fmt = "{0,-30} {1,7} {2,9} {3,10} {4,9} {5,9} {6,9} {7,10} {8,10}"
Write-Host ($fmt -f "File", "Points", "Closure", "Length", "AvgJump", "MaxJump", "StdJump", "AvgSpeed", "Score")
Write-Host ("-" * 130)

foreach ($r in $results | Sort-Object Score -Descending) {
    Write-Host ($fmt -f `
        $r.FileName, `
        $r.NumPoints, `
        "$($r.ClosureDistance.ToString('F1'))m", `
        "$($r.TotalLength.ToString('F0'))m", `
        "$($r.AvgJump.ToString('F1'))m", `
        "$($r.MaxJump.ToString('F1'))m", `
        "$($r.StdJump.ToString('F1'))m", `
        $r.AvgSpeed.ToString('F1'), `
        $r.Score.ToString('F0'))
}

$best = $results | Sort-Object Score -Descending | Select-Object -First 1

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "RECOMMENDATION" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "MOST ACCURATE LAP: $($best.FileName)" -ForegroundColor Green
Write-Host "  Points: $($best.NumPoints)"
Write-Host "  Closure quality: $($best.ClosureDistance.ToString('F2'))m"
Write-Host "  Total track length: $($best.TotalLength.ToString('F2'))m"
Write-Host "  GPS consistency (std): $($best.StdJump.ToString('F2'))m"
Write-Host "  Max GPS jump: $($best.MaxJump.ToString('F2'))m"
Write-Host "  Average speed: $($best.AvgSpeed.ToString('F2'))"
Write-Host "  Quality score: $($best.Score.ToString('F1'))"

# Save coordinates
$coords = @()
foreach ($row in $best.LapData) {
    $coords += ,@([double]$row.latitude, [double]$row.longitude)
}

$jsonPath = "c:\Users\Juju\Desktop\shell - Copy\best_lap_output.json"
@{
    source_file = $best.FileName
    analysis = @{
        num_points = $best.NumPoints
        closure_distance_m = [Math]::Round($best.ClosureDistance, 2)
        total_length_m = [Math]::Round($best.TotalLength, 2)
        avg_jump_m = [Math]::Round($best.AvgJump, 2)
        max_jump_m = [Math]::Round($best.MaxJump, 2)
        std_jump_m = [Math]::Round($best.StdJump, 2)
        avg_speed = [Math]::Round($best.AvgSpeed, 2)
        max_speed = [Math]::Round($best.MaxSpeed, 2)
        quality_score = [Math]::Round($best.Score, 1)
    }
    coordinates = $coords
} | ConvertTo-Json -Depth 10 | Out-File $jsonPath -Encoding UTF8

Write-Host ""
Write-Host "Saved to: $jsonPath" -ForegroundColor Cyan

# JavaScript format
$jsPath = "c:\Users\Juju\Desktop\shell - Copy\best_track_outline.js"
$js = "// Best track outline from: $($best.FileName)`n"
$js += "// Points: $($best.NumPoints), Closure: $($best.ClosureDistance.ToString('F2'))m`n"
$js += "const trackOutline = [`n"
for ($i = 0; $i -lt $coords.Count; $i++) {
    $comma = if ($i -lt $coords.Count - 1) { "," } else { "" }
    $js += "  [$($coords[$i][0]), $($coords[$i][1])]$comma`n"
}
$js += "];`n"
$js | Out-File $jsPath -Encoding UTF8

Write-Host "JavaScript saved to: $jsPath" -ForegroundColor Cyan

# Compare with current (Aziz)
$aziz = $results | Where-Object { $_.FileName -eq "Aziz27Dec -uni.csv" }
if ($aziz) {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Magenta
    Write-Host "COMPARISON WITH AZIZ27DEC (CURRENT FILE)" -ForegroundColor Magenta
    Write-Host "========================================================================" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "Aziz27Dec -uni.csv:"
    Write-Host "  Points: $($aziz.NumPoints)"
    Write-Host "  Closure: $($aziz.ClosureDistance.ToString('F2'))m"
    Write-Host "  Length: $($aziz.TotalLength.ToString('F2'))m"
    Write-Host "  GPS std: $($aziz.StdJump.ToString('F2'))m"
    Write-Host "  Score: $($aziz.Score.ToString('F1'))"
    Write-Host ""

    if ($best.FileName -eq "Aziz27Dec -uni.csv") {
        Write-Host "VERDICT: Aziz27Dec IS the best lap!" -ForegroundColor Green
    } else {
        Write-Host "VERDICT: $($best.FileName) is BETTER" -ForegroundColor Yellow
        Write-Host "  +$($best.NumPoints - $aziz.NumPoints) more points"
        Write-Host "  Closure improved by $([Math]::Round($aziz.ClosureDistance - $best.ClosureDistance, 2))m"
        Write-Host "  Score improved by $([Math]::Round($best.Score - $aziz.Score, 1))"
    }
}

# Compare with current script.js outline (56 points)
Write-Host ""
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "COMPARISON WITH CURRENT SCRIPT.JS OUTLINE" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "Current script.js has 56 points from Aziz27Dec file"
Write-Host "Best lap found has $($best.NumPoints) points"
Write-Host ""
if ($best.NumPoints -gt 56) {
    Write-Host "Recommendation: UPDATE script.js with the new lap ($($best.NumPoints - 56) more points)" -ForegroundColor Green
} elseif ($best.NumPoints -lt 56) {
    Write-Host "Current outline has more points, but check quality score" -ForegroundColor Yellow
} else {
    Write-Host "Same number of points - compare quality metrics" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "Analysis complete!" -ForegroundColor Green