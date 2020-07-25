SHELL=/bin/bash -o pipefail # This ensures that when you run a pipe, any command can fail the pipeline (default, only the last)
ROBOT=robot
OUTPUTFILER=| { grep -v 'OWLRDFConsumer\|RDFParserRegistry\|Injector' || true; } # Appended to all commands; this allows us to filter annoying bits of output

.PHONY: checkenv

# Executing this ensures that the necessary environment variables are set.
checkenv:
ifndef OUTDIR
	$(error OUTDIR is undefined)
endif
ifndef RAW_DUMPS_DIR
	$(error RAW_DUMPS_DIR is undefined)
endif
ifndef FINAL_DUMPS_DIR
	$(error FINAL_DUMPS_DIR is undefined)
endif
ifndef WORKSPACE
	$(error WORKSPACE is undefined)
endif

all: checkenv $(FINAL_DUMPS_DIR)/owlery.owl $(FINAL_DUMPS_DIR)/pdb.ttl $(FINAL_DUMPS_DIR)/solr.json 

$(RAW_DUMPS_DIR)/%.ttl:
	curl -G --data-urlencode "query=`cat $(SPARQL_DIR)/$*.sparql`" $(SPARQL_ENDPOINT) -o $@

$(FINAL_DUMPS_DIR)/owlery.owl: $(RAW_DUMPS_DIR)/dump_all.ttl
	$(ROBOT) filter -i $< --axioms "logical" -o $@ $(OUTPUTFILER)
	
$(FINAL_DUMPS_DIR)/solr.json: $(RAW_DUMPS_DIR)/dump_all.ttl
	$(ROBOT) convert -i $< -f json -o $@ $(OUTPUTFILER)

$(FINAL_DUMPS_DIR)/pdb.ttl: $(RAW_DUMPS_DIR)/dump_all.ttl
	$(ROBOT) merge -i $< -o $@ $(OUTPUTFILER)
