###########################################################################################################
#
# How to build:
#
# docker build -t arkcase/tika:latest .
#
# How to run: (Helm)
#
# helm repo add arkcase https://arkcase.github.io/ark_helm_charts/
# helm install ark-tika arkcase/ark-tika
# helm uninstall ark-tika
#
# How to run: (Docker)
#
# docker run --name ark_tika -p 8443:8443  -d arkcase/tika:latest
# docker exec -it ark_tika /bin/bash
# docker stop ark_tika
# docker rm ark_tika
#
# How to run: (Kubernetes)
#
# kubectl create -f pod_ark_tika.yaml
# kubectl --namespace default port-forward tika 8443:8443 --address='0.0.0.0'
# kubectl exec -it pod/tika -- bash
# kubectl delete -f pod_ark_tika.yaml
#
###########################################################################################################

ARG FIPS=""
ARG PRIVATE_REGISTRY
ARG PUBLIC_REGISTRY="public.ecr.aws"
ARG ARCH="amd64"
ARG OS="linux"
ARG VER="3.3.2"
ARG PKG="tika"
ARG KEYS="https://www.apache.org/dist/tika/KEYS"
ARG LOG4J_VER="2.26.1"
ARG LOG4J_JUL_SRC="org.apache.logging.log4j:log4j-jul:${LOG4J_VER}:jar"
ARG JAVA="17"

ARG ARKCASE_MVN_REPO="https://nexus.armedia.com/repository/arkcase/"
ARG ARK_TIKA_JAR_GROUP="com.armedia"
ARG ARK_TIKA_JAR_ARTIFACT="arkcase-tika"
ARG ARK_TIKA_JAR_VERSION="1.0.4"
ARG ARK_TIKA_JAR_SRC="${ARK_TIKA_JAR_GROUP}:${ARK_TIKA_JAR_ARTIFACT}:${ARK_TIKA_JAR_VERSION}"

ARG BASE_REGISTRY="${PUBLIC_REGISTRY}"
ARG BASE_REPO="arkcase/base-java"
ARG BASE_VER="24.04"
ARG BASE_VER_PFX=""
ARG BASE_IMG="${BASE_REGISTRY}/${BASE_REPO}${FIPS}:${BASE_VER_PFX}${BASE_VER}"

ARG TIKA_REG="${PRIVATE_REGISTRY}"
ARG TIKA_REPO="arkcase/rebuild-tika"
ARG TIKA_VER="${VER}"
ARG TIKA_VER_PFX="${BASE_VER_PFX}"
ARG TIKA_IMG="${TIKA_REG}/${TIKA_REPO}:${TIKA_VER_PFX}${TIKA_VER}"

FROM "${TIKA_IMG}" AS tika-src

ARG BASE_IMG

FROM "${BASE_IMG}"

ARG FIPS
ARG ARCH
ARG OS
ARG VER
ARG PKG
ARG APP_UID="1999"
ARG APP_GID="${APP_UID}"
ARG APP_USER="${PKG}"
ARG APP_GROUP="${APP_USER}"
ARG LOG4J_JUL_SRC
ARG JAVA

ARG ARKCASE_MVN_REPO
ARG ARK_TIKA_JAR_VERSION
ARG ARK_TIKA_JAR_SRC
ARG TIKA_MVN_REPO
ARG TIKA_GROUP
ARG TIKA_VER

#
# Basic Parameters
#

LABEL ORG="Armedia LLC"
LABEL MAINTAINER="Armedia Devops Team <devops@armedia.com>"
LABEL APP="Tika"
LABEL VERSION="${VER}"
LABEL ARK_TIKA_JAR_VERSION="${ARK_TIKA_JAR_VERSION}"

# Environment variables: ActiveMQ directories
ENV HOME_DIR="${BASE_DIR}/${PKG}"

# Environment variables: system stuff
ENV APP_UID="${APP_UID}"
ENV APP_GID="${APP_GID}"
ENV APP_USER="${APP_USER}"
ENV APP_GROUP="${APP_GROUP}"

# Environment variables: Java stuff
ENV USER="${APP_USER}"

WORKDIR "${BASE_DIR}"

ENV PATH="${HOME_DIR}/bin:${PATH}"

#
# Update local packages and install required packages
#
RUN set-java "${JAVA}" && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -y install \
        gdal-bin \
        imagemagick \
        tesseract-ocr \
        tesseract-ocr-eng \
        tesseract-ocr-fra \
        tesseract-ocr-spa \
      && \
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get -y install \
        fonts-liberation \
        ttf-mscorefonts-installer \
        cabextract \
      && \
    apt-get clean -y

RUN --mount=type=secret,id=mvn_get_auth,uid=${APP_UID},gid=${APP_GID} \
    . /run/secrets/mvn_get_auth && \
    umask 0022 && \
    mkdir -p "${CONF_DIR}" "${LOGS_DIR}" "${TEMP_DIR}" "${LIB_DIR}" && \
    mvn-get "${LOG4J_JUL_SRC}" "${LIB_DIR}" && \
    mvn-get "${ARK_TIKA_JAR_SRC}" "${ARKCASE_MVN_REPO}" "${LIB_DIR}"

COPY --chmod=0644 --chown=root:root --from=tika-src /tika-app-*.jar /tika-server-*.jar /usr/local/bin/
COPY --chmod=0644 --chown=root:root --from=tika-src /tika-emitter-*.jar /tika-fetcher-*.jar "${LIB_DIR}"

#
# Install the remaining files
#
COPY --chown=root:root --chmod=0755 entrypoint /

#
# Create the required user/group
#
RUN groupadd --gid "${APP_GID}" "${APP_GROUP}" && \
    useradd  --uid "${APP_UID}" --gid "${APP_GROUP}" --groups "${ACM_GROUP}" --create-home --home-dir "${HOME_DIR}" "${APP_USER}"

COPY --chown=${APP_GID}:${APP_UID} --chmod=0644 server.xml "${CONF_DIR}/server.xml"

RUN --mount=type=bind,source=CVE,target=/CVE apply-fixes /CVE

RUN rm -rf /tmp/* && \
    mkdir -p "${HOME_DIR}/bin" && \
    chown -R "${APP_USER}:${APP_GROUP}" "${BASE_DIR}" && \
    chmod -R "u=rwX,g=rX,o=" "${BASE_DIR}" && \
    chown root "${HOME_DIR}/bin"

#
# Launch as the application's user
#
USER "${APP_USER}"

EXPOSE 8443

ENTRYPOINT [ "/entrypoint" ]
