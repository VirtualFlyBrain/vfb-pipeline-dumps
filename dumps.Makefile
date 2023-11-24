# Specifies the shell to be used and ensures that any command that fails the pipeline also fails the Makefile.
SHELL=/bin/bash -o pipefail

# Specifies the command used to invoke the ROBOT tool.
ROBOT=robot

# Specifies the name of the log file used to record the time each target starts and ends.
LOG_FILE = vfb_pipeline_dumps.log

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
all: checkenv remove_embargoed_data $(FINAL_DUMPS_DIR)/owlery.owl $(FINAL_DUMPS_DIR)/solr.json $(FINAL_DUMPS_DIR)/pdb.owl pdb_csvs

# Declares a phony target to remove embargoed data.
.PHONY: remove_embargoed_data
# This target deletes the data that is embargoed by executing all of the delete_*.sparql files in the SPARQL directory.
remove_embargoed_data: $(SPARQL_DIR)/delete_*.sparql
	echo $@ started: `date +%s` > $(LOG_FILE)
	$(foreach f,$^,curl -X POST -H "Content-Type:application/x-www-form-urlencoded" -d "update=`cat $(f)`" $(SPARQL_ENDPOINT)/statements)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# This target constructs a TTL file from the SPARQL query specified in the construct_*.sparql file and downloads it from the SPARQL endpoint.
$(RAW_DUMPS_DIR)/%.ttl:
	curl -G --data-urlencode "query=`cat $(SPARQL_DIR)/construct_$*.sparql`" $(SPARQL_ENDPOINT) -o $@

# This target constructs an OWL file from the TTL file specified in the prerequisite and adds an ontology IRI, then converts it to the OWL format.
$(RAW_DUMPS_DIR)/construct_%.owl: $(RAW_DUMPS_DIR)/%.ttl
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) merge -i $< \
		annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/$*.owl" \
		convert -f owl -o $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# This target constructs an OWL file from the SPARQL query specified in the constructReasoned_*.sparql file via querying it in the reasoned ontology.
$(RAW_DUMPS_DIR)/constructReasoned_%.owl: $(RAW_DUMPS_DIR)/reasoned.owl
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) query -i $< --query $(SPARQL_DIR)/constructReasoned_$*.sparql $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# Generates an OWL file from multiple TTL files, infers annotations and relations,
# reduces the ontology, annotates it, and saves it to disk.
# Intermediate files directory
INTERMEDIATE_DIR = $(RAW_DUMPS_DIR)/intermediate

# Create the intermediate directory
$(INTERMEDIATE_DIR):
	mkdir -p $@

# Modified target to use intermediate files and clean up after each step
$(RAW_DUMPS_DIR)/construct_all.owl: $(RAW_DUMPS_DIR)/all.ttl | $(INTERMEDIATE_DIR)
	echo $@ started: `date +%s` >> $(LOG_FILE)

	# Step 1: Merge
	$(ROBOT) merge -vvv -i $< -o $(INTERMEDIATE_DIR)/merged.owl $(STDOUT_FILTER)

	# Step 2: Reason
	$(ROBOT) reason -i $(INTERMEDIATE_DIR)/merged.owl --reasoner ELK --axiom-generators "SubClass EquivalentClass ClassAssertion" --exclude-tautologies structural -o $(INTERMEDIATE_DIR)/reasoned.owl $(STDOUT_FILTER)
	rm $(INTERMEDIATE_DIR)/merged.owl

	# Step 3: Relax
	$(ROBOT) relax -i $(INTERMEDIATE_DIR)/reasoned.owl -o $(INTERMEDIATE_DIR)/relaxed.owl $(STDOUT_FILTER)
	rm $(INTERMEDIATE_DIR)/reasoned.owl

	# Step 4: Reduce
	$(ROBOT) reduce -i $(INTERMEDIATE_DIR)/relaxed.owl --reasoner ELK -o $(INTERMEDIATE_DIR)/reduced.owl $(STDOUT_FILTER)
	rm $(INTERMEDIATE_DIR)/relaxed.owl

	# Step 5: Annotate
	$(ROBOT) annotate -i $(INTERMEDIATE_DIR)/reduced.owl --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/raw/all.owl" -o $(INTERMEDIATE_DIR)/annotated.owl $(STDOUT_FILTER)
	rm $(INTERMEDIATE_DIR)/reduced.owl

	# Step 6: Convert and clean up
	$(ROBOT) convert -i $(INTERMEDIATE_DIR)/annotated.owl -f owl -o $@ $(STDOUT_FILTER)
	rm $(INTERMEDIATE_DIR)/annotated.owl

	echo $@ ended: `date +%s` >> $(LOG_FILE)


# Infers annotations and relations for the virtual fly brain ontology using the ROBOT inference engine.
$(RAW_DUMPS_DIR)/inferred_annotation.owl: $(FINAL_DUMPS_DIR)/owlery.owl $(RAW_DUMPS_DIR)/vfb-config.yaml
	echo $@ started: `date +%s` >> $(LOG_FILE)
	java $(ROBOT_ARGS) -jar $ $(SCRIPTS_DIR)/infer-annotate.jar $^ $(INFER_ANNOTATE_RELATION) $@
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# Infers unique facets for the virtual fly brain ontology using the ROBOT inference engine.
$(RAW_DUMPS_DIR)/unique_facets.owl: $(FINAL_DUMPS_DIR)/owlery.owl $(RAW_DUMPS_DIR)/vfb-config.yaml
	echo $@ started: `date +%s` >> $(LOG_FILE)
	java -jar $ $(SCRIPTS_DIR)/infer-annotate.jar $^ $(UNIQUE_FACETS_ANNOTATION) $@ true
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# Downloads the VFB configuration file and saves it to disk.
$(RAW_DUMPS_DIR)/vfb-config.yaml:
	wget $(VFB_CONFIG) -O $@

# Generates a Solr JSON file from the OWL file and VFB configuration file.
$(FINAL_DUMPS_DIR)/solr.json: $(FINAL_DUMPS_DIR)/obographs.json $(RAW_DUMPS_DIR)/vfb-config.yaml
	echo $@ started: `date +%s` >> $(LOG_FILE)
	python3 $(SCRIPTS_DIR)/obographs-solr.py $^ $@
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# Add a new dump:
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
PDB_EXTERNAL_ONTS=connectome_fafb.owl connectome_l1em.owl connectome_hemibrain.owl

# Specifies the location where the CSV import files are stored.
CSV_IMPORTS="$(FINAL_DUMPS_DIR)/csv_imports"

# Specifies the JAR file used to convert OWL files to CSV format for import into Neo4j.
OWL2NEOCSV="$(SCRIPTS_DIR)/owl2neo4jcsv.jar"

# Creates the CSV_IMPORTS directory.
$(CSV_IMPORTS):
	mkdir -p $@

# reasoned and merged intermediate product to be used by 'constructReasoned_name.sparql' queries
$(RAW_DUMPS_DIR)/reasoned.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_SOLR)) $(patsubst %, $(RAW_DUMPS_DIR)/%, $(PDB_EXTERNAL_ONTS))
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) merge $(patsubst %, -i %, $^) -o $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# Generates the obographs.json file, which is used to generate the SOLR index.
$(FINAL_DUMPS_DIR)/obographs.json: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_SOLR)) $(patsubst %, $(RAW_DUMPS_DIR)/constructReasoned_%.owl, $(DUMPS_REASONED)) $(RAW_DUMPS_DIR)/inferred_annotation.owl $(RAW_DUMPS_DIR)/unique_facets.owl
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) merge $(patsubst %, -i %, $^) convert -f json -o $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# Generates the PDB.owl file, which is used to generate the PDB.
$(FINAL_DUMPS_DIR)/pdb.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_PDB)) $(patsubst %, $(RAW_DUMPS_DIR)/constructReasoned_%.owl, $(DUMPS_REASONED)) $(RAW_DUMPS_DIR)/inferred_annotation.owl $(RAW_DUMPS_DIR)/unique_facets.owl $(patsubst %, $(RAW_DUMPS_DIR)/%, $(PDB_EXTERNAL_ONTS))
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) -vvv merge $(patsubst %, -i %, $^) -o $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# Generates the owlery.owl file, which is used for other purposes.
$(FINAL_DUMPS_DIR)/owlery.owl: $(patsubst %, $(RAW_DUMPS_DIR)/construct_%.owl, $(DUMPS_OWLERY)) $(patsubst %, $(RAW_DUMPS_DIR)/constructReasoned_%.owl, $(DUMPS_REASONED))
	echo $@ started: `date +%s` >> $(LOG_FILE)
	$(ROBOT) filter -i $< --axioms "logical" --preserve-structure true annotate --ontology-iri "http://virtualflybrain.org/data/VFB/OWL/owlery.owl" -o $@ $(STDOUT_FILTER)
	echo $@ ended: `date +%s` >> $(LOG_FILE)

# Generates the CSV files for the PDB and imports them into Neo4j.
pdb_csvs: $(FINAL_DUMPS_DIR)/pdb.owl | $(CSV_IMPORTS)
	echo $@ started: `date +%s` >> $(LOG_FILE)
	java $(ROBOT_ARGS) -jar $(OWL2NEOCSV) $< "$(VFB_CONFIG)" $(CSV_IMPORTS) false $(INFER_ANNOTATE_RELATION)
	echo $@ ended: `date +%s` >> $(LOG_FILE)
	echo "=== Print Timer Logs ==="
	echo "`cat $(LOG_FILE)`"

