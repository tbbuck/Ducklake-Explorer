#!/usr/bin/env bash
# Build (and validate) the sample DuckLake fixture.
# Rebuilds from scratch, then re-opens it READ_ONLY by ABSOLUTE path from a
# neutral working directory to prove the catalog is openable the way the app
# will open it (CWD-independent), with data_path resolved relative to the file.
set -euo pipefail

cd "$(dirname "$0")"                 # -> Fixtures/
CATALOG="sample.ducklake"
ABS="$(pwd)/$CATALOG"

echo "==> Rebuilding $ABS"
rm -rf "$CATALOG" "$CATALOG.files"
duckdb -init /dev/null -f build_fixture.sql
echo "==> Built. Validating a READ_ONLY open by absolute path from /tmp ..."

cd /tmp
duckdb -init /dev/null <<SQL
LOAD ducklake;
LOAD spatial;
ATTACH 'ducklake:$ABS' AS lake (READ_ONLY);
USE lake;
.mode box
SELECT count(*) AS observations_now FROM observations;
SELECT count(*) AS n_snapshots FROM ducklake_snapshots('lake');
SELECT * FROM ducklake_snapshots('lake') ORDER BY snapshot_id;
SELECT id, species, region, ST_AsText(geom) AS geom_wkt FROM observations ORDER BY id;
SELECT * FROM ducklake_list_files('lake', 'observations') LIMIT 8;
SQL
echo "==> Fixture OK: $ABS"
