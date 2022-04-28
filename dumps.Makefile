SHELL=/bin/bash -o pipefail # This ensures that when you run a pipe, any command can fail the pipeline (default, only the last)
ROBOT=robot

LOG_FILE = vfb_pipeline_dumps.log

.PHONY: checkenv

# Executing this ensures that the necessary environment variables are set.
checkenv:
ifndef OUTDIR
	$(error OUTDIR environment variable not set)
endif
ifndef RAW_DUMPS_DIR
	$(error RAW_DUMPS_DIR environment variable not set)
endif
ifndef FINAL_DUMPS_DIR
	$(error FINAL_DUMPS_DIR environment variable not set)
endif
ifndef WORKSPACE
	$(error WORKSPACE environment variable not set)
endif
ifndef SPARQL_DIR
	$(error SPARQL_DIR environment variable not set)
endif
ifndef SCRIPTS_DIR
	$(error SCRIPTS_DIR environment variable not set)
endif
ifndef VFB_CONFIG
	$(error VFB_CONFIG environment variable not set)
endif
ifndef STDOUT_FILTER
$(error STDOUT_FILTER environment variable not set)
endif
ifndef INFER_ANNOTATE_RELATION
$(error INFER_ANNOTATE_RELATION environment variable not set)
endif
ifndef UNIQUE_FACETS_ANNOTATION
$(error UNIQUE_FACETS_ANNOTATION environment variable not set)
endif

all: checkenv remove_embargoed_data $(FINAL_DUMPS_DIR)/owlery.owl $(FINAL_DUMPS_DIR)/solr.json $(FINAL_DUMPS_DIR)/pdb.owl pdb_csvs

.PHONY: remove_embargoed_data
remove_embargoed_data: $(SPARQL_DIR)/delete_*.sparql
	echo $@ started: `date +%s` > $(LOG_FILE)
	$(foreach f,$^,curl -X POST -H "Content-Type:application/x-www-form-urlencoded" -d "update=`cat $(f)`" $(SPARQL_ENDPOINT)/statements)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

$(RAW_DUMPS_DIR)/%.ttl:
	curl -G --data-urlencode "query=`cat $(SPARQL_DIR)/construct_$*.sparql`" $(SPARQL_ENDPOINT) -o $@

$(RAW_DUMPS_DIR)/construct_%.owl: $(RAW_DUMPS_DIR)/%.ttl
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) merge -i $< \
		annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/$*.owl" \
		convert -f owl -o $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

$(RAW_DUMPS_DIR)/construct_all.owl: $(RAW_DUMPS_DIR)/all.ttl
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) merge -i $< \
		reason --reasoner ELK --axiom-generators "SubClass EquivalentClass ClassAssertion" --exclude-tautologies structural \
		relax \
		reduce --reasoner ELK \
		annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/all.owl" \
		convert -f owl -o $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

$(RAW_DUMPS_DIR)/inferred_annotation.owl: $(FINAL_DUMPS_DIR)/owlery.owl $(RAW_DUMPS_DIR)/vfb-config.yaml
	echo $@ started: `date +%s` >> $(LOG_FILE)
	java $(ROBOT_ARGS) -jar $ $(SCRIPTS_DIR)/infer-annotate.jar $^ $(INFER_ANNOTATE_RELATION) $@
	echo $@ ended: `date +%s` >> $(LOG_FILE)

$(RAW_DUMPS_DIR)/unique_facets.owl: $(FINAL_DUMPS_DIR)/owlery.owl $(RAW_DUMPS_DIR)/vfb-config.yaml
	echo $@ started: `date +%s` >> $(LOG_FILE)
	java -jar $ $(SCRIPTS_DIR)/infer-annotate.jar $^ $(UNIQUE_FACETS_ANNOTATION) $@ true
	echo $@ ended: `date +%s` >> $(LOG_FILE)

$(RAW_DUMPS_DIR)/vfb-config.yaml:
	wget $(VFB_CONFIG) -O $@

$(FINAL_DUMPS_DIR)/solr.json: $(FINAL_DUMPS_DIR)/obographs.json $(RAW_DUMPS_DIR)/vfb-config.yaml
	echo $@ started: `date +%s` >> $(LOG_FILE)
	python3 $(SCRIPTS_DIR)/obographs-solr.py $^ $@
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# Add a new dump:
# 1. pick name, add to the correct DUMPS variable (DUMPS_SOLR, DUMPS_PDB, DUMPS_OWLERY)
# 2. create new sparql query in sparql/, naming it 'construct_name.sparql', e.g. sparql/construct_image_names.sparql
# Note that non-sparql goals, like 'inferred_annotation', need to be added separately
DUMPS_SOLR=all preferred_roots deprecation_label image_names has_image
DUMPS_PDB=all preferred_roots deprecation_label has_image
DUMPS_OWLERY=all
CSV_IMPORTS="$(FINAL_DUMPS_DIR)/csv_imports"
OWL2NEOCSV="$(SCRIPTS_DIR)/owl2neo4jcsv.jar"

$(CSV_IMPORTS):
	mkdir -p $@

$(FINAL_DUMPS_DIR)/obographs.json: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_SOLR)) $(RAW_DUMPS_DIR)/inferred_annotation.owl $(RAW_DUMPS_DIR)/unique_facets.owl
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) merge $(patsubst %, -i %, $^) convert -f json -o $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

PDB_EXTERNAL_ONTS=connectome_fafb.owl connectome_l1em.owl connectome_hemibrain.owl
$(FINAL_DUMPS_DIR)/pdb.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_PDB)) $(RAW_DUMPS_DIR)/inferred_annotation.owl $(RAW_DUMPS_DIR)/unique_facets.owl $(patsubst %, $(RAW_DUMPS_DIR)/%, $(PDB_EXTERNAL_ONTS))
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) -vvv merge $(patsubst %, -i %, $^) -o $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

$(FINAL_DUMPS_DIR)/owlery.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_OWLERY))
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) filter -i $< --axioms "logical" --preserve-structure true annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/owlery.owl" -o $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

pdb_csvs: $(FINAL_DUMPS_DIR)/pdb.owl | $(CSV_IMPORTS)
	echo $@ started: `date +%s` >> $(LOG_FILE)
	java $(ROBOT_ARGS) -jar $(OWL2NEOCSV) $< "$(VFB_CONFIG)" $(CSV_IMPORTS) false $(INFER_ANNOTATE_RELATION)
	echo $@ ended: `date +%s` >> $(LOG_FILE)
