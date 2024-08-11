#!/bin/bash

SPARQL_QUERY_FILE=$1
OUTPUT_FILE=$2
CHUNK_SIZE=$3
REASONED_ONTOLOGY=$4
TEMP_DIR=$(mktemp -d)

OFFSET=0
CHUNK_OUTPUT="${TEMP_DIR}/chunk_$(printf "%05d" ${OFFSET}).ttl"

# Run the first chunk
robot query -i "$REASONED_ONTOLOGY" --query "$SPARQL_QUERY_FILE" --limit "$CHUNK_SIZE" --offset "$OFFSET" "$CHUNK_OUTPUT"

while [ -s "$CHUNK_OUTPUT" ]; do
    OFFSET=$((OFFSET + CHUNK_SIZE))
    CHUNK_OUTPUT="${TEMP_DIR}/chunk_$(printf "%05d" ${OFFSET}).ttl"
    robot query -i "$REASONED_ONTOLOGY" --query "$SPARQL_QUERY_FILE" --limit "$CHUNK_SIZE" --offset "$OFFSET" "$CHUNK_OUTPUT"
done

# Merge all chunk files
robot merge $(find "$TEMP_DIR" -name "*.ttl" | xargs -I {} echo "-i {}") -o "$OUTPUT_FILE"

# Check if the output file was created.
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Final output file $OUTPUT_FILE was not created."
    ls -lh "$TEMP_DIR"
    exit 1
fi

# Clean up
rm -r "$TEMP_DIR"