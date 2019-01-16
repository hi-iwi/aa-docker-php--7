很多常用的PHP扩展，可以直接通过 -e "PHPEnableExts=???" 来自动添加，不需要手动去编译了



# Usage 使用方法
```
sh$ cd ./AaDocker
sh$ ./docker-build php--7     

sh$ docker run  --name='aa_php' --detach='true' --restart='always' --ulimit='nofile=100000:100000' --net='bridge' --link='aa-ccs:aa-ccs' --link='aa_redis:aa_redis' --link='aa_redisslave:aa_redisslave' --link='aa_mysql:aa_mysql' --link='aa_mysqlslave:aa_mysqlslave' --volume='/htdocs:/var/lib/htdocs' --volume='/var/log/aa_php:/var/log' --volume='/etc/letsencrypt:/etc/letsencrypt' --publish='9000:9000' --env='ENTRYPOINT_LOG=/var/log/docker_entrypoint.log' --env='UPDATE_REPO=0' --env='TIMEZONE=Asia/Shanghai' --env='PHPEnableExts=gd,imagick-3.4.3,lua-2.0.4,redis-3.1.3,yaconf-1.0.6,bz2,swoole-2.0.10' --env='PHPExtsWithHTTP2=0' --env='PHPExtsWithSSL=1' --env='PHPExtraConfs=yaconf.directory=/.conf;yaconf.check_delay=10' --env='PHPCleanCompiledExtSrc=0' --env=RUNING_ID='1518722860754619823' aario/php:7 


```

### Docker-Composer Demo  
```
services:
  aa_php:
    build: "./php--7"
    image: "aario/php:7"
    #cidfile: "/aa_run/php_0.cid"
    volume:
      - "${DEPLOY_DIR}/proj:/var/lib/htdocs"
      - "${REPO_DIR}/log/aa_php:/var/log"
      - "/etc/letsencrypt:/etc/letsencrypt"
    link:
      - "aa-ccs:aa-ccs"
      - "aa_redis:aa_redis"
      - "aa_redisslave:aa_redisslave"
      - "aa_mysql:aa_mysql"
      - "aa_mysqlslave:aa_mysqlslave"
    publish:
      - "9000:9000"
    expose:
      - "9000"
    env:
    #PHPEnableExts=composer,protobuf-3.1.0,imagick-3.4.1,lua-2.0.1,redis-3.0.0,xdebug-2.4.1,xhprof-php7/extension,yaconf-yaconf-1.0.2,swoole-src-1.8.11-stable,pthreads-3.1.6,pdo,pdo_mysql,pdo_pgsql,pgsql,bz2,curl,phalcon,mosquitto
      - "PHPEnableExts=gd,imagick-3.4.3,lua-2.0.4,redis-3.1.3,yaconf-1.0.6,bz2,swoole-2.0.10"
 
      - "PHPExtsWithHTTP2=0"
      - "PHPExtsWithSSL=1"
      - "PHPExtraConfs=yaconf.directory=/var/lib/htdocs/AaPHP/.conf;yaconf.check_delay=10"
      - "PHPCleanCompiledExtSrc=0"
      - "PHPCleanCompiledExtSrc=0"
      - "PHPCleanCompiledExtSrc=0"
```