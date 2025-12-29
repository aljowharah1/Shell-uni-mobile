import pandas as pd
import numpy as np
from pathlib import Path
import json

def haversine_distance(lat1, lon1, lat2, lon2):
    """Calculate distance between two GPS points in meters"""
    R = 6371000  # Earth radius in meters
    phi1 = np.radians(lat1)
    phi2 = np.radians(lat2)
    dphi = np.radians(lat2 - lat1)
    dlambda = np.radians(lon2 - lon1)

    a = np.sin(dphi/2)**2 + np.cos(phi1) * np.cos(phi2) * np.sin(dlambda/2)**2
    c = 2 * np.arctan2(np.sqrt(a), np.sqrt(1-a))

    return R * c

def calculate_gps_jumps(lats, lons):
    """Calculate distances between consecutive GPS points"""
    jumps = []
    for i in range(len(lats) - 1):
        dist = haversine_distance(lats[i], lons[i], lats[i+1], lons[i+1])
        jumps.append(dist)
    return jumps

def find_lap_indices(lats, lons, closure_threshold=50):
    """Find indices where car completes a lap (returns close to start)"""
    if len(lats) < 50:  # Need at least 50 points for a meaningful lap
        return []

    start_lat, start_lon = lats[0], lons[0]
    lap_indices = []

    # Look for points that are close to the starting position
    for i in range(50, len(lats)):
        dist = haversine_distance(start_lat, start_lon, lats[i], lons[i])
        if dist < closure_threshold:
            lap_indices.append(i)

    return lap_indices

def extract_best_lap(df):
    """Extract the best complete lap from the dataframe"""
    # Filter out invalid GPS data
    df = df[(df['latitude'] != 0) & (df['longitude'] != 0)].copy()
    df = df.dropna(subset=['latitude', 'longitude'])

    if len(df) < 50:
        return None, "Insufficient GPS data"

    lats = df['latitude'].values
    lons = df['longitude'].values

    # Find potential lap completion points
    lap_indices = find_lap_indices(lats, lons, closure_threshold=50)

    if not lap_indices:
        # If no complete lap found, try larger threshold
        lap_indices = find_lap_indices(lats, lons, closure_threshold=100)

    if not lap_indices:
        return None, "No complete lap found"

    # Evaluate each potential lap
    best_lap = None
    best_score = -1

    for end_idx in lap_indices:
        lap_df = df.iloc[:end_idx+1].copy()

        if len(lap_df) < 50:
            continue

        # Calculate quality metrics
        lap_lats = lap_df['latitude'].values
        lap_lons = lap_df['longitude'].values

        # Closure quality
        closure_dist = haversine_distance(lap_lats[0], lap_lons[0], lap_lats[-1], lap_lons[-1])

        # GPS consistency (look for jumps)
        jumps = calculate_gps_jumps(lap_lats, lap_lons)
        avg_jump = np.mean(jumps)
        max_jump = np.max(jumps)
        std_jump = np.std(jumps)

        # Average speed
        if 'speed' in lap_df.columns:
            avg_speed = lap_df['speed'].mean()
        else:
            avg_speed = 0

        # Score based on multiple factors (lower is better for closure and std, higher for points)
        # Penalize large max jumps and poor closure
        if max_jump > 200 or closure_dist > 100:
            continue

        score = len(lap_df) * 10 - closure_dist - std_jump

        if score > best_score:
            best_score = score
            best_lap = {
                'df': lap_df,
                'num_points': len(lap_df),
                'closure_dist': closure_dist,
                'avg_jump': avg_jump,
                'max_jump': max_jump,
                'std_jump': std_jump,
                'avg_speed': avg_speed
            }

    if best_lap is None:
        return None, "No valid lap meeting quality criteria"

    return best_lap, "Success"

def analyze_file(filepath):
    """Analyze a single CSV file and extract lap information"""
    try:
        # Try reading with different encodings
        try:
            df = pd.read_csv(filepath)
        except UnicodeDecodeError:
            df = pd.read_csv(filepath, encoding='latin1')

        print(f"\nAnalyzing: {filepath.name}")
        print(f"Total rows: {len(df)}")
        print(f"Columns: {df.columns.tolist()}")

        # Check for GPS data
        if 'latitude' not in df.columns or 'longitude' not in df.columns:
            return None, "Missing GPS columns"

        # Count valid GPS points
        valid_gps = df[(df['latitude'] != 0) & (df['longitude'] != 0) &
                       (df['latitude'].notna()) & (df['longitude'].notna())]
        print(f"Valid GPS points: {len(valid_gps)}")

        if len(valid_gps) < 50:
            return None, "Insufficient valid GPS data"

        # Extract best lap
        lap_info, status = extract_best_lap(df)

        if lap_info is None:
            print(f"Status: {status}")
            return None, status

        print(f"Lap extracted: {lap_info['num_points']} points")
        print(f"Closure distance: {lap_info['closure_dist']:.2f}m")
        print(f"Avg GPS jump: {lap_info['avg_jump']:.2f}m")
        print(f"Max GPS jump: {lap_info['max_jump']:.2f}m")
        print(f"Std GPS jump: {lap_info['std_jump']:.2f}m")
        print(f"Avg speed: {lap_info['avg_speed']:.2f}")

        return lap_info, status

    except Exception as e:
        print(f"Error analyzing {filepath.name}: {str(e)}")
        return None, f"Error: {str(e)}"

def main():
    base_path = Path(r"c:\Users\Juju\Desktop\shell - Copy\dashboardPSU_ECOteam")

    files = [
        base_path / "Mishal29dec01-uni.csv",
        base_path / "Ahmed24Dec-uni.csv",
        base_path / "Mishal25Dec-uni.csv",
        base_path / "Ahmed25Dec-uni.csv",
        base_path / "Aziz27Dec -uni.csv",
        base_path / "data" / "2025" / "practice1" / "inuniithink1.csv",
        base_path / "data" / "2025" / "practice1" / "inuniithink2.csv",
    ]

    results = {}

    print("="*80)
    print("ANALYZING ALL UNIVERSITY TEST DRIVE FILES")
    print("="*80)

    for filepath in files:
        if not filepath.exists():
            print(f"\nWARNING: File not found: {filepath}")
            continue

        lap_info, status = analyze_file(filepath)

        if lap_info is not None:
            results[filepath.name] = lap_info

    print("\n" + "="*80)
    print("COMPARISON SUMMARY")
    print("="*80)

    if not results:
        print("No valid laps found in any file!")
        return

    # Create comparison table
    print(f"\n{'File Name':<35} {'Points':<8} {'Closure':<10} {'Avg Jump':<10} {'Max Jump':<10} {'Std Jump':<10} {'Avg Speed':<10}")
    print("-" * 120)

    for filename, info in sorted(results.items()):
        print(f"{filename:<35} {info['num_points']:<8} {info['closure_dist']:<10.2f} "
              f"{info['avg_jump']:<10.2f} {info['max_jump']:<10.2f} "
              f"{info['std_jump']:<10.2f} {info['avg_speed']:<10.2f}")

    # Find the best lap based on composite score
    best_file = None
    best_composite_score = -999999

    for filename, info in results.items():
        # Composite score: favor more points, low closure, low std, reasonable avg jump
        score = (info['num_points'] * 5) - (info['closure_dist'] * 2) - (info['std_jump'] * 1) - (abs(info['avg_jump'] - 20) * 0.5)

        # Penalize if max jump is too large (indicates GPS errors)
        if info['max_jump'] > 150:
            score -= 500

        # Penalize if closure is poor
        if info['closure_dist'] > 50:
            score -= 200

        if score > best_composite_score:
            best_composite_score = score
            best_file = filename

    print("\n" + "="*80)
    print("RECOMMENDATION")
    print("="*80)

    if best_file:
        best_info = results[best_file]
        print(f"\nMOST ACCURATE LAP: {best_file}")
        print(f"  - Number of GPS points: {best_info['num_points']}")
        print(f"  - Loop closure quality: {best_info['closure_dist']:.2f}m (closer to 0 is better)")
        print(f"  - GPS consistency (avg jump): {best_info['avg_jump']:.2f}m")
        print(f"  - GPS consistency (std jump): {best_info['std_jump']:.2f}m")
        print(f"  - Max GPS jump: {best_info['max_jump']:.2f}m")
        print(f"  - Average speed: {best_info['avg_speed']:.2f}")

        # Generate GPS outline in JavaScript format
        lap_df = best_info['df']
        coords = []
        for _, row in lap_df.iterrows():
            coords.append([row['latitude'], row['longitude']])

        # Save to JSON
        output = {
            'filename': best_file,
            'num_points': best_info['num_points'],
            'closure_distance_m': best_info['closure_dist'],
            'avg_jump_m': best_info['avg_jump'],
            'max_jump_m': best_info['max_jump'],
            'std_jump_m': best_info['std_jump'],
            'avg_speed': best_info['avg_speed'],
            'coordinates': coords
        }

        output_path = Path(r"c:\Users\Juju\Desktop\shell - Copy\best_lap_analysis.json")
        with open(output_path, 'w') as f:
            json.dump(output, f, indent=2)

        print(f"\nBest lap data saved to: {output_path}")

        # Print JavaScript format
        print("\n" + "="*80)
        print("GPS OUTLINE (JavaScript Format)")
        print("="*80)
        print("\nconst trackOutline = [")
        for i, coord in enumerate(coords):
            if i < len(coords) - 1:
                print(f"  [{coord[0]}, {coord[1]}],")
            else:
                print(f"  [{coord[0]}, {coord[1]}]")
        print("];")

        # Comparison with current (Aziz27Dec)
        if "Aziz27Dec -uni.csv" in results:
            aziz_info = results["Aziz27Dec -uni.csv"]
            print("\n" + "="*80)
            print("COMPARISON WITH CURRENT LAP (Aziz27Dec -uni.csv)")
            print("="*80)
            print(f"\nCurrent lap (Aziz27Dec):")
            print(f"  - Points: {aziz_info['num_points']} (you mentioned 126)")
            print(f"  - Closure: {aziz_info['closure_dist']:.2f}m")
            print(f"  - GPS consistency: {aziz_info['std_jump']:.2f}m std")

            if best_file == "Aziz27Dec -uni.csv":
                print("\nVERDICT: Current lap is confirmed as the BEST choice!")
            else:
                print(f"\nVERDICT: {best_file} is BETTER than current lap")
                print(f"  Improvement: {best_info['num_points'] - aziz_info['num_points']} more points")
                print(f"  Better closure: {aziz_info['closure_dist'] - best_info['closure_dist']:.2f}m improvement")

if __name__ == "__main__":
    main()