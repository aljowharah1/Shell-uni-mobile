const fs = require('fs');

function haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371000; // Earth's radius in meters
    const phi1 = lat1 * Math.PI / 180;
    const phi2 = lat2 * Math.PI / 180;
    const deltaPhi = (lat2 - lat1) * Math.PI / 180;
    const deltaLambda = (lon2 - lon1) * Math.PI / 180;

    const a = Math.sin(deltaPhi/2) * Math.sin(deltaPhi/2) +
              Math.cos(phi1) * Math.cos(phi2) *
              Math.sin(deltaLambda/2) * Math.sin(deltaLambda/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));

    return R * c;
}

function extractLap() {
    console.log('Reading CSV file...');

    const csvContent = fs.readFileSync('dashboardPSU_ECOteam/Mishal29dec01-uni.csv', 'utf-8');
    const lines = csvContent.split('\n');

    // Skip header
    const header = lines[0].split(',');
    const speedIdx = header.indexOf('speed');
    const latIdx = header.indexOf('latitude');
    const lonIdx = header.indexOf('longitude');

    // Collect moving points
    const movingPoints = [];

    for (let i = 1; i < lines.length; i++) {
        if (!lines[i].trim()) continue;

        const cols = lines[i].split(',');
        const speed = parseFloat(cols[speedIdx]);
        const lat = parseFloat(cols[latIdx]);
        const lon = parseFloat(cols[lonIdx]);

        if (speed > 1.0 && !isNaN(lat) && !isNaN(lon)) {
            movingPoints.push([lat, lon]);
        }
    }

    console.log(`Found ${movingPoints.length} moving points`);

    if (movingPoints.length < 50) {
        console.log('Not enough moving points!');
        return;
    }

    // Starting position
    const [startLat, startLon] = movingPoints[0];
    console.log(`Start position: [${startLat}, ${startLon}]`);

    // Find complete lap
    const lapPoints = [movingPoints[0]];
    let lapEndIdx = -1;

    for (let i = 1; i < movingPoints.length; i++) {
        const [lat, lon] = movingPoints[i];
        lapPoints.push([lat, lon]);

        // Check if returned to start (skip first 50 points)
        if (i > 50) {
            const dist = haversineDistance(lat, lon, startLat, startLon);
            if (dist < 25) {
                console.log(`Completed lap at point ${i}, distance to start: ${dist.toFixed(2)}m`);
                lapEndIdx = i;
                break;
            }
        }
    }

    console.log(`Lap contains ${lapPoints.length} points`);

    // Sample to 55 evenly spaced points
    const targetPoints = 55;
    let sampledPoints = [];

    if (lapPoints.length > targetPoints) {
        const step = lapPoints.length / targetPoints;
        for (let i = 0; i < targetPoints; i++) {
            const idx = Math.floor(i * step);
            if (idx < lapPoints.length) {
                sampledPoints.push(lapPoints[idx]);
            }
        }
    } else {
        sampledPoints = lapPoints;
    }

    // Close the loop
    if (sampledPoints[sampledPoints.length - 1][0] !== sampledPoints[0][0] ||
        sampledPoints[sampledPoints.length - 1][1] !== sampledPoints[0][1]) {
        sampledPoints.push(sampledPoints[0]);
    }

    console.log(`Sampled to ${sampledPoints.length} points`);

    // Calculate center
    const avgLat = sampledPoints.reduce((sum, p) => sum + p[0], 0) / sampledPoints.length;
    const avgLon = sampledPoints.reduce((sum, p) => sum + p[1], 0) / sampledPoints.length;

    // Format output
    console.log('\n' + '='.repeat(60));
    console.log('JAVASCRIPT OUTPUT:');
    console.log('='.repeat(60));
    console.log('\noutline: [');

    sampledPoints.forEach(([lat, lon]) => {
        console.log(`    [${lat}, ${lon}],`);
    });

    console.log(']');
    console.log(`\ncenter: [${avgLat}, ${avgLon}]`);
    console.log('='.repeat(60));

    // Save to file
    let output = 'outline: [\n';
    sampledPoints.forEach(([lat, lon]) => {
        output += `    [${lat}, ${lon}],\n`;
    });
    output += ']\n\n';
    output += `center: [${avgLat}, ${avgLon}]\n`;

    fs.writeFileSync('mishal_track_outline.txt', output);
    console.log('\nOutput also saved to: mishal_track_outline.txt');
}

extractLap();