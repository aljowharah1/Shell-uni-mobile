#!/bin/bash

# Function to analyze a CSV file and extract lap information
analyze_file() {
    local file="$1"
    local basename=$(basename "$file")

    echo "========================================================================"
    echo "Analyzing: $basename"
    echo "========================================================================"

    # Count total lines
    local total_lines=$(wc -l < "$file")
    echo "Total lines: $total_lines"

    # Extract latitude and longitude columns (columns 8 and 9)
    # Skip header and rows with 0,0 coordinates
    awk -F',' 'NR>1 && $8!=0 && $9!=0 {print $8","$9}' "$file" > "temp_coords_${basename}.txt"

    local valid_points=$(wc -l < "temp_coords_${basename}.txt")
    echo "Valid GPS points: $valid_points"

    if [ $valid_points -lt 50 ]; then
        echo "ERROR: Insufficient valid GPS data"
        rm -f "temp_coords_${basename}.txt"
        return
    fi

    # Get first coordinate
    local first_coord=$(head -n1 "temp_coords_${basename}.txt")
    local first_lat=$(echo $first_coord | cut -d',' -f1)
    local first_lon=$(echo $first_coord | cut -d',' -f2)

    echo "Starting position: $first_lat, $first_lon"

    # Find points that are close to starting position (within ~0.0005 degrees, roughly 50m)
    # This finds potential lap completion points
    awk -v flat=$first_lat -v flon=$first_lon -F',' '
    {
        lat=$1; lon=$2
        # Simple distance approximation
        dlat = lat - flat
        dlon = lon - flon
        dist_sq = (dlat*dlat + dlon*dlon)

        # Within roughly 50m (0.0005 degrees squared = 0.00000025)
        if (dist_sq < 0.00000025 && NR > 50) {
            print NR
        }
    }' "temp_coords_${basename}.txt" > "temp_lap_points_${basename}.txt"

    local num_lap_points=$(wc -l < "temp_lap_points_${basename}.txt")
    echo "Found $num_lap_points potential lap completion points"

    if [ $num_lap_points -eq 0 ]; then
        echo "No complete lap found (threshold 50m)"
        rm -f "temp_coords_${basename}.txt" "temp_lap_points_${basename}.txt"
        return
    fi

    # Take the first lap completion point
    local lap_end=$(head -n1 "temp_lap_points_${basename}.txt")
    echo "Best lap ends at point: $lap_end"

    # Extract the lap
    head -n $lap_end "temp_coords_${basename}.txt" > "lap_${basename}.txt"

    # Calculate lap statistics
    echo ""
    echo "LAP STATISTICS:"
    echo "  Number of points: $lap_end"

    # Calculate distances between consecutive points (simplified)
    awk -F',' '
    NR==1 {prev_lat=$1; prev_lon=$2; next}
    {
        lat=$1; lon=$2
        dlat = lat - prev_lat
        dlon = lon - prev_lon
        # Approximate distance in meters (1 degree ~= 111km at this latitude)
        dist = sqrt((dlat*111000)^2 + (dlon*85000)^2)

        sum += dist
        sum_sq += dist*dist
        count++

        if (dist > max_dist) max_dist = dist

        prev_lat = lat
        prev_lon = lon
    }
    END {
        avg = sum / count
        variance = (sum_sq / count) - (avg * avg)
        std = sqrt(variance)

        printf "  Average GPS jump: %.2f m\n", avg
        printf "  Max GPS jump: %.2f m\n", max_dist
        printf "  Std GPS jump: %.2f m\n", std
    }
    ' "lap_${basename}.txt"

    # Calculate closure distance
    local last_coord=$(tail -n1 "lap_${basename}.txt")
    local last_lat=$(echo $last_coord | cut -d',' -f1)
    local last_lon=$(echo $last_coord | cut -d',' -f2)

    awk -v flat=$first_lat -v flon=$first_lon -v llat=$last_lat -v llon=$last_lon '
    BEGIN {
        dlat = llat - flat
        dlon = llon - flon
        dist = sqrt((dlat*111000)^2 + (dlon*85000)^2)
        printf "  Loop closure distance: %.2f m\n", dist
    }'

    echo ""

    # Clean up temp files
    rm -f "temp_coords_${basename}.txt" "temp_lap_points_${basename}.txt"
}

# Main execution
cd "c:\Users\Juju\Desktop\shell - Copy\dashboardPSU_ECOteam"

echo "========================================================================"
echo "UNIVERSITY TEST DRIVE LAP ANALYSIS"
echo "========================================================================"
echo ""

# Analyze each file
analyze_file "Mishal29dec01-uni.csv"
analyze_file "Ahmed24Dec-uni.csv"
analyze_file "Mishal25Dec-uni.csv"
analyze_file "Ahmed25Dec-uni.csv"
analyze_file "Aziz27Dec -uni.csv"
analyze_file "data/2025/practice1/inuniithink1.csv"
analyze_file "data/2025/practice1/inuniithink2.csv"

echo ""
echo "========================================================================"
echo "ANALYSIS COMPLETE"
echo "========================================================================"
echo "Lap files saved as: lap_*.txt"