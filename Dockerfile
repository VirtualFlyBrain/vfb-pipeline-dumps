FROM python:3.6

VOLUME /logs
VOLUME /out

ENV WORKSPACE=/opt/VFB
ENV VALIDATE=true
ENV VALIDATESHEX=true
ENV VALIDATESHACL=true
ENV SPARQL_ENDPOINT=http://ts.p2.virtualflybrain.org/rdf4j-server/repositories/vfb
ENV VFB_CONFIG=http://virtualflybrain.org/config/neo4j2owl-config.yaml

# This is appended to all ROBOT commands. It basically filters out all lines in stdout that match the grep.

ENV PATH "/opt/VFB/:/opt/VFB/shacl/bin:$PATH"

RUN pip3 install wheel requests psycopg2 pandas base36 PyYAML

RUN apt-get -qq update || apt-get -qq update && \
apt-get -qq -y install git curl wget default-jdk pigz maven libpq-dev python-dev tree gawk

RUN mkdir $WORKSPACE

###### ROBOT ######
ENV ROBOT v1.8.3
ENV ROBOT_ARGS -Xmx20G
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
COPY process.sh $WORKSPACE/process.sh
COPY dumps.Makefile $WORKSPACE/Makefile
RUN chmod +x $WORKSPACE/process.sh
# COPY vfb*.txt $WORKSPACE/
COPY /sparql $WORKSPACE/sparql
COPY /scripts $WORKSPACE/scripts
# COPY /shacl $WORKSPACE/shacl
# COPY /shex $WORKSPACE/shex
# COPY /test.ttl $WORKSPACE/

CMD ["/opt/VFB/process.sh"]
