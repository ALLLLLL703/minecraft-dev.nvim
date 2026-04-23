#!/bin/env python
import requests
import xml.etree.ElementTree as ET
import json
import sys
from pathlib import Path


BASE = "https://meta.fabricmc.net/v2"
MAVEN = "https://maven.fabricmc.net"


def fetch_json(url: str) -> dict | list:
    resp = requests.get(url, timeout=10)
    resp.raise_for_status()
    return resp.json()


def get_mc_version(stable_only: bool = True) -> list[str]:
    data = fetch_json(f"{BASE}/versions/game")
    return [v["version"] for v in data if not stable_only or v["stable"]]


def get_yarn_for_mc_version(version: str) -> str | None:
    data = fetch_json(f"{BASE}/versions/yarn/{version}")
    if not data:
        return None
    return data[0]["version"]


def get_latest_loader() -> str:
    data = fetch_json(f"{BASE}/versions/loader")
    for v in data:
        if v["stable"]:
            return v["version"]
    return data[0]["version"]


def get_fabric_api_versions_mc(mc_version: str) -> list[str] | None:

    url = f"{MAVEN}/net/fabricmc/fabric-api/fabric-api/maven-metadata.xml"
    resp = requests.get(url, timeout=10)
    resp.raise_for_status()

    root = ET.fromstring(resp.text)
    all_versions = [v.text for v in root.findall(".//version")]

    matched = [
        v for v in all_versions if type(v) == str and v.endswith(f"+{mc_version}")
    ]
    return matched[:-1] if matched else None


def build_versions_map(stable_only: bool = True) -> dict:

    mc_versions = get_mc_version(stable_only)
    loader = get_latest_loader()
    current_file = Path(__file__).resolve()
    plugin_root = current_file.parent.parent
    data_fabric_dir = plugin_root.joinpath("data/fabric/versions")
    if not data_fabric_dir.exists():
        data_fabric_dir.mkdir(parents=True)

    result = {}
    for mc in mc_versions:
        print(f"Fetching {mc}...")
        result[mc] = {
            "yarn": get_yarn_for_mc_version(mc),
            "loader": loader,
            "fabric_api": get_fabric_api_versions_mc(mc),
            
        }
        data_fabric_json = data_fabric_dir.joinpath(f"{mc}.json") 
        data_fabric_json.write_text(json.dumps(result[mc]))
    return result
def build_version_map(mc_version: str) -> dict:
    loader = get_latest_loader()
    result = {"yarn": get_yarn_for_mc_version(mc_version),"loader": loader,"fabric_api" : get_fabric_api_versions_mc(mc_version)}
    return result
    
     
    


if __name__ == "__main__":
    if sys.argv.__len__() <= 1:
        version_map = build_versions_map(stable_only=True)
    else:
        result_map = build_version_map(sys.argv[1])
        print(json.dumps(result_map))
        

    
