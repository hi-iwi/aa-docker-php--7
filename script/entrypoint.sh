#!/bin/bash
# MAINTAINER Aario <Aario@luexu.com>
set -e

. /aa_script/entrypointBase.sh

TIMEZONE=${TIMEZONE:-""}
HOST=${HOST:-"aa_php"}
LOG_TAG=${LOG_TAG:-"php_entrypoint[$$]"}

UPDATE_REPO=${UPDATE_REPO:-0}
GEN_SSL_CRT=${GEN_SSL_CRT:-""}

PHPUser=${PHPUser:-'php'}
PHPGroup=${PHPGroup:-'php'}
WWW_HTDOCS=${WWW_HTDOCS:-'/var/lib/htdocs'}
PHPLogDir=${PHPLogDir:-'/var/log/php'}
PHPPrefix=${PHPPrefix:-'/var/local/php'}

if [ -z "${PHPExtSrc}" ]; then
    for src in $(ls /usr/src); do
        if [ ${src:0:3} == 'php' -a -d "$src/ext" ]; then
            PHPExtSrc=$src
        fi
    done
fi

PHPExtsWithSSL=${PHPExtsWithSSL:-0}
PHPExtsWithHTTP2=${PHPExtsWithHTTP2:-0}
PHPExtDependencies=${PHPExtDependencies:-"${PHPExtSrc}/ext_dependencies"}
PHPCleanCompiledExtSrc=${PHPCleanCompiledExtSrc:-1}
# PHP_CONF_SCAN_DIR=${PHP_CONF_SCAN_DIR:-''}

cat "/aa_script/entrypointConst.sh"
aaLog() {
    AaLog --aalogheader_host "${HOST}" --aalogtag "${LOG_TAG}" "$@"
}


aaLog "Adjusting date... : $(date)"
AaAdjustTime "${TIMEZONE}"
aaLog "Adjusted date : $(date)"

aaLog "Doing yum update ..."
YumUpdate "${UPDATE_REPO}"

aaLog "Generating SSL Certificate..."
GenSslCrt "${GEN_SSL_CRT}"


php_ext_dir=$(php -i | grep "^extension_dir =>" | awk -F ' => ' '{print $2}')
php_conf_dir=$(echo $(php --ini | grep "Scan") | awk -F ': ' '{print $2}')

if [ ! -z "$php_conf_dir" ]; then
	default_php_conf=$php_conf_dir"/php.ini"
fi

# xdebug-2.4.0,xhprof-php7/extension

installZephir() {
    dependency="$1"
    # Install zephir
    aaLog ":  Installing $dependency"
    #remove all sudo in zephir shell scripts
    find "${PHPExtDependencies}/$dependency" -type f -print0 | xargs -0 sed -i 's/sudo //g'
    sed -i "s/\/usr\/local\/bin\/zephir/\/usr\/sbin\/zephir/g" "${PHPExtDependencies}/$dependency/install"
    # go inside to install zephir is required
    cd "${PHPExtDependencies}/$dependency"
    ./install -c
    chmod a+x /usr/sbin/zephir
    aaLog ":  Installed zephir"
}

enableExtCassandra() {
    yum install -y gmp gmp-devel libuv libuv-devel
    if [ -z "${CppDriverVer}" ]; then
        # https://github.com/datastax/cpp-driver/archive/2.5.0.tar.gz
        for cppDriver in $(ls "${PHPExtDependencies}" | grep ^cpp-driver); do
            if [ -f "${PHPExtDependencies}/${cppDriver}/cassconfig.hpp.in" ]; then
                CppDriverVer="${cppDriver}"
                break
            fi
        done
    fi
    mkdir -p "${PHPExtDependencies}/${CppDriverVer}/build"
    cd "${PHPExtDependencies}/${CppDriverVer}/build"
    cmake --INSTALL-DIR /usr/local/cassandra-cpp-driver --SHARED ..
    make && make install

    [ ! -f '/usr/lib64/libcassandra.so' ] && ln -s /usr/local/lib64/libcassandra.so /usr/lib64/libcassandra.so
    [ ! -f '/usr/lib64/libcassandra.so.2' ] && ln -s /usr/local/lib64/libcassandra.so.2 /usr/lib64/libcassandra.so.2
    [ ! -f '/usr/lib64/libcassandra.so.2.5.0' ] && ln -s /usr/local/lib64/libcassandra.so.2.5.0 /usr/lib64/libcassandra.so.2.5.0
}

enableExtRdkafka() {
    if [ -z "${LibRdkafkaVer}" ]; then
        for librdkafka in $(ls "${PHPExtDependencies}" | grep ^librdkafka); do
            if [ -f "${PHPExtDependencies}/${librdkafka}/Makefile" ]; then
                LibRdkafkaVer="${librdkafka}"
                break
            fi
        done
    fi
    if [ -z "${LibRdkafkaVer}" ]; then
        aaLog --aalogpri_severity EMERGENCY "librdkafka (version 0.11.3+) is not specified!!!"
    fi
    aaLog "Trying to install LibRdKafka: ${LibRdkafkaVer}"
    libKafka="${PHPExtDependencies}/${LibRdkafkaVer}"
    if [ ! -f "${libKafka}/Makefile" ]; then
        aaLog "LibRdKafka: ${LibRdkafkaVer} Not Exist! Downloading..."
        v=${LibRdkafkaVer/librdkafka-/}
        curl -sSL "https://github.com/edenhill/librdkafka/archive/v${v}.tar.gz" -o $libKafka'.tgz'
        cd ${PHPExtDependencies}
        tar -zxvf $libKafka'.tgz' -C "${libKafka}"
        rm -f "${libKafka}.tgz"
    fi
    cd "${libKafka}"
    ./configure
    make && make install
}

enableExtZookeeper() {
    # requires libzookeeper
    # libzookeeper is in  zookeeper/src/c/
    if [ -z "${LibZookeeperVer}" ]; then
        for libzookeeper in $(ls "${PHPExtDependencies}" | grep ^zookeeper); do
            if [ -f "${PHPExtDependencies}/${libzookeeper}/src/c/configure" ]; then
                LibZookeeperVer="${libzookeeper}"
                break
            fi
        done
    fi
    if [ -z "${LibZookeeperVer}" ]; then
        aaLog --aalogpri_severity EMERGENCY "zookeeper lib (version 3.4.11+) is not specified!!!"
    fi
    aaLog "Trying to install Zookeeper Lib: ${LibZookeeperVer}"

    libZookeeper="${PHPExtDependencies}/${LibZookeeperVer}"

    if [ ! -f "${libZookeeper}/src/c/configure" ]; then
        cd ${PHPExtSrc}
        curl -sSL "http://www-us.apache.org/dist/zookeeper/${LibZookeeperVer}/${LibZookeeperVer}.tar.gz"
        tar -zxvf "${LibZookeeperVer}.tar.gz"
        rm -f ${LibZookeeperVer}.tar.gz
    fi
    cd "${libZookeeper}/src/c"
    ./configure --prefix=/usr/local/zookeeper-c-cli
    make && make install
}
enableExtComposer() {
    cd ${PHPExtSrc}
    if [ ! -f "${PHPExtSrc}/composer-setup.php" ]; then
        aaLog "curl -sSL https://getcomposer.org/installer -o composer-setup.php"
        curl -sSL https://getcomposer.org/installer -o composer-setup.php
    fi

    aaLog $(sha384sum ./composer-setup.php)
    php composer-setup.php --install-dir=/usr/bin --filename=composer
    rm -f composer-setup.php
}
enableExtGd() {
    yum install -y gd freetype freetype-devel libjpeg libjpeg-devel libpng libpng-devel
}
enableExtXdebug() {
    enableExt=$1
    if [ ! -d "${PHPExtSrc}/${enableExt}" ]; then
        cd ${PHPExtSrc}
        if  curl -sSL "https://xdebug.org/files/${enableExt}.tgz" -o "${PHPExtSrc}/${enableExt}.tgz"; then
            tar -zxvf ${PHPExtSrc}"/"$enableExt".tgz"
            rm -f ${PHPExtSrc}"/"$enableExt".tgz"
        fi
    fi
}

enableExtXml() {
    yum install -y libxml2 libxml2-devel
}

enableExtPgsql() {
    yum install -y postgresql-devel
}

enableExtImagick() {
    yum install -y ImageMagick ImageMagick-devel
}

enableExtLua() {
    yum install -y lua-devel lua-static
    if [ ! -d "/usr/include/lua" ]; then
        mkdir /usr/include/lua
    fi
    ln -s /usr/include/lua.h /usr/include/lua/lua.h
}

enableExtZlib() {
    yum install -y zlib zlib-devel
}

enableExtRedis() {
    enableExt=$1
    if [ ! -d "${PHPExtSrc}/${enableExt}" ]; then
        cd ${PHPExtSrc}
        if  curl -sSL "http://pecl.php.net/get/$enableExt.tgz" -o "${PHPExtSrc}/${enableExt}.tgz"; then
            tar -zxvf "${PHPExtSrc}/${enableExt}.tgz"
            rm -f "${PHPExtSrc}/${enableExt}.tgz"
        fi
    fi
}

enableExtPhalcon() {
    # https://gist.github.com/michael34435/c682271492a03f0af686


    aaLog ": Installing phalcon dependencies..."

    if yum install -y re2c; then
        aaLog "re2c yum depository exists"
    else
        declare epel_rpm
        # ls "*.rpm"    --> "*.rpm" file only;
        # ls *.rpm      --> regexp, all .rpm files
        cd "${PHPExtDependencies}"
        for rpm_file in $(ls *.rpm); do
            case "${rpm_file:0:4}" in
                epel)
                    aaLog "local $rpm_file exits"
                    epel_rpm="${PHPExtDependencies}/$rpm_file"
                ;;
            esac

        done

        epel_rpm=${epel_rpm:-'http://download.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm'}
        aaLog ": rpm -Uvh $epel_rpm"
        rpm -Uvh "$epel_rpm"
        yum update -y
        yum install -y re2c
        aaLog ": rpm success"

    fi

    yum install -y make gcc file git

    declare zephir_ver
    declare cphalcon_ver

    cd "${PHPExtSrc}"
    for dependency in $(ls "_dependencies"); do
        if [ -d "${PHPExtDependencies}/$dependency" ]; then
            case "${dependency:0:4}" in
                #re2c)
                #    # Install re2c
                #    aaLog ":  Installing $dependency"
                #
                #    cd "${PHPExtDependencies}/$dependency"
                #
                #    if [ -d "${PHPExtDependencies}/$dependency/re2c/" ]; then
                #        cd "${PHPExtDependencies}/$dependency/re2c"
                #    fi
                #
                #    mkdir -p "/usr/local/re2c"
                #
                #    ./configure --prefix="/usr/local/re2c"
                #    make
                #    make install
                #    if [ -f "/usr/local/re2c/bin/re2c" ]; then
                #        aaLog "[Error] re2c installed failed"
                #        exit 1
                #    fi
                #    ln "/usr/local/re2c/bin/re2c" "/usr/sbin/re2c"
                #    chmod a+x "/usr/sbin/re2c"
                #    aaLog ":  Installed $dependency"
                #;;
                zeph)
                    # if [ -z $zephir_ver ] --> git clone
                    zephir_ver="$dependency"
                    installZephir "$zephir_ver"
                ;;
                cpha)
                    cphalcon_ver="$dependency"
                ;;
            esac
        fi
    done
    ## Install re2c ############################################################
    #if [ ! -d "${PHPExtDependencies}/re2c" ]; then

    #    aaLog " re2c source doesn't exist; git clone it from remote"

    #    cd "${PHPExtDependencies}"
    #    git clone https://github.com/skvadrik/re2c.git re2c


    #fi

    #if [ -d "${PHPExtDependencies}/re2c/re2c" ]; then
    #    cd "${PHPExtDependencies}"

    #    aaLog "  Compiling re2c/autogen | autogen.sh"
    #    if [ -f "${PHPExtDependencies}/re2c/re2c/autogen.sh" ]; then
    #        ./re2c/re2c/autogen.sh
    #    elif [ -f"${PHPExtDependencies}/re2c/re2c/autogen" ]; then
    #        ./re2c/re2c/autogen
    #    fi
    #    aaLog "  Compiled re2c/autogen | autogen.sh"
    #    rm -rf "/tmp/re2c"
    #    aaLog "  Moving re2c/re2c to re2c"
    #    mv ./re2c/re2c /tmp/re2c
    #    mv /tmp/re2c/re2c "${PHPExtDependencies}/re2c"
    #fi




    if [ -z "$zephir_ver" ]; then
        aaLog ":  zephir source doesn't exist; git clone it from remote"
        rm -rf zephir
        git clone https://github.com/phalcon/zephir.git "zephir"
        installZephir "zephir"
    fi



    aaLog "Installing $cphalcon_ver"
    if [ -z "$cphalcon_ver" ]; then
        aaLog ":  cphalcon source doesn't exist; git clone it from remote"
        cphalcon_ver="cphalcon-2.1.x"
        cd "${PHPExtDependencies}"
        git clone https://github.com/phalcon/cphalcon "$cphalcon_ver"
    fi

    if [ -d "${PHPExtDependencies}/$cphalcon_ver/.git" ]; then
        aaLog ":    cphalcon git checkout 2.1.x"
        cd "${PHPExtDependencies}/$cphalcon_ver"
        git checkout "2.1.x"
    fi

    cd "${PHPExtDependencies}/$cphalcon_ver/ext"
    phpize
    cd "${PHPExtDependencies}/$cphalcon_ver"

    # memory_allow in php.ini

    if [ ! -z "$default_php_conf" -a -f "$default_php_conf" ]; then
        sed -i "s/^\s*;.*//g" "$default_php_conf"
        sed -Ei "s/^\s*memory_limit/;&/g" "$default_php_conf"
        echo -e "\nmemory_limit=384M\n" >> "$default_php_conf"
    fi

    aaLog ":  zephir build --backend=ZendEngine3"
    zephir fullclean
    zephir build --backend=ZendEngine3
    echo "extension=phalcon.so" > "$default_php_conf"

    aaLog ":  Installed $cphalcon_ver"

    # set back memory_limit
    if [ ! -z "$default_php_conf" -a -f "$default_php_conf" ]; then
        sed -i "s/^\s*memory_limit=384M//g" "$default_php_conf"
        sed -Ei "s/^\s*;\s*//g" "$default_php_conf"
    fi
}

enableExtPthread() {
    enableExt=$1
    if [ ! -d "${PHPExtSrc}/$enableExt" ]; then
        # pthreads-3.1.6  --->  3.1.6
        pthreads_ver=$(echo $enableExt | awk -F '-' '{print $2}')
        if curl -sSL "https://github.com/krakjoe/pthreads/archive/v"$pthreads_ver".tar.gz" -o "${PHPExtSrc}/${enableExt}.tar.gz"; then
            cd ${PHPExtSrc}
            tar -zxvf "${PHPExtSrc}/$enableExt.tar.gz"
            rm -f "${PHPExtSrc}/$enableExt.tar.gz"
        fi
    fi
}

enableExtCodecept() {
    [ ! -f "${PHPExtDependencies}/codecept.phar" ] && curl -sSL http://codeception.com/codecept.phar -o "${PHPExtDependencies}/codecept.phar"
    yes | cp "${PHPExtDependencies}/codecept.phar" "/usr/sbin/codecept"
    chmod a+x /usr/sbin/codecept
}

enableExtMosquitto() {
    yum install -y mosquitto-devel
    cd "${PHPExtSrc}/"
    if [ ! -f "${PHPExtSrc}/mosquitto/config.m4" ]; then
        aaLog "git clone -b php7 --single-branch https://github.com/mgdm/Mosquitto-PHP.git mosquitto"
        git clone -b master --single-branch "https://github.com/mgdm/Mosquitto-PHP.git" "mosquitto"
    fi
}

enableExtProtobuf() {
    enableExt=$1
    if [ ! -d "${PHPExtSrc}/${enableExt}" ]; then
        aaLog ""
        protobuf_file_prefix='protobuf-php-'
        protobuf_ver=${enableExt:${#protobuf_file_prefix}}
        curl -sSL "https://github.com/google/protobuf/releases/download/v"$protobuf_ver"/"$enableExt".tar.gz" -o "${PHPExtSrc}/"$enableExt".tar.gz"
        tar -zxvf "${PHPExtSrc}/"$enableExt".tar.gz"
        rm -f "${PHPExtSrc}/"$enableExt".tar.gz"
    fi

    cd "${PHPExtSrc}/$enableExt"
    ./configure
    make && make install
}

enableExtSwoole() {
    enableExt=$1
    #ulimit -n 100000
    [ ${PHPExtsWithSSL} -eq 1 ] && config_opt+=" --enable-openssl"
    if [ ${PHPExtsWithHTTP2} -eq 1 ]; then
        for dependency in $(ls "${PHPExtDependencies}"); do
            if [ -f "${PHPExtDependencies}/$dependency/configure" ]; then
                case "${dependency:0:7}" in
                    nghttp2)
                        aaLog "$dependency is installing..."
                        cd "${PHPExtDependencies}/$dependency"
                        ./configure
                        make
                        break
                    ;;
                esac
            fi
        done
        config_opt+=" --enable-http2"
    fi
    if [ ! -d "${PHPExtSrc}/${enableExt}" ]; then
        aaLog "${PHPExtSrc}/${enableExt}  dosen't exist!"
        if curl -sSL "http://pecl.php.net/get/${enableExt}.tgz" -o "${PHPExtSrc}/${enableExt}.tgz"; then
            cd ${PHPExtSrc}
            tar -zxvf "${PHPExtSrc}/${enableExt}.tgz"
            rm -f "${PHPExtSrc}/${enableExt}.tgz"
        fi
    fi
}
enableExts() {
	if [ -z "${PHPEnableExts}" ]; then
	    return 0
	fi
    aaLog "Enabling Extensions: ${PHPEnableExts}"
    # for i in 100 200 300; do
    # for i in "100 200 300"; do    error!!!
    for enableExt in $(echo "${PHPEnableExts}" | tr ',' "\n"); do
        ext=$(echo "${enableExt}" | awk -F '-' '{print $1}')
        pecl_channel=''
        aaLog "Handling Extension: $ext"
        case "$ext" in
            phpredis)
                aaLog " chang extension name phpredis to redis.so"
                ext="redis"
            ;;
        esac

        extFile="${php_ext_dir}/${ext}.so"

        if [ ! -f  $extFile ]; then
            aaLog " $ext doesn't exist. compile it..."
            cd "${PHPExtSrc}"
            isStandardExt=1
            config_opt=""

            case "$ext" in
                'bz2')
                    yum install -y bzip2-devel
                ;;
                'cassandra') enableExtCassandra ;;
                'rdkafka') enableExtRdkafka ;;
                'zookeeper')
                    enableExtZookeeper
                    config_opt+=' --with-libzookeeper-dir=/usr/local/zookeeper-c-cli'
                ;;
                'composer')
                    enableExtComposer
                    continue
                ;;
                'gd')
                    enableExtGd
                    config_opt+=" --enable-gd-native-ttf --with-jpeg-dir --with-freetype-dir"
                ;;
                'xml')
                    enableExtXml
                ;;
                # pdo_pgsql/pgsql needs a pre-installed postgresql
                'pgsql' | 'pdo_pgsql')
                    enableExtPgsql
                ;;
                'imagick')
                    enableExtImagick
                ;;
                'lua')
                    enableExtLua
                ;;
                'zlib')
                    enableExtZlib
                ;;
                'xdebug')
                    enableExtXdebug "${enableExt}"
                ;;
                'redis')
                    enableExtRedis "${enableExt}"
                ;;
                'phalcon')
                    isStandardExt=0
                    enableExtPhalcon
                ;;
                'pthreads')
                    enableExtPthread "${enableExt}"
                ;;
                'codecept' | 'codeception')
                    isStandardExt=0
                    enableExtCodecept
                ;;
                'mosquitto')
                    enableExtMosquitto
                ;;
                'protobuf')
                    enableExtProtobuf "${enableExt}"
                    enableExt="${enableExt}/php/ext/google/protobuf"
                ;;
                'swoole')
                    enableExtSwoole "${enableExt}"
                ;;
            esac

            aaLog "Checking whether $enableExt is a standard php extension: $isStandardExt"

            if [ $isStandardExt -eq 1 ]; then
                if [ ! -d "${PHPExtSrc}/$enableExt" -a "$enableExt" == "$ext" ]; then
                    ext_list=$(ls ${PHPExtSrc} | grep ^"$enableExt"-)
                    if [ ! -z "$ext_list" ]; then
                        for e in $(ls ${PHPExtSrc} | grep ^"$enableExt"-); do
                            if [ -f "${PHPExtSrc}/$e/config.m4" ]; then
                                enableExt="$e"
                                break
                            fi
                        done
                    fi
                fi

                if [ ! -d "${PHPExtSrc}/$enableExt" ]; then
                    if [ ! -z "$pecl_channel" ]; then
                        $ext="$pecl_channel"
                    fi
                    ${PHPPrefix}/bin/pecl install $ext
                else
                    cd "${PHPExtSrc}/$enableExt"
                    if [ ! -e "Makefile" ]; then
                        aaLog "phpize"
                        phpize
                        aaLog "./configure $enableExt $config_opt"
                        ./configure $config_opt
                    fi

                    aaLog "make"
                    make
                    aaLog "make install"
                    make install
                    find modules -maxdepth 1 -name '*.so' -exec basename '{}' ';' | xargs --no-run-if-empty --verbose docker-php-ext-enable
                    make clean
                fi
            fi

            if [ -f "$php_ext_dir/"$ext".so" ]; then
                aaLog "$ext Installed Successed"
            else
                aaLog --aalogpri_severity ERROR "$ext Installed Failured!!!"
            fi
        fi
    done

    # PHPExtraConfs='yaconf.directory=/tmp/;boc=/love'
    # Warning: PHPExtraConfs="'yaconf.directory=/tmp/;boc=/love'"
    if [ ! -z "${PHPExtraConfs}" ]; then
        # Remove the extra single-quotations
        extra_confs=$(echo ${PHPExtraConfs} | sed "s/^'//")
        if [ "$extra_confs" != ${PHPExtraConfs} ]; then
            extra_confs=$(echo $extra_confs | sed "s/'$//")
        fi
        for extra_conf in $(echo "$extra_confs" | tr ';' "\n"); do
            if [ ! -z "$default_php_conf" -a -f "$default_php_conf" ]; then
                ini="$default_php_conf"
            else
                ini="${PHP_CONF_SCAN_DIR}/aa_${ext}.ini"
            fi
            echo -e "\n${extra_conf}" >> "$ini"
        done
    fi

    aaLog "Enabled Extensions: ${PHPEnableExts}"
    if [ ${PHPCleanCompiledExtSrc} -eq 1 ]; then
        aaLog "Cleaning compiled PHP extension sources..."
        rm -rf ${PHPExtSrc}
    fi
}

disableExts() {
    if [ -z "${PHPDisableExts}" ]; then
        return 0
    fi
    aaLog "Disabling Extensions: ${PHPDisableExts}"
    disable_exts=$(echo "${PHPDisableExts}" | tr ',' "\n")
    for disable_ext in  $disable_exts; do
        ext=$(echo "$disable_ext" | awk -F '-' '{print $1}')
        case "$ext" in
            phpredis)
                ext="redis"
        esac
        [ -f "$php_ext_dir/"$ext".so" ] && rm -f "$php_ext_dir/"$ext".so"
    done
    aaLog "Disabled Extensions: ${PHPDisableExts}"

}

grantPrivileges() {
	[ ! -d "${WWW_HTDOCS}" ] && mkdir -p "${WWW_HTDOCS}"
	[ ! -d "${PHPLogDir}" ] && mkdir -p "${WWW_HTDOCS}"
	[ ! -d "${PHPLogDir}" ] && mkdir -p "${PHPLogDir}"
	chown -R ${PHPUser}:${PHPGroup} ${WWW_HTDOCS} ${PHPLogDir}
	chmod -R u+rwx ${WWW_HTDOCS} ${PHPLogDir}
}

lock_file="${S_P_L_DIR}/php-entrypoint-"$( echo -n "${LOG_TAG}" | md5sum | cut -d ' ' -f1)
if [ ! -f "$lock_file" ]; then
	enableExts
	disableExts
	grantPrivileges
	touch "$lock_file"
fi

for i in $(ls "${AUTORUN_SCRIPT_DIR}"); do
    . "${AUTORUN_SCRIPT_DIR}/"$i &
done

RunningSignal ${RUNING_ID:-''}

if [ $# -gt 0 ]; then
	echo "Running $@"
	if [ "${1: -7}" == 'php-fpm' -o "${1: -3}" == 'php' ]; then
		su - ${PHPUser} << EOF
		$@
EOF
	else
	    exec "$@"
	fi
fi