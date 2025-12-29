BEGIN {
    FS = ","
    moving_count = 0
    start_lat = 0
    start_lon = 0
    lap_complete = 0
    PI = 3.14159265358979323846
    R = 6371000  # Earth radius in meters
}

NR == 1 {
    # Find column indices
    for (i = 1; i <= NF; i++) {
        if ($i == "speed") speed_col = i
        if ($i == "latitude") lat_col = i
        if ($i == "longitude") lon_col = i
    }
    next
}

NR > 1 {
    speed = $speed_col
    lat = $lat_col
    lon = $lon_col

    # Only process moving points
    if (speed > 1.0 && lat != "" && lon != "") {
        moving_count++
        lats[moving_count] = lat
        lons[moving_count] = lon

        # Set start position
        if (moving_count == 1) {
            start_lat = lat
            start_lon = lon
        }

        # Check for lap completion (after 50 points)
        if (moving_count > 50 && lap_complete == 0) {
            # Calculate distance to start
            phi1 = start_lat * PI / 180
            phi2 = lat * PI / 180
            delta_phi = (lat - start_lat) * PI / 180
            delta_lambda = (lon - start_lon) * PI / 180

            a = sin(delta_phi/2) * sin(delta_phi/2) + cos(phi1) * cos(phi2) * sin(delta_lambda/2) * sin(delta_lambda/2)
            c = 2 * atan2(sqrt(a), sqrt(1-a))
            dist = R * c

            if (dist < 25) {
                lap_end = moving_count
                lap_complete = 1
            }
        }
    }
}

END {
    if (lap_complete == 0) {
        lap_end = moving_count
    }

    print "Found", moving_count, "moving points" > "/dev/stderr"
    print "Lap end:", lap_end > "/dev/stderr"

    # Sample to ~55 points
    target = 55
    step = lap_end / target

    # Output sampled points
    for (i = 0; i < target; i++) {
        idx = int(i * step) + 1
        if (idx <= lap_end) {
            print lats[idx], lons[idx]
        }
    }

    # Add start point to close loop if needed
    if (lats[int((target-1) * step) + 1] != lats[1] || lons[int((target-1) * step) + 1] != lons[1]) {
        print lats[1], lons[1]
    }
}