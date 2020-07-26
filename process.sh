#!/bin/bash

set -e
set -o pipefail

echo "process started"
echo "Start: vfb-pipeline-dumps"
echo "VFBTIME:"
date

export ROBOT_JAVA_ARGS=${ROBOT_ARGS}
export OUTDIR=/out
export RAW_DUMPS_DIR=$OUTDIR/raw
export FINAL_DUMPS_DIR=$OUTDIR/dumps
export SPARQL_DIR=$WORKSPACE/sparql
export SCRIPTS_DIR=$WORKSPACE/scripts

echo "** Creating temporary directories.. **"
cd ${WORKSPACE}
rm -rf $FINAL_DUMPS_DIR $RAW_DUMPS_DIR
mkdir $FINAL_DUMPS_DIR $RAW_DUMPS_DIR

echo "VFBTIME:"
date

echo '** Executing pipeline.. **'

make all

echo "End: vfb-pipeline-dumps"
echo "VFBTIME:"
date
echo "process complete"