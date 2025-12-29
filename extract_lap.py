import csv
import math

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate the great circle distance between two points on earth in meters."""
    R = 6371000  # Radius of earth in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = math.sin(delta_phi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

    return R * c

def find_complete_lap(csv_file, speed_threshold=1.0, proximity_threshold=25):
    """Extract one complete lap from the CSV file."""

    print("Reading CSV file...")
    moving_points = []

    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                speed = float(row['speed'])
                lat = float(row['latitude'])
                lon = float(row['longitude'])

                # Only collect points where car is moving
                if speed > speed_threshold:
                    moving_points.append((lat, lon))
            except (ValueError, KeyError):
                continue

    print(f"Found {len(moving_points)} moving points")

    if len(moving_points) < 50:
        print("Not enough moving points found!")
        return None, None

    # Use the first moving point as the start
    start_lat, start_lon = moving_points[0]
    print(f"Start position: ({start_lat}, {start_lon})")

    # Find where the car returns close to the starting position
    lap_points = [moving_points[0]]

    for i in range(1, len(moving_points)):
        lat, lon = moving_points[i]
        lap_points.append((lat, lon))

        # Check if we've returned to start (skip first 50 points to avoid false positives)
        if i > 50:
            distance_to_start = haversine_distance(lat, lon, start_lat, start_lon)
            if distance_to_start < proximity_threshold:
                print(f"Completed lap at point {i}, distance to start: {distance_to_start:.2f}m")
                break

    print(f"Lap contains {len(lap_points)} points")

    # Sample evenly spaced points (target: 50-60 points)
    target_points = 55
    if len(lap_points) > target_points:
        step = len(lap_points) / target_points
        sampled_points = []
        for i in range(target_points):
            idx = int(i * step)
            if idx < len(lap_points):
                sampled_points.append(lap_points[idx])
    else:
        sampled_points = lap_points

    # Ensure the loop is closed (last point connects to first)
    if sampled_points[-1] != sampled_points[0]:
        sampled_points.append(sampled_points[0])

    print(f"Sampled to {len(sampled_points)} points")

    # Calculate center point
    avg_lat = sum(p[0] for p in sampled_points) / len(sampled_points)
    avg_lon = sum(p[1] for p in sampled_points) / len(sampled_points)

    return sampled_points, (avg_lat, avg_lon)

def format_javascript_output(points, center):
    """Format the output as JavaScript array."""
    print("\n" + "="*60)
    print("JAVASCRIPT OUTPUT:")
    print("="*60)
    print("\noutline: [")
    for lat, lon in points:
        print(f"    [{lat}, {lon}],")
    print("]")
    print(f"\ncenter: [{center[0]}, {center[1]}]")
    print("="*60)

if __name__ == "__main__":
    csv_file = r"c:\Users\Juju\Desktop\shell - Copy\dashboardPSU_ECOteam\Mishal29dec01-uni.csv"

    lap_points, center = find_complete_lap(csv_file)

    if lap_points and center:
        format_javascript_output(lap_points, center)

        # Also save to a file for easy copying
        with open(r"c:\Users\Juju\Desktop\shell - Copy\mishal_track_outline.txt", 'w') as f:
            f.write("outline: [\n")
            for lat, lon in lap_points:
                f.write(f"    [{lat}, {lon}],\n")
            f.write("]\n\n")
            f.write(f"center: [{center[0]}, {center[1]}]\n")

        print("\nOutput also saved to: mishal_track_outline.txt")
    else:
        print("Failed to extract lap data")