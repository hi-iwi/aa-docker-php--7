FROM aario/centos:7
MAINTAINER Aario <Aario@luexu.com>

# http://pecl.php.net/package-stats.php

ENV PHPVer php-7.3.1
ENV PHPSrcURL http://cn.php.net/distributions/${PHPVer}.tar.gz
ENV PHPUser ${SHARED_USER}
ENV PHPGroup ${SHARED_GROUP}

WORKDIR ${SRC_DIR}
ADD ./src/* ${SRC_DIR}/
RUN if [ ! -d "${SRC_DIR}/${PHPVer}" ]; then                               \
        curl -sSL ${PHPSrcURL} -o ${SRC_DIR}/${PHPVer}.tar.gz;           \
        tar -zxvf ${SRC_DIR}/${PHPVer}.tar.gz;                             \
        rm -f ${SRC_DIR}/${PHPVer}.tar.gz;                                 \
    fi

# RUN 
   						# \
    # && yum install -y libicu-devel openldap-devel bzip2* libtidy* 			\
                   # \
    # && yum install -y glibc glibc-devel glib2 glib2-devel

ENV PHPPrefix ${PREFIX_BASE}/php
ENV PHPConfScanDir ${PHPPrefix}/etc


# for --with-curl --with-openssl 
# autoconf  :  phpize
RUN yum install -y gcc gcc-c++ autoconf libxml2-devel curl-devel libcurl libcurl-devel openssl openssl-devel pcre pcre-devel
 
WORKDIR ${SRC_DIR}/${PHPVer}
# 	--with-gettext                                          \
#	--enable-bcmath                                         \
#	--with-pdo_mysql=mysqlnd
#	--with-pdo_pgsql
# http://php.net/manual/en/configure.about.php
#	--with-mysqli=mysqlnd                                   \
#	http://php.net/manual/zh/mysqli.installation.php
# --gettext    for locale http://php.net/manual/zh/book.gettext.php
# Debug
#   --enable-phpdbg                                         \
#   --enable-phpdbg-debug                                   \
#   --enable-debug                                          \
RUN ./configure                                             \
	--prefix="${PHPPrefix}"                                \
	--with-config-file-scan-dir="${PHPConfScanDir}"      \
	--enable-fpm                                            \
	--with-fpm-user=${PHPUser}                             \
	--with-fpm-group=${PHPGroup}                           \
	--disable-short-tags                                    \
	--with-openssl                                          \
	--with-curl												\
	--enable-mbstring                                       \
	--enable-opcache                                        \
	--enable-opcache-file									\
	--enable-sockets                                        \
	--with-mhash                                            \
	--with-pdo-mysql=mysqlnd 								\
	--with-mysqli=mysqlnd									\
	&& make && make install && make clean
	
################### configurations7 ###############
ENV PHPFPMPort 9000
ENV PHPLogDir /var/log/php
ENV WWW_HTDOCS /var/lib/htdocs
    
COPY ./etc/* ${PHPConfScanDir}/
    
WORKDIR ${PHPConfScanDir}
RUN chown -R ${PHPUser}:${PHPGroup} ${PHPConfScanDir}
RUN chmod -R g+rx ${PHPConfScanDir}

RUN if [ ! -d "${PHPConfScanDir}/php-fpm.d" ]; then mkdir -p ${PHPConfScanDir}/php-fpm.d; fi

RUN if [ ! -f "${PHPConfScanDir}/php-fpm.conf" ]; then                                       \
        if [ -f "${PHPConfScanDir}/php-fpm.conf.default" ]; then                             \
            cp "${PHPConfScanDir}/php-fpm.conf.default" "${PHPConfScanDir}/php-fpm.conf"; \
        else                                                                                    \
            touch "${PHPConfScanDir}/php-fpm.conf";                                          \
        fi                                                                                      \
    fi

RUN if [ ! -f "${PHPConfScanDir}/php-fpm.d/www.conf" ]; then cp "${PHPConfScanDir}/php-fpm.d/www.conf.default" "${PHPConfScanDir}/php-fpm.d/www.conf"; fi

RUN if [ ! -f "${PHPConfScanDir}/php.ini" ]; then touch "${PHPConfScanDir}/php.ini"; fi

# to check whether host allow hugepages
RUN echo | awk '{"cat /proc/sys/vm/nr_hugepages" | getline s;if(s > 0){print("opcache.huge_code_pages=1") >> "opcache.ini"}}'

RUN sed -i "s/^[\s;]*listen\s*=.*/listen=[::]:${PHPFPMPort}/"  ${PHPConfScanDir}/php-fpm.conf     \
    && sed -i "s/^[\s;]*user\s*=.*/user=${PHPUser}/"              ${PHPConfScanDir}/php-fpm.conf  \
    && sed -i "s/^[\s;]*group\s*=.*/group=${PHPGroup}/"           ${PHPConfScanDir}/php-fpm.conf  \
    && sed -i "s/^[\s;]*listen\s*=.*/listen=[::]:${PHPFPMPort}/"  ${PHPConfScanDir}/php-fpm.d/www.conf     \
    && sed -i "s/^[\s;]*user\s*=.*/user=${PHPUser}/"              ${PHPConfScanDir}/php-fpm.d/www.conf  \
    && sed -i "s/^[\s;]*group\s*=.*/group=${PHPGroup}/"           ${PHPConfScanDir}/php-fpm.d/www.conf
#################################################

################## extensions 7 ####################
ENV PHPExtSrc             ${PHPPrefix}/src/ext
ENV PHPExtDependencies    ${PHPPrefix}/src/ext_dependencies

RUN mkdir -p $PHPExtSrc $PHPExtDependencies

RUN if [ "${PHPExtSrc}" != "${SRC_DIR}/${PHPVer}/ext" ]; then    \
        mv ${SRC_DIR}/${PHPVer}/ext/* "${PHPExtSrc}/";           \
    fi
    
ADD ./ext/* ${PHPExtSrc}/
ADD ./ext_dependencies/* ${PHPExtDependencies}/

WORKDIR ${PHPExtSrc}

COPY ./bin/* /usr/bin/
# Notice: ${PHPExtSrc} includes '/'
RUN sed -i 's/^\s*#\!\/bin\/bash\s*$//g' /usr/bin/docker-php-ext-*      \
    && sed -i 's/^\s*set\s*\-e\s*$//g' /usr/bin/docker-php-ext-*        \
    && sed -i "1s/.*/\#\!\/bin\/bash\nset \-e\n\. \/aa_script\/entrypointConst\.sh\n&/" /usr/bin/docker-php-ext-*   \
    && sed -i 's/\r$//' /usr/bin/docker-php-ext-*

################ Entrypoint ########################
COPY ./script/entrypoint.sh         ${ENT_SCRIPT}
COPY ./script/autorun/*             ${AUTORUN_SCRIPT_DIR}/

RUN echo -e "\n PHPVer='${PHPVer}' \n PHPSrcURL='${PHPSrcURL}' \n PHPExtSrc='${PHPExtSrc}' \n PHPExtDependencies='${PHPExtDependencies}' \n PHPGroup='${PHPGroup}' \n PHPUser='${PHPUser}' \n PHPPrefix='${PHPPrefix}' \n PHPConfScanDir='${PHPConfScanDir}' \n PHPLogDir='${PHPLogDir}' \n WWW_HTDOCS='${WWW_HTDOCS}'" >> ${ENT_CONST_SCRIPT}         \
    && sed -i 's/^\s*//g' ${ENT_CONST_SCRIPT}

RUN rm -rf /tmp/spool && mkdir /tmp/spool
COPY ./spool/* /tmp/spool
RUN if [ -f "/tmp/spool/crontab" ]; then            \
        if [ -f "/etc/crontab" ]; then              \
            yes | cp /etc/crontab /etc/crontab-cp1; \
            cat /tmp/spool/crontab >> /etc/crontab; \
        else                                        \
            mv /tmp/spool/crontab /etc/crontab;     \
        fi;                                         \
        sort -k2n "/etc/crontab" | sed '$!N; /^\(.*\)\n\1$/!P; D' > "/tmp/crontab";    \
        yes | mv "/tmp/crontab" "/etc/crontab";     \
        yes | cp /etc/crontab /etc/crontab-cp2;     \
        rm -rf /tmp/spool;                          \
    fi
RUN yum clean all  && rm -rf /var/cache/yum && rm -rf ${SRC_DIR}/*
#################################################


# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/stdout.log    		\
    && ln -sf /dev/stderr /var/log/stderr.log

RUN ln ${PHPPrefix}/sbin/php-fpm       /usr/sbin/php-fpm   \
	&& ln ${PHPPrefix}/bin/php         /usr/bin/php        \
	&& ln ${PHPPrefix}/bin/phpize      /usr/bin/phpize     \
	&& ln ${PHPPrefix}/bin/php-config  /usr/bin/php-config
# /aa_script/entrypoint.sh php-fpm -F
ENTRYPOINT ["/aa_script/entrypoint.sh", "/usr/local/php/sbin/php-fpm", "-F"]

#COLUME ['/var/lib/htdocs', '/var/log']