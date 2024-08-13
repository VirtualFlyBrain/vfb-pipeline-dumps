#!/bin/bash

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

    # Create a temporary SPARQL file with LIMIT and OFFSET
    TEMP_SPARQL=$(mktemp).sparql
    cat "$SPARQL_QUERY_FILE" > "$TEMP_SPARQL"
    echo "LIMIT $CHUNK_SIZE OFFSET $OFFSET" >> "$TEMP_SPARQL"

    # Debug output: print the command about to be run
    echo "Running robot query with the following command:"
    echo "robot query --input \"$INPUT_ONTOLOGY\" --query \"$TEMP_SPARQL\" \"$CHUNK_OUTPUT\""
    echo "$TEMP_SPARQL:"
    cat -n "$TEMP_SPARQL"

    # Run the query with the current OFFSET and CHUNK_SIZE
    robot query --input "$INPUT_ONTOLOGY" --query "$TEMP_SPARQL" "$CHUNK_OUTPUT"

    # Check if the chunk output file exists and is not empty
    if [ ! -s "$CHUNK_OUTPUT" ]; then
        echo "No more results found at offset $OFFSET. Stopping."
        break
    fi

    # Merge the chunk into the final output file
    if [ -f "$OUTPUT_FILE" ]; then
        robot merge -i "$OUTPUT_FILE" -i "$CHUNK_OUTPUT" "$OUTPUT_FILE"
    else
        mv "$CHUNK_OUTPUT" "$OUTPUT_FILE"
    fi

    # Increment the offset
    OFFSET=$((OFFSET + CHUNK_SIZE))

    # Clean up the temporary SPARQL file
    rm "$TEMP_SPARQL"
done

# Clean up temporary files
rm -r "$TEMP_DIR"

# Final check to see if the output file was created
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Final output file $OUTPUT_FILE was not created."
    exit 1
fi
