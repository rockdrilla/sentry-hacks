ARG IMAGE_PATH=docker.io/rockdrilla
ARG DISTRO
ARG SUITE
ARG PYTHON_VERSION

ARG BUILDER_INTERIM_IMAGE
ARG UWSGI_INTERIM_IMAGE
ARG LIBRDKAFKA_INTERIM_IMAGE
ARG SENTRY_DEPS_INTERIM_IMAGE
ARG SNUBA_DEPS_INTERIM_IMAGE
ARG HELPER_IMAGE=${DISTRO}-buildd:${SUITE}
ARG STAGE_IMAGE=python-dev:${PYTHON_VERSION}-${SUITE}
ARG BASE_IMAGE=python-min:${PYTHON_VERSION}-${SUITE}

## ---

FROM ${IMAGE_PATH}/${HELPER_IMAGE} as sentry-prepare
SHELL [ "/bin/sh", "-ec" ]

ARG SENTRY_GITREF

COPY /sentry/  /app/sentry/

COPY /patches/sentry-build.patch  /app/

## repack sentry tarball
RUN mkdir /tmp/sentry ; \
    cd /tmp/sentry ; \
    tar --strip-components=1 -xf /run/artifacts/sentry-${SENTRY_GITREF}.tar.gz ; \
    ## remove unused things
    rm -rf tests ; \
    ## replace with local changes
    tar -C /app/sentry -cf - . | tar -xf - ; \
    ## apply patch
    patch -p1 < /app/sentry-build.patch ; \
    ## save tarball
    tar -cf - . | gzip -9 > /app/sentry.tar.gz ; \
    ls -l /run/artifacts/sentry-${SENTRY_GITREF}.tar.gz /app/sentry.tar.gz ; \
    cd / ; \
    cleanup

## ---

FROM ${IMAGE_PATH}/${HELPER_IMAGE} as snuba-prepare
SHELL [ "/bin/sh", "-ec" ]

ARG SNUBA_GITREF

COPY /snuba/               /app/snuba/
COPY /patches/snuba.patch  /app/

## repack snuba tarball
RUN mkdir /tmp/snuba ; \
    cd /tmp/snuba ; \
    tar --strip-components=1 -xf /run/artifacts/snuba-${SNUBA_GITREF}.tar.gz ; \
    ## remove unused things
    rm -rf docs tests ; \
    ## replace with local changes
    tar -C /app/snuba -cf - . | tar -xf - ; \
    ## apply patch
    patch -p1 < /app/snuba.patch ; \
    ## save tarball
    tar -cf - . | gzip -9 > /app/snuba.tar.gz ; \
    ls -l /run/artifacts/snuba-${SNUBA_GITREF}.tar.gz /app/snuba.tar.gz ; \
    cd / ; \
    cleanup

## ---

FROM ${IMAGE_PATH}/${HELPER_IMAGE} as uwsgi-prepare
SHELL [ "/bin/sh", "-ec" ]

ARG UWSGI_GITREF

COPY /patches/uwsgi/  /app/uwsgi/

## repack uwsgi tarball
RUN mkdir /tmp/uwsgi ; \
    cd /tmp/uwsgi ; \
    tar --strip-components=1 -xf /run/artifacts/uwsgi-${UWSGI_GITREF}.tar.gz ; \
    ## apply patches
    find /app/uwsgi/ -name '*.patch' -type f | sort -V | \
    while read -r pfile ; do \
        [ -n "${pfile}" ] || continue ; \
        echo "# applying ${pfile}" ; \
        patch -p1 < "${pfile}" ; \
    done ; \
    ## save tarball
    tar -cf - . | gzip -9 > /app/uwsgi.tar.gz ; \
    ls -l /run/artifacts/uwsgi-${UWSGI_GITREF}.tar.gz /app/uwsgi.tar.gz ; \
    cd / ; \
    cleanup

## ---

FROM ${IMAGE_PATH}/${HELPER_IMAGE} as sentry-arroyo-prepare
SHELL [ "/bin/sh", "-ec" ]

ARG SENTRY_ARROYO_GITREF

WORKDIR /app

## repack sentry-arroyo tarball
RUN mkdir /tmp/sentry-arroyo ; \
    cd /tmp/sentry-arroyo ; \
    tar --strip-components=1 -xf /run/artifacts/sentry-arroyo-${SENTRY_ARROYO_GITREF}.tar.gz ; \
    ## remove unused things
    rm -rf docs tests ; \
    ## monkey patch requirements.txt
    sed -Ei 's/^(confluent-kafka)([=><].*|)$/\1==2.2.0/' requirements.txt ; \
    ## save tarball
    tar -cf - . | gzip -9 > /app/sentry-arroyo.tar.gz ; \
    ls -l /run/artifacts/sentry-arroyo-${SENTRY_ARROYO_GITREF}.tar.gz /app/sentry-arroyo.tar.gz ; \
    cd / ; \
    cleanup

## ---

FROM ${IMAGE_PATH}/${HELPER_IMAGE} as xmlsec-prepare
SHELL [ "/bin/sh", "-ec" ]

ARG PYTHON_XMLSEC_GITREF

COPY /patches/python-xmlsec.patch  /app/

## repack python-xmlsec tarball
RUN mkdir /tmp/python-xmlsec ; \
    cd /tmp/python-xmlsec ; \
    tar --strip-components=1 -xf /run/artifacts/python-xmlsec-${PYTHON_XMLSEC_GITREF}.tar.gz ; \
    ## apply patch
    patch -p1 < /app/python-xmlsec.patch ; \
    ## save tarball
    tar -cf - . | gzip -9 > /app/python-xmlsec.tar.gz ; \
    ls -l /run/artifacts/python-xmlsec-${PYTHON_XMLSEC_GITREF}.tar.gz /app/python-xmlsec.tar.gz ; \
    cd / ; \
    cleanup

## ---

FROM ${IMAGE_PATH}/${STAGE_IMAGE} as builder

ENV DEB_BUILD_OPTIONS='hardening=+all,-pie,-stackprotectorstrong optimize=-lto' \
    _CFLAGS_STRIP='-g -O2' \
    _CFLAGS_PREPEND='-g -O3 -fPIC -flto=2 -fuse-linker-plugin -ffat-lto-objects -flto-partition=none'

ENV DEB_CFLAGS_STRIP="${_CFLAGS_STRIP}" \
    DEB_CXXFLAGS_STRIP="${_CFLAGS_STRIP}" \
    DEB_CFLAGS_PREPEND="${_CFLAGS_PREPEND}" \
    DEB_CFLAGS_PREPEND="${_CFLAGS_PREPEND}"

# hack the python!

RUN grep -ZFRl -e fstack-protector-strong $(python-config --prefix)/ \
    | xargs -0r sed -i -e 's/fstack-protector-strong/fstack-protector/g'

RUN grep -ZFRl -e fno-lto $(python-config --prefix)/ \
    | xargs -0r sed -Ei -e 's/\s*-fno-lto\s*//g'

RUN cd / ; \
    apt-wrap 'gcc dpkg-dev' \
      sh -ec 'dpkg-buildflags --export=sh > /opt/flags' ; \
    . /opt/flags ; \
    for f in ${CFLAGS} ; do \
        case "$f" in \
        -specs=* ) \
            _CFLAGS_PREPEND="${_CFLAGS_PREPEND} $f" ; \
        ;; \
        esac ; \
    done ; \
    grep -ZFRl -e ' -O2 ' $(python-config --prefix)/ \
    | xargs -0r sed -i -e "s#-g -O2 #${_CFLAGS_PREPEND} #g"

## finish layer
RUN cleanup ; \
    ## smoke/qa
    python-config --cflags

## ---

FROM ${BUILDER_INTERIM_IMAGE} as uwsgi
SHELL [ "/bin/sh", "-ec" ]

ENV UWSGI_PROFILE_OVERRIDE='malloc_implementation=jemalloc;pcre=true;ssl=false;xml=false'
ENV UWSGI_BUILD_DEPS='libjemalloc-dev libpcre2-dev'

COPY --from=uwsgi-prepare  /app/uwsgi.tar.gz  /app/

WORKDIR /app

RUN apt-list-installed > apt.deps.0

## build uwsgi
RUN export APPEND_CFLAGS="$( . /opt/flags ; printf '%s' "${CFLAGS}" )" ; \
    apt-wrap-python -d "${UWSGI_BUILD_DEPS}" \
      -p "/usr/local:${SITE_PACKAGES}" \
        pip -v install /app/uwsgi.tar.gz ; \
    rm /app/uwsgi.tar.gz ; \
    LD_PRELOAD= ldd /usr/local/bin/uwsgi

RUN apt-list-installed > apt.deps.1 ; \
    set +e ; \
    grep -Fvx -f apt.deps.0 apt.deps.1 > apt.deps.uwsgi ; \
    rm -f apt.deps.0 apt.deps.1

ARG UWSGI_DOGSTATSD_GITREF

WORKDIR /app/uwsgi

## build uwsgi-dogstatsd
RUN mkdir /tmp/uwsgi-dogstatsd /tmp/uwsgi-dogstatsd.build ; \
    tar -C /tmp/uwsgi-dogstatsd --strip-components=1 -xf /run/artifacts/uwsgi-dogstatsd-${UWSGI_DOGSTATSD_GITREF}.tar.gz ; \
    env -C /tmp/uwsgi-dogstatsd.build \
    apt-wrap-python -d "${UWSGI_BUILD_DEPS}" \
      uwsgi --build-plugin /tmp/uwsgi-dogstatsd \
    ; \
    cp -t ${PWD} /tmp/uwsgi-dogstatsd.build/*.so ; \
    LD_PRELOAD= ldd ./*.so ; \
    uwsgi --need-plugin=./dogstatsd --help > /dev/null

## finish layer
RUN quiet apt-install binutils ; \
    ufind -z /app /usr/local "${SITE_PACKAGES}" | xvp is-elf -z - | sort -zV > /tmp/elves ; \
    xvp ls -lrS /tmp/elves ; \
    xvp strip --strip-debug /tmp/elves ; echo ; \
    xvp ls -lrS /tmp/elves ; \
    cleanup

## ---

FROM ${BUILDER_INTERIM_IMAGE} as librdkafka
SHELL [ "/bin/sh", "-ec" ]

ENV BUILD_DEPS='libcurl4-openssl-dev libffi-dev liblz4-dev libsasl2-dev libssl-dev libzstd-dev zlib1g-dev'

ARG LIBRDKAFKA_GITREF

WORKDIR /app

RUN apt-list-installed > apt.deps.0

## build local librdkafka (*crazy*)
RUN mkdir /tmp/librdkafka ; \
    cd /tmp/librdkafka ; \
    apt-wrap 'gcc dpkg-dev' \
      sh -ec 'dpkg-buildflags --export=sh > /tmp/librdkafka.buildenv' ; \
    . /tmp/librdkafka.buildenv ; \
    export CPPFLAGS="${CPPFLAGS} -Wno-free-nonheap-object" ; \
    export LDFLAGS="${LDFLAGS} -Wno-free-nonheap-object" ; \
    tar --strip-components=1 -xf /run/artifacts/librdkafka-${LIBRDKAFKA_GITREF}.tar.gz ; \
    apt-wrap-sodeps -p /usr/local "build-essential ${BUILD_DEPS}" \
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
    rm -rf /usr/local/share/doc /usr/local/lib/librdkafka*.a

COPY --from=sentry-arroyo-prepare  /app/sentry-arroyo.tar.gz  /app/

## install sentry-arroyo
RUN apt-wrap-python -d "${BUILD_DEPS}" \
      pip -v install --no-binary 'confluent-kafka' /app/sentry-arroyo.tar.gz ; \
    rm /app/sentry-arroyo.tar.gz

RUN apt-list-installed > apt.deps.1 ; \
    set +e ; \
    grep -Fvx -f apt.deps.0 apt.deps.1 > apt.deps.librdkafka ; \
    rm -f apt.deps.0 apt.deps.1

## finish layer
RUN quiet apt-install binutils ; \
    ufind -z /usr/local ${SITE_PACKAGES} | xvp is-elf -z - | sort -zV > /tmp/elves ; \
    xvp ls -lrS /tmp/elves ; \
    xvp strip --strip-debug /tmp/elves ; echo ; \
    xvp ls -lrS /tmp/elves ; \
    cleanup

## ---

FROM ${BUILDER_INTERIM_IMAGE} as sentry-deps
SHELL [ "/bin/sh", "-ec" ]

ENV BUILD_DEPS='libbrotli-dev libcurl4-openssl-dev libffi-dev libkrb5-dev liblz4-dev libmaxminddb-dev libpq-dev libsasl2-dev libssl-dev libxmlsec1-dev libxslt1-dev libyaml-dev libzstd-dev rapidjson-dev zlib1g-dev'
ENV BUILD_FROM_SRC='cffi,brotli,google-crc32c,grpcio,hiredis,lxml,maxminddb,mmh3,msgpack,psycopg2,python-rapidjson,pyyaml,regex,simplejson,zstandard'

ARG UWSGI_INTERIM_IMAGE
ARG LIBRDKAFKA_INTERIM_IMAGE

## copy uwsgi and dependencies
COPY --from=${UWSGI_INTERIM_IMAGE}  /app/              /app/
COPY --from=${UWSGI_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${UWSGI_INTERIM_IMAGE}  /usr/local/        /usr/local/

## copy sentry-arroyo and librdkafka
COPY --from=${LIBRDKAFKA_INTERIM_IMAGE}  /app/              /app/
COPY --from=${LIBRDKAFKA_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${LIBRDKAFKA_INTERIM_IMAGE}  /usr/local/        /usr/local/

COPY --from=xmlsec-prepare    /app/python-xmlsec.tar.gz  /app/

COPY /sentry/  /tmp/sentry/

WORKDIR /app

RUN cat apt.deps.uwsgi apt.deps.librdkafka \
    | sort -uV | xargs -r apt-install ; \
    ldconfig ; \
    apt-list-installed > apt.deps.0

## install python-xmlsec
RUN apt-wrap-python -d "${BUILD_DEPS}" \
      pip -v install --no-binary "${BUILD_FROM_SRC}" ./python-xmlsec.tar.gz ; \
    rm python-xmlsec.tar.gz

RUN apt-wrap-python -d "${BUILD_DEPS}" \
      pip -v install --no-binary "${BUILD_FROM_SRC}" -r /tmp/sentry/requirements-base.txt ; \
    cleanup ; \
    # monkey patch python-memcached
    sed -i \
      -e "s/if key is ''/if key == ''/" \
      -e "s/if key_extra_len is 0/if key_extra_len == 0/" \
    ${SITE_PACKAGES}/memcache.py ; \
    # recompile python cache
    python -m compileall -q ${SITE_PACKAGES} ; \
    # smoke/qa
    python -c 'import maxminddb.extension; maxminddb.extension.Reader'

RUN apt-list-installed > apt.deps.1 ; \
    cat apt.deps.uwsgi apt.deps.librdkafka | sort -uV > apt.deps ; \
    set +e ; \
    grep -Fvx -f apt.deps.0 apt.deps.1 >> apt.deps ; \
    rm -f apt.deps.0 apt.deps.1

## finish layer
RUN quiet apt-install binutils ; \
    ufind -z /usr/local ${SITE_PACKAGES} | xvp is-elf -z - | sort -zV > /tmp/elves ; \
    xvp ls -lrS /tmp/elves ; \
    xvp strip --strip-debug /tmp/elves ; echo ; \
    xvp ls -lrS /tmp/elves ; \
    cleanup

## ---

FROM ${IMAGE_PATH}/${STAGE_IMAGE} as sentry-aldente
SHELL [ "/bin/sh", "-ec" ]

ARG SENTRY_DEPS_INTERIM_IMAGE
ARG SENTRY_RELEASE

ENV SENTRY_BUILD=krd.1
ENV SENTRY_WHEEL="sentry-${SENTRY_RELEASE}-py311-none-any.whl"

## copy uwsgi and dependencies
COPY --from=${SENTRY_DEPS_INTERIM_IMAGE}  /app/              /app/
COPY --from=${SENTRY_DEPS_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${SENTRY_DEPS_INTERIM_IMAGE}  /usr/local/        /usr/local/

COPY --from=sentry-prepare  /app/sentry.tar.gz  /app/

COPY /patches/sentry.patch  /app/
COPY /patches/django.patch  /app/

WORKDIR /app

## install sentry as wheel
RUN xargs -r -a apt.deps apt-install ; \
    ldconfig ; \
    tar -xf sentry.tar.gz ; \
    if ! [ -s "/run/artifacts/${SENTRY_WHEEL}" ] ; then \
        mkdir -p /tmp/sentry-build ; \
        cd /tmp/sentry-build ; \
        tar -xf /app/sentry.tar.gz ; \
        apt-wrap 'yarnpkg' \
          sh -ec '\
            command -V yarn >/dev/null || which yarnpkg | while read -r n ; do ln -sv $n ${n%/*}/yarn ; done ; \
            python setup.py bdist_wheel' ; \
        find dist/ -name '*.whl' -type f -exec cp -nvt /run/artifacts {} + ; \
        cd /app ; \
        cleanup ; \
        ## cleanup after yarn
        rm -rf /usr/local/share/.cache ; \
    fi ; \
    rm sentry.tar.gz ; \
    rm apt.deps.* || : ; \
    ## hack wheel
    quiet apt-install patch ; \
    cd /tmp ; \
    wheel unpack /run/artifacts/${SENTRY_WHEEL} ; \
    cd sentry-${SENTRY_RELEASE} ; \
    patch -p2 < /app/sentry.patch ; \
    rm /app/sentry.patch ; \
    cd /tmp ; \
    wheel pack sentry-${SENTRY_RELEASE} ; \
    ## install new wheel
    pip -v install --no-deps "${SENTRY_WHEEL}" ; \
    cd /app ; \
    cleanup ; \
    ## hack django
    cd ${SITE_PACKAGES} ; \
    patch -p1 < /app/django.patch ; \
    rm /app/django.patch ; \
    cd /app ; \
    # recompile python cache
    python -m compileall -q ${SITE_PACKAGES} ; \
    ## smoke/qa
    set -xv ; \
    sentry --version

## ---

FROM ${BUILDER_INTERIM_IMAGE} as snuba-deps
SHELL [ "/bin/sh", "-ec" ]

ENV BUILD_DEPS='libcurl4-openssl-dev libffi-dev liblz4-dev libpcre3-dev libsasl2-dev libssl-dev libyaml-dev libzstd-dev rapidjson-dev zlib1g-dev'
ENV BUILD_FROM_SRC='cffi,charset-normalizer,clickhouse-driver,lz4,markupsafe,python-rapidjson,pyyaml,regex,simplejson'

ARG UWSGI_INTERIM_IMAGE
ARG LIBRDKAFKA_INTERIM_IMAGE

## copy uwsgi and dependencies
COPY --from=${UWSGI_INTERIM_IMAGE}  /app/              /app/
COPY --from=${UWSGI_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${UWSGI_INTERIM_IMAGE}  /usr/local/        /usr/local/

## copy sentry-arroyo and librdkafka
COPY --from=${LIBRDKAFKA_INTERIM_IMAGE}  /app/              /app/
COPY --from=${LIBRDKAFKA_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${LIBRDKAFKA_INTERIM_IMAGE}  /usr/local/        /usr/local/

COPY /snuba/  /tmp/snuba/

WORKDIR /app

RUN cat apt.deps.uwsgi apt.deps.librdkafka \
    | sort -uV | xargs -r apt-install ; \
    ldconfig ; \
    apt-list-installed > apt.deps.0

RUN apt-wrap-python -d "${BUILD_DEPS}" \
      pip -v install --no-binary "${BUILD_FROM_SRC}" -r /tmp/snuba/requirements.txt ; \
    cleanup

RUN apt-list-installed > apt.deps.1 ; \
    cat apt.deps.uwsgi apt.deps.librdkafka | sort -uV > apt.deps ; \
    set +e ; \
    grep -Fvx -f apt.deps.0 apt.deps.1 >> apt.deps ; \
    rm -f apt.deps.0 apt.deps.1

## finish layer
RUN quiet apt-install binutils ; \
    ufind -z /usr/local ${SITE_PACKAGES} | xvp is-elf -z - | sort -zV > /tmp/elves ; \
    xvp ls -lrS /tmp/elves ; \
    xvp strip --strip-debug /tmp/elves ; echo ; \
    xvp ls -lrS /tmp/elves ; \
    cleanup

## ---

FROM ${IMAGE_PATH}/${STAGE_IMAGE} as snuba-aldente
SHELL [ "/bin/sh", "-ec" ]

ARG SNUBA_DEPS_INTERIM_IMAGE

## copy uwsgi and dependencies
COPY --from=${SNUBA_DEPS_INTERIM_IMAGE}  /app/              /app/
COPY --from=${SNUBA_DEPS_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${SNUBA_DEPS_INTERIM_IMAGE}  /usr/local/        /usr/local/

COPY --from=snuba-prepare  /app/snuba.tar.gz  /app/

WORKDIR /app

## install snuba "in-place"
RUN xargs -r -a apt.deps apt-install ; \
    ldconfig ; \
    tar -xf snuba.tar.gz ; \
    rm snuba.tar.gz ; \
    rm apt.deps.* || : ; \
    pip -v install --no-deps -e . ; \
    cleanup ; \
    python -m compileall -q . ; \
    ## adjust permissions
    chmod -R go-w /app ; \
    ## smoke/qa
    set -xv ; \
    snuba --version

## ---

FROM ${IMAGE_PATH}/${BASE_IMAGE} as sentry
SHELL [ "/bin/sh", "-ec" ]

WORKDIR /app

## prepare user
RUN add-simple-user sentry 30000 /app/sentry

## copy sentry and dependencies
COPY --from=sentry-aldente  /app/              /app/
COPY --from=sentry-aldente  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=sentry-aldente  /usr/local/        /usr/local/

RUN xargs -r -a /app/apt.deps apt-install ; \
    ldconfig ; \
    install -d -m 01777 /data ; \
    cleanup

VOLUME /data

ARG SENTRY_RELEASE
ENV SENTRY_RELEASE="${SENTRY_RELEASE}" \
    SENTRY_CONF=/etc/sentry \
    GRPC_POLL_STRATEGY=epoll1 \
    UWSGI_NEED_PLUGIN=/app/uwsgi/dogstatsd

RUN mkdir -p ${SENTRY_CONF} ; \
    cp -t ${SENTRY_CONF} /app/docker/sentry.conf.py /app/docker/config.yml

EXPOSE 9000

CMD [ "sentry", "run", "web" ]

## switch user
USER sentry

## ---

FROM ${IMAGE_PATH}/${BASE_IMAGE} as snuba
SHELL [ "/bin/sh", "-ec" ]

WORKDIR /app

## prepare user
RUN add-simple-user snuba 30000 /app/snuba

## copy snuba and dependencies
COPY --from=snuba-aldente  /app/              /app/
COPY --from=snuba-aldente  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=snuba-aldente  /usr/local/        /usr/local/

RUN xargs -r -a /app/apt.deps apt-install ; \
    ldconfig ; \
    cleanup

ARG SENTRY_RELEASE
ENV SNUBA_RELEASE="${SENTRY_RELEASE}" \
    FLASK_DEBUG=0 \
    UWSGI_ENABLE_METRICS=true \
    UWSGI_NEED_PLUGIN=/app/uwsgi/dogstatsd \
    UWSGI_STATS_PUSH=dogstatsd:127.0.0.1:8126 \
    UWSGI_DOGSTATSD_EXTRA_TAGS=service:snuba

CMD [ "snuba", "api" ]

## switch user
USER snuba
