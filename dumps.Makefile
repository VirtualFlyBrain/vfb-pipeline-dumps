SHELL=/bin/bash -o pipefail # This ensures that when you run a pipe, any command can fail the pipeline (default, only the last)
ROBOT=robot

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

all: checkenv $(FINAL_DUMPS_DIR)/owlery.owl $(FINAL_DUMPS_DIR)/solr.json $(FINAL_DUMPS_DIR)/pdb.owl

$(RAW_DUMPS_DIR)/%.ttl:
	curl -G --data-urlencode "query=`cat $(SPARQL_DIR)/construct_$*.sparql`" $(SPARQL_ENDPOINT) -o $@

$(RAW_DUMPS_DIR)/construct_%.owl: $(RAW_DUMPS_DIR)/%.ttl
	$(ROBOT) merge -i $< \
		annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/$*.owl" \
		convert -f owl -o $@ $(STDOUT_FILTER)

$(RAW_DUMPS_DIR)/construct_all.owl: $(RAW_DUMPS_DIR)/all.ttl
	$(ROBOT) merge -i $< \
		reason --reasoner ELK --axiom-generators "SubClass EquivalentClass ClassAssertion" --exclude-tautologies structural \
		relax \
		reduce --reasoner ELK --named-classes-only true \
		annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/all.owl" \
		convert -f owl -o $@ $(STDOUT_FILTER)

$(RAW_DUMPS_DIR)/inferred_annotation.owl: $(FINAL_DUMPS_DIR)/owlery.owl $(RAW_DUMPS_DIR)/vfb-config.yaml
	java -jar $ $(SCRIPTS_DIR)/infer-annotate.jar $^ $(INFER_ANNOTATE_RELATION) $@

$(RAW_DUMPS_DIR)/vfb-config.yaml:
	wget $(VFB_CONFIG) -O $@

$(FINAL_DUMPS_DIR)/solr.json: $(FINAL_DUMPS_DIR)/obographs.json $(RAW_DUMPS_DIR)/vfb-config.yaml
	python3 $(SCRIPTS_DIR)/obographs-solr.py $^ $@

# Add a new dump:
# 1. pick name, add to the correct DUMPS variable (DUMPS_SOLR, DUMPS_PDB, DUMPS_OWLERY)
# 2. create new sparql query in sparql/, naming it 'construct_name.sparql', e.g. sparql/construct_image_names.sparql
# Note that non-sparql goals, like 'inferred_annotation', need to be added separately
DUMPS_SOLR=all preferred_roots deprecation_label image_names has_image
DUMPS_PDB=all preferred_roots deprecation_label has_image has_neuron_neuron_connectivity has_neuron_region_connectivity
DUMPS_OWLERY=all

$(FINAL_DUMPS_DIR)/obographs.json: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_SOLR)) $(RAW_DUMPS_DIR)/inferred_annotation.owl
	$(ROBOT) merge $(patsubst %, -i %, $^) convert -f json -o $@ $(STDOUT_FILTER)

$(FINAL_DUMPS_DIR)/pdb.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_PDB)) $(RAW_DUMPS_DIR)/inferred_annotation.owl
	$(ROBOT) merge $(patsubst %, -i %, $^) -o $@ $(STDOUT_FILTER)

$(FINAL_DUMPS_DIR)/owlery.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_OWLERY))
	$(ROBOT) filter -i $< --axioms "logical" --preserve-structure true annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/owlery.owl" -o $@ $(STDOUT_FILTER)
