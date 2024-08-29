# Specifies the shell to be used and ensures that any command that fails the pipeline also fails the Makefile.
SHELL=/bin/bash -o pipefail

# Specifies the command used to invoke the ROBOT tool.
ROBOT=robot

# Specifies the name of the log file used to record the time each target starts and ends.
LOG_FILE=vfb_pipeline_dumps.log

# Function to log start and end times, as well as errors
define log
    @echo $1 started: `date +%s` >> $(LOG_FILE)
    $2 || { echo "$1 failed: `date +%s`" >> $(LOG_FILE); exit 1; }
    @echo $1 ended: `date +%s` >> $(LOG_FILE)
endef

# Suggest parallel execution in comments
# To speed up the build process, you can run make with parallel jobs: `make -j 4 all`

# Declares a phony target to check that all necessary environment variables are set.
.PHONY: checkenv

# This target checks that all necessary environment variables are set. If any of them are not set, an error is thrown.
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

# The default target that generates all necessary OWL files.
all: checkenv print_pdb_external_onts print_query_outputs remove_embargoed_data $(FINAL_DUMPS_DIR)/owlery.owl $(FINAL_DUMPS_DIR)/solr.json $(FINAL_DUMPS_DIR)/pdb.owl pdb_csvs pdb_sideloads

# Declares a phony target to remove embargoed data.
.PHONY: remove_embargoed_data

# This target deletes the data that is embargoed by executing all of the delete_*.sparql files in the SPARQL directory.
remove_embargoed_data: $(SPARQL_DIR)/delete_*.sparql
	$(call log, $@, $(foreach f,$^,curl -X POST -H "Content-Type:application/x-www-form-urlencoded" -d "update=`cat $(f)`" $(SPARQL_ENDPOINT)/statements))

# This target constructs a TTL file from the SPARQL query specified in the construct_*.sparql file and downloads it from the SPARQL endpoint.
$(RAW_DUMPS_DIR)/%.ttl:
	$(call log, $@, curl -G --data-urlencode "query=`cat $(SPARQL_DIR)/construct_$*.sparql`" $(SPARQL_ENDPOINT) -o $@)

# This target constructs an OWL file from the TTL file specified in the prerequisite and adds an ontology IRI, then converts it to the OWL format.
$(RAW_DUMPS_DIR)/construct_%.owl: $(RAW_DUMPS_DIR)/%.ttl
	$(call log, $@, $(ROBOT) merge -i $< annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/$*.owl" convert -f owl -o $@ $(STDOUT_FILTER))

# Generates an OWL file from multiple TTL files, infers annotations and relations,
# reduces the ontology, annotates it, and saves it to disk.
$(RAW_DUMPS_DIR)/construct_all.owl: $(RAW_DUMPS_DIR)/all.ttl
	$(call log, $@, $(ROBOT) merge -i $< reason --reasoner ELK --axiom-generators "SubClass EquivalentClass ClassAssertion" --exclude-tautologies structural relax reduce --reasoner ELK annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/all.owl" convert -f owl -o $@ $(STDOUT_FILTER))

# Infers annotations and relations for the virtual fly brain ontology using the ROBOT inference engine.
$(RAW_DUMPS_DIR)/inferred_annotation.owl: $(FINAL_DUMPS_DIR)/owlery.owl $(RAW_DUMPS_DIR)/vfb-config.yaml
	$(call log, $@, java $(ROBOT_ARGS) -jar $(SCRIPTS_DIR)/infer-annotate.jar $^ $(INFER_ANNOTATE_RELATION) $@)

# Infers unique facets for the virtual fly brain ontology using the ROBOT inference engine.
$(RAW_DUMPS_DIR)/unique_facets.owl: $(FINAL_DUMPS_DIR)/owlery.owl $(RAW_DUMPS_DIR)/vfb-config.yaml
	$(call log, $@, java -jar $(SCRIPTS_DIR)/infer-annotate.jar $^ $(UNIQUE_FACETS_ANNOTATION) $@ true)

# Downloads the VFB configuration file and saves it to disk.
$(RAW_DUMPS_DIR)/vfb-config.yaml:
	$(call log, $@, wget $(VFB_CONFIG) -O $@)

# Generates a Solr JSON file from the OWL file and VFB configuration file.
$(FINAL_DUMPS_DIR)/solr.json: $(FINAL_DUMPS_DIR)/obographs.json $(RAW_DUMPS_DIR)/vfb-config.yaml
	$(call log, $@, python3 $(SCRIPTS_DIR)/obographs-solr.py $^ $@)

# Add new dump:
# 1. pick name, add to the correct DUMPS variable (DUMPS_SOLR, DUMPS_PDB, DUMPS_OWLERY)
# 2. create new sparql query in sparql/, naming it 'construct_name.sparql', e.g. sparql/construct_image_names.sparql
# Note that non-sparql goals, like 'inferred_annotation', need to be added separately

# Specifies the names of the dumps used to generate the SOLR index.
DUMPS_SOLR=all preferred_roots deprecation_label image_names has_image

# Specifies the names of the dumps used to generate the PDB.
DUMPS_PDB=all preferred_roots deprecation_label has_image

# Specifies the names of the dumps used to generate the OWLery.
DUMPS_OWLERY=all

# Specifies the names of the dumps that are generated by ROBOT query after reasoning
# Query file format should be 'constructReasoned_name.sparql'
DUMPS_REASONED=has_subClass

# ontologies for side-loading
PDB_EXTERNAL_ONTS := $(wildcard $(RAW_DUMPS_DIR)/connectome_*.owl $(RAW_DUMPS_DIR)/VFB_scRNAseq_exp_*.owl $(RAW_DUMPS_DIR)/VFB_EPseq_exp_*.owl)


# Debugging: Print the value of PDB_EXTERNAL_ONTS to ensure it's being set correctly
print_pdb_external_onts:
	echo "PDB_EXTERNAL_ONTS is: $(PDB_EXTERNAL_ONTS)"

# Specifies the location where the CSV import files are stored.
CSV_IMPORTS="$(FINAL_DUMPS_DIR)/csv_imports"

# Specifies the JAR file used to convert OWL files to CSV format for import into Neo4j.
OWL2NEOCSV="$(SCRIPTS_DIR)/owl2neo4jcsv.jar"

# Creates the CSV_IMPORTS directory.
$(CSV_IMPORTS):
	mkdir -p $@

# This target constructs an OWL file from the SPARQL query specified in the constructReasoned_*.sparql file via querying it in the reasoned ontology.
# $(RAW_DUMPS_DIR)/constructReasoned_%.owl: $(RAW_DUMPS_DIR)/reasoned.owl
# 	$(call log, $@, $(ROBOT) query -i $< --query $(SPARQL_DIR)/constructReasoned_$*.sparql $@ $(STDOUT_FILTER))

$(RAW_DUMPS_DIR)/construct_merged.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_SOLR))
	$(call log, $@, $(ROBOT) merge $(patsubst %, -i %, $^) -o $@ $(STDOUT_FILTER))

$(RAW_DUMPS_DIR)/constructReasoned_construct_%.owl: $(RAW_DUMPS_DIR)/construct_merged.owl
	$(call log, $@, $(ROBOT) query -i $< --query $(SPARQL_DIR)/constructReasoned_$*.sparql $@ $(STDOUT_FILTER))

# Run DUMPS_REASONED construct queries on PDB_EXTERNAL_ONTS
SIDE_LOADING_ONTS := $(wildcard $(addprefix $(RAW_DUMPS_DIR)/, $(PDB_EXTERNAL_ONTS)))
QUERY_OUTPUTS := $(foreach query, $(DUMPS_REASONED), $(foreach file, $(SIDE_LOADING_ONTS), $(addprefix $(FINAL_DUMPS_DIR)/, $(basename $(notdir $(file)))_$(query).owl)))

print_query_outputs:
    @echo "QUERY_OUTPUTS is: $(QUERY_OUTPUTS)"

# Add new goal for each new query in DUMPS_REASONED
$(FINAL_DUMPS_DIR)/%_has_subClass.owl: $(RAW_DUMPS_DIR)/%.owl $(SPARQL_DIR)/constructReasoned_has_subClass.sparql
	$(call log, $@, $(ROBOT) query -i $< --query $(word 2,$^) $@ $(STDOUT_FILTER))

$(RAW_DUMPS_DIR)/constructReasoned_construct_side_loading.owl: $(QUERY_OUTPUTS)
	ifeq ($(strip $(QUERY_OUTPUTS)),)
        $(error No input files found for constructReasoned_construct_side_loading.owl)
    else
        $(call log, $@, $(ROBOT) merge $(patsubst %, -i %, $(QUERY_OUTPUTS)) -o $@ $(STDOUT_FILTER))
    endif

$(RAW_DUMPS_DIR)/constructReasoned_merged.owl: $(patsubst %, $(RAW_DUMPS_DIR)/constructReasoned_construct_%.owl, $(DUMPS_REASONED)) $(RAW_DUMPS_DIR)/constructReasoned_construct_side_loading.owl
	$(call log, $@, $(ROBOT) merge $(patsubst %, -i %, $^) -o $@ $(STDOUT_FILTER))

# Generates the obographs.json file, which is used to generate the SOLR index.
$(FINAL_DUMPS_DIR)/obographs.json: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_SOLR)) $(RAW_DUMPS_DIR)/constructReasoned_merged.owl $(RAW_DUMPS_DIR)/inferred_annotation.owl $(RAW_DUMPS_DIR)/unique_facets.owl
	$(call log, $@, $(ROBOT) merge $(patsubst %, -i %, $^) convert -f json -o $@ $(STDOUT_FILTER))

# Generates the PDB.owl file, which is used to generate the PDB.
$(FINAL_DUMPS_DIR)/pdb.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_PDB)) $(RAW_DUMPS_DIR)/constructReasoned_merged.owl $(RAW_DUMPS_DIR)/inferred_annotation.owl $(RAW_DUMPS_DIR)/unique_facets.owl
	$(call log, $@, $(ROBOT) -vvv merge $(patsubst %, -i %, $^) -o $@ $(STDOUT_FILTER))

# Generates the owlery.owl file, which is used for other purposes.
$(FINAL_DUMPS_DIR)/owlery.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_OWLERY)) $(RAW_DUMPS_DIR)/constructReasoned_merged.owl
	$(call log, $@, $(ROBOT) filter -i $< --axioms "logical" --preserve-structure true annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/owlery.owl" -o $@ $(STDOUT_FILTER))

# Generates the side loading CSV files for the PDB
pdb_sideloads: $(SIDE_LOADING_ONTS) | $(CSV_IMPORTS)
	$(call log, $@, for file in $(SIDE_LOADING_ONTS); do base=$$(basename $$file .owl); var_part=$${base#*_}; java $(ROBOT_ARGS) -jar $(OWL2NEOCSV) $$file "none" $(CSV_IMPORTS) false $(INFER_ANNOTATE_RELATION) $${var_part}; done)

# Generates the CSV files for the PDB and imports them into Neo4j.
pdb_csvs: $(FINAL_DUMPS_DIR)/pdb.owl | $(CSV_IMPORTS)
	$(call log, $@, java $(ROBOT_ARGS) -jar $(OWL2NEOCSV) $< "$(VFB_CONFIG)" $(CSV_IMPORTS) false $(INFER_ANNOTATE_RELATION))
	@echo "=== Print Timer Logs ==="
	@cat $(LOG_FILE)
