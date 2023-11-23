FROM maven:3.6-jdk-11 as builder

WORKDIR /code

ARG SQLRENDER_VERSION=1.16.1-SNAPSHOT
ARG ARACHNE_VERSION=1.20.3-SNAPSHOT
ARG INTERSYSTEMS_JDBC_VERSION=3.7.1

ARG MAVEN_PROFILE=webapi-docker
ARG MAVEN_PARAMS="-DSqlRender.version=${SQLRENDER_VERSION} -Darachne.version=${ARACHNE_VERSION}" # can use maven options, e.g. -DskipTests=true -DskipUnitTests=true

ARG OPENTELEMETRY_JAVA_AGENT_VERSION=1.17.0
RUN curl -LSsO https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OPENTELEMETRY_JAVA_AGENT_VERSION}/opentelemetry-javaagent.jar

COPY lib/* /tmp/lib/
COPY src/main/extras/iris/intersystems-jdbc-${INTERSYSTEMS_JDBC_VERSION}.jar /tmp/lib/
# RUN ls -l /tmp/lib/ | sed -e 's/^/mvn install:install-file -Dpackaging=jar -DgeneratePom=true -D/'

RUN mvn install:install-file -Dfile=/tmp/lib/intersystems-jdbc-${INTERSYSTEMS_JDBC_VERSION}.jar -DgroupId=com.intersystems -DartifactId=intersystems-jdbc  -Dversion=${INTERSYSTEMS_JDBC_VERSION} -Dpackaging=jar -DgeneratePom=true && \
    mvn install:install-file -Dfile=/tmp/lib/SqlRender-${SQLRENDER_VERSION}.jar -DgroupId=org.ohdsi.sql -DartifactId=SqlRender  -Dversion=${SQLRENDER_VERSION} -Dpackaging=jar -DgeneratePom=true && \
    mvn install:install-file -Dfile=/tmp/lib/arachne-common-types-${ARACHNE_VERSION}.jar -DgroupId=com.odysseusinc.arachne -DartifactId=arachne-common-types  -Dversion=${ARACHNE_VERSION} -Dpackaging=jar -DgeneratePom=true  && \
    mvn install:install-file -Dfile=/tmp/lib/arachne-common-utils-${ARACHNE_VERSION}.jar -DgroupId=com.odysseusinc.arachne -DartifactId=arachne-common-utils  -Dversion=${ARACHNE_VERSION} -Dpackaging=jar -DgeneratePom=true  && \
    mvn install:install-file -Dfile=/tmp/lib/arachne-commons-${ARACHNE_VERSION}.jar -DgroupId=com.odysseusinc.arachne -DartifactId=arachne-commons  -Dversion=${ARACHNE_VERSION} -Dpackaging=jar -DgeneratePom=true  && \
    mvn install:install-file -Dfile=/tmp/lib/arachne-scheduler-${ARACHNE_VERSION}.jar -DgroupId=com.odysseusinc.arachne -DartifactId=arachne-scheduler  -Dversion=${ARACHNE_VERSION} -Dpackaging=jar -DgeneratePom=true  && \
    mvn install:install-file -Dfile=/tmp/lib/data-source-manager-${ARACHNE_VERSION}.jar -DgroupId=com.odysseusinc -DartifactId=data-source-manager  -Dversion=${ARACHNE_VERSION} -Dpackaging=jar -DgeneratePom=true  && \
    mvn install:install-file -Dfile=/tmp/lib/execution-engine-commons-${ARACHNE_VERSION}.jar -DgroupId=com.odysseusinc.arachne -DartifactId=execution-engine-commons  -Dversion=${ARACHNE_VERSION} -Dpackaging=jar -DgeneratePom=true  && \
    mvn install:install-file -Dfile=/tmp/lib/logging-${ARACHNE_VERSION}.jar -DgroupId=com.odysseusinc -DartifactId=logging  -Dversion=${ARACHNE_VERSION} -Dpackaging=jar -DgeneratePom=true 


# Download dependencies
COPY pom.xml /code/
RUN mkdir .git \
    && mvn package \
     -P${MAVEN_PROFILE}

ARG GIT_BRANCH=unknown
ARG GIT_COMMIT_ID_ABBREV=unknown

# Compile code and repackage it
COPY src /code/src
RUN mvn package ${MAVEN_PARAMS} \
    -Dgit.branch=${GIT_BRANCH} \
    -Dgit.commit.id.abbrev=${GIT_COMMIT_ID_ABBREV} \
    -P${MAVEN_PROFILE} -e \
    && mkdir war \
    && mv target/WebAPI.war war \
    && cd war \
    && jar -xf WebAPI.war \
    && rm WebAPI.war

# OHDSI WebAPI and ATLAS web application running as a Spring Boot application with Java 11
FROM openjdk:8-jre-slim

MAINTAINER Lee Evans - www.ltscomputingllc.com

# Any Java options to pass along, e.g. memory, garbage collection, etc.
ENV JAVA_OPTS=""
# Additional classpath parameters to pass along. If provided, start with colon ":"
ENV CLASSPATH=""
# Default Java options. The first entry is a fix for when java reads secure random numbers:
# in a containerized system using /dev/random may reduce entropy too much, causing slowdowns.
# https://ruleoftech.com/2016/avoiding-jvm-delays-caused-by-random-number-generation
ENV DEFAULT_JAVA_OPTS="-Djava.security.egd=file:///dev/./urandom"

# set working directory to a fixed WebAPI directory
WORKDIR /var/lib/ohdsi/webapi

COPY --from=builder /code/opentelemetry-javaagent.jar .

# deploy the just built OHDSI WebAPI war file
# copy resources in order of fewest changes to most changes.
# This way, the libraries step is not duplicated if the dependencies
# do not change.
COPY --from=builder /code/war/WEB-INF/lib*/* WEB-INF/lib/
COPY --from=builder /code/war/org org
COPY --from=builder /code/war/WEB-INF/classes WEB-INF/classes
COPY --from=builder /code/war/META-INF META-INF

# force copy
COPY src/main/extras/iris/intersystems-jdbc-3.7.1.jar WEB-INF/lib/

EXPOSE 8080

USER 101

# Directly run the code as a WAR.
CMD exec java ${DEFAULT_JAVA_OPTS} ${JAVA_OPTS} \
    -cp ".:WebAPI.jar:WEB-INF/lib/*.jar${CLASSPATH}" \
    org.springframework.boot.loader.WarLauncher