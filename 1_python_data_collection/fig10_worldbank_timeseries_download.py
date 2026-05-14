from pathlib import Path
import io
import requests
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation, PillowWriter


def fetch_wb_indicator(indicator_code: str, start_year: int, end_year: int) -> pd.DataFrame:
    # World Bank API returns paginated JSON: [metadata, rows]
    url = (
        f"https://api.worldbank.org/v2/country/all/indicator/{indicator_code}"
        f"?format=json&per_page=20000&date={start_year}:{end_year}"
    )
    resp = requests.get(url, timeout=60)
    resp.raise_for_status()
    payload = resp.json()
    if not isinstance(payload, list) or len(payload) < 2:
        raise RuntimeError(f"Unexpected API response for {indicator_code}")

    rows = payload[1]
    out = []
    for r in rows:
        country_info = r.get("country", {}) or {}
        region_info = r.get("countryiso3code", "")
        out.append(
            {
                "iso3c": (r.get("countryiso3code") or "").strip(),
                "country": (country_info.get("value") or "").strip(),
                "year": int(r.get("date")) if r.get("date") else np.nan,
                "value": r.get("value"),
            }
        )
    return pd.DataFrame(out)


def fetch_country_meta() -> pd.DataFrame:
    url = "https://api.worldbank.org/v2/country?format=json&per_page=400"
    resp = requests.get(url, timeout=60)
    resp.raise_for_status()
    payload = resp.json()
    if not isinstance(payload, list) or len(payload) < 2:
        raise RuntimeError("Unexpected country metadata response")

    rows = payload[1]
    meta = []
    for r in rows:
        meta.append(
            {
                "iso3c": (r.get("id") or "").strip(),
                "iso2c": (r.get("iso2Code") or "").strip(),
                "region": ((r.get("region") or {}).get("value") or "").strip(),
                "income": ((r.get("incomeLevel") or {}).get("value") or "").strip(),
            }
        )
    return pd.DataFrame(meta)


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]
    out_dir = project_root / "2_rscript"
    out_dir.mkdir(parents=True, exist_ok=True)

    start_year, end_year = 2000, 2024
    indicators = {
        "forest_cover": "AG.LND.FRST.ZS",
        "urbanization": "SP.URB.TOTL.IN.ZS",
        "elderly_ratio": "SP.POP.65UP.TO.ZS",
        "gdp_per_capita": "NY.GDP.PCAP.CD",
    }

    frames = []
    for name, code in indicators.items():
        df = fetch_wb_indicator(code, start_year, end_year)
        df = df.rename(columns={"value": name})
        frames.append(df)

    # Merge on iso3c-country-year
    merged = frames[0]
    for df in frames[1:]:
        merged = merged.merge(df[["iso3c", "country", "year", [c for c in df.columns if c not in ["iso3c", "country", "year"]][0]]], on=["iso3c", "country", "year"], how="outer")

    meta = fetch_country_meta()
    wb_ts = merged.merge(meta, on="iso3c", how="left")

    # Drop aggregates and invalid codes
    wb_ts = wb_ts[
        (wb_ts["iso3c".strip()].str.len() == 3)
        & (~wb_ts["region"].fillna("").eq("Aggregates"))
        & (~wb_ts["region"].fillna("").eq(""))
    ].copy()

    wb_ts = wb_ts[[
        "iso2c", "iso3c", "country", "region", "income", "year",
        "forest_cover", "urbanization", "elderly_ratio", "gdp_per_capita"
    ]].sort_values(["country", "year"])

    csv_path = out_dir / "fig10_worldbank_timeseries_2000_2024.csv"
    xlsx_path = out_dir / "fig10_worldbank_timeseries_2000_2024.xlsx"
    wb_ts.to_csv(csv_path, index=False, encoding="utf-8-sig")
    wb_ts.to_excel(xlsx_path, index=False)

    # Build animation on regional yearly means
    anim_df = (
        wb_ts.groupby(["region", "year"], as_index=False)
        .agg(
            forest_cover=("forest_cover", "mean"),
            urbanization=("urbanization", "mean"),
            elderly_ratio=("elderly_ratio", "mean"),
            gdp_per_capita=("gdp_per_capita", "mean"),
        )
        .melt(id_vars=["region", "year"], var_name="indicator", value_name="value")
        .dropna(subset=["value"])
    )

    indicators_order = ["forest_cover", "urbanization", "elderly_ratio", "gdp_per_capita"]
    label_map = {
        "forest_cover": "Forest Cover (% land)",
        "urbanization": "Urbanization (% population)",
        "elderly_ratio": "Elderly Ratio (% 65+)",
        "gdp_per_capita": "GDP per Capita (USD)",
    }

    regions = sorted(anim_df["region"].dropna().unique().tolist())
    years = sorted(anim_df["year"].dropna().astype(int).unique().tolist())

    fig, axes_2d = plt.subplots(2, 2, figsize=(16, 11))
    axes = [axes_2d[0, 0], axes_2d[0, 1], axes_2d[1, 0], axes_2d[1, 1]]
    fig.patch.set_facecolor("white")

    color_cycle = plt.cm.tab20(np.linspace(0, 1, max(20, len(regions))))
    color_map = {r: color_cycle[i % len(color_cycle)] for i, r in enumerate(regions)}

    for ax, ind in zip(axes, indicators_order):
        ax.set_title(label_map[ind], fontsize=13, fontweight="bold", ha="center")
        ax.grid(True, alpha=0.2)

    def update(frame_year: int):
        for ax in axes:
            ax.cla()

        for ax, ind in zip(axes, indicators_order):
            ax.set_title(label_map[ind], fontsize=13, fontweight="bold", ha="center")
            sub = anim_df[(anim_df["indicator"] == ind) & (anim_df["year"] <= frame_year)]
            for r in regions:
                rs = sub[sub["region"] == r]
                if rs.empty:
                    continue
                ax.plot(rs["year"], rs["value"], linewidth=1.8, alpha=0.9, color=color_map[r], label=r)
                ax.scatter(rs["year"].iloc[-1], rs["value"].iloc[-1], s=18, color=color_map[r], alpha=0.95)
            ax.grid(True, alpha=0.2)
            ax.tick_params(axis="both", labelsize=10)
            ax.set_ylabel("Value", fontsize=11)
            ax.set_xlabel("Year", fontsize=11)
        fig.suptitle(
            f"Global Time Evolution of Key Indicators ({frame_year})\n"
            "World Bank annual series, 2000-2024 (regional means)",
            fontsize=16,
            fontweight="bold",
            y=0.98,
        )
        fig.text(
            0.01,
            0.01,
            "Note: dog park currently snapshot-based (2023 static).",
            fontsize=10,
            color="#444444",
        )

    # Draw legend once using all regions
    legend_handles = [
        plt.Line2D([0], [0], color=color_map[r], lw=2, label=r) for r in regions
    ]
    fig.legend(handles=legend_handles, loc="lower center", ncol=4, fontsize=9, frameon=False, bbox_to_anchor=(0.5, 0.0))
    plt.tight_layout(rect=[0, 0.07, 1, 0.94])

    gif_path = out_dir / "fig10_time_evolution.gif"
    ani = FuncAnimation(fig, update, frames=years, repeat=True)
    ani.save(gif_path, writer=PillowWriter(fps=8))
    plt.close(fig)

    print(f"Saved: {csv_path}")
    print(f"Saved: {xlsx_path}")
    print(f"Saved: {gif_path}")


if __name__ == "__main__":
    main()
