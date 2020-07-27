SHELL=/bin/bash -o pipefail # This ensures that when you run a pipe, any command can fail the pipeline (default, only the last)
ROBOT=robot
OUTPUTFILER=| { grep -v 'OWLRDFConsumer\|RDFParserRegistry\|Injector' || true; } # Appended to all commands; this allows us to filter annoying bits of output

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

all: checkenv $(FINAL_DUMPS_DIR)/owlery.owl $(FINAL_DUMPS_DIR)/pdb.ttl $(FINAL_DUMPS_DIR)/solr.json 

$(RAW_DUMPS_DIR)/%.ttl:
	curl -G --data-urlencode "query=`cat $(SPARQL_DIR)/$*.sparql`" $(SPARQL_ENDPOINT) -o $@

$(FINAL_DUMPS_DIR)/owlery.owl: $(RAW_DUMPS_DIR)/dump_all.ttl
	$(ROBOT) filter -i $< --axioms "logical"  annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/owlery.owl" -o $@ $(OUTPUTFILER)

$(RAW_DUMPS_DIR)/dump_all.owl: $(RAW_DUMPS_DIR)/dump_all.ttl
	$(ROBOT) merge -i $< annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/dump_all.owl" convert -f owl -o $@ $(OUTPUTFILER)

$(FINAL_DUMPS_DIR)/obographs.json: $(RAW_DUMPS_DIR)/dump_all.owl
	$(ROBOT) convert -i $< -f json -o $@ $(OUTPUTFILER)

$(RAW_DUMPS_DIR)/vfb-config.yaml:
	wget $(VFB_CONFIG) -O $@

$(FINAL_DUMPS_DIR)/solr.json: $(FINAL_DUMPS_DIR)/obographs.json $(RAW_DUMPS_DIR)/vfb-config.yaml
	python3 $(SCRIPTS_DIR)/obographs-solr.py $^ $@

$(FINAL_DUMPS_DIR)/pdb.ttl: $(RAW_DUMPS_DIR)/dump_all.ttl
	$(ROBOT) merge -i $< -o $@ $(OUTPUTFILER)
