-- Builds the sample DuckLake used by tests and the M0 demo.
-- Run via build_fixture.sh (which cd's into Fixtures/ first). The ATTACH sets an explicit
-- relative DATA_PATH, so the catalog stores 'sample.ducklake.files/' rather than an absolute
-- machine path. DuckLake resolves a relative data_path against the catalog file's own directory,
-- so the committed fixture is portable (CI, a clean Mac, any clone) — verified by moving a lake
-- and reopening it from a neutral working directory.
--
-- Exercises, across ~10 snapshots: table creation, partitioning, a sort order,
-- two insert batches, a DELETE (delete file), schema evolution (ADD COLUMN +
-- UPDATE), a GEOMETRY column, and a second unpartitioned table.
-- Coordinates are EPSG:4326 lon/lat (DuckDB GEOMETRY is SRID-less).

INSTALL ducklake;
LOAD ducklake;
INSTALL spatial;
LOAD spatial;

-- Creating a DuckLake is just attaching it (CREATE_IF_NOT_EXISTS defaults true).
ATTACH 'ducklake:sample.ducklake' AS lake (DATA_PATH 'sample.ducklake.files');
USE lake;

-- snapshot: create table with a geometry column
CREATE TABLE observations (
    id          INTEGER,
    species     VARCHAR,
    recorded_at TIMESTAMP,
    region      VARCHAR,
    geom        GEOMETRY
);

-- snapshot: partition new data by region
ALTER TABLE observations SET PARTITIONED BY (region);

-- snapshot: define a sort order
ALTER TABLE observations SET SORTED BY (recorded_at ASC);

-- snapshot: insert batch 1
INSERT INTO observations VALUES
    (1, 'Vulpes vulpes',        TIMESTAMP '2026-01-05 08:15', 'north', ST_Point(-1.55, 53.80)),
    (2, 'Erinaceus europaeus',  TIMESTAMP '2026-01-06 21:40', 'north', ST_Point(-1.62, 53.72)),
    (3, 'Sciurus vulgaris',     TIMESTAMP '2026-02-11 11:05', 'south', ST_Point(-3.10, 51.48)),
    (4, 'Meles meles',          TIMESTAMP '2026-02-19 23:10', 'south', ST_Point(-2.98, 51.50));

-- snapshot: insert batch 2 (introduces a new partition value)
INSERT INTO observations VALUES
    (5, 'Lutra lutra',          TIMESTAMP '2026-03-02 06:25', 'west',  ST_Point(-4.15, 52.41)),
    (6, 'Vulpes vulpes',        TIMESTAMP '2026-03-14 19:55', 'west',  ST_Point(-4.22, 52.39));

-- snapshot: delete a row (writes a delete file)
DELETE FROM observations WHERE id = 2;

-- snapshot: schema evolution — add a column
ALTER TABLE observations ADD COLUMN observer VARCHAR;

-- snapshot: populate the new column for some rows
UPDATE observations SET observer = 'A. Naturalist' WHERE region = 'north';

-- snapshot: a second, unpartitioned reference table
CREATE TABLE regions (region VARCHAR, name VARCHAR, centroid GEOMETRY);
INSERT INTO regions VALUES
    ('north', 'Northern Uplands', ST_Point(-1.60, 53.80)),
    ('south', 'Southern Vale',    ST_Point(-3.00, 51.50)),
    ('west',  'Western Coast',    ST_Point(-4.20, 52.40));
