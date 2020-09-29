"""OBOGraphs JSON to VFB SOLR document converter
Created on July 26, 2020

@author: matentzn

This script translates the obographs json format to the native VFB solr format.
"""

import json
import yaml
import sys
import re

n2o_nodelabel_iri = "http://n2o.neo/property/nodeLabel"
n2o_filename_iri = "http://n2o.neo/custom/filename"
n2o_thumbnail_iri = "http://n2o.neo/custom/thumbnail"
obo_iri = "http://purl.obolibrary.org/obo/"

def load_json(obographs_file):
    with open(obographs_file) as json_file:
        data: dict = json.load(json_file)
    return data
    # print(data)


def save_json(solr, solr_out_file):
    with open(solr_out_file, 'w') as outfile:
        outfile.write(json.dumps(solr, indent=4, sort_keys=True))


def parse_config(curie_map_file):
    with open(curie_map_file, 'r') as stream:
        config = yaml.safe_load(stream)
    x = config['curie_map']
    config_out = dict()
    config_out['curie_map'] = {k: v for k, v in sorted(x.items(), key=lambda item: item[1], reverse=True)}
    filters = dict()
    if 'filters' in config:
        if 'solr' in config['filters']:
            if 'exclusion' in config['filters']['solr']:
                filters['exclusion']=config['filters']['solr']['exclusion']
            if 'inclusion' in config['filters']['solr']:
                filters['inclusion']=config['filters']['solr']['inclusion']
    config_out['filters'] = filters
    return config_out


def get_id_variants(id, curie_map):
    id_meta = dict()
    for pre in curie_map:
        prefix_url = curie_map[pre]
        if id.startswith(prefix_url):
            short_form = id.replace(prefix_url,'')
            id_meta['obo_id'] = pre+":"+short_form
            if prefix_url.endswith(pre+"_"):
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


def get_string_derivatives(label):
    label_alpha = re.sub('[^0-9a-zA-Z ]+', ' ', label)
    label_alpha = re.sub('\s+', ' ', label_alpha)
    label_split_numerics_alpha = re.sub('(?<=\d)(?!\d)|(?<!\d)(?=\d)', ' ', label_alpha)
    label_split_numerics_alpha_camel = re.sub("([a-z])([A-Z])","\g<1> \g<2>",label_split_numerics_alpha)
    label_split_numerics_alpha = re.sub('\s+', ' ', label_split_numerics_alpha)
    label_split_numerics_alpha_camel = re.sub('\s+', ' ', label_split_numerics_alpha_camel)
    #label_split_numerics = re.sub('(?<=\d)(?!\d)|(?<!\d)(?=\d)', ' ', label)
    #label_split_numerics = re.sub('\s+', ' ', label_split_numerics)
    return [label_alpha.strip(), label_split_numerics_alpha.strip(),label_split_numerics_alpha_camel.strip()]


def filterOut(e,filters):
    if 'iri_prefix' in filters['exclusion']:
        for iri in filters['exclusion']['iri_prefix']:
            if iri in e['iri']:
                return True
    if 'neo4j_node_label' in filters['exclusion']:
        for neo4j_label in filters['exclusion']['neo4j_node_label']:
            if neo4j_label in e['facets_annotation']:
                return True
    return False


def obographs2solr(obo, curie_map, filters):
    solr = []
    for g in obo['graphs']:
        for e in g["nodes"]:
            se = dict()
            id = e["id"]
            id_meta = get_id_variants(id,curie_map)

            se["id"] = id
            se["iri"] = id
            se["short_form"] = id_meta['short_form']
            se["obo_id"] = id_meta['obo_id']

            se["obo_id_autosuggest"] = []
            se["obo_id_autosuggest"].append(id_meta['obo_id'])
            se["obo_id_autosuggest"].append(id_meta['short_form'])

            se["shortform_autosuggest"] = []
            se["shortform_autosuggest"].extend(se["obo_id_autosuggest"])

            se["label_autosuggest"] = []


            if 'lbl' in e:
                se["label"] = e["lbl"]
                se["label_autosuggest"].append(e["lbl"])
            else:
                se["label"] = ""  # Should this be done?

            se["synonym"] = []
            se["synonym"].append(se["label"])
            se["synonym_autosuggest"] = []
            se["synonym_autosuggest"].extend(se["label_autosuggest"])

            se["facets_annotation"] = []
            se["filename"] = []
            se["thumbnail"] = []

            if 'type' in e:
                entity_type = e['type'].capitalize()
                se["facets_annotation"].append(entity_type)

            if 'meta' in e:
                if 'basicPropertyValues' in e['meta']:
                    for annotation in e['meta']['basicPropertyValues']:
                        if annotation['pred']==n2o_nodelabel_iri:
                            se["facets_annotation"].append(annotation['val'])
                        if annotation['pred']==n2o_filename_iri:
                            se["filename"].append(annotation['val'])
                        if annotation['pred']==n2o_thumbnail_iri:
                            se["thumbnail"].append(annotation['val'])
                if 'synonyms' in e['meta']:
                    for syn in e['meta']['synonyms']:
                        se["synonym"].append(syn['val'])
                        se["synonym_autosuggest"].append(syn['val'])

                        syntype = syn['pred']
                        if 'synonym_'+syntype not in se:
                            se['synonym_'+syntype] = []
                            se['synonym_' + syntype+'_autosuggest'] = []
                        se['synonym_'+syntype].append(syn['val'])
                        se['synonym_' + syntype+'_autosuggest'].append(syn['val'])

                        # Removed as discussed https://github.com/VirtualFlyBrain/vfb-pipeline-dumps/issues/9
                        #if 'xrefs' in syn:
                        #    se["synonym"].extend(syn['xrefs'])
                        #    se["synonym_autosuggest"].extend(syn['xrefs'])

                if 'definition' in e['meta']:
                    se['definition'] = e['meta']['definition']['val']
                    se['definition'] = (se['definition'][:98] + '..') if len(se['definition']) > 100 else se['definition']

            for key in se:
                if isinstance(se[key], list) and ('autosuggest' in key):
                    derivatives = []
                    for l in se[key]:
                        derivatives.extend(get_string_derivatives(l))
                    se[key].extend(derivatives)
                se[key] = list(set(se[key])) if isinstance(se[key], list) else se[key]
            if not filterOut(se, filters):
                solr.append(se)
    return solr

#obographs_file = "/Users/matentzn/vfb/vfb-pipeline-dumps/test/obographs.json"
#solr_out_file = "/Users/matentzn/vfb/vfb-pipeline-dumps/test/solr.json"
#curie_map_file = "/Users/matentzn/vfb/vfb-prod/neo4j2owl-config.yaml"

obographs_file = sys.argv[1]
curie_map_file = sys.argv[2]
solr_out_file = sys.argv[3]

obo = load_json(obographs_file)
config = parse_config(curie_map_file)
curie_map = config['curie_map']
filters = config['filters']
solr = obographs2solr(obo,curie_map,filters)
save_json(solr, solr_out_file)
