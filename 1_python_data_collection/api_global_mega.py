#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Global Dog Parks Data - Unified Collector
Data Source: OpenStreetMap + Overpass API

Modes:
1) Full collection (all ISO 3166-1 alpha-2 code elements)
2) Targeted recovery (US/HK) with merge into existing outputs
"""

import argparse
import json
import os
import time
from typing import Dict, List, Optional, Tuple

import pandas as pd
import pycountry
import requests


API_URL = "https://overpass.kumi.systems/api/interpreter"
BACKUP_URL = "https://z.overpass-api.de/api/interpreter"
THIRD_URL = "https://overpass-api.de/api/interpreter"
OVERPASS_ENDPOINTS = [API_URL, BACKUP_URL, THIRD_URL]

OUTPUT_DIR = os.path.join("3_output", "dashboard")
CSV_FILE = os.path.join(OUTPUT_DIR, "pet_parks_by_country.csv")
GEOJSON_FILE = os.path.join(OUTPUT_DIR, "pet_parks_by_country.geojson")
COVERAGE_FILE = os.path.join(OUTPUT_DIR, "country_coverage_report.csv")
METADATA_FILE = os.path.join(OUTPUT_DIR, "dataset_metadata.json")

PRIORITY_COUNTRIES = {"US", "GB", "HK", "CN", "JP", "DE", "FR", "IN", "BR"}

ISO_STANDARD_NAME = "ISO 3166-1 alpha-2"
ISO_STANDARD_SCOPE = "code elements for countries and territories"
ISO_STANDARD_NOTE = "This scope is not equivalent to sovereign-state counts."

os.makedirs(OUTPUT_DIR, exist_ok=True)

HTTP_PROXY = os.getenv("HTTP_PROXY")
HTTPS_PROXY = os.getenv("HTTPS_PROXY")
PROXIES = None
if HTTP_PROXY or HTTPS_PROXY:
    PROXIES = {
        "http": HTTP_PROXY or HTTPS_PROXY,
        "https": HTTPS_PROXY or HTTP_PROXY,
    }

session = requests.Session()
session.headers.update(
    {
        "User-Agent": "GlobalDogParksCollector/2.0 (academic use; local-research-script)",
    }
)


def load_iso_countries() -> Tuple[List[str], Dict[str, str]]:
    countries_list = []
    country_names = {}
    for country in pycountry.countries:
        countries_list.append(country.alpha_2)
        country_names[country.alpha_2] = country.name
    return countries_list, country_names


def build_country_query(iso_code: str) -> str:
    return f"""
[out:json][timeout:90];
area["ISO3166-1"="{iso_code}"][admin_level=2]->.searchArea;
(
  node["leisure"="dog_park"](area.searchArea);
  way["leisure"="dog_park"](area.searchArea);
);
out center;
"""


def post_overpass(
    query: str,
    label: str,
    max_retries: int = 3,
    timeout: Tuple[int, int] = (10, 30),
    sleep_base: float = 2.0,
) -> Tuple[Optional[dict], Optional[str], Optional[int]]:
    last_err = None
    last_code = None

    for attempt in range(max_retries + 1):
        url = OVERPASS_ENDPOINTS[attempt % len(OVERPASS_ENDPOINTS)]
        try:
            response = session.post(url, data=query, timeout=timeout, proxies=PROXIES)
            last_code = response.status_code

            if response.status_code == 200:
                try:
                    return response.json(), None, 200
                except json.JSONDecodeError:
                    return None, "failed_json", 200

            if response.status_code == 429:
                last_err = "rate_limit"
            elif response.status_code == 504:
                last_err = "gateway_timeout"
            else:
                last_err = f"http_{response.status_code}"

            time.sleep(sleep_base + attempt)
        except requests.exceptions.Timeout:
            last_err = "timeout"
            time.sleep(sleep_base + attempt)
        except requests.exceptions.RequestException:
            last_err = "request_exception"
            time.sleep(sleep_base + attempt)
        except KeyboardInterrupt:
            raise
        except Exception:
            last_err = "unknown_exception"
            time.sleep(sleep_base + attempt)

    print(f"  ❌ {label} failed after retries: {last_err}")
    return None, last_err, last_code


def normalize_park_elements(elements: List[dict], country_code: str, country_name: str) -> List[dict]:
    parks = []
    for elem in elements:
        etype = elem.get("type")

        if etype == "node":
            lat = elem.get("lat")
            lon = elem.get("lon")
        elif etype == "way" and "center" in elem:
            lat = elem["center"].get("lat")
            lon = elem["center"].get("lon")
        else:
            continue

        if lat is None or lon is None:
            continue

        name = elem.get("tags", {}).get("name", f"Dog Park {elem.get('id')}")
        parks.append(
            {
                "name": name,
                "latitude": float(lat),
                "longitude": float(lon),
                "country_code": country_code,
                "country_name": country_name,
                "osm_id": int(elem.get("id")),
                "osm_type": etype,
                "data_source": "OpenStreetMap",
            }
        )
    return parks


def write_geojson(df: pd.DataFrame, countries_queried: int, successful_queries: int, query_method: str) -> None:
    features = []
    for _, row in df.iterrows():
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [float(row["longitude"]), float(row["latitude"])],
            },
            "properties": {
                "name": row["name"],
                "country": row["country_name"],
                "country_code": row["country_code"],
                "osm_id": int(row["osm_id"]),
                "osm_type": row["osm_type"],
            },
        }
        features.append(feature)

    geojson = {
        "type": "FeatureCollection",
        "properties": {
            "title": "Global Dog Parks Dataset",
            "description": f"Dog parks from {countries_queried} ISO 3166-1 code elements",
            "data_source": "OpenStreetMap contributors via Overpass API",
            "citation": "OpenStreetMap Foundation (2024). https://www.openstreetmap.org/",
            "api": "Overpass API https://overpass-api.de/",
            "query_method": query_method,
            "query_tag": "leisure=dog_park",
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "total_parks": int(len(df)),
            "countries_queried": int(countries_queried),
            "countries_with_results": int(df["country_code"].nunique() if not df.empty else 0),
            "successful_queries": int(successful_queries),
            "iso_standard": ISO_STANDARD_NAME,
            "iso_scope": ISO_STANDARD_SCOPE,
            "iso_total_code_elements": int(countries_queried),
            "iso_note": ISO_STANDARD_NOTE,
        },
        "features": features,
    }

    with open(GEOJSON_FILE, "w", encoding="utf-8") as f:
        json.dump(geojson, f, indent=2, ensure_ascii=False)


def write_metadata_json(
    countries_queried: int,
    successful_queries: int,
    countries_with_data: int,
    failed_queries: int,
    zero_result_queries: int,
    mode: str,
) -> None:
    metadata = {
        "dataset": "Global Dog Parks Dataset",
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "mode": mode,
        "source": "OpenStreetMap contributors via Overpass API",
        "query_tag": "leisure=dog_park",
        "iso_standard": ISO_STANDARD_NAME,
        "iso_scope": ISO_STANDARD_SCOPE,
        "iso_total_code_elements": int(countries_queried),
        "iso_note": ISO_STANDARD_NOTE,
        "summary": {
            "countries_queried": int(countries_queried),
            "successful_queries": int(successful_queries),
            "countries_with_data": int(countries_with_data),
            "failed_queries": int(failed_queries),
            "zero_result_queries": int(zero_result_queries),
        },
        "files": {
            "csv": CSV_FILE,
            "geojson": GEOJSON_FILE,
            "coverage": COVERAGE_FILE,
        },
    }

    with open(METADATA_FILE, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, ensure_ascii=False)


def init_empty_df() -> pd.DataFrame:
    cols = [
        "name",
        "latitude",
        "longitude",
        "country_code",
        "country_name",
        "osm_id",
        "osm_type",
        "data_source",
    ]
    return pd.DataFrame(columns=cols)


def sanitize_df(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return df

    cleaned = df.copy()
    for col in ["country_code", "osm_type", "osm_id", "latitude", "longitude"]:
        if col not in cleaned.columns:
            continue
        cleaned[col] = cleaned[col].astype(str).str.strip() if col in {"country_code", "osm_type"} else cleaned[col]

    cleaned = cleaned[cleaned["country_code"].notna()]
    cleaned = cleaned[cleaned["country_code"].astype(str).str.len() > 0]
    cleaned = cleaned[cleaned["osm_type"].notna()]
    cleaned = cleaned[cleaned["osm_type"].astype(str).str.len() > 0]
    cleaned = cleaned[cleaned["osm_id"].notna()]
    cleaned = cleaned[cleaned["latitude"].notna()]
    cleaned = cleaned[cleaned["longitude"].notna()]

    cleaned["country_code"] = cleaned["country_code"].astype(str)
    cleaned["osm_type"] = cleaned["osm_type"].astype(str)
    cleaned["osm_id"] = pd.to_numeric(cleaned["osm_id"], errors="coerce")
    cleaned = cleaned[cleaned["osm_id"].notna()]
    cleaned["osm_id"] = cleaned["osm_id"].astype(int)
    return cleaned


def run_full_collection(countries_list: List[str], country_names: Dict[str, str]) -> None:
    print("\nGlobal Dog Parks Data - Full Collection")
    print("=" * 70)

    all_parks = []
    success_count = 0
    failed_countries = []
    zero_result_countries = []
    query_result_count = {}
    query_status = {}

    for i, iso_code in enumerate(countries_list):
        country_name = country_names.get(iso_code, iso_code)
        display_name = f"{iso_code} ({country_name[:20]})"
        print(f"[{i + 1:3d}/{len(countries_list)}] {display_name:30s}", end=" ", flush=True)

        query = build_country_query(iso_code)
        data, err, status_code = post_overpass(query, f"FULL-{iso_code}", max_retries=2, timeout=(10, 30))

        if data is None:
            print("❌ Failed", flush=True)
            query_result_count[iso_code] = 0
            if err == "failed_json":
                query_status[iso_code] = "failed_json"
            else:
                query_status[iso_code] = "failed_http_or_exception"
            failed_countries.append(iso_code)
            time.sleep(1.0)
            continue

        elements = data.get("elements", [])
        count = len(elements)
        query_result_count[iso_code] = count
        query_status[iso_code] = "success_with_data" if count > 0 else "success_zero_results"

        if count == 0:
            zero_result_countries.append(iso_code)

        parks = normalize_park_elements(elements, iso_code, country_name)
        all_parks.extend(parks)
        success_count += 1

        print(f"✅ {count:4d} parks", flush=True)
        time.sleep(1.2)

    df = pd.DataFrame(all_parks) if all_parks else init_empty_df()
    df = sanitize_df(df)
    if not df.empty:
        df = df.drop_duplicates(subset=["osm_type", "osm_id"], keep="first")

    df.to_csv(CSV_FILE, index=False)

    write_geojson(
        df=df,
        countries_queried=len(countries_list),
        successful_queries=success_count,
        query_method="By country administrative boundaries",
    )

    countries_with_data = set(df["country_code"].unique()) if not df.empty else set()
    missing_countries = sorted(list(set(countries_list) - countries_with_data))

    coverage_rows = []
    for iso_code in countries_list:
        coverage_rows.append(
            {
                "country_code": iso_code,
                "country_name": country_names.get(iso_code, iso_code),
                "query_status": query_status.get(iso_code, "unknown"),
                "park_count": int(query_result_count.get(iso_code, 0)),
                "has_data": iso_code in countries_with_data,
                "is_priority_country": iso_code in PRIORITY_COUNTRIES,
                "is_missing_after_run": iso_code in missing_countries,
            }
        )

    coverage_df = pd.DataFrame(coverage_rows)
    coverage_df.to_csv(COVERAGE_FILE, index=False)

    write_metadata_json(
        countries_queried=len(countries_list),
        successful_queries=success_count,
        countries_with_data=len(countries_with_data),
        failed_queries=len(failed_countries),
        zero_result_queries=len(zero_result_countries),
        mode="full",
    )

    print("\n" + "=" * 70)
    print("\nSaved files:")
    print(f"  - {CSV_FILE}")
    print(f"  - {GEOJSON_FILE}")
    print(f"  - {COVERAGE_FILE}")
    print(f"  - {METADATA_FILE}")

    print("\nDetailed Statistics:")
    print(f"  Total parks: {len(df):,}")
    print(f"  Countries queried: {len(countries_list)}")
    print(f"  Countries with data: {len(countries_with_data)}")
    print(f"  Successful queries: {success_count}")
    print(f"  Zero-result queries: {len(zero_result_countries)}")
    print(f"  Failed queries: {len(failed_countries)}")

    priority_missing = [c for c in missing_countries if c in PRIORITY_COUNTRIES]
    if priority_missing:
        print(f"\nPriority countries still missing: {', '.join(priority_missing)}")


def fetch_hk_targeted(country_names: Dict[str, str]) -> Tuple[List[dict], str]:
    hk_name = country_names.get("HK", "Hong Kong")
    print("\nTargeted HK query")

    query_main = """
[out:json][timeout:120];
area["ISO3166-1"="HK"]->.searchArea;
(
  node["leisure"="dog_park"](area.searchArea);
  way["leisure"="dog_park"](area.searchArea);
);
out center;
"""

    data, err, _ = post_overpass(query_main, "HK-main", max_retries=4, timeout=(15, 60))
    if data is not None:
        parks = normalize_park_elements(data.get("elements", []), "HK", hk_name)
        print(f"  HK-main: {len(parks)} parks")
        if parks:
            return parks, "success_with_data"

    query_bbox = """
[out:json][timeout:120];
(
  node["leisure"="dog_park"](22.15,113.82,22.57,114.45);
  way["leisure"="dog_park"](22.15,113.82,22.57,114.45);
);
out center;
"""

    data_fb, err_fb, _ = post_overpass(query_bbox, "HK-bbox", max_retries=4, timeout=(15, 60))
    if data_fb is not None:
        parks_fb = normalize_park_elements(data_fb.get("elements", []), "HK", hk_name)
        print(f"  HK-bbox: {len(parks_fb)} parks")
        if parks_fb:
            return parks_fb, "success_with_data"
        return [], "success_zero_results"

    return [], "failed_http_or_exception"


def fetch_us_targeted(country_names: Dict[str, str]) -> Tuple[List[dict], str, int, int]:
    us_name = country_names.get("US", "United States")
    print("\nTargeted US query by state chunks")

    states_query = """
[out:json][timeout:180];
area["ISO3166-1"="US"]["admin_level"="2"]->.us;
rel(area.us)["boundary"="administrative"]["admin_level"="4"]["ISO3166-2"~"^US-"];
out ids tags;
"""

    states_data, err, _ = post_overpass(states_query, "US-state-list", max_retries=6, timeout=(20, 120))
    if states_data is None:
        return [], "failed_http_or_exception", 0, 0

    state_rels = [e for e in states_data.get("elements", []) if e.get("type") == "relation"]
    state_rels.sort(key=lambda x: x.get("tags", {}).get("ISO3166-2", ""))

    print(f"  State chunks: {len(state_rels)}")
    all_us = []
    ok_states = 0
    failed_states = 0

    for idx, rel in enumerate(state_rels, start=1):
        rel_id = rel.get("id")
        code = rel.get("tags", {}).get("ISO3166-2", f"US-UNK-{idx}")
        state_name = rel.get("tags", {}).get("name", code)
        area_id = 3600000000 + int(rel_id)

        parks_query = f"""
[out:json][timeout:180];
area({area_id})->.searchArea;
(
  node["leisure"="dog_park"](area.searchArea);
  way["leisure"="dog_park"](area.searchArea);
);
out center;
"""

        data, err, _ = post_overpass(parks_query, f"US-{code}", max_retries=5, timeout=(20, 120))
        if data is None:
            failed_states += 1
            print(f"  [{idx:02d}/{len(state_rels)}] {code:<8} {state_name[:24]:24s} failed")
            continue

        parks = normalize_park_elements(data.get("elements", []), "US", us_name)
        all_us.extend(parks)
        ok_states += 1
        print(f"  [{idx:02d}/{len(state_rels)}] {code:<8} {state_name[:24]:24s} {len(parks):4d} parks")
        time.sleep(0.7)

    if all_us:
        return all_us, "success_with_data", ok_states, failed_states
    if failed_states == 0:
        return [], "success_zero_results", ok_states, failed_states
    return [], "failed_http_or_exception", ok_states, failed_states


def load_existing_csv() -> pd.DataFrame:
    if os.path.exists(CSV_FILE):
        return pd.read_csv(CSV_FILE)
    return init_empty_df()


def load_or_init_coverage(countries_list: List[str], country_names: Dict[str, str]) -> pd.DataFrame:
    if os.path.exists(COVERAGE_FILE):
        return pd.read_csv(COVERAGE_FILE)

    rows = []
    for code in countries_list:
        rows.append(
            {
                "country_code": code,
                "country_name": country_names.get(code, code),
                "query_status": "unknown",
                "park_count": 0,
                "has_data": False,
                "is_priority_country": code in PRIORITY_COUNTRIES,
                "is_missing_after_run": True,
            }
        )
    return pd.DataFrame(rows)


def run_targeted_recovery(countries_list: List[str], country_names: Dict[str, str], only_hk: bool, only_us: bool) -> None:
    active_targets = {"US", "HK"}
    if only_hk and only_us:
        raise SystemExit("Please use only one of --only-hk or --only-us.")
    if only_hk:
        active_targets = {"HK"}
    elif only_us:
        active_targets = {"US"}

    print("\nGlobal Dog Parks Data - Targeted Recovery")
    print("=" * 70)

    hk_parks = []
    us_parks = []
    hk_status = "not_run"
    us_status = "not_run"
    us_ok_states = 0
    us_failed_states = 0

    if "HK" in active_targets:
        hk_parks, hk_status = fetch_hk_targeted(country_names)
    if "US" in active_targets:
        us_parks, us_status, us_ok_states, us_failed_states = fetch_us_targeted(country_names)

    recovered = hk_parks + us_parks
    recovered_df = pd.DataFrame(recovered) if recovered else init_empty_df()

    existing = load_existing_csv()
    base = existing[~existing["country_code"].isin(active_targets)].copy()
    merged = pd.concat([base, recovered_df], ignore_index=True)
    merged = sanitize_df(merged)

    if not merged.empty:
        # Keep new recovered rows when OSM objects overlap.
        merged = merged.drop_duplicates(subset=["osm_type", "osm_id"], keep="last")
        merged = merged.sort_values(by=["country_code", "name", "osm_id"], kind="stable").reset_index(drop=True)

    merged.to_csv(CSV_FILE, index=False)

    coverage = load_or_init_coverage(countries_list, country_names)
    status_map = {"HK": hk_status, "US": us_status}

    # Keep park_count/has_data fully aligned with merged output for all countries.
    merged_counts = merged.groupby("country_code").size().to_dict() if not merged.empty else {}
    coverage["park_count"] = coverage["country_code"].map(lambda c: int(merged_counts.get(c, 0)))
    coverage["has_data"] = coverage["park_count"] > 0
    coverage["is_missing_after_run"] = ~coverage["has_data"]

    for code in active_targets:
        count = int(merged_counts.get(code, 0))
        status = status_map.get(code, "unknown")
        if status == "success_with_data" and count == 0:
            status = "success_zero_results"

        coverage.loc[coverage["country_code"] == code, "query_status"] = status

    coverage.to_csv(COVERAGE_FILE, index=False)

    success_rows = int((coverage["query_status"].astype(str).str.startswith("success")).sum())
    failed_rows = int((coverage["query_status"].astype(str).str.startswith("failed")).sum())
    zero_rows = int((coverage["query_status"] == "success_zero_results").sum())
    has_data_rows = int((coverage["has_data"] == True).sum())

    write_geojson(
        df=merged,
        countries_queried=len(countries_list),
        successful_queries=success_rows,
        query_method="Targeted recovery merge (US/HK) on top of existing dataset",
    )

    write_metadata_json(
        countries_queried=len(countries_list),
        successful_queries=success_rows,
        countries_with_data=has_data_rows,
        failed_queries=failed_rows,
        zero_result_queries=zero_rows,
        mode="targeted_recovery",
    )

    print("\nSaved files:")
    print(f"  - {CSV_FILE}")
    print(f"  - {GEOJSON_FILE}")
    print(f"  - {COVERAGE_FILE}")
    print(f"  - {METADATA_FILE}")

    if "HK" in active_targets:
        hk_count = int((merged["country_code"] == "HK").sum())
        print(f"  HK parks: {hk_count} | status={hk_status}")
    if "US" in active_targets:
        us_count = int((merged["country_code"] == "US").sum())
        print(f"  US parks: {us_count} | status={us_status}")
        print(f"  US state chunks: success={us_ok_states}, failed={us_failed_states}")

    print("\nCoverage Summary:")
    print(f"  countries queried: {len(countries_list)}")
    print(f"  success rows: {success_rows}")
    print(f"  failed rows: {failed_rows}")
    print(f"  countries with data: {has_data_rows}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Global dog park collection and targeted recovery")
    parser.add_argument(
        "--mode",
        choices=["full", "targeted"],
        default="full",
        help="Run full collection or targeted US/HK recovery",
    )
    parser.add_argument("--only-hk", action="store_true", help="Targeted mode: run HK only")
    parser.add_argument("--only-us", action="store_true", help="Targeted mode: run US only")
    args = parser.parse_args()

    print("\nGlobal Dog Parks Data")
    print("=" * 70)

    if PROXIES:
        print("Proxy mode: enabled")
    else:
        print("Proxy mode: direct")

    countries_list, country_names = load_iso_countries()
    print(f"ISO list loaded: {len(countries_list)} code elements")
    print(f"ISO standard: {ISO_STANDARD_NAME}")
    print(f"ISO scope: {ISO_STANDARD_SCOPE}")

    if args.mode == "full":
        run_full_collection(countries_list, country_names)
    else:
        run_targeted_recovery(countries_list, country_names, args.only_hk, args.only_us)


if __name__ == "__main__":
    main()
