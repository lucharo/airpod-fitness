# /// script
# dependencies = ["pandas", "numpy", "matplotlib"]
# ///
"""Summarise an Air Posture position recording (air-posture-positions-*.csv).

For each position and rep, compares the "hold" segment with the "upright" segment just before it:
change in pitch, roll and yaw, the angle between the two gravity vectors, and the peak user
acceleration during the transition into the position. Writes <csv>.summary.csv and <csv>.png.

uv run tools/analyze_positions.py path/to/air-posture-positions-....csv
"""
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


def angle_between(a: np.ndarray, b: np.ndarray) -> float:
    cos = np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b))
    return float(np.degrees(np.arccos(np.clip(cos, -1, 1))))


def summarise(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    # build 4 and earlier: reference phase "upright", opening "baseline"; build 8+: "rest" and position "usual"
    reference_phases = {"upright", "rest"}
    opening = {"baseline", "usual"}
    for (pos, rep), g in df[~df.position.isin(opening | {"setup", "end"})].groupby(["position", "rep"], sort=False):
        upright, hold, into = g[g.phase.isin(reference_phases)], g[g.phase == "hold"], g[g.phase == "into"]
        if upright.empty:  # first rep of the first position uses the opening reference
            upright = df[df.position.isin(opening)].tail(200)
        if hold.empty:
            continue
        if "still" in hold:  # build 8+: keep only the still samples of a hold
            hold = hold[hold.still == 1]
        else:  # skip the first second of each hold so the transition does not leak in
            hold = hold[hold.t_wall >= hold.t_wall.min() + 1]
        if hold.empty:
            continue
        grav_u = upright[["grav_x", "grav_y", "grav_z"]].mean().to_numpy()
        grav_h = hold[["grav_x", "grav_y", "grav_z"]].mean().to_numpy()
        acc = np.sqrt(into.acc_x**2 + into.acc_y**2 + into.acc_z**2) if not into.empty else pd.Series([np.nan])
        # iPhone in a chest pocket (pocket mode): trunk angle change between upright and hold
        trunk = np.nan
        if "ph_grav_x" in df and hold.ph_grav_x.notna().any() and upright.ph_grav_x.notna().any():
            trunk = angle_between(upright[["ph_grav_x", "ph_grav_y", "ph_grav_z"]].mean().to_numpy(),
                                  hold[["ph_grav_x", "ph_grav_y", "ph_grav_z"]].mean().to_numpy())
        rows.append({
            "position": pos, "rep": rep,
            "d_pitch": hold.pitch.mean() - upright.pitch.mean(),
            "d_roll": hold.roll.mean() - upright.roll.mean(),
            "d_yaw": hold.yaw.mean() - upright.yaw.mean(),
            "gravity_angle": angle_between(grav_u, grav_h),
            "hold_pitch_sd": hold.pitch.std(),
            "into_peak_acc_g": acc.max(),
            "trunk_angle": trunk,
            "n_hold": len(hold),
            "moved_by": g.moved_by.dropna().iloc[0] if "moved_by" in g and g.moved_by.notna().any() else "",
        })
    return pd.DataFrame(rows)


def main() -> None:
    path = Path(sys.argv[1])
    df = pd.read_csv(path, comment="#")
    df["t"] = df.t_wall - df.t_wall.min()
    s = summarise(df)
    s.round(2).to_csv(path.with_suffix(".summary.csv"), index=False)
    by_pos = s.groupby("position", sort=False)[["d_pitch", "d_roll", "d_yaw", "gravity_angle", "trunk_angle", "into_peak_acc_g"]].mean()
    rate = len(df) / df.t.max() if df.t.max() > 0 else 0
    print(f"{len(df)} samples over {df.t.max():.0f} s ({rate:.1f} Hz), sensors: {df.sensor.value_counts().to_dict()}")
    print(by_pos.round(1).to_string())

    fig, axes = plt.subplots(3, 1, figsize=(16, 9), sharex=True)
    for ax, col in zip(axes, ["pitch", "roll", "yaw"]):
        ax.plot(df.t, df[col], lw=0.8, color="black")
        ax.set_ylabel(f"{col} (°)")
        for _, seg in df[df.phase == "hold"].groupby(["position", "rep"], sort=False):
            ax.axvspan(seg.t.min(), seg.t.max(), color="0.85", lw=0)
    for (pos, rep), seg in df[(df.phase == "hold") & (df.rep == 1)].groupby(["position", "rep"], sort=False):
        axes[0].annotate(pos, (seg.t.mean(), axes[0].get_ylim()[1]), ha="center", va="top", fontsize=8, rotation=90)
    axes[-1].set_xlabel("seconds (grey = hold segments)")
    fig.tight_layout()
    fig.savefig(path.with_suffix(".png"), dpi=150)
    print(f"wrote {path.with_suffix('.summary.csv')} and {path.with_suffix('.png')}")


if __name__ == "__main__":
    main()
