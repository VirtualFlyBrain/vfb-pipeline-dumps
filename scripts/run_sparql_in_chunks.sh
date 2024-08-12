#!/bin/bash

# Assign passed parameters to variables
SPARQL_QUERY_FILE=$1    # The SPARQL query file
OUTPUT_FILE=$2          # The final OWL output file
CHUNK_SIZE=$3           # Number of results to fetch in each chunk
INPUT_ONTOLOGY=$4       # The input ontology file
STDOUT_FILTER=$5        # Additional filters for logging (optional)

# Debug output: print the received parameters
echo "SPARQL_QUERY_FILE: $SPARQL_QUERY_FILE"
echo "OUTPUT_FILE: $OUTPUT_FILE"
echo "CHUNK_SIZE: $CHUNK_SIZE"
echo "INPUT_ONTOLOGY: $INPUT_ONTOLOGY"
echo "STDOUT_FILTER: $STDOUT_FILTER"

# Create a temporary directory for storing intermediate results
TEMP_DIR=$(mktemp -d)

OFFSET=0

# Loop to execute the query in chunks
while true; do
    # Define the output file for the current chunk
    CHUNK_OUTPUT="${TEMP_DIR}/chunk_${OFFSET}.owl"

    # Debug output: print the command about to be run
    echo "Running robot query with the following command:"
    echo "robot query -i \"$INPUT_ONTOLOGY\" --query \"$SPARQL_QUERY_FILE\" -o \"$CHUNK_OUTPUT\" --limit \"$CHUNK_SIZE\" --offset \"$OFFSET\""

    # Run the query with the current OFFSET and CHUNK_SIZE
    robot query -i "$INPUT_ONTOLOGY" --query "$SPARQL_QUERY_FILE" -o "$CHUNK_OUTPUT" \
        --limit "$CHUNK_SIZE" --offset "$OFFSET" 2>&1 | grep -v 'OWLRDFConsumer\|InvalidReferenceViolation\|RDFParserRegistry' || true

    # Check if the chunk output file exists and is not empty
    if [ ! -s "$CHUNK_OUTPUT" ]; then
        echo "No more results found at offset $OFFSET. Stopping."
        break
    fi

    # Debug output: print the merge command if it runs
    if [ -f "$OUTPUT_FILE" ]; then
        echo "Merging chunk with command:"
        echo "robot merge -i \"$OUTPUT_FILE\" -i \"$CHUNK_OUTPUT\" -o \"$OUTPUT_FILE\""
        robot merge -i "$OUTPUT_FILE" -i "$CHUNK_OUTPUT" -o "$OUTPUT_FILE"
    else
        mv "$CHUNK_OUTPUT" "$OUTPUT_FILE"
    fi

    # Increment the offset
    OFFSET=$((OFFSET + CHUNK_SIZE))
done

# Clean up temporary files
rm -r "$TEMP_DIR"

# Final check to see if the output file was created
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Final output file $OUTPUT_FILE was not created."
    exit 1
fi
