# syntax=docker/dockerfile:1.7
# Receta de compilacion de Millennial Global.
# Copia fiel de docker/Dockerfile.x86 de Canary (mismo Ubuntu 24.04, mismas librerias, mismos presets),
# SALVO que no usa el almacen privado de librerias ya compiladas del proyecto Canary:
# aqui las librerias se construyen desde cero (la primera vez tarda mas; despues se reutiliza la cache).

# Etapa 1: librerias (vcpkg)
FROM ubuntu:24.04 AS dependencies

ARG DEBIAN_FRONTEND=noninteractive
ENV DEBIAN_FRONTEND=${DEBIAN_FRONTEND}
ENV TZ=Etc/UTC
ENV VCPKG_DISABLE_METRICS=1

RUN apt-get update && apt-get install -y --no-install-recommends cmake git \
	unzip build-essential ca-certificates curl zip unzip tar \
	pkg-config ninja-build autoconf automake libtool \
	python3 tzdata \
	&& ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
	&& echo "${TZ}" > /etc/timezone \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /opt
COPY vcpkg.json /opt
RUN vcpkgCommitId=$(grep '.builtin-baseline' vcpkg.json | awk -F: '{print $2}' | tr -d '," ') \
	&& echo "vcpkg commit ID: $vcpkgCommitId" \
	&& git clone https://github.com/Microsoft/vcpkg.git \
	&& cd vcpkg \
	&& git checkout $vcpkgCommitId \
	&& ./bootstrap-vcpkg.sh

WORKDIR /opt/vcpkg_manifest
COPY vcpkg.json vcpkg-configuration.json /opt/vcpkg_manifest/
COPY vcpkg-registry /opt/vcpkg_manifest/vcpkg-registry
COPY cmake/triplets /opt/vcpkg_manifest/cmake/triplets

RUN /opt/vcpkg/vcpkg install \
	--x-manifest-root=/opt/vcpkg_manifest \
	--x-install-root=/opt/vcpkg_installed \
	--triplet=x64-linux --host-triplet=x64-linux \
	--clean-after-build

# Etapa 2: compilar el servidor
FROM dependencies AS build

COPY . /srv/
WORKDIR /srv

COPY --from=dependencies /opt/vcpkg_installed /srv/vcpkg_installed

RUN export VCPKG_ROOT=/opt/vcpkg/ && \
    cmake --preset linux-release -DTOGGLE_BIN_FOLDER=ON -DVCPKG_MANIFEST_INSTALL=OFF -DVCPKG_INSTALLED_DIR=/srv/vcpkg_installed && \
    cmake --build --preset linux-release

# Etapa 3: sacar SOLO el programa compilado
FROM scratch AS export
COPY --from=build /srv/build/linux-release/bin/canary /canary
