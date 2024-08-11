#!/bin/bash

SPARQL_QUERY_FILE=$1    # The SPARQL file to run
OUTPUT_FILE=$2          # The final OWL output file
CHUNK_SIZE=$3           # Number of results to fetch in each chunk
INPUT_ONTOLOGY=$4       # The input ontology file
STDOUT_FILTER=$5        # Additional filters for logging

TEMP_DIR=$(mktemp -d)

OFFSET=0

while true; do
    # Define the output file for the current chunk
    CHUNK_OUTPUT="${TEMP_DIR}/chunk_${OFFSET}.owl"

    # Run the query with the current OFFSET and CHUNK_SIZE
    robot query -i "$INPUT_ONTOLOGY" --query "$SPARQL_QUERY_FILE" -o "$CHUNK_OUTPUT" \
        --limit "$CHUNK_SIZE" --offset "$OFFSET" 2>&1 | grep -v 'OWLRDFConsumer\|InvalidReferenceViolation\|RDFParserRegistry' || true

    # Check if the chunk output file exists and is not empty
    if [ ! -s "$CHUNK_OUTPUT" ]; then
        echo "No more results found at offset $OFFSET. Stopping."
        break
    fi

    # Merge the chunk into the final output file
    if [ -f "$OUTPUT_FILE" ]; then
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
