# PowerShell script to analyze lap data from university test drive files

function Get-Distance {
    param($lat1, $lon1, $lat2, $lon2)

    $R = 6371000  # Earth radius in meters
    $phi1 = [Math]::PI * $lat1 / 180
    $phi2 = [Math]::PI * $lat2 / 180
    $dphi = [Math]::PI * ($lat2 - $lat1) / 180
    $dlambda = [Math]::PI * ($lon2 - $lon1) / 180

    $a = [Math]::Sin($dphi/2) * [Math]::Sin($dphi/2) + `
         [Math]::Cos($phi1) * [Math]::Cos($phi2) * `
         [Math]::Sin($dlambda/2) * [Math]::Sin($dlambda/2)

    $c = 2 * [Math]::Atan2([Math]::Sqrt($a), [Math]::Sqrt(1-$a))

    return $R * $c
}

function Analyze-LapFile {
    param($FilePath)

    $fileName = Split-Path $FilePath -Leaf
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "Analyzing: $fileName" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan

    # Read CSV file
    try {
        $data = Import-Csv $FilePath
        $totalLines = $data.Count
        Write-Host "Total lines: $totalLines"

        # Filter valid GPS data
        $validData = $data | Where-Object {
            $_.latitude -ne "0" -and $_.longitude -ne "0" -and `
            $_.latitude -ne $null -and $_.longitude -ne $null -and `
            $_.latitude -ne "" -and $_.longitude -ne ""
        }

        $validPoints = $validData.Count
        Write-Host "Valid GPS points: $validPoints"

        if ($validPoints -lt 50) {
            Write-Host "ERROR: Insufficient valid GPS data" -ForegroundColor Red
            return $null
        }

        # Get starting position
        $startLat = [double]$validData[0].latitude
        $startLon = [double]$validData[0].longitude
        Write-Host "Starting position: $startLat, $startLon"

        # Find lap completion points
        $lapIndices = @()
        for ($i = 50; $i -lt $validPoints; $i++) {
            $lat = [double]$validData[$i].latitude
            $lon = [double]$validData[$i].longitude
            $dist = Get-Distance $startLat $startLon $lat $lon

            if ($dist -lt 50) {
                $lapIndices += $i
            }
        }

        Write-Host "Found $($lapIndices.Count) potential lap completion points"

        if ($lapIndices.Count -eq 0) {
            # Try with larger threshold
            for ($i = 50; $i -lt $validPoints; $i++) {
                $lat = [double]$validData[$i].latitude
                $lon = [double]$validData[$i].longitude
                $dist = Get-Distance $startLat $startLon $lat $lon

                if ($dist -lt 100) {
                    $lapIndices += $i
                }
            }

            Write-Host "Found $($lapIndices.Count) potential lap completion points (100m threshold)"
        }

        if ($lapIndices.Count -eq 0) {
            Write-Host "No complete lap found" -ForegroundColor Yellow
            return $null
        }

        # Use the first lap completion
        $lapEnd = $lapIndices[0]
        $lapData = $validData[0..$lapEnd]

        Write-Host "Best lap ends at point: $lapEnd"
        Write-Host ""
        Write-Host "LAP STATISTICS:" -ForegroundColor Green

        # Calculate GPS jumps
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

        # Calculate closure distance
        $endLat = [double]$lapData[-1].latitude
        $endLon = [double]$lapData[-1].longitude
        $closureDist = Get-Distance $startLat $startLon $endLat $endLon

        # Calculate average speed
        $avgSpeed = 0
        if ($lapData[0].PSObject.Properties.Name -contains "speed") {
            $speeds = $lapData | ForEach-Object { [double]$_.speed } | Where-Object { $_ -gt 0 }
            if ($speeds.Count -gt 0) {
                $avgSpeed = ($speeds | Measure-Object -Average).Average
            }
        }

        Write-Host "  Number of points: $($lapData.Count)"
        Write-Host "  Loop closure distance: $($closureDist.ToString('F2')) m"
        Write-Host "  Average GPS jump: $($avgJump.ToString('F2')) m"
        Write-Host "  Max GPS jump: $($maxJump.ToString('F2')) m"
        Write-Host "  Std GPS jump: $($stdJump.ToString('F2')) m"
        Write-Host "  Average speed: $($avgSpeed.ToString('F2'))"

        # Calculate composite score
        $score = ($lapData.Count * 5) - ($closureDist * 2) - $stdJump - ([Math]::Abs($avgJump - 20) * 0.5)
        if ($maxJump -gt 150) { $score -= 500 }
        if ($closureDist -gt 50) { $score -= 200 }

        Write-Host ""

        return @{
            FileName = $fileName
            NumPoints = $lapData.Count
            ClosureDistance = $closureDist
            AvgJump = $avgJump
            MaxJump = $maxJump
            StdJump = $stdJump
            AvgSpeed = $avgSpeed
            Score = $score
            LapData = $lapData
        }

    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Main execution
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
Write-Host "UNIVERSITY TEST DRIVE LAP ANALYSIS" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host ""

$results = @()

foreach ($file in $files) {
    if (Test-Path $file) {
        $result = Analyze-LapFile $file
        if ($result -ne $null) {
            $results += $result
        }
    } else {
        Write-Host "WARNING: File not found: $file" -ForegroundColor Yellow
        Write-Host ""
    }
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "COMPARISON SUMMARY" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host ""

if ($results.Count -eq 0) {
    Write-Host "No valid laps found in any file!" -ForegroundColor Red
    exit
}

# Display comparison table
$format = "{0,-35} {1,8} {2,10} {3,10} {4,10} {5,10} {6,10} {7,10}"
Write-Host ($format -f "File Name", "Points", "Closure", "Avg Jump", "Max Jump", "Std Jump", "Avg Speed", "Score")
Write-Host ("-" * 120)

foreach ($result in $results | Sort-Object Score -Descending) {
    Write-Host ($format -f `
        $result.FileName, `
        $result.NumPoints, `
        $result.ClosureDistance.ToString("F2"), `
        $result.AvgJump.ToString("F2"), `
        $result.MaxJump.ToString("F2"), `
        $result.StdJump.ToString("F2"), `
        $result.AvgSpeed.ToString("F2"), `
        $result.Score.ToString("F1"))
}

# Find best lap
$best = $results | Sort-Object Score -Descending | Select-Object -First 1

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host "RECOMMENDATION" -ForegroundColor Magenta
Write-Host "========================================================================" -ForegroundColor Magenta
Write-Host ""
Write-Host "MOST ACCURATE LAP: $($best.FileName)" -ForegroundColor Green
Write-Host "  - Number of GPS points: $($best.NumPoints)"
Write-Host "  - Loop closure quality: $($best.ClosureDistance.ToString('F2')) m (closer to 0 is better)"
Write-Host "  - GPS consistency (avg jump): $($best.AvgJump.ToString('F2')) m"
Write-Host "  - GPS consistency (std jump): $($best.StdJump.ToString('F2')) m"
Write-Host "  - Max GPS jump: $($best.MaxJump.ToString('F2')) m"
Write-Host "  - Average speed: $($best.AvgSpeed.ToString('F2'))"
Write-Host "  - Composite score: $($best.Score.ToString('F1'))"

# Save best lap coordinates to JSON
$coords = @()
foreach ($row in $best.LapData) {
    $coords += ,@([double]$row.latitude, [double]$row.longitude)
}

$output = @{
    filename = $best.FileName
    num_points = $best.NumPoints
    closure_distance_m = [Math]::Round($best.ClosureDistance, 2)
    avg_jump_m = [Math]::Round($best.AvgJump, 2)
    max_jump_m = [Math]::Round($best.MaxJump, 2)
    std_jump_m = [Math]::Round($best.StdJump, 2)
    avg_speed = [Math]::Round($best.AvgSpeed, 2)
    score = [Math]::Round($best.Score, 2)
    coordinates = $coords
}

$jsonPath = "c:\Users\Juju\Desktop\shell - Copy\best_lap_analysis.json"
$output | ConvertTo-Json -Depth 10 | Out-File $jsonPath -Encoding UTF8

Write-Host ""
Write-Host "Best lap data saved to: $jsonPath" -ForegroundColor Cyan

# Save JavaScript format
$jsPath = "c:\Users\Juju\Desktop\shell - Copy\best_lap_track_outline.js"
$jsContent = "const trackOutline = [`n"
for ($i = 0; $i -lt $coords.Count; $i++) {
    if ($i -lt $coords.Count - 1) {
        $jsContent += "  [$($coords[$i][0]), $($coords[$i][1])],`n"
    } else {
        $jsContent += "  [$($coords[$i][0]), $($coords[$i][1])]`n"
    }
}
$jsContent += "];`n"
$jsContent | Out-File $jsPath -Encoding UTF8

Write-Host "JavaScript track outline saved to: $jsPath" -ForegroundColor Cyan

# Comparison with Aziz file
$aziz = $results | Where-Object { $_.FileName -eq "Aziz27Dec -uni.csv" }
if ($aziz -ne $null) {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Magenta
    Write-Host "COMPARISON WITH CURRENT LAP (Aziz27Dec -uni.csv)" -ForegroundColor Magenta
    Write-Host "========================================================================" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "Current lap (Aziz27Dec):"
    Write-Host "  - Points: $($aziz.NumPoints) (you mentioned 126)"
    Write-Host "  - Closure: $($aziz.ClosureDistance.ToString('F2')) m"
    Write-Host "  - GPS consistency: $($aziz.StdJump.ToString('F2')) m std"
    Write-Host "  - Score: $($aziz.Score.ToString('F1'))"

    if ($best.FileName -eq "Aziz27Dec -uni.csv") {
        Write-Host ""
        Write-Host "VERDICT: Current lap (Aziz27Dec) is confirmed as the BEST choice!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "VERDICT: $($best.FileName) is BETTER than current lap" -ForegroundColor Yellow
        Write-Host "  Improvement in points: $($best.NumPoints - $aziz.NumPoints)"
        Write-Host "  Improvement in closure: $($aziz.ClosureDistance - $best.ClosureDistance) m"
        Write-Host "  Improvement in score: $($best.Score - $aziz.Score)"
    }
}

Write-Host ""
Write-Host "Analysis complete!" -ForegroundColor Green