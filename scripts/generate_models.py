"""Bootstrap/refresh Wren MDL model files from the live sidora schema.

Runs INSIDE the wren container (has psycopg + wren.type_mapping + DB env):
    ssh terracotta 'docker exec -i wren python -' < scripts/generate_models.py
then pull back:  rsync -az --exclude target/ terracotta:/opt/wren/project/ wren-project/

Writes models/<table>/metadata.yml for every table in SCHEMAS and rewrites
relationships.yml from foreign keys. Existing `description` fields in
metadata.yml are preserved so hand-written business context survives a rerun.
"""
import os
import pathlib

import psycopg
import yaml
from wren.type_mapping import parse_type

SCHEMAS = ("public",)
PROJECT = pathlib.Path("/project")

conn = psycopg.connect(
    host=os.environ["POSTGRES_HOST"], port=os.environ["POSTGRES_PORT"],
    dbname=os.environ["POSTGRES_DATABASE"], user=os.environ["POSTGRES_USER"],
    password=os.environ["POSTGRES_PASSWORD"], sslmode="require",
)
cur = conn.cursor()


def q(sql, *args):
    cur.execute(sql, args)
    return cur.fetchall()


def load_existing_descriptions(path):
    if not path.exists():
        return {}, None
    old = yaml.safe_load(path.read_text()) or {}
    cols = {c["name"]: c.get("properties", {}).get("description") for c in old.get("columns", [])}
    return cols, old.get("properties", {}).get("description")


def pg_type(dt, udt, length, prec, scale):
    if dt == "numeric" and prec:
        return f"numeric({prec},{scale or 0})"
    if dt == "character varying" and length:
        return f"character varying({length})"
    if dt in ("ARRAY", "USER-DEFINED"):
        return udt
    return dt


relationships = []
for schema in SCHEMAS:
    tables = q(
        "select table_name from information_schema.tables where table_schema=%s and table_type='BASE TABLE' order by 1",
        schema,
    )
    for (table,) in tables:
        cols = q(
            """select column_name, data_type, udt_name, is_nullable, character_maximum_length, numeric_precision, numeric_scale
               from information_schema.columns where table_schema=%s and table_name=%s order by ordinal_position""",
            schema, table,
        )
        pk = [r[0] for r in q(
            """select kcu.column_name from information_schema.table_constraints tc
               join information_schema.key_column_usage kcu on tc.constraint_name=kcu.constraint_name and tc.table_schema=kcu.table_schema
               where tc.table_schema=%s and tc.table_name=%s and tc.constraint_type='PRIMARY KEY' order by kcu.ordinal_position""",
            schema, table,
        )]
        fks = q(
            """select kcu.column_name, ccu.table_name, ccu.column_name from information_schema.table_constraints tc
               join information_schema.key_column_usage kcu on tc.constraint_name=kcu.constraint_name and tc.table_schema=kcu.table_schema
               join information_schema.constraint_column_usage ccu on ccu.constraint_name=tc.constraint_name
               where tc.table_schema=%s and tc.table_name=%s and tc.constraint_type='FOREIGN KEY'""",
            schema, table,
        )
        path = PROJECT / "models" / table / "metadata.yml"
        old_col_desc, old_model_desc = load_existing_descriptions(path)

        columns = []
        for name, dt, udt, nullable, length, prec, scale in cols:
            col = {"name": name, "type": parse_type(pg_type(dt, udt, length, prec, scale), "postgres")}
            if nullable == "NO":
                col["not_null"] = True
            if old_col_desc.get(name):
                col["properties"] = {"description": old_col_desc[name]}
            columns.append(col)

        model = {
            "name": table,
            "table_reference": {"catalog": "", "schema": schema, "table": table},
            "columns": columns,
        }
        if len(pk) == 1:
            model["primary_key"] = pk[0]
        if old_model_desc:
            model["properties"] = {"description": old_model_desc}
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(yaml.safe_dump(model, sort_keys=False, allow_unicode=True))
        print(f"model {table}: {len(columns)} cols, pk={pk}")

        for col, ref_table, ref_col in fks:
            relationships.append({
                "name": f"{table}_{ref_table}",
                "models": [table, ref_table],
                "join_type": "many_to_one",
                "condition": f"{table}.{col} = {ref_table}.{ref_col}",
            })

(PROJECT / "relationships.yml").write_text(yaml.safe_dump({"relationships": relationships}, sort_keys=False))
print(f"relationships: {len(relationships)}")
