#!/usr/bin/env python3
"""
Script to clean OWL files by removing invalid rdf:type triples where the object is a blank node.
Usage: python clean_owl.py input.owl output.owl
"""

import sys
from rdflib import Graph, RDF, URIRef, BNode

def clean_owl(input_file, output_file):
    g = Graph()
    print(f"Loading {input_file}...")
    try:
        g.parse(input_file, format='xml')  # Assuming OWL/XML; adjust if Turtle/NT
    except Exception as e:
        print(f"Error parsing {input_file}: {e}")
        with open(input_file, 'r') as f:
            lines = f.readlines()[:10]
            print("First 10 lines of the file:")
            for i, line in enumerate(lines, 1):
                print(f"{i}: {line.rstrip()}")
        raise

    invalid_count = 0
    for s, p, o in list(g.triples((None, RDF.type, None))):
        if isinstance(o, BNode) or (isinstance(o, URIRef) and str(o).startswith('_:')):
            g.remove((s, p, o))
            invalid_count += 1

    print(f"Removed {invalid_count} invalid rdf:type triples.")
    print(f"Saving cleaned ontology to {output_file}...")
    g.serialize(output_file, format='xml')
    print("Done.")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python clean_owl.py input.owl output.owl")
        sys.exit(1)
    clean_owl(sys.argv[1], sys.argv[2])