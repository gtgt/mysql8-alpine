FROM alpine:3.15
ENV MYSQL_MAJOR 8.0
ENV MYSQL_VERSION 8.0.22
ENV BOOST_VERSION 1.73.0
ENV GPG_KEY "859BE8D7C586F538430B19C2467B942D3A79BD29"
RUN apk add --no-cache --virtual .build-deps \
        pigz \
        git \
        cmake \
        curl \
        g++ \
        gcc \
        bison \
        gnupg \
        libaio-dev \
        libc-dev \
        libedit-dev \
        openssl-dev \
        libtirpc-dev \
        zstd-dev \
        libevent-dev \
        lz4-dev \
        icu-dev \
        protobuf-dev \
        linux-headers \
        rpcsvc-proto \
        make \
        patch \
        perl && \
    mkdir -p /usr/src/boost && \
    echo "Downloading boost v${BOOST_VERSION}..." && \
    wget -qO- "https://boostorg.jfrog.io/artifactory/main/release/${BOOST_VERSION}/source/boost_1_73_0.tar.bz2" | tar --strip-components 1 -xjC /usr/src/boost && \
    gpg --recv-keys "$GPG_KEY" && \
    curl -fSL "https://downloads.mysql.com/archives/get/p/23/file/mysql-${MYSQL_VERSION}.tar.gz" -o mysql.tar.gz && \
    curl -fSL "https://downloads.mysql.com/archives/gpg/?file=${MYSQL_VERSION}.tar.gz&p=23" -o mysql.tar.gz.asc && \
    #gpg --verify mysql.tar.gz.asc mysql.tar.gz && \
    mkdir -p /usr/src/mysql && \
    echo "Extracting source..." && \
    pigz -dc mysql.tar.gz|tar  --strip-components 1 -xC /usr/src/mysql -f -

COPY patch /patch
RUN cd /usr/src/mysql && \
    patch -p1 < /patch/libmysql-musl.patch && patch -p0 < /patch/icu68.patch && \
    mkdir build && cd build && \
    _CFLAGS="-DSIGEV_THREAD_ID=4" \
    cmake .. -DBUILD_CONFIG=mysql_release -DCMAKE_BUILD_TYPE=Release -DWITH_BOOST=/usr/src/boost \
    -DENABLED_LOCAL_INFILE=ON \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DSYSCONFDIR=/etc/mysql \
    -DMYSQL_DATADIR=/var/lib/mysql \
    -DMYSQL_UNIX_ADDR=/var/run/mysqld/mysqld.sock \
    -DWITH_LIBWRAP=OFF \
    -DWITH_LTO=ON \
    -DWITH_UNIT_TESTS=OFF \
    -DPLUGIN_FEEDBACK=NO \
    -DPLUGIN_EXAMPLE=NO \
    -DWITHOUT_EXAMPLE_STORAGE_ENGINE=ON \
    -DWITH_ROUTER=OFF \
    -DWITH_SYSTEM_LIBS=ON \
    -DPLUGIN_FEDERATED=ON \
    -DWITH_FEDERATED_STORAGE_ENGINE=ON \
    -DCMAKE_C_FLAGS="${CFLAGS}" \
    -DCMAKE_C_LINK_FLAGS="${LDFLAGS}" \
    -DCMAKE_CXX_FLAGS="${CXXFLAGS} -DU_DEFINE_FALSE_AND_TRUE=1" \
    -DCMAKE_CXX_LINK_FLAGS="${LDFLAGS}" && \
    make -j$(getconf _NPROCESSORS_ONLN) && \
    make install

FROM alpine:3.15
COPY entrypoint.sh /usr/local/bin
RUN apk add --no-cache libstdc++6 openssl libcrypto1.1 zstd-libs libaio icu-libs icu-data libgcc libprotobuf-lite libevent lz4-libs libedit shadow xz && \
    useradd -m -r -d /var/lib/mysql -s /bin/false mysql && \
    mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld && \
    chmod a+x /usr/local/bin/entrypoint.sh
COPY --from=0 /usr/local/bin /usr/local/bin
COPY --from=0 /usr/local/lib /usr/local/lib
COPY --from=0 /usr/local/share /usr/local/share
COPY --from=0 /usr/local/support-files/mysql-log-rotate /etc/logrotate.d/
COPY --from=0 /usr/local/support-files/mysql.server /usr/local/support-files/mysqld_multi.server /usr/local/bin/
COPY --from=0 /usr/src/mysql/build/scripts/mysqlclient.pc /usr/lib/pkgconfig/mysqlclient.pc

EXPOSE 3306 33060
ENTRYPOINT ["entrypoint.sh"]
CMD "--user=mysql --bind-address=0.0.0.0 --console"
