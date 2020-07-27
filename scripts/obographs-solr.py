"""OBOGraphs JSON to VFB SOLR document converter
Created on July 26, 2020

@author: matentzn

This script translates the obographs json format to the native VFB solr format.
"""

import json
import yaml
import sys

n2o_nodelabel_iri = "http://n2o.neo/property/nodeLabel"
obo_iri = "http://purl.obolibrary.org/obo/"

def load_json(obographs_file):
    with open(obographs_file) as json_file:
        data: dict = json.load(json_file)
    return data
    # print(data)


def save_json(solr, solr_out_file):
    with open(solr_out_file, 'w') as outfile:
        outfile.write(json.dumps(solr, indent=4, sort_keys=True))


def parse_curie_map(curie_map_file):
    with open(curie_map_file, 'r') as stream:
        config = yaml.safe_load(stream)
    return config['curie_map']


def get_id_variants(id, curie_map):
    id_meta = dict()
    for pre in curie_map:
        prefix_url = curie_map[pre]
        if id.startswith(prefix_url):
            short_form = id.replace(prefix_url,'')
            id_meta['obo_id'] = pre+":"+short_form
            if short_form.isnumeric(): # Discuss
                id_meta['short_form'] = pre+"_"+short_form
            else:
                id_meta['short_form'] = short_form
    if 'short_form' not in id_meta:
        if id.startswith(obo_iri):
            short_form = id.replace(obo_iri, '')
            id_meta['obo_id'] = short_form.replace("_",":")
            id_meta['short_form'] = short_form
        else:
            print("WARNING: ID "+id+" does not have a prefixable IRI")
            id_meta['obo_id'] = id
            id_meta['short_form'] = id
    return id_meta


def obographs2solr(obo, curie_map):
    solr = []
    for g in obo['graphs']:
        for e in g["nodes"]:
            se = dict()
            #print(e['id'])
            id = e["id"]
            id_meta = get_id_variants(id,curie_map)
            se["id"] = id
            se["iri"] = id
            se["short_form"] = id_meta['short_form']
            se["obo_id"] = id_meta['obo_id']
            se["obo_id_autosuggest"] = []  # "FBbt_00007239", "FBbt:00007239"
            se["obo_id_autosuggest"].append(id_meta['obo_id'])
            se["obo_id_autosuggest"].append(id_meta['short_form'])

            se["shortform_autosuggest"] = []  # "Court2017", "Court2017", "Court 2017"
            se["shortform_autosuggest"].append(id_meta['short_form'])
            # regex rule for tokenising split string from numeric ->
            # @dosumis: in Perl you can specify any boundaries like that.
            # That would make sense. @Robbie1977 should be in the indexer in the separate thing;
            # check whether custom tokenisation is better or create the tokens manually and push them in the fields.
            # Check what OLS does (@Robbie1977 to share schema)

            se["label_autosuggest"] = []
            if 'lbl' in e:
                se["label"] = e["lbl"]
                se["label_autosuggest"].append(e["lbl"])
            else:
                se["label"] = ""  # Should this be done?

            se["synonym"] = []
            se["synonym_autosuggest"] = []
            if 'synonyms' in e:
                for syn in e['synonyms']:
                    se["synonym"].append(syn['val'])
                    se["synonym_autosuggest"].append(syn['val'])

            se["facets_annotation"] = []  # "Individual", "DataSet", "Entity"
            if 'meta' in e:
                if 'basicPropertyValues' in e['meta']:
                    for annotation in e['meta']['basicPropertyValues']:
                        if annotation['pred']==n2o_nodelabel_iri:
                            se["facets_annotation"].append(annotation['val'])
            solr.append(se)
    return solr

# obographs_file = "/Users/matentzn/pipeline/vfb-pipeline-dumps/solr.json"
# solr_out_file = "/Users/matentzn/pipeline/vfb-pipeline-dumps/solr_out.json"
# curie_map_file = "/Users/matentzn/pipeline/vfb-prod/neo4j2owl-config.yaml"

obographs_file = sys.argv[1]
curie_map_file = sys.argv[2]
solr_out_file = sys.argv[3]

obo = load_json(obographs_file)
curie_map = parse_curie_map(curie_map_file)
solr = obographs2solr(obo,curie_map)
save_json(solr, solr_out_file)
