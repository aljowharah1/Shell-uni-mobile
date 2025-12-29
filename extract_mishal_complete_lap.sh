#!/bin/bash

CSV_FILE="dashboardPSU_ECOteam/Mishal29dec01-uni.csv"
OUTPUT_FILE="mishal_track_outline.txt"

echo "Extracting complete lap from Mishal's data..."

# Extract moving points (speed > 1.0) with lat, lon
awk -F',' '
BEGIN {
    PI = 3.14159265358979323846
    R = 6371000
}

NR==1 {
    for(i=1; i<=NF; i++) {
        if($i=="speed") sc=i
        if($i=="latitude") lc=i
        if($i=="longitude") lnc=i
    }
    next
}

NR>1 && $sc > 1.0 && $lc != "" && $lnc != "" {
    lat[NR] = $lc
    lon[NR] = $lnc
    if (count == 0) {
        start_lat = $lc
        start_lon = $lnc
        start_line = NR
    }
    count++

    # Check for lap completion after 200 points
    if (count > 200) {
        # Haversine distance to start
        phi1 = start_lat * PI / 180
        phi2 = $lc * PI / 180
        dphi = ($lc - start_lat) * PI / 180
        dlambda = ($lnc - start_lon) * PI / 180

        a = sin(dphi/2)^2 + cos(phi1) * cos(phi2) * sin(dlambda/2)^2
        c = 2 * atan2(sqrt(a), sqrt(1-a))
        dist = R * c

        if (dist < 30 && lap_end == 0) {
            lap_end = count
            lap_end_line = NR
            exit
        }
    }
}

END {
    if (lap_end == 0) {
        lap_end = count
        lap_end_line = NR
    }

    print "Found", count, "moving points" > "/dev/stderr"
    print "Start position: lat=" start_lat ", lon=" start_lon > "/dev/stderr"
    print "Lap completed at point", lap_end > "/dev/stderr"

    # Output all lap points (we will sample later)
    point_num = 0
    for (line = start_line; line <= lap_end_line; line++) {
        if (line in lat) {
            print lat[line], lon[line]
            point_num++
        }
    }

    print "Output", point_num, "lap points" > "/dev/stderr"
}
' "$CSV_FILE" > temp_lap_points.txt

# Now sample to ~55 points evenly
total_points=$(wc -l < temp_lap_points.txt)
echo "Total lap points: $total_points"

if [ "$total_points" -lt 55 ]; then
    echo "Warning: Less than 55 points in lap"
    cp temp_lap_points.txt sampled_points.txt
else
    # Sample evenly
    awk -v total="$total_points" -v target=55 '
    BEGIN {
        step = total / target
    }
    {
        points[NR] = $0
    }
    END {
        for (i = 0; i < target; i++) {
            idx = int(i * step) + 1
            if (idx in points) {
                print points[idx]
            }
        }
        # Add first point to close loop
        if (points[1] != points[int((target-1) * step) + 1]) {
            print points[1]
        }
    }
    ' temp_lap_points.txt > sampled_points.txt
fi

# Calculate center and format output
awk '
{
    lat_sum += $1
    lon_sum += $2
    lats[NR] = $1
    lons[NR] = $2
    count++
}
END {
    center_lat = lat_sum / count
    center_lon = lon_sum / count

    print "outline: ["
    for (i = 1; i <= count; i++) {
        print "    [" lats[i] ", " lons[i] "],"
    }
    print "]"
    print ""
    print "center: [" center_lat ", " center_lon "]"
}
' sampled_points.txt > "$OUTPUT_FILE"

echo ""
echo "============================================================"
cat "$OUTPUT_FILE"
echo "============================================================"
echo ""
echo "Output saved to: $OUTPUT_FILE"

# Cleanup
rm -f temp_lap_points.txt sampled_points.txt