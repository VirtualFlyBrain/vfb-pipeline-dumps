#!/bin/bash

set -e
set -o pipefail

export ROBOT_JAVA_ARGS=${ROBOT_ARGS}
export JAVA_OPTS=${ROBOT_ARGS}
export OUTDIR=/out
export RAW_DUMPS_DIR=$OUTDIR/raw
export FINAL_DUMPS_DIR=$OUTDIR/dumps
export SPARQL_DIR=$WORKSPACE/sparql
export SCRIPTS_DIR=$WORKSPACE/scripts

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a ${OUTDIR}/dumps.log
}

log "process started"
log "Start: vfb-pipeline-dumps"
log "VFBTIME:"
date | tee -a ${OUTDIR}/dumps.log

log "** Creating temporary directories.. **"
cd ${WORKSPACE}
mkdir -p $FINAL_DUMPS_DIR $RAW_DUMPS_DIR
find $FINAL_DUMPS_DIR -type f -delete
find $RAW_DUMPS_DIR -type f -delete

log "VFBTIME:"
date | tee -a ${OUTDIR}/dumps.log

log '** Executing pipeline.. **' | tee -a ${OUTDIR}/dumps.log

{ /usr/bin/time -v make 2>&1 ; } | tee -a ${OUTDIR}/dumps.log

log "End: vfb-pipeline-dumps"
log "VFBTIME:"
date | tee -a ${OUTDIR}/dumps.log
log "process complete"
