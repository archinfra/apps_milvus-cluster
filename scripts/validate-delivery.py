#!/usr/bin/env python3
"""Static delivery invariants for the Archinfra Milvus offline package."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IMAGE_JSON = ROOT / "images" / "image.json"
CHART = ROOT / "charts" / "milvus" / "Chart.yaml"
DELIVERY_VALUES = ROOT / "charts" / "milvus" / "archinfra-values.yaml"
OVERLAY = ROOT / "scripts" / "install-overlay.sh"
BUILD = ROOT / "build.sh"


def require(path: Path, *needles: str) -> None:
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            raise SystemExit(f"{path}: missing required invariant: {needle}")


def reject(path: Path, *needles: str) -> None:
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle in text:
            raise SystemExit(f"{path}: forbidden delivery invariant remains: {needle}")


def validate_images() -> None:
    items = json.loads(IMAGE_JSON.read_text(encoding="utf-8"))
    by_arch: dict[str, dict[str, dict]] = {}
    for item in items:
        arch = item["arch"]
        tar = item["tar"]
        by_arch.setdefault(arch, {})[tar.split(f"-{arch}.tar")[0]] = item

    for arch in ("amd64", "arm64"):
        images = by_arch.get(arch, {})
        if not images:
            raise SystemExit(f"missing image set for {arch}")

        expected_pull = {
            "milvus": "milvusdb/milvus:v2.6.23",
            # Explicit freeze requested for this hardening release.
            "etcd": "milvusdb/etcd:3.5.25-r1",
            # Keep the exact frozen MinIO release. Quay is the original chart's
            # published source; Docker Hub stopped serving this old tag to CI.
            "minio": "quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z",
            "pulsar": "apachepulsar/pulsar:3.0.17",
        }
        expected_target = {
            "milvus": "sealos.hub:5000/kube4/milvus:v2.6.23",
            "etcd": "sealos.hub:5000/kube4/etcd:3.5.25-r1",
            "minio": "sealos.hub:5000/kube4/minio:RELEASE.2024-12-18T13-15-44Z",
            "pulsar": "sealos.hub:5000/kube4/pulsar:3.0.17",
        }
        for name, pull in expected_pull.items():
            actual = images.get(name, {}).get("pull")
            if actual != pull:
                raise SystemExit(
                    f"{arch}: {name} pull mismatch: expected {pull!r}, got {actual!r}"
                )
            target = images.get(name, {}).get("tag")
            if target != expected_target[name]:
                raise SystemExit(
                    f"{arch}: {name} target mismatch: expected {expected_target[name]!r}, got {target!r}"
                )

        platform = f"linux/{arch}"
        for item in images.values():
            if item.get("platform") != platform:
                raise SystemExit(
                    f"{arch}: platform mismatch for {item.get('tar')}: {item.get('platform')}"
                )


def main() -> int:
    validate_images()

    require(CHART, "appVersion: 2.6.23", "version: 5.0.12")
    require(
        DELIVERY_VALUES,
        "tag: v2.6.23",
        "tag: 3.0.17",
        "format: json",
        "Embedded etcd and MinIO are intentionally NOT changed",
    )
    require(
        OVERLAY,
        'APP_VERSION="0.2.0"',
        'RESOURCE_PROFILE="standard"',
        'ENABLE_AUTH="true"',
        'AUTH_SECRET="milvus-auth"',
        "authorizationEnabled: true",
        "defaultRootPassword:",
        "resource-profile 仅支持 lite|standard|large",
        "--compact 已移除",
        'MILVUS_STREAMINGNODE_LIMIT_MEM="4Gi"',
        'MILVUS_STREAMINGNODE_REPLICAS="2"',
        "Secret/${AUTH_SECRET}",
    )
    require(
        BUILD,
        'INSTALLER_OVERLAY="${ROOT_DIR}/scripts/install-overlay.sh"',
        "assemble_installer_template",
        "bash -n",
    )

    # The build/runtime path must not depend on jq in restricted customer sites.
    reject(BUILD, "command -v jq", "jq ")
    reject(OVERLAY, "command -v jq", "jq ")

    print(
        "validated Milvus 2.6.23 delivery baseline, canonical resource profiles, "
        "authentication defaults, frozen etcd/MinIO pins, optional Pulsar 3.0.17, "
        "and offline installer invariants"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
