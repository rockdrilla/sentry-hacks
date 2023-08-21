ARG IMAGE_PATH=docker.io/rockdrilla
ARG DISTRO
ARG SUITE
ARG PYTHON_VERSION

ARG UWSGI_INTERIM_IMAGE
ARG HELPER_IMAGE=${DISTRO}-buildd:${SUITE}
ARG STAGE_IMAGE=python-dev:${PYTHON_VERSION}-${SUITE}
ARG BASE_IMAGE=python-min:${PYTHON_VERSION}-${SUITE}

## ---

FROM ${IMAGE_PATH}/${HELPER_IMAGE} as sentry-prepare
SHELL [ "/bin/sh", "-ec" ]

ARG SENTRY_GITREF

COPY /sentry/               /app/sentry/
COPY /patches/sentry.patch  /app/

## repack sentry tarball
RUN mkdir /tmp/sentry ; \
    cd /tmp/sentry ; \
    tar --strip-components=1 -xf /run/artifacts/sentry-${SENTRY_GITREF}.tar.gz ; \
    ## remove unused things
    rm -rf tests ; \
    ## replace with local changes
    tar -C /app/sentry -cf - . | tar -xf - ; \
    ## apply patch
    patch -p1 < /app/sentry.patch ; \
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

FROM ${IMAGE_PATH}/${STAGE_IMAGE} as uwsgi
SHELL [ "/bin/sh", "-ec" ]

ENV UWSGI_PROFILE_OVERRIDE='malloc_implementation=jemalloc;pcre=true;ssl=false;xml=false'
ENV UWSGI_BUILD_DEPS='libjemalloc-dev libpcre2-dev'
ENV APPEND_CFLAGS='-g -O3 -flto=1 -fuse-linker-plugin -ffat-lto-objects -flto-partition=none'

COPY --from=uwsgi-prepare  /app/uwsgi.tar.gz  /app/

WORKDIR /app/uwsgi

RUN apt-list-installed > apt.deps.0

## build uwsgi
RUN apt-wrap-python -d "${UWSGI_BUILD_DEPS}" \
      -p "/usr/local:${SITE_PACKAGES}" \
        pip -v install /app/uwsgi.tar.gz ; \
    rm /app/uwsgi.tar.gz ; \
    LD_PRELOAD= ldd /usr/local/bin/uwsgi

RUN apt-list-installed > apt.deps.1 ; \
    set +e ; \
    grep -Fvx -f apt.deps.0 apt.deps.1 > apt.deps ; \
    rm -f apt.deps.0 apt.deps.1

ARG UWSGI_DOGSTATSD_GITREF

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

FROM ${IMAGE_PATH}/${STAGE_IMAGE} as sentry-aldente
SHELL [ "/bin/sh", "-ec" ]

ENV SENTRY_LIGHT_BUILD=1
ENV SENTRY_BUILD_DEPS='libffi-dev libjpeg-dev libmaxminddb-dev libpq-dev libxmlsec1-dev libxmlsec1-dev libxslt-dev libyaml-dev'

ARG UWSGI_INTERIM_IMAGE

## copy uwsgi and dependencies
COPY --from=${UWSGI_INTERIM_IMAGE}  /app/uwsgi/        /app/uwsgi/
COPY --from=${UWSGI_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${UWSGI_INTERIM_IMAGE}  /usr/local/        /usr/local/

COPY --from=sentry-prepare  /app/sentry.tar.gz  /app/

WORKDIR /app

RUN xargs -r -a /app/uwsgi/apt.deps apt-install ; \
    apt-list-installed > apt.deps.0

## install sentry "in-place"
RUN tar -xf /app/sentry.tar.gz ; \
    rm /app/sentry.tar.gz ; \
    apt-wrap-python -d "${SENTRY_BUILD_DEPS}" \
      pip install -e . ; \
    cleanup ; \
    python -m compileall -q . ; \
    ## adjust permissions
    chmod -R go-w /app ; \
    # smoke/qa
    set -xv ; \
    sentry --version ; \
    python -c 'import maxminddb.extension; maxminddb.extension.Reader'

RUN apt-list-installed > apt.deps.1 ; \
    cp /app/uwsgi/apt.deps ./ ; \
    set +e ; \
    grep -Fvx -f apt.deps.0 apt.deps.1 >> apt.deps ; \
    rm -f apt.deps.0 apt.deps.1

## ---

FROM ${IMAGE_PATH}/${STAGE_IMAGE} as snuba-aldente
SHELL [ "/bin/sh", "-ec" ]

ARG UWSGI_INTERIM_IMAGE

## copy uwsgi and dependencies
COPY --from=${UWSGI_INTERIM_IMAGE}  /app/uwsgi/        /app/uwsgi/
COPY --from=${UWSGI_INTERIM_IMAGE}  ${SITE_PACKAGES}/  ${SITE_PACKAGES}/
COPY --from=${UWSGI_INTERIM_IMAGE}  /usr/local/        /usr/local/

COPY --from=snuba-prepare  /app/snuba.tar.gz  /app/

WORKDIR /app

RUN xargs -r -a /app/uwsgi/apt.deps apt-install ; \
    apt-list-installed > apt.deps.0

## install snuba "in-place"
RUN tar -xf /app/snuba.tar.gz ; \
    rm /app/snuba.tar.gz ; \
    apt-wrap-python \
      pip install -e . ; \
    cleanup ; \
    python -m compileall -q . ; \
    ## adjust permissions
    chmod -R go-w /app ; \
    # smoke/qa
    set -xv ; \
    snuba --version

RUN apt-list-installed > apt.deps.1 ; \
    cp /app/uwsgi/apt.deps ./ ; \
    set +e ; \
    grep -Fvx -f apt.deps.0 apt.deps.1 >> apt.deps ; \
    rm -f apt.deps.0 apt.deps.1

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
