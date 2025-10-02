# syntax=docker/dockerfile:1.3-labs
ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION:-3.22}
ARG MYSQL_VERSION
ARG BOOST_VERSION
ENV MYSQL_VERSION ${MYSQL_VERSION:-8.0.43}
ENV BOOST_VERSION ${BOOST_VERSION:-1.77.0}
ENV GPG_KEY "859BE8D7C586F538430B19C2467B942D3A79BD29"
RUN apk add --no-cache --virtual .build-deps \
        pigz \
        git patch sed \
        gnupg \
        curl \
        linux-headers \
        libc-dev gcompat libc6-compat \
        gcc g++ bison \
        make cmake \
        libaio-dev \
        openssl-dev \
        libtirpc-dev rpcgen \
        libnsl ncurses-dev \
        perl perl-dev perl-app-cpanminus perl-devel-checklib perl-dbi

#curl -fSL "https://downloads.mysql.com/archives/get/p/23/file/mysql-${MYSQL_VERSION}.tar.gz" -o mysql.tar.gz && \
#curl -fSL "https://downloads.mysql.com/archives/gpg/?file=${MYSQL_VERSION}.tar.gz&p=23" -o mysql.tar.gz.asc && \
#gpg --verify mysql.tar.gz.asc mysql.tar.gz && \

RUN mkdir -p /usr/src/boost && \
    echo "Downloading boost v${BOOST_VERSION}..." && \
    wget --progress=bar:force:noscroll --show-progress -qO- "https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION//./_}.tar.bz2" | tar --strip-components 1 -xjC /usr/src/boost && \
    gpg --recv-keys "$GPG_KEY"
RUN MYSQL_MAJOR=$(echo "${MYSQL_VERSION}"|sed 's/\.[^.]*$//') && \
    echo "Downloading MySQL ${MYSQL_MAJOR} (${MYSQL_VERSION}) source..." && \
    (curl -fSL "https://cdn.mysql.com/Downloads/MySQL-${MYSQL_MAJOR}/mysql-${MYSQL_VERSION}.tar.gz" -o mysql.tar.gz || curl -fSL "https://cdn.mysql.com/archives/mysql-${MYSQL_MAJOR}/mysql-${MYSQL_VERSION}.tar.gz" -o mysql.tar.gz) && \
    mkdir -p /usr/src/mysql && \
    echo "Extracting source..." && \
    pigz -dc mysql.tar.gz|tar  --strip-components 1 -xC /usr/src/mysql -f - && \
    rm mysql.tar.gz

COPY patch /patch

#-DWITHSSL=openssl11/openssl3/system/yes
RUN --mount=type=cache,target=/usr/src/mysql/build,sharing=locked \
    cd /usr/src/mysql && \
    #(patch -p1 < /patch/libmysql-musl.patch; patch -p0 < /patch/icu68.patch; true) && \
    (patch -p1 < /patch/openssl3.patch; patch -p1 < /patch/8.4-bulk_data_service.patch; true) && \
    mkdir -p build && cd build && \
    _CFLAGS="-DSIGEV_THREAD_ID=4" \
    cmake .. -DBUILD_CONFIG=mysql_release -DCMAKE_BUILD_TYPE=Release -DWITH_BOOST=/usr/src/boost -DDOWNLOAD_BOOST=OFF -DENABLE_DOWNLOADS=ON \
    -DCOMPILATION_COMMENT_SERVER="MySQL8 for Alpine Linux by GT" \
    -DDEFAULT_THREAD_STACK=262144 \
    -DWITH_SYSTEM_LIBS=OFF \
    -DWITH_SSL=system \
    -DDISABLE_SHARED=OFF \
    -DWITH_BUILD_ID=OFF \
    -DENABLED_PROFILING=ON \
    -DWITH_LTO=ON \
    -DWITH_ROUTER=OFF \
    -DWITH_NDB=OFF \
    -DWITH_MYSQLX=ON \
    -DWITH_FIDO=none \
    -DWITH_LIBWRAP=OFF \
    -DWITH_FEDERATED_STORAGE_ENGINE=ON \
    -DWITH_INNODB_MEMCACHED=ON \
    -DWITHOUT_EXAMPLE_STORAGE_ENGINE=ON \
    -DWITH_UNIT_TESTS=OFF \
    -DENABLED_LOCAL_INFILE=ON \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DSYSCONFDIR=/etc \
    -DMYSQL_DATADIR=/var/lib/mysql \
    -DMYSQL_UNIX_ADDR=/var/run/mysqld/mysqld.sock \
    -DCMAKE_C_FLAGS="${CFLAGS}" \
    -DCMAKE_C_LINK_FLAGS="${LDFLAGS}" \
    -DCMAKE_CXX_FLAGS="${CXXFLAGS} -DU_DEFINE_FALSE_AND_TRUE=1" \
    -DCMAKE_CXX_LINK_FLAGS="${LDFLAGS}" && \
    make -j$(getconf _NPROCESSORS_ONLN) && \
    make install && \
    echo "!includedir /etc/my.cnf.d" >> /etc/my.cnf
RUN --mount=type=cache,target=/usr/src/mysql/build,sharing=locked \
    cp /usr/src/mysql/build/scripts/mysqlclient.pc /usr/lib/pkgconfig/mysqlclient.pc

FROM alpine:${ALPINE_VERSION:-3.18}
MAINTAINER "Tamás Gere <gt@kani.hu>"
LABEL description="MySQL8 for Alpine Linux by GT"
LABEL org.opencontainers.image.authors="Tamás Gere <gt@kani.hu>"

COPY entrypoint.sh /usr/local/bin
RUN apk add --no-cache bash libstdc++ gcompat gzip openssl libaio libgcc ncurses-libs shadow tzdata xz && \
    useradd -m -r -d /var/lib/mysql -s /bin/false mysql && \
    mkdir -p /run/mysqld /etc/my.cnf.d && chown mysql:mysql /run/mysqld && \
    chmod a+x /usr/local/bin/entrypoint.sh
COPY --from=0 /etc/my.cnf /etc/my.cnf
COPY --from=0 /usr/local/bin /usr/local/bin
COPY --from=0 /usr/local/lib /usr/local/lib
#COPY --from=0 /usr/local/man /usr/local/man
#COPY --from=0 /usr/local/docs /usr/local/docs
COPY --from=0 /usr/local/share /usr/local/share
COPY --from=0 /usr/local/include /usr/local/include
COPY --from=0 /usr/local/support-files/mysql-log-rotate /etc/logrotate.d/
COPY --from=0 /usr/local/support-files/mysql.server /usr/local/support-files/mysqld_multi.server /usr/local/bin/
COPY --from=0 /usr/lib/pkgconfig/mysqlclient.pc /usr/lib/pkgconfig/mysqlclient.pc

EXPOSE 3306 33060
ENTRYPOINT ["entrypoint.sh"]
CMD ["mysqld", "--bind-address=0.0.0.0"]
#VOLUME /var/lib/mysql

