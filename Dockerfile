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

ARG PUBLIC_REGISTRY="public.ecr.aws"
ARG ARCH="amd64"
ARG OS="linux"
ARG VER="3.2.3"
ARG PKG="tika"
ARG KEYS="https://www.apache.org/dist/tika/KEYS"
ARG APP_SRC="https://dlcdn.apache.org/tika/${VER}/tika-app-${VER}.jar"
ARG SERVER_SRC="https://dlcdn.apache.org/tika/${VER}/tika-server-standard-${VER}.jar"
ARG JAVA="17"

ARG BASE_REGISTRY="${PUBLIC_REGISTRY}"
ARG BASE_REPO="arkcase/base-java"
ARG BASE_VER="24.04"
ARG BASE_VER_PFX=""
ARG BASE_IMG="${BASE_REGISTRY}/${BASE_REPO}:${BASE_VER_PFX}${BASE_VER}"

FROM "${BASE_IMG}"

ARG ARCH
ARG OS
ARG VER
ARG PKG
ARG APP_UID="1999"
ARG APP_GID="${APP_UID}"
ARG APP_USER="${PKG}"
ARG APP_GROUP="${APP_USER}"
ARG KEYS
ARG APP_SRC
ARG SERVER_SRC
ARG JAVA

#
# Basic Parameters
#

LABEL ORG="Armedia LLC"
LABEL MAINTAINER="Armedia Devops Team <devops@armedia.com>"
LABEL APP="Tika"
LABEL VERSION="${VER}"

# Environment variables: ActiveMQ directories
ENV HOME_DIR="${BASE_DIR}/${PKG}"

ENV LIB_DIR="${BASE_DIR}/lib"

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
        wget \
        cabextract \
      && \
    apt-get clean -y

RUN mkdir -p "${CONF_DIR}" "${LOGS_DIR}" "${TEMP_DIR}" && \
    verified-download --no-hash --keys "${KEYS}" "${APP_SRC}" "/usr/local/bin/tika.jar" && \
    verified-download --no-hash --keys "${KEYS}" "${SERVER_SRC}" "/usr/local/bin/tika-server.jar"

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

COPY --chown=root:root --chmod=0755 CVE /CVE
RUN apply-fixes /CVE

RUN rm -rf /tmp/* && \
    chown -R "${APP_USER}:${APP_GROUP}" "${BASE_DIR}" && \
    chmod -R "u=rwX,g=rX,o=" "${BASE_DIR}"

COPY --chown=root:root stig/ /usr/share/stig/
RUN cd /usr/share/stig && ./run-all

#
# Launch as the application's user
#
USER "${APP_USER}"

EXPOSE 8443

ENTRYPOINT [ "/entrypoint" ]
