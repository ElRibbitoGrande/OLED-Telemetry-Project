#!/usr/bin/env python3
"""Analyze a simultaneous Windows AudioLevel / Box 1 VU diagnostic capture."""

from __future__ import annotations

import argparse
import csv
import math
import statistics
import sys
import tempfile
from pathlib import Path
from typing import Iterable, Sequence


UPDATE_SECONDS = 0.032
GAIN = 2.7
ATTACK_MS = 85.0
DECAY_MS = 520.0


def clamp(value: float) -> float:
    return max(0.0, min(1.0, value))


def db_to_amplitude(value: float) -> float:
    return clamp(10.0 ** (value / 20.0))


def as_float(row: dict[str, str], name: str) -> float:
    try:
        return float(row[name])
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError(f"Invalid numeric field {name!r}: {row.get(name)!r}") from error


def as_int(row: dict[str, str], name: str) -> int:
    try:
        return int(float(row[name]))
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError(f"Invalid integer field {name!r}: {row.get(name)!r}") from error


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        raise FileNotFoundError(path)
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise ValueError(f"Capture log contains no records: {path}")
    return rows


def stereo_mean(left: Sequence[float], right: Sequence[float]) -> list[float]:
    return [(l + r) * 0.5 for l, r in zip(left, right)]


def pearson(left: Sequence[float], right: Sequence[float]) -> float:
    if len(left) != len(right) or len(left) < 3:
        return float("nan")
    left_mean = statistics.fmean(left)
    right_mean = statistics.fmean(right)
    left_delta = [value - left_mean for value in left]
    right_delta = [value - right_mean for value in right]
    numerator = sum(a * b for a, b in zip(left_delta, right_delta))
    denominator = math.sqrt(
        sum(value * value for value in left_delta)
        * sum(value * value for value in right_delta)
    )
    return numerator / denominator if denominator > 0.0 else float("nan")


def lagged_values(
    reference: Sequence[float], candidate: Sequence[float], lag: int
) -> tuple[Sequence[float], Sequence[float]]:
    count = min(len(reference), len(candidate))
    if lag >= 0:
        return reference[: count - lag], candidate[lag:count]
    return reference[-lag:count], candidate[: count + lag]


def best_lag(
    reference: Sequence[float],
    candidate: Sequence[float],
    maximum_lag: int,
    minimum_overlap: int,
) -> tuple[int, float]:
    best_offset = 0
    best_correlation = -2.0
    for lag in range(-maximum_lag, maximum_lag + 1):
        left, right = lagged_values(reference, candidate, lag)
        if len(left) < minimum_overlap:
            continue
        correlation = pearson(left, right)
        if math.isfinite(correlation) and correlation > best_correlation:
            best_offset = lag
            best_correlation = correlation
    if best_correlation < -1.0:
        raise ValueError("No valid cross-correlation window was available.")
    return best_offset, best_correlation


def segment_correlation(
    reference: Sequence[float],
    candidate: Sequence[float],
    start: int,
    end: int,
    lag: int,
) -> float:
    candidate_start = start + lag
    candidate_end = end + lag
    if candidate_start < 0 or candidate_end > len(candidate):
        return float("nan")
    return pearson(reference[start:end], candidate[candidate_start:candidate_end])


def local_lags(
    reference: Sequence[float],
    candidate: Sequence[float],
    global_lag: int,
    window_frames: int,
    step_frames: int,
    search_frames: int,
) -> list[dict[str, float]]:
    results: list[dict[str, float]] = []
    for start in range(0, len(reference) - window_frames + 1, step_frames):
        end = start + window_frames
        best_offset = global_lag
        best_correlation = -2.0
        for lag in range(global_lag - search_frames, global_lag + search_frames + 1):
            correlation = segment_correlation(reference, candidate, start, end, lag)
            if math.isfinite(correlation) and correlation > best_correlation:
                best_offset = lag
                best_correlation = correlation
        if best_correlation >= -1.0:
            results.append(
                {
                    "WindowStartSeconds": start * UPDATE_SECONDS,
                    "WindowEndSeconds": end * UPDATE_SECONDS,
                    "OffsetMilliseconds": best_offset * UPDATE_SECONDS * 1000.0,
                    "Correlation": best_correlation,
                }
            )
    return results


def percentile(values: Sequence[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    position = (len(ordered) - 1) * fraction
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def detect_events(
    times: Sequence[float],
    values: Sequence[float],
    minimum_spacing: float,
) -> list[dict[str, float]]:
    if len(values) < 5:
        return []
    positive_changes = [max(0.0, current - previous) for previous, current in zip(values, values[1:])]
    change_floor = max(0.008, percentile(positive_changes, 0.90))
    amplitude_floor = percentile(values, 0.60)
    candidates: list[dict[str, float]] = []
    for index, change in enumerate(positive_changes, start=1):
        value = values[index]
        if change >= change_floor and value >= amplitude_floor:
            candidates.append(
                {"TimeSeconds": times[index], "Amplitude": value, "Prominence": change}
            )

    selected: list[dict[str, float]] = []
    for event in sorted(candidates, key=lambda item: item["Amplitude"], reverse=True):
        if all(abs(event["TimeSeconds"] - kept["TimeSeconds"]) >= minimum_spacing for kept in selected):
            selected.append(event)
    return sorted(selected, key=lambda item: item["TimeSeconds"])


def match_events(
    reference: Sequence[dict[str, float]],
    candidate: Sequence[dict[str, float]],
    candidate_offset_seconds: float,
    tolerance_seconds: float,
) -> tuple[set[int], set[int]]:
    reference_matches: set[int] = set()
    candidate_matches: set[int] = set()
    pairs: list[tuple[float, int, int]] = []
    for left_index, left in enumerate(reference):
        for right_index, right in enumerate(candidate):
            aligned_time = right["TimeSeconds"] - candidate_offset_seconds
            distance = abs(left["TimeSeconds"] - aligned_time)
            if distance <= tolerance_seconds:
                pairs.append((distance, left_index, right_index))
    for _, left_index, right_index in sorted(pairs):
        if left_index not in reference_matches and right_index not in candidate_matches:
            reference_matches.add(left_index)
            candidate_matches.add(right_index)
    return reference_matches, candidate_matches


def fit_line(xs: Sequence[float], ys: Sequence[float]) -> tuple[float, float]:
    if len(xs) != len(ys) or len(xs) < 2:
        return 0.0, 1.0
    x_mean = statistics.fmean(xs)
    y_mean = statistics.fmean(ys)
    denominator = sum((value - x_mean) ** 2 for value in xs)
    if denominator == 0.0:
        return y_mean, 1.0
    slope = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys)) / denominator
    return y_mean - slope * x_mean, slope


def response_output(previous_power: float, target: float) -> tuple[float, float]:
    target = clamp(target)
    target_power = target * target
    response_ms = ATTACK_MS if target_power >= previous_power else DECAY_MS
    coefficient = math.exp(-2.0 * 32.0 / response_ms) if response_ms > 0.0 else 0.0
    power = target_power + coefficient * (previous_power - target_power)
    return power, clamp(math.sqrt(max(0.0, power)) * GAIN)


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: Sequence[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def svg_polyline(values: Sequence[float], width: int, height: int) -> str:
    if not values:
        return ""
    denominator = max(1, len(values) - 1)
    return " ".join(
        f"{index * width / denominator:.2f},{height - clamp(value) * height:.2f}"
        for index, value in enumerate(values)
    )


def write_plot(
    path: Path,
    windows: Sequence[float],
    box_final: Sequence[float],
    box_pre: Sequence[float],
    lag: int,
) -> None:
    aligned_windows, aligned_box = lagged_values(windows, box_final, lag)
    if lag >= 0:
        aligned_pre = box_pre[lag : lag + len(aligned_windows)]
    else:
        aligned_pre = box_pre[: len(aligned_windows)]
    width, panel_height, margin = 1200, 240, 45
    panels = [
        ("Windows AudioLevel (blue) vs aligned Box final (orange)", aligned_windows, aligned_box),
        ("Aligned Box pre-response RMS (green) vs Box final (orange)", aligned_pre, aligned_box),
    ]
    total_height = panel_height * len(panels) + margin * (len(panels) + 1)
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width + 100}" height="{total_height}">',
        '<rect width="100%" height="100%" fill="#11151d"/>',
    ]
    colors = [("#61a8ff", "#ffad5c"), ("#64d98b", "#ffad5c")]
    for panel_index, (title, first, second) in enumerate(panels):
        y = margin + panel_index * (panel_height + margin)
        parts.append(f'<text x="50" y="{y - 12}" fill="#e8eef8" font-family="Segoe UI" font-size="16">{title}</text>')
        parts.append(f'<rect x="50" y="{y}" width="{width}" height="{panel_height}" fill="#080b10" stroke="#3c4657"/>')
        parts.append(f'<polyline transform="translate(50 {y})" points="{svg_polyline(first, width, panel_height)}" fill="none" stroke="{colors[panel_index][0]}" stroke-width="1"/>')
        parts.append(f'<polyline transform="translate(50 {y})" points="{svg_polyline(second, width, panel_height)}" fill="none" stroke="{colors[panel_index][1]}" stroke-width="1"/>')
    parts.append("</svg>")
    path.write_text("\n".join(parts), encoding="utf-8")


def self_test() -> None:
    count = 1800
    lag = 73
    reference = [0.08 + 0.025 * math.sin(index * 0.07) for index in range(count)]
    for center, height in ((180, 0.8), (420, 0.65), (760, 0.9), (1100, 0.7), (1450, 0.85)):
        for distance in range(-8, 9):
            index = center + distance
            if 0 <= index < count:
                reference[index] += height * math.exp(-((distance / 3.0) ** 2))
    reference = [clamp(value) for value in reference]
    candidate = [0.0] * lag + reference[: count - lag]
    measured_lag, correlation = best_lag(reference, candidate, 200, 500)
    if measured_lag != lag or correlation < 0.999999:
        raise AssertionError(
            f"Cross-correlation self-test failed: lag={measured_lag}, correlation={correlation}"
        )

    with tempfile.TemporaryDirectory(prefix="box1-vu-comparison-") as temporary:
        directory = Path(temporary)
        duration_seconds = 25.0
        raw_count = int(duration_seconds * 100)
        rain_count = int(duration_seconds / UPDATE_SECONDS)
        sequence_start = 500_000
        ticks_start = 638_908_000_000_000_000

        def synthetic(time_value: float) -> float:
            value = 0.07 + 0.025 * math.sin(time_value * 3.7)
            for center, height in ((3.0, 0.72), (7.5, 0.55), (12.0, 0.82), (18.0, 0.68), (22.0, 0.75)):
                value += height * math.exp(-(((time_value - center) / 0.075) ** 2))
            return clamp(value)

        windows_targets = [synthetic(index * UPDATE_SECONDS) for index in range(rain_count)]
        box_targets = [
            synthetic(index * UPDATE_SECONDS - lag * UPDATE_SECONDS)
            for index in range(rain_count)
        ]
        windows_outputs: list[float] = []
        box_outputs: list[float] = []
        windows_power = 0.0
        box_power = 0.0
        for windows_target, box_target in zip(windows_targets, box_targets):
            windows_power, windows_output = response_output(windows_power, windows_target)
            box_power, box_output = response_output(box_power, box_target)
            windows_outputs.append(windows_output)
            box_outputs.append(box_output)

        with (directory / "box1_raw.csv").open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(
                [
                    "UtcTicks",
                    "TimestampLocal",
                    "Sequence",
                    "LeftRmsDb",
                    "LeftPeakDb",
                    "LeftVuDb",
                    "RightRmsDb",
                    "RightPeakDb",
                    "RightVuDb",
                ]
            )
            for index in range(raw_count):
                time_value = index * 0.01
                amplitude = max(0.000001, synthetic(time_value - lag * UPDATE_SECONDS))
                db = 20.0 * math.log10(amplitude)
                writer.writerow(
                    [
                        ticks_start + index * 100_000,
                        "2026-08-15T12:00:00.0000000-07:00",
                        sequence_start + index,
                        db,
                        db,
                        db,
                        db,
                        db,
                        db,
                    ]
                )

        with (directory / "rainmeter_comparison.csv").open("w", encoding="utf-8", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(
                [
                    "EpochSecond",
                    "RainmeterFrame",
                    "NominalElapsedMs",
                    "Source",
                    "WindowsRawLeft",
                    "WindowsRawRight",
                    "Box1LeftRmsDb",
                    "Box1RightRmsDb",
                    "Box1PreLeft",
                    "Box1PreRight",
                    "Box1FinalLeft",
                    "Box1FinalRight",
                    "Box1Sequence",
                ]
            )
            for frame_index in range(rain_count):
                time_value = frame_index * UPDATE_SECONDS
                windows_target = windows_targets[frame_index]
                box_target = box_targets[frame_index]
                windows_value = windows_outputs[frame_index]
                box_value = box_outputs[frame_index]
                raw_index = min(raw_count - 1, int(round(time_value / 0.01)))
                box_db = 20.0 * math.log10(max(0.000001, box_target))
                writer.writerow(
                    [
                        1_786_000_000 + int(time_value),
                        frame_index,
                        frame_index * 32,
                        "LYR+",
                        windows_value,
                        windows_value,
                        box_db,
                        box_db,
                        box_target,
                        box_target,
                        box_value,
                        box_value,
                        sequence_start + raw_index,
                    ]
                )

        analyze(directory, 5.0)
        required_outputs = (
            "analysis_summary.txt",
            "window_correlation.csv",
            "events.csv",
            "box_transport.csv",
            "box_raw_transients.csv",
            "aligned_signals.csv",
            "comparison.svg",
        )
        missing = [name for name in required_outputs if not (directory / name).is_file()]
        if missing:
            raise AssertionError(f"Full analysis self-test did not create: {', '.join(missing)}")
        summary = (directory / "analysis_summary.txt").read_text(encoding="utf-8")
        if "2336.000 ms" not in summary:
            raise AssertionError("Full analysis self-test did not recover the known playback offset.")

    print(f"Self-test PASS: recovered offset={lag * 32} ms correlation={correlation:.9f}")


def analyze(capture_directory: Path, maximum_offset_seconds: float) -> None:
    collector_rows = read_csv(capture_directory / "box1_raw.csv")
    rainmeter_rows = read_csv(capture_directory / "rainmeter_comparison.csv")

    rain_times = [as_float(row, "NominalElapsedMs") / 1000.0 for row in rainmeter_rows]
    windows_left = [as_float(row, "WindowsRawLeft") for row in rainmeter_rows]
    windows_right = [as_float(row, "WindowsRawRight") for row in rainmeter_rows]
    box_pre_left = [as_float(row, "Box1PreLeft") for row in rainmeter_rows]
    box_pre_right = [as_float(row, "Box1PreRight") for row in rainmeter_rows]
    box_final_left = [as_float(row, "Box1FinalLeft") for row in rainmeter_rows]
    box_final_right = [as_float(row, "Box1FinalRight") for row in rainmeter_rows]
    rain_sequences = [as_int(row, "Box1Sequence") for row in rainmeter_rows]
    sources = [row.get("Source", "") for row in rainmeter_rows]

    windows = stereo_mean(windows_left, windows_right)
    box_pre = stereo_mean(box_pre_left, box_pre_right)
    box_final = stereo_mean(box_final_left, box_final_right)

    maximum_lag = min(
        int(round(maximum_offset_seconds / UPDATE_SECONDS)),
        max(1, len(windows) - int(round(5.0 / UPDATE_SECONDS))),
    )
    lag, aligned_correlation = best_lag(
        windows, box_final, maximum_lag, int(round(5.0 / UPDATE_SECONDS))
    )
    pre_lag, pre_correlation = best_lag(
        windows, box_pre, maximum_lag, int(round(5.0 / UPDATE_SECONDS))
    )
    offset_seconds = lag * UPDATE_SECONDS

    windows_results = local_lags(
        windows,
        box_final,
        lag,
        int(round(10.0 / UPDATE_SECONDS)),
        int(round(5.0 / UPDATE_SECONDS)),
        int(round(1.0 / UPDATE_SECONDS)),
    )
    write_csv(
        capture_directory / "window_correlation.csv",
        windows_results,
        ["WindowStartSeconds", "WindowEndSeconds", "OffsetMilliseconds", "Correlation"],
    )

    local_offsets = [row["OffsetMilliseconds"] for row in windows_results]
    offset_range = max(local_offsets) - min(local_offsets) if local_offsets else float("nan")
    offset_stddev = statistics.pstdev(local_offsets) if len(local_offsets) > 1 else 0.0

    raw_ticks = [as_int(row, "UtcTicks") for row in collector_rows]
    raw_time_origin = raw_ticks[0]
    raw_times = [(value - raw_time_origin) / 10_000_000.0 for value in raw_ticks]
    raw_sequences = [as_int(row, "Sequence") for row in collector_rows]
    raw_left = [db_to_amplitude(as_float(row, "LeftRmsDb")) for row in collector_rows]
    raw_right = [db_to_amplitude(as_float(row, "RightRmsDb")) for row in collector_rows]
    raw_level = stereo_mean(raw_left, raw_right)
    raw_by_sequence = {
        sequence: (time_value, left, right)
        for sequence, time_value, left, right in zip(raw_sequences, raw_times, raw_left, raw_right)
    }

    seen_sequence_set = set(rain_sequences)
    observed_pairs = [
        (raw_by_sequence[sequence][0], rain_times[index])
        for index, sequence in enumerate(rain_sequences)
        if sequence in raw_by_sequence
    ]
    transport_intercept, transport_slope = fit_line(
        [pair[0] for pair in observed_pairs], [pair[1] for pair in observed_pairs]
    )
    raw_to_rain_time = lambda value: transport_intercept + transport_slope * value

    raw_gaps = sum(max(0, current - previous - 1) for previous, current in zip(raw_sequences, raw_sequences[1:]))
    raw_scope = [sequence for sequence in raw_sequences if min(rain_sequences) <= sequence <= max(rain_sequences)]
    seen_in_raw_scope = set(raw_scope) & seen_sequence_set

    mapping_errors_left: list[float] = []
    mapping_errors_right: list[float] = []
    transport_rows: list[dict[str, object]] = []
    for index, sequence in enumerate(rain_sequences):
        raw = raw_by_sequence.get(sequence)
        if raw is None:
            continue
        left_error = box_pre_left[index] - raw[1]
        right_error = box_pre_right[index] - raw[2]
        mapping_errors_left.append(left_error)
        mapping_errors_right.append(right_error)
        transport_rows.append(
            {
                "RainmeterFrame": index,
                "Sequence": sequence,
                "RawMappedRainmeterSeconds": raw_to_rain_time(raw[0]),
                "RainmeterSeconds": rain_times[index],
                "LeftPreMinusRaw": left_error,
                "RightPreMinusRaw": right_error,
            }
        )
    write_csv(
        capture_directory / "box_transport.csv",
        transport_rows,
        [
            "RainmeterFrame",
            "Sequence",
            "RawMappedRainmeterSeconds",
            "RainmeterSeconds",
            "LeftPreMinusRaw",
            "RightPreMinusRaw",
        ],
    )

    expected_final: list[float] = [box_final[0]]
    initial_unclamped = min(1.0, box_final[0]) / GAIN
    power = initial_unclamped * initial_unclamped
    for target in box_pre[1:]:
        power, output = response_output(power, target)
        expected_final.append(output)
    response_errors = [actual - expected for actual, expected in zip(box_final, expected_final)]

    windows_events = detect_events(rain_times, windows, 0.16)
    box_final_events = detect_events(rain_times, box_final, 0.16)
    raw_event_times = [raw_to_rain_time(value) for value in raw_times]
    raw_events = detect_events(raw_event_times, raw_level, 0.12)
    windows_matches, box_matches = match_events(
        windows_events, box_final_events, offset_seconds, 0.16
    )
    raw_matches, _ = match_events(raw_events, box_final_events, 0.0, 0.16)

    event_rows: list[dict[str, object]] = []
    for name, events, matches, alignment in (
        ("WindowsAudioLevel", windows_events, windows_matches, 0.0),
        ("BoxFinal", box_final_events, box_matches, offset_seconds),
        ("BoxRaw", raw_events, raw_matches, 0.0),
    ):
        for index, event in enumerate(events):
            event_rows.append(
                {
                    "Trace": name,
                    "TimeSeconds": event["TimeSeconds"],
                    "AlignedTimeSeconds": event["TimeSeconds"] - alignment,
                    "Amplitude": event["Amplitude"],
                    "Prominence": event["Prominence"],
                    "Matched": int(index in matches),
                }
            )
    write_csv(
        capture_directory / "events.csv",
        event_rows,
        ["Trace", "TimeSeconds", "AlignedTimeSeconds", "Amplitude", "Prominence", "Matched"],
    )

    raw_transient_rows: list[dict[str, object]] = []
    for index, event in enumerate(raw_events):
        raw_index = min(range(len(raw_event_times)), key=lambda item: abs(raw_event_times[item] - event["TimeSeconds"]))
        sequence = raw_sequences[raw_index]
        raw_transient_rows.append(
            {
                "Sequence": sequence,
                "MappedRainmeterSeconds": event["TimeSeconds"],
                "Amplitude": event["Amplitude"],
                "SeenSequenceByRainmeter": int(sequence in seen_sequence_set),
                "MatchedFinalEvent": int(index in raw_matches),
            }
        )
    write_csv(
        capture_directory / "box_raw_transients.csv",
        raw_transient_rows,
        [
            "Sequence",
            "MappedRainmeterSeconds",
            "Amplitude",
            "SeenSequenceByRainmeter",
            "MatchedFinalEvent",
        ],
    )

    aligned_windows, aligned_box = lagged_values(windows, box_final, lag)
    aligned_rows = [
        {"AlignedFrame": index, "WindowsAudioLevel": left, "BoxFinal": right}
        for index, (left, right) in enumerate(zip(aligned_windows, aligned_box))
    ]
    write_csv(
        capture_directory / "aligned_signals.csv",
        aligned_rows,
        ["AlignedFrame", "WindowsAudioLevel", "BoxFinal"],
    )
    write_plot(capture_directory / "comparison.svg", windows, box_final, box_pre, lag)

    def rmse(values: Sequence[float]) -> float:
        return math.sqrt(statistics.fmean(value * value for value in values)) if values else float("nan")

    non_lyr_frames = sum(source != "LYR+" for source in sources)
    summary = [
        "Box 1 / Windows VU comparison",
        "================================",
        f"Rainmeter frames: {len(rainmeter_rows)} ({rain_times[-1]:.3f} s nominal)",
        f"Collector raw records: {len(collector_rows)} ({raw_times[-1]:.3f} s)",
        f"Rainmeter frames where Source was not LYR+: {non_lyr_frames}",
        "",
        "Playback-path correlation",
        f"Best Box-final offset relative to Windows: {offset_seconds * 1000.0:.3f} ms (positive means Box occurs later)",
        f"Aligned Windows-vs-Box-final correlation: {aligned_correlation:.6f}",
        f"Best Box-pre offset relative to Windows: {pre_lag * UPDATE_SECONDS * 1000.0:.3f} ms",
        f"Aligned Windows-vs-Box-pre correlation: {pre_correlation:.6f}",
        f"Local offset range: {offset_range:.3f} ms",
        f"Local offset standard deviation: {offset_stddev:.3f} ms",
        "",
        "Collector-to-Rainmeter transport",
        f"Raw collector sequence gaps: {raw_gaps}",
        f"Raw records in Rainmeter sequence span: {len(raw_scope)}",
        f"Unique raw sequences observed by Rainmeter: {len(seen_in_raw_scope)}",
        f"Raw records naturally between/not selected by Rainmeter observations: {max(0, len(raw_scope) - len(seen_in_raw_scope))}",
        f"Rainmeter-pre vs exact raw-sequence left RMSE: {rmse(mapping_errors_left):.9f}",
        f"Rainmeter-pre vs exact raw-sequence right RMSE: {rmse(mapping_errors_right):.9f}",
        f"Raw-to-Rainmeter fitted clock slope: {transport_slope:.9f} ({(transport_slope - 1.0) * 1_000_000.0:.3f} ppm)",
        "",
        "Box response",
        f"Measured Box-final vs reconstructed Lua response RMSE: {rmse(response_errors):.9f}",
        f"Raw prominent events: {len(raw_events)}",
        f"Raw events whose exact sequence was not observed by Rainmeter: {sum(row['SeenSequenceByRainmeter'] == 0 for row in raw_transient_rows)}",
        f"Raw events without a Box-final event within 160 ms: {len(raw_events) - len(raw_matches)}",
        "",
        "Cross-path events",
        f"Windows prominent events: {len(windows_events)}; matched after alignment: {len(windows_matches)}",
        f"Box-final prominent events: {len(box_final_events)}; matched after alignment: {len(box_matches)}",
    ]
    (capture_directory / "analysis_summary.txt").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print("\n".join(summary))
    print(f"\nResults written to: {capture_directory}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_directory", nargs="?", type=Path)
    parser.add_argument("--maximum-offset-seconds", type=float, default=30.0)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return 0
    if arguments.capture_directory is None:
        parser.error("capture_directory is required unless --self-test is used")
    analyze(arguments.capture_directory.resolve(), arguments.maximum_offset_seconds)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise
