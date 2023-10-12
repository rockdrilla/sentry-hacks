ARG IMAGE_PATH=docker.io/rockdrilla
ARG DISTRO
ARG SUITE
ARG PYTHON_VERSION
ARG NODEJS_VERSION

ARG STAGE_IMAGE=${IMAGE_PATH}/python-dev:${PYTHON_VERSION}-${SUITE}
ARG BASE_IMAGE=${IMAGE_PATH}/python:${PYTHON_VERSION}-${SUITE}
ARG NODEJS_PKG_IMAGE=${IMAGE_PATH}/nodejs-pkg:${NODEJS_VERSION}-${SUITE}

ARG BUILDER_INTERIM_IMAGE
ARG UWSGI_INTERIM_IMAGE
ARG LIBRDKAFKA_INTERIM_IMAGE
ARG COMMON_DEPS_INTERIM_IMAGE
ARG COMMON_INTERIM_IMAGE
ARG SENTRY_DEPS_INTERIM_IMAGE
ARG SENTRY_WHL_INTERIM_IMAGE
ARG SNUBA_DEPS_INTERIM_IMAGE

## ---

FROM ${BUILDER_INTERIM_IMAGE} as sentry-prepare
SHELL [ "/bin/sh", "-ec" ]

ARG SENTRY_GITREF
COPY --from=artifacts  tarballs/sentry-${SENTRY_GITREF}.tar.gz  /tmp/sentry.tar.gz

COPY /sentry/  /app/sentry/

COPY /patches/sentry-build.patch  /app/

## repack sentry tarball
RUN mkdir /tmp/sentry ; \
    cd /tmp/sentry ; \
    tar --strip-components=1 -xf /tmp/sentry.tar.gz ; \
    ## replace with local changes
    tar -C /app/sentry -cf - . | tar -xf - ; \
    ## apply patch
    patch -p1 < /app/sentry-build.patch ; \
    ## save tarball
    tar -cf - . | gzip -9 > /app/sentry.tar.gz ; \
    ls -l /tmp/sentry.tar.gz /app/sentry.tar.gz ; \
    cd / ; \
    cleanup

## ---

FROM ${BUILDER_INTERIM_IMAGE} as snuba-prepare
SHELL [ "/bin/sh", "-ec" ]

ARG SNUBA_GITREF
COPY --from=artifacts  tarballs/snuba-${SNUBA_GITREF}.tar.gz  /tmp/snuba.tar.gz

COPY /snuba/               /app/snuba/
COPY /patches/snuba.patch  /app/

## repack snuba tarball
RUN mkdir /tmp/snuba ; \
    cd /tmp/snuba ; \
    tar --strip-components=1 -xf /tmp/snuba.tar.gz ; \
    ## remove unused things
    rm -rf docs tests ; \
    ## replace with local changes
    tar -C /app/snuba -cf - . | tar -xf - ; \
    ## apply patch
    patch -p1 < /app/snuba.patch ; \
    ## save tarball
    tar -cf - . | gzip -9 > /app/snuba.tar.gz ; \
    ls -l /tmp/snuba.tar.gz /app/snuba.tar.gz ; \
    cd / ; \
    cleanup

## ---

FROM ${BUILDER_INTERIM_IMAGE} as uwsgi-prepare
SHELL [ "/bin/sh", "-ec" ]

ARG UWSGI_GITREF
COPY --from=artifacts  tarballs/uwsgi-${UWSGI_GITREF}.tar.gz  /tmp/uwsgi.tar.gz

ARG UWSGI_DOGSTATSD_GITREF
COPY --from=artifacts  tarballs/uwsgi-dogstatsd-${UWSGI_DOGSTATSD_GITREF}.tar.gz  /app/uwsgi-dogstatsd.tar.gz

COPY /patches/uwsgi/  /app/uwsgi/

## repack uwsgi tarball
RUN mkdir /tmp/uwsgi ; \
    cd /tmp/uwsgi ; \
    tar --strip-components=1 -xf /tmp/uwsgi.tar.gz ; \
    ## apply patches
    find /app/uwsgi/ -name '*.patch' -type f | sort -V | \
    while read -r pfile ; do \
        [ -n "${pfile}" ] || continue ; \
        echo "# applying ${pfile}" ; \
        patch -p1 < "${pfile}" ; \
    done ; \
    ## save tarball
    tar -cf - . | gzip -9 > /app/uwsgi.tar.gz ; \
    ls -l /tmp/uwsgi.tar.gz /app/uwsgi.tar.gz ; \
    cd / ; \
    cleanup

## ---

FROM ${BUILDER_INTERIM_IMAGE} as xmlsec-prepare
SHELL [ "/bin/sh", "-ec" ]

ARG PYTHON_XMLSEC_GITREF
COPY --from=artifacts  tarballs/python-xmlsec-${PYTHON_XMLSEC_GITREF}.tar.gz  /tmp/python-xmlsec.tar.gz

COPY /patches/python-xmlsec.patch  /app/

## repack python-xmlsec tarball
RUN mkdir /tmp/python-xmlsec ; \
    cd /tmp/python-xmlsec ; \
    tar --strip-components=1 -xf /tmp/python-xmlsec.tar.gz ; \
    ## apply patch
    patch -p1 < /app/python-xmlsec.patch ; \
    ## save tarball
    tar -cf - . | gzip -9 > /app/python-xmlsec.tar.gz ; \
    ls -l /tmp/python-xmlsec.tar.gz /app/python-xmlsec.tar.gz ; \
    cd / ; \
    cleanup

## ---

FROM ${STAGE_IMAGE} as builder

ENV _CFLAGS_PREPEND='-g -O3 -fPIC -flto=2 -fuse-linker-plugin -ffat-lto-objects -flto-partition=none' \
    _CFLAGS_STRIP='-g -O2'

ENV DEB_BUILD_OPTIONS='hardening=+all,-pie,-stackprotectorstrong optimize=-lto' \
    DEB_CFLAGS_STRIP="${_CFLAGS_STRIP}" \
    DEB_CXXFLAGS_STRIP="${_CFLAGS_STRIP}" \
    DEB_CFLAGS_PREPEND="${_CFLAGS_PREPEND}" \
    DEB_CFLAGS_PREPEND="${_CFLAGS_PREPEND}"

RUN quiet apt-install apt-utils build-essential curl debhelper fakeroot gnupg jq zstd ; \
    cleanup

COPY /build-scripts/*.sh  /usr/local/sbin/
RUN chmod +x /usr/local/sbin/*.sh

## hack everything!

ARG PYTHON_VERSION
ENV PATH="/opt/python-${PYTHON_VERSION}/bin:${PATH}"

RUN cd / ; \
    dpkg-buildflags --export=sh > /opt/flags ; \
    . /opt/flags ; \
    for f in ${CFLAGS} ; do \
        case "$f" in \
        -specs=* ) \
            _CFLAGS_PREPEND="${_CFLAGS_PREPEND} $f" ; \
        ;; \
        esac ; \
    done ; \
    grep -ZFRl -e fstack-protector-strong $(python-config --prefix)/ \
    | grep -zEv '\.(o|pyc|so)$' \
    | xargs -0r sed -i -e 's/fstack-protector-strong/fstack-protector/g' ; \
    grep -ZFRl -e fno-lto $(python-config --prefix)/ \
    | grep -zEv '\.(o|pyc|so)$' \
    | xargs -0r sed -Ei -e 's/\s*-fno-lto\s*/ /g' ; \
    grep -ZFRl -e ' -O2 ' $(python-config --prefix)/ \
    | grep -zEv '\.(o|pyc|so)$' \
    | xargs -0r sed -i -e 's#\s*-g -O2\s*# -O2 #g;'"s# -O2 # ${_CFLAGS_PREPEND} #g" ; \
    python-compile.sh "$(python-config --prefix)/lib/" ; \
    ## smoke/qa
    python-config --cflags

## install python build deps

RUN cd /tmp ; \
    pip-list.sh > list0 ; \
    K2_PYTHON_INSTALL=dist \
    pip install -v \
      'cython<3' \
      'maturin~=1.3.0' \
      'mypy~=1.5.1' \
    ; \
    pip-list.sh > list1 ; \
    set +e ; \
    grep -Fvx -f list0 list1 > list2 || : ; \
    grep -Ev -e '^(cython|maturin|mypy)' list2 > list3 ; \
    set -e ; \
    xargs -r -a list3 pip install --force-reinstall ; \
    cd / ; cleanup

## ---

FROM ${BUILDER_INTERIM_IMAGE} as uwsgi
SHELL [ "/bin/sh", "-ec" ]

ENV BUILD_DEPS='libjemalloc-dev libpcre2-dev'

ENV UWSGI_PROFILE_OVERRIDE='malloc_implementation=jemalloc;pcre=true;ssl=false;xml=false'

WORKDIR /app

RUN apt-list-installed > apt.deps.0

COPY --from=uwsgi-prepare  /app/*.tar.gz  /tmp/

RUN cd /tmp ; \
    ## build uwsgi
    export APPEND_CFLAGS="$( . /opt/flags ; printf '%s' "${CFLAGS}" )" ; \
    apt-wrap-python -p "/usr/local:${SITE_PACKAGES}" -d "${BUILD_DEPS}" \
      pip install -v \
        uwsgi.tar.gz \
    ; \
    LD_PRELOAD= ldd /usr/local/bin/uwsgi ; \
    unset APPEND_CFLAGS ; \
    ## build uwsgi-dogstatsd
    mkdir uwsgi-dogstatsd uwsgi-dogstatsd.build ; \
    tar -C uwsgi-dogstatsd --strip-components=1 -xf uwsgi-dogstatsd.tar.gz ; \
    env -C uwsgi-dogstatsd.build \
    apt-wrap-python -d "${BUILD_DEPS}" \
      uwsgi --build-plugin /tmp/uwsgi-dogstatsd \
    ; \
    mkdir -p cd /usr/local/lib/uwsgi ; \
    cd /usr/local/lib/uwsgi ; \
    cp -t ${PWD} /tmp/uwsgi-dogstatsd.build/*.so ; \
    LD_PRELOAD= ldd ./*.so ; \
    uwsgi --need-plugin=./dogstatsd --help > /dev/null ; \
    cd / ; cleanup

## finish layer

RUN diff-apt-lists.sh apt.deps.uwsgi apt.deps.0 ; \
    strip-debug-elf.sh /app /usr/local "${SITE_PACKAGES}"

## ---

FROM ${BUILDER_INTERIM_IMAGE} as librdkafka
SHELL [ "/bin/sh", "-ec" ]

ENV BUILD_DEPS='libcurl4-openssl-dev libffi-dev liblz4-dev libsasl2-dev libssl-dev libzstd-dev zlib1g-dev'
ENV BUILD_FROM_SRC='confluent-kafka'

WORKDIR /app

RUN apt-list-installed > apt.deps.0

ARG LIBRDKAFKA_GITREF
COPY --from=artifacts  tarballs/librdkafka-${LIBRDKAFKA_GITREF}.tar.gz  /tmp/librdkafka.tar.gz

RUN cd /tmp ; \
    ## build librdkafka
    mkdir librdkafka ; \
    cd librdkafka ; \
    . /opt/flags ; \
    export CPPFLAGS="${CPPFLAGS} -Wno-free-nonheap-object" ; \
    export LDFLAGS="${LDFLAGS} -Wno-free-nonheap-object" ; \
    tar --strip-components=1 -xf /tmp/librdkafka.tar.gz ; \
    apt-wrap-sodeps -p /usr/local "${BUILD_DEPS}" \
      sh -ec '\
        ./configure \
          --prefix=/usr/local \
          --sysconfdir=/etc \
          --localstatedir=/var \
          --runstatedir=/run \
        ; \
        make -j$(nproc) libs ; \
        make install-subdirs ; \
        ldconfig' ; \
    ## remove unused things
    rm -rf /usr/local/share/doc /usr/local/lib/librdkafka*.a ; \
    ## install confluent-kafka
    apt-wrap-python -p "/usr/local:${SITE_PACKAGES}" -d "${BUILD_DEPS}" \
      pip install -v --no-binary "${BUILD_FROM_SRC}" \
        confluent-kafka==2.2.0 \
    ; \
    cd / ; cleanup

## finish layer

RUN diff-apt-lists.sh apt.deps.librdkafka apt.deps.0 ; \
    strip-debug-elf.sh /app /usr/local "${SITE_PACKAGES}"

## ---

FROM ${BUILDER_INTERIM_IMAGE} as common-deps
SHELL [ "/bin/sh", "-ec" ]

ENV BUILD_DEPS='libffi-dev libyaml-dev rapidjson-dev'
ENV BUILD_FROM_SRC='cffi,charset-normalizer,python-rapidjson,pyyaml,regex,simplejson'

ENV CHARSET_NORMALIZER_USE_MYPYC=1
ENV PYYAML_FORCE_CYTHON=1

ARG UWSGI_INTERIM_IMAGE
ARG LIBRDKAFKA_INTERIM_IMAGE

## copy uwsgi and dependencies
COPY --from=${UWSGI_INTERIM_IMAGE}  /app/              /app/
COPY --from=${UWSGI_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${UWSGI_INTERIM_IMAGE}  /usr/local/        /usr/local/

## copy librdkafka and confluent-kafka
COPY --from=${LIBRDKAFKA_INTERIM_IMAGE}  /app/              /app/
COPY --from=${LIBRDKAFKA_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${LIBRDKAFKA_INTERIM_IMAGE}  /usr/local/        /usr/local/

WORKDIR /app

RUN sort -uV apt.deps.uwsgi apt.deps.librdkafka \
    | xargs -r apt-install ; \
    ldconfig ; \
    apt-list-installed > apt.deps.0 ; \
    list-elf.sh /app /usr/local "${SITE_PACKAGES}" > elves.0

COPY /common/  /tmp/common/

RUN cd /tmp ; \
    ## install (binary) dependencies
    apt-wrap-python -p "/usr/local:${SITE_PACKAGES}" -d "${BUILD_DEPS}" \
      pip install -v --no-binary "${BUILD_FROM_SRC}" \
        -r common/requirements-binary.txt \
    ; \
    ## install remaining dependencies
    pip install -v \
      -r common/requirements.txt \
    ; \
    ## adjust *.pem (if any)
    find ${SITE_PACKAGES} -name '*.pem' -type f \
    | while read -r n ; do \
        [ -n "$n" ] || continue ; \
        rm -fv "$n" ; \
        ln -sfv /etc/ssl/certs/ca-certificates.crt "$n" ; \
    done ; \
    cd / ; cleanup

## finish layer

RUN diff-apt-lists.sh apt.deps.common apt.deps.0 apt.deps.uwsgi apt.deps.librdkafka ; \
    strip-debug-diff-elf-lists.sh elves.0 /app /usr/local "${SITE_PACKAGES}"

## ---

FROM ${COMMON_DEPS_INTERIM_IMAGE} as sentry-deps
SHELL [ "/bin/sh", "-ec" ]

ENV BUILD_DEPS='libmaxminddb-dev libpq-dev libre2-dev libxmlsec1-dev libxslt1-dev libzstd-dev rapidjson-dev'
ENV BUILD_FROM_SRC='brotli,google-crc32c,grpcio,hiredis,lxml,maxminddb,mmh3,msgpack,protobuf,psycopg2,zstandard'

ENV CRC32C_PURE_PYTHON=0
ENV GRPC_PYTHON_DISABLE_LIBC_COMPATIBILITY=1
ENV GRPC_PYTHON_BUILD_SYSTEM_OPENSSL=1
ENV GRPC_PYTHON_BUILD_WITH_CYTHON=1
## Debian 12 Bookworm libre2 is newer than in grpcio (1.57.0)
ENV GRPC_PYTHON_BUILD_SYSTEM_RE2=1
ENV PYXMLSEC_OPTIMIZE_SIZE=0

WORKDIR /app

RUN apt-list-installed > apt.deps.0 ; \
    list-elf.sh /app /usr/local "${SITE_PACKAGES}" > elves.0

ARG GOOGLE_CRC32C_GITREF
COPY --from=artifacts  tarballs/google-crc32c-${GOOGLE_CRC32C_GITREF}.tar.gz  /tmp/google-crc32c.tar.gz

COPY /sentry/  /tmp/sentry/

COPY --from=xmlsec-prepare  /app/python-xmlsec.tar.gz  /tmp/

RUN cd /tmp ; \
    ## build google-crc32c
    mkdir /tmp/google-crc32c ; \
    cd /tmp/google-crc32c ; \
    . /opt/flags ; \
    tar --strip-components=1 -xf /tmp/google-crc32c.tar.gz ; \
    apt-wrap-sodeps -p /usr/local "cmake" \
      sh -ec '\
        pfx=/usr/local ; \
        cmake \
          -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
          -DCMAKE_INSTALL_PREFIX=${pfx} \
          -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_SHARED_LIBS=yes \
          -DCRC32C_BUILD_TESTS=0 \
          -DCRC32C_BUILD_BENCHMARKS=0 \
          -DCRC32C_USE_GLOG=0 \
        ; \
        cmake --build . -j $(nproc) ; \
        cmake --install . --prefix ${pfx} ; \
        ldconfig' ; \
    cd /tmp ; \
    ## install (binary) dependencies
    apt-wrap-python -p "/usr/local:${SITE_PACKAGES}" -d "${BUILD_DEPS}" \
      pip install -v --no-binary "${BUILD_FROM_SRC}" \
        python-xmlsec.tar.gz \
        -r sentry/requirements-binary.txt \
    ; \
    ## smoke/qa
    python -c 'import maxminddb.extension; maxminddb.extension.Reader' ; \
    ## install remaining dependencies
    pip install -v \
      -r sentry/requirements-frozen.txt \
    ; \
    ## adjust *.pem (if any)
    find ${SITE_PACKAGES} -name '*.pem' -type f \
    | while read -r n ; do \
        [ -n "$n" ] || continue ; \
        rm -fv "$n" ; \
        ln -sfv /etc/ssl/certs/ca-certificates.crt "$n" ; \
    done ; \
    cd / ; cleanup

## finish layer

RUN diff-apt-lists.sh apt.deps apt.deps.0 apt.deps.common ; \
    strip-debug-diff-elf-lists.sh elves.0 /app /usr/local "${SITE_PACKAGES}"

## ---

FROM ${SENTRY_DEPS_INTERIM_IMAGE} as sentry-wheels
SHELL [ "/bin/sh", "-ec" ]

ARG SENTRY_RELEASE
ARG SENTRY_BUILD

ENV SENTRY_WHEEL="sentry-${SENTRY_RELEASE}-py311-none-any.whl"
ENV SENTRY_LIGHT_WHEEL="sentry-light-${SENTRY_RELEASE}-py311-none-any.whl"

COPY --from=sentry-prepare  /app/sentry.tar.gz  /app/

RUN if ! [ -s "/run/artifacts/${SENTRY_LIGHT_WHEEL}" ] ; then \
        export SENTRY_LIGHT_BUILD=1 ; \
        mkdir -p /tmp/sentry-build ; \
        cd /tmp/sentry-build ; \
        tar -xf /app/sentry.tar.gz ; \
        python setup.py bdist_wheel ; \
        cd dist ; \
        mv "${SENTRY_WHEEL}" "/run/artifacts/${SENTRY_LIGHT_WHEEL}" ; \
        cd / ; cleanup ; \
    fi

ARG NODEJS_PKG_IMAGE
ARG NODEJS_VERSION

COPY --from=${NODEJS_PKG_IMAGE}  /deb/  /tmp/deb/

RUN if ! [ -s "/run/artifacts/${SENTRY_WHEEL}" ] ; then \
        unset SENTRY_LIGHT_BUILD ; \
        apt-install /tmp/deb/k2-nodejs-*_${NODEJS_VERSION}-*.deb ; \
        mkdir -p /tmp/sentry-build ; \
        cd /tmp/sentry-build ; \
        tar -xf /app/sentry.tar.gz ; \
        python setup.py bdist_wheel ; \
        cd dist ; \
        mv "${SENTRY_WHEEL}" /run/artifacts/ ; \
    fi ; \
    cd / ; cleanup

## ---

FROM ${BUILDER_INTERIM_IMAGE} as sentry-aldente
SHELL [ "/bin/sh", "-ec" ]

ARG SENTRY_WHL_INTERIM_IMAGE
ARG SENTRY_RELEASE
ARG SENTRY_BUILD
ARG SENTRY_LIGHT

ENV SENTRY_WHEEL="sentry-${SENTRY_RELEASE}-py311-none-any.whl"
ENV SENTRY_LIGHT_WHEEL="sentry-light-${SENTRY_RELEASE}-py311-none-any.whl"

## copy binary dependencies
COPY --from=${SENTRY_WHL_INTERIM_IMAGE}  /app/              /app/
COPY --from=${SENTRY_WHL_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${SENTRY_WHL_INTERIM_IMAGE}  /usr/local/        /usr/local/

WORKDIR /app

COPY /patches/*.patch  /tmp/

## install remaining dependencies
RUN xargs -r -a apt.deps apt-install ; \
    ldconfig ; \
    ## patch packages
    cd ${SITE_PACKAGES} ; \
    for n in celery django memcached ; do \
        patch -p1 < /tmp/$n.patch ; \
    done ; \
    python-compile.sh . ; \
    cleanup

## provide some data for sentry
RUN tar -xf /app/sentry.tar.gz ./docker ; \
    rm /app/sentry.tar.gz

COPY --from=artifacts  "${SENTRY_WHEEL}"        /tmp/
COPY --from=artifacts  "${SENTRY_LIGHT_WHEEL}"  /tmp/

COPY /patches/sentry.patch  /tmp/

## install sentry as wheel (patch before installation)
RUN wheel_name="${SENTRY_WHEEL}" ; \
    [ "${SENTRY_LIGHT}" = 0 ] || wheel_name="${SENTRY_LIGHT_WHEEL}" ; \
    cd /tmp ; \
    wheel unpack /tmp/${wheel_name} ; \
    rm *.whl ; \
    cd sentry-${SENTRY_RELEASE} ; \
    patch -p2 < /tmp/sentry.patch ; \
    cd /tmp ; \
    wheel pack sentry-${SENTRY_RELEASE} ; \
    ## install new wheel
    pip -v install --no-deps "${SENTRY_WHEEL}" ; \
    cd /app ; \
    cleanup ; \
    python-compile.sh ${SITE_PACKAGES} ; \
    ## smoke/qa
    set -xv ; \
    sentry --version

## finish layer

RUN rm /usr/local/sbin/*.sh

## ---

FROM ${COMMON_DEPS_INTERIM_IMAGE} as snuba-deps
SHELL [ "/bin/sh", "-ec" ]

ENV BUILD_FROM_SRC='clickhouse-driver,markupsafe'

ENV CIBUILDWHEEL=1

WORKDIR /app

RUN apt-list-installed > apt.deps.0 ; \
    list-elf.sh /app /usr/local "${SITE_PACKAGES}" > elves.0

COPY /snuba/  /tmp/snuba/

RUN cd /tmp ; \
    ## install (binary) dependencies
    apt-wrap-python -p "/usr/local:${SITE_PACKAGES}" \
      pip install -v --no-binary "${BUILD_FROM_SRC}" \
        -r snuba/requirements-binary.txt \
    ; \
    ## install remaining dependencies
    pip install -v \
      -r snuba/requirements.txt \
    ; \
    ## adjust *.pem (if any)
    find ${SITE_PACKAGES} -name '*.pem' -type f \
    | while read -r n ; do \
        [ -n "$n" ] || continue ; \
        rm -fv "$n" ; \
        ln -sfv /etc/ssl/certs/ca-certificates.crt "$n" ; \
    done ; \
    cd / ; cleanup

## finish layer

RUN diff-apt-lists.sh apt.deps apt.deps.0 apt.deps.common ; \
    strip-debug-diff-elf-lists.sh elves.0 /app /usr/local "${SITE_PACKAGES}"

## ---

FROM ${BUILDER_INTERIM_IMAGE} as snuba-aldente
SHELL [ "/bin/sh", "-ec" ]

ARG SNUBA_DEPS_INTERIM_IMAGE

## copy binary dependencies
COPY --from=${SNUBA_DEPS_INTERIM_IMAGE}  /app/              /app/
COPY --from=${SNUBA_DEPS_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${SNUBA_DEPS_INTERIM_IMAGE}  /usr/local/        /usr/local/

WORKDIR /app

RUN xargs -r -a apt.deps apt-install ; \
    ldconfig ; \
    cleanup

COPY --from=snuba-prepare  /app/snuba.tar.gz  /app/

## install snuba "in-place"
RUN tar -xf snuba.tar.gz ; \
    rm snuba.tar.gz ; \
    pip -v install --no-deps -e . ; \
    python-compile.sh . ; \
    ## adjust permissions
    chmod -R go-w /app ; \
    ## smoke/qa
    set -xv ; \
    snuba --version

## finish layer

RUN rm /usr/local/sbin/*.sh

## ---

FROM ${BASE_IMAGE} as common
SHELL [ "/bin/sh", "-ec" ]

ARG COMMON_DEPS_INTERIM_IMAGE

## copy binary dependencies
COPY --from=${COMMON_DEPS_INTERIM_IMAGE}  /app/              /app/
COPY --from=${COMMON_DEPS_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${COMMON_DEPS_INTERIM_IMAGE}  /usr/local/        /usr/local/

RUN rm /usr/local/sbin/*.sh

WORKDIR /app

RUN xargs -r -a /app/apt.deps.common apt-install ; \
    rm /app/apt.deps.common ; \
    ldconfig ; \
    cleanup

ARG SENTRY_RELEASE
ENV SENTRY_RELEASE="${SENTRY_RELEASE}" \
    UWSGI_NEED_PLUGIN=/usr/local/lib/uwsgi/dogstatsd

CMD [ "bash" ]

## ---

FROM ${COMMON_INTERIM_IMAGE} as sentry
SHELL [ "/bin/sh", "-ec" ]

WORKDIR /app

## prepare user
RUN add-simple-user sentry 30000 /app

## copy sentry and dependencies
COPY --from=sentry-aldente  /app/              /app/
COPY --from=sentry-aldente  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=sentry-aldente  /usr/local/        /usr/local/

RUN xargs -r -a /app/apt.deps apt-install ; \
    ldconfig ; \
    install -d -m 01777 /data ; \
    cleanup

VOLUME /data

ARG SENTRY_BUILD
ENV SENTRY_BUILD=${SENTRY_BUILD} \
    SENTRY_CONF=/etc/sentry \
    GRPC_POLL_STRATEGY=epoll1

RUN mkdir -p ${SENTRY_CONF} ; \
    cp -t ${SENTRY_CONF} /app/docker/sentry.conf.py /app/docker/config.yml

EXPOSE 9000

CMD [ "sentry", "run", "web" ]

## switch user
USER sentry

## ---

FROM ${COMMON_INTERIM_IMAGE} as snuba
SHELL [ "/bin/sh", "-ec" ]

WORKDIR /app

## prepare user
RUN add-simple-user snuba 30000 /app

## copy snuba and dependencies
COPY --from=snuba-aldente  /app/              /app/
COPY --from=snuba-aldente  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=snuba-aldente  /usr/local/        /usr/local/

RUN xargs -r -a /app/apt.deps apt-install ; \
    ldconfig ; \
    cleanup

ENV SNUBA_RELEASE="${SENTRY_RELEASE}" \
    FLASK_DEBUG=0 \
    UWSGI_ENABLE_METRICS=true \
    UWSGI_STATS_PUSH=dogstatsd:127.0.0.1:8126 \
    UWSGI_DOGSTATSD_EXTRA_TAGS=service:snuba

CMD [ "snuba", "api" ]

## switch user
USER snuba
