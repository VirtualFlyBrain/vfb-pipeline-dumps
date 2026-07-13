# VFB Pipeline 2: Preparing datadumps (vfb-pipeline-dumps)

**Developer notes:**
- Make sure `ENV SPARQL_ENDPOINT` is set (it is **not** verified by the `checkenv` target).

Docker Hub: https://hub.docker.com/repository/docker/virtualflybrain/vfb-pipeline-dumps

---

The **data-dump stage** of the [Virtual Fly Brain](https://virtualflybrain.org) (VFB) pipeline.

This repository is a Dockerised batch job that **queries VFB's assembled triplestore and produces the
final data artifacts that serve the website**: a Solr search index, an OWLery reasoning ontology, and
the Neo4j "PDB" production graph (plus side-loaded connectome/expression data).

It runs *after* [`vfb-pipeline-collectdata`](https://github.com/VirtualFlyBrain/vfb-pipeline-collectdata),
which assembles the ontologies and knowledge-base export and loads them into the triplestore. The
overall chain is:

```
collectdata  →  (triplestore)  →  dumps  →  Solr + OWLery + Neo4j PDB  →  live site
```

## How it works

- [`process.sh`](process.sh) is the container entrypoint. It creates the output directories, symlinks
  any `connectome_*.owl` side-load files into `raw/`, then runs the pipeline with
  `make -j${CORES} all`.
- [`dumps.Makefile`](dumps.Makefile) (copied into the image as `Makefile`) is the actual engine — a
  dependency graph of SPARQL + ROBOT steps. Running the stages as Make targets gives parallelism
  (`-j`) and incremental rebuilds for free.
- The data source is the SPARQL endpoint set by `SPARQL_ENDPOINT`
  (default `http://ts.p2.virtualflybrain.org/rdf4j-server/repositories/vfb`), i.e. the RDF4J
  triplestore populated by `collectdata`.

Output is written to the container's `/out` volume:

| Directory | Contents |
|---|---|
| `/out/raw` | Intermediate TTL/OWL files produced by each query and reasoning step |
| `/out/dumps` | Final artifacts (`solr.json`, `owlery.owl`, `pdb.owl`) and `csv_imports/` |
| `/out/dumps.log` | Full build log |

## Pipeline steps

1. **Remove embargoed data.** The `remove_embargoed_data` target runs every
   [`sparql/delete_*.sparql`](sparql) as a SPARQL `UPDATE` against `${SPARQL_ENDPOINT}/statements`,
   deleting embargoed data directly in the triplestore before anything is dumped.

2. **Construct dumps** (one per query). The core Make pattern rules turn each
   `sparql/construct_<name>.sparql` query into an OWL file:
   - `raw/<name>.ttl` — run the CONSTRUCT query against the endpoint (`curl`), save as Turtle.
   - `raw/construct_<name>.owl` — `robot merge`, stamp an ontology IRI, convert to OWL.
   - `raw/construct_all.owl` is special: after merging it **reasons** with ELK
     (`SubClass EquivalentClass ClassAssertion`), then `relax` / `reduce` to materialise the class
     hierarchy.

   There are ~25 construct queries — the core graph (`all`), display/search helpers
   (`has_image`, `image_names`, `preferred_roots`, `deprecation_label`), connectivity, GO
   cross-references, and per-dataset connectome queries (`hemibrain`, `flywire`, `manc`, `fafb`,
   `l1em`, `opticlobe`, …).

3. **Enrich.** Two external JARs (downloaded in the `Dockerfile`) add inferred data:
   - `infer-annotate.jar` ([vfb_expression_annotator](https://github.com/VirtualFlyBrain/vfb_expression_annotator))
     → `raw/inferred_annotation.owl` and `raw/unique_facets.owl`.
   - Reasoned sub-class queries (`constructReasoned_has_subClass.sparql`) run over the merged data and
     the side-load ontologies.

4. **Build the three final products** (the `all` target), each a different merge of the constructed
   pieces:

   | Output | Consumer | Built from |
   |---|---|---|
   | `dumps/solr.json` | **Solr** search / autocomplete index | `DUMPS_SOLR` (`all preferred_roots deprecation_label image_names has_image`) → `obographs.json` (ROBOT `convert -f json`) → `obographs-solr.py` |
   | `dumps/owlery.owl` | **OWLery** reasoning endpoint (class-expression queries) | `DUMPS_OWLERY` (`all`) + reasoned + side-loads, filtered to logical axioms only |
   | `dumps/pdb.owl` + `dumps/csv_imports/` | **PDB** — the production Neo4j graph the site queries | `DUMPS_PDB` (`all preferred_roots deprecation_label has_image`) + reasoned + inferred; `owl2neo4jcsv.jar` converts `pdb.owl` to Neo4j bulk-import CSVs |

5. **Side-loads.** Large connectivity / expression datasets
   (`PDB_EXTERNAL_ONTS = connectome_*.owl VFB_scRNAseq_exp_*.owl VFB_EPseq_exp_*.owl`) are **not**
   merged into the main graph. The `pdb_sideloads` target converts each into **edge-only** Neo4j CSVs
   (`owl2neo4jcsv.jar … only_edges`), keeping the huge connectome/expression data out of the
   reasoning and merge steps.

## Configuration

Defaults are set in the [`Dockerfile`](Dockerfile); override via `docker run --env`.

| Variable | Default | Purpose |
|---|---|---|
| `SPARQL_ENDPOINT` | `http://ts.p2.virtualflybrain.org/rdf4j-server/repositories/vfb` | Source triplestore (RDF4J) — **must be set** |
| `VFB_CONFIG` | `http://virtualflybrain.org/config/neo4j2owl-config.yaml` | neo4j2owl config (CURIE map, filters) used by the Solr and CSV steps |
| `CORES` | `4` | Parallel `make` jobs |
| `ROBOT_ARGS` | `-Xmx20G -D…parallelism=1` | JVM args applied to ROBOT and the JARs (`ROBOT_JAVA_ARGS` / `JAVA_OPTS`) |
| `INFER_ANNOTATE_RELATION` | `http://n2o.neo/property/nodeLabel` | Relation used by the annotation inference / CSV export |
| `UNIQUE_FACETS_ANNOTATION` | `http://n2o.neo/property/uniqueFacets` | Annotation for unique-facet inference |
| `STDOUT_FILTER` | grep filter | Appended to ROBOT commands to suppress noisy parser warnings |

`process.sh` sets the directory variables (`OUTDIR`, `RAW_DUMPS_DIR`, `FINAL_DUMPS_DIR`,
`SPARQL_DIR`, `SCRIPTS_DIR`); the `checkenv` target fails fast if any required variable is missing.

### Adding a new dump

1. Pick a name and add it to the relevant list in `dumps.Makefile` (`DUMPS_SOLR`, `DUMPS_PDB`,
   and/or `DUMPS_OWLERY`).
2. Create `sparql/construct_<name>.sparql`.

Non-SPARQL goals (e.g. `inferred_annotation`) need their own Make target.

## Repository layout

| Path | Purpose |
|---|---|
| [`process.sh`](process.sh) | Container entrypoint; sets up dirs and runs `make all` |
| [`dumps.Makefile`](dumps.Makefile) | The pipeline definition (copied to `Makefile` in the image) |
| [`Makefile`](Makefile) | Local Docker build/run/publish helpers (**not** the pipeline) |
| [`sparql/`](sparql) | `construct_*.sparql` (dumps), `constructReasoned_*.sparql`, `delete_*.sparql` (embargo) |
| [`scripts/obographs-solr.py`](scripts/obographs-solr.py) | Converts OBOGraphs JSON → VFB Solr documents |
| [`scripts/lib.py`](scripts/lib.py) | Helpers (ID/CURIE variants, JSON I/O) |
| [`scripts/clean_owl.py`](scripts/clean_owl.py) | OWL cleanup helper |
| [`scripts/run_sparql_in_chunks.sh`](scripts/run_sparql_in_chunks.sh) | Runs a SPARQL query in paged chunks for large result sets |

The `owl2neo4jcsv.jar` ([neo4j2owl](https://github.com/VirtualFlyBrain/neo4j2owl)) and
`infer-annotate.jar` are downloaded into `scripts/` at image-build time (see `Dockerfile`).

## Building and running

The [`Makefile`](Makefile) wraps the Docker commands:

```bash
# Build the image
make docker-build            # with cache
make docker-build-no-cache

# Run the pipeline (writes to OUTDIR, default ~/data/vfb)
make docker-run

# Publish to Docker Hub
make docker-publish
```

Override variables inline, e.g.:

```bash
make docker-run OUTDIR=/path/to/out SPARQL_ENDPOINT=http://my-triplestore/repositories/vfb
```

The image mounts two volumes: `/out` (output data) and `/logs`.

## Continuous integration

[`.github/workflows/docker-image.yml`](.github/workflows/docker-image.yml) builds the image on every
push and on PRs against `master`. Pushes are published to Docker Hub as
`virtualflybrain/vfb-pipeline-dumps` tagged with the branch name; PR builds are built but not pushed.

## Tools used

- [ROBOT](http://robot.obolibrary.org/) — OWL manipulation, ELK reasoning, format conversion
- [ELK](https://github.com/liveontologies/elk-reasoner) — OWL EL reasoner (via ROBOT)
- [neo4j2owl / owl2neo4jcsv](https://github.com/VirtualFlyBrain/neo4j2owl) — OWL → Neo4j CSV conversion
- [vfb_expression_annotator](https://github.com/VirtualFlyBrain/vfb_expression_annotator) — annotation / unique-facet inference
- [OBOGraphs](https://github.com/geneontology/obographs) JSON — intermediate format for the Solr index
