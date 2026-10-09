FROM python:3.6

VOLUME /logs
VOLUME /out

ENV WORKSPACE=/opt/VFB
ENV VALIDATE=true
ENV VALIDATESHEX=true
ENV VALIDATESHACL=true
ENV SPARQL_ENDPOINT=http://ts.p2.virtualflybrain.org/rdf4j-server/repositories/vfb
ENV VFB_CONFIG=http://virtualflybrain.org/config/neo4j2owl-config.yaml
ENV CORES=4

# This is appended to all ROBOT commands. It filters out all lines in stdout that match the grep.

ENV PATH "/opt/VFB/:/opt/VFB/shacl/bin:$PATH"

RUN pip3 install wheel requests psycopg2 pandas base36 PyYAML rdflib

# python:3.6 is Debian bullseye, which has moved to archive.debian.org; the live mirrors now 404 on its packages.
RUN sed -i -e 's|http://deb.debian.org/debian-security|http://archive.debian.org/debian-security|g' \
           -e 's|http://security.debian.org/debian-security|http://archive.debian.org/debian-security|g' \
           -e 's|http://deb.debian.org/debian|http://archive.debian.org/debian|g' /etc/apt/sources.list && \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archive

RUN apt-get -qq update || apt-get -qq update && \
apt-get -qq -y install git curl wget default-jdk pigz maven libpq-dev python-dev tree gawk

RUN mkdir $WORKSPACE

###### ROBOT ######
ENV ROBOT v1.8.3
ENV ROBOT_ARGS -Xmx20G -Djava.util.concurrent.ForkJoinPool.common.parallelism=1
ARG ROBOT_JAR=https://github.com/ontodev/robot/releases/download/$ROBOT/robot.jar
ENV ROBOT_JAR ${ROBOT_JAR}
RUN wget $ROBOT_JAR -O $WORKSPACE/robot.jar && \
    wget https://raw.githubusercontent.com/ontodev/robot/$ROBOT/bin/robot -O $WORKSPACE/robot && \
    chmod +x $WORKSPACE/robot && chmod +x $WORKSPACE/robot.jar

###### SHACL ######
ENV SHACL_VERSION 1.3.2
ARG SHACL_ZIP=https://repo1.maven.org/maven2/org/topbraid/shacl/$SHACL_VERSION/shacl-$SHACL_VERSION-bin.zip
ENV SHACL_ZIP ${SHACL_ZIP}
RUN wget $SHACL_ZIP -O $WORKSPACE/shacl.zip && \
    unzip $WORKSPACE/shacl.zip -d $WORKSPACE && \
    mv $WORKSPACE/shacl-$SHACL_VERSION $WORKSPACE/shacl && \
    rm $WORKSPACE/shacl.zip && chmod +x $WORKSPACE/shacl/bin/shaclvalidate.sh && chmod +x $WORKSPACE/shacl/bin/shaclinfer.sh

###### Copy pipeline files ########
ENV STDOUT_FILTER=\|\ \{\ grep\ -v\ \'OWLRDFConsumer\\\|InvalidReferenceViolation\\\|RDFParserRegistry\'\ \|\|\ true\;\ \}
ENV INFER_ANNOTATE_RELATION=http://n2o.neo/property/nodeLabel
ENV UNIQUE_FACETS_ANNOTATION=http://n2o.neo/property/uniqueFacets
COPY process.sh $WORKSPACE/process.sh
COPY dumps.Makefile $WORKSPACE/Makefile
RUN chmod +x $WORKSPACE/process.sh
# COPY vfb*.txt $WORKSPACE/
COPY /sparql $WORKSPACE/sparql
COPY /scripts $WORKSPACE/scripts
# COPY /shacl $WORKSPACE/shacl
# COPY /shex $WORKSPACE/shex
# COPY /test.ttl $WORKSPACE/

###### NEO4J2OWL ######
# Built from the git tag (no GitHub release asset needed). 1.2.3.13-PRE indexes entities by IRI: the pdb_csvs step
# drops from ~69 h to ~0.7 h on the full pdb.owl with identical CSV output (A/B-tested 2026-10-09).
ENV NEO4J2OWL_VERSION 1.2.3.13-PRE
RUN git clone -q --depth 1 -b $NEO4J2OWL_VERSION https://github.com/VirtualFlyBrain/neo4j2owl.git /tmp/neo4j2owl && \
    cd /tmp/neo4j2owl && mvn -q -B -DskipTests package && \
    cp target/owl2neo4jcsv.jar $WORKSPACE/scripts/owl2neo4jcsv.jar && chmod +x $WORKSPACE/scripts/owl2neo4jcsv.jar && \
    cd / && rm -rf /tmp/neo4j2owl /root/.m2

ENV INFER_ANNOTATE_VERSION v0.0.3
ARG INFER_ANNOTATE_JAR=https://github.com/VirtualFlyBrain/vfb_expression_annotator/releases/download/$INFER_ANNOTATE_VERSION/infer-annotate.jar
ENV INFER_ANNOTATE_JAR ${INFER_ANNOTATE_JAR}
RUN wget $INFER_ANNOTATE_JAR -O $WORKSPACE/scripts/infer-annotate.jar && \
    chmod +x $WORKSPACE/scripts/infer-annotate.jar

###### Debug tools ########
RUN apt-get -y update && apt-get -y install time

CMD ["/opt/VFB/process.sh"]
