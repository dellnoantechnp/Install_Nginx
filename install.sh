#!/bin/bash
#
#
MAIN_DIR=$(pwd)
NGINX_SOURCE_DIR=$MAIN_DIR/nginx-1.17.9
NGX_DYNAMIC_MODULE=$MAIN_DIR/ngx_dynamic_upstream-master
NGX_REALTIME_REQUEST_MODULE=$MAIN_DIR/ngx_realtime_request_module
NGX_REQ_STATUS_MODULE=$MAIN_DIR/ngx_req_status
NGX_VTS_MODULE=$MAIN_DIR/nginx-module-vts
#OPENSSL_DIR=$MAIN_DIR/openssl-1.1.0e
OPENSSL_DIR=$MAIN_DIR/openssl-1.1.1d
OPENSSL_VERSION=$(basename ${OPENSSL_DIR})
NGINX_OTHER_CONFIG_DIR=$MAIN_DIR/nginx_some_config_file
NGINX_STICKY_MODULE=$MAIN_DIR/nginx-sticky-module-ng
NGX_HTTP_PROXY_CONNECT_MODULE=${MAIN_DIR}/ngx_http_proxy_connect_module
#NGINX_CONNECT_PATCH_PATH=${MAIN_DIR}/proxy_connect_rewrite_1018.patch

INSTALL_PREFIX_DIR=/usr/local/nginx
NGINX_USER=nginx
NGINX_LOG_DIR=/var/log/nginx

help_info="Nginx 安装脚本\n
-h\t\t\t显示帮助信息。\n
--with-openssl\t\t安装 ${OPENSSL_VERSION} (默认安装)\n
--with-lua\t\t安装 lua 扩展 (默认不安装, lua 扩展与 ${OPENSSL_VERSION} 不兼容。)\n
-s|--version_string\t更改 nginx version 字符串。(\033[1mversion_string\033[0m-1.12.0)\n
"

if gcc -dM -E - </dev/null | grep -q __SIZEOF_INT128__
then
  ECFLAG="enable-ec_nistp_64_gcc_128"
else
  ECFLAG=""
fi

function dep_package() {
id $NGINX_USER > /dev/null  2>&1
    if [ $? -ne 0 ]; then
        echo "add nginx unser: nginx"
    	adduser -r -M -s /sbin/nologin nginx
    fi
    # 创建 nginx 用户
    
    if [ ! -d $NGINX_LOG_DIR ]; then
    	mkdir -p $NGINX_LOG_DIR/json
    	chown -R ${NGINX_USER}.${NGINX_USER} $NGINX_LOG_DIR
    fi
    
    if [ ! -f /usr/bin/pcre-config ]; then
        echo "install pcre-devel ..."
    	yum install -q -y pcre-devel
    fi
    
    make > /dev/null 2>&1
    if [ $? -eq 127 ]; then
        echo "install make ..."
    	yum install -y -q make 
    fi
    
    gcc > /dev/null 2>&1
    if [ $? -eq 127 ]; then
        echo "install gcc glibc gcc-c++ ..."
    	yum install -y -q gcc glibc gcc-c++
    fi

    if [[ ! -f /usr/include/zlib.h ]]; then
        echo "install zlib-devel ..."
        yum install -y -q zlib-devel
    fi

    cd $MAIN_DIR
    if [ -d $NGINX_SOURCE_DIR ]; then
    	cd $NGINX_SOURCE_DIR
    else
    	tar xf ${NGINX_SOURCE_DIR}.tar.gz
    	cd $NGINX_SOURCE_DIR
    	#patch -p1 < $NGX_REQ_STATUS_MODULE/write_filter-1.7.11.patch
    fi
}

function is_failed(){
	if [ $? -ne 0 ]; then
		echo -e "\033[31mxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx failed xxxxxxxx\033[0m"
		exit 9
	fi
}

function start_openssl() {
    cd $MAIN_DIR
    if [ ! -d ${OPENSSL_VERSION} ]; then
    	tar xf ${OPENSSL_VERSION}.tar.gz
    fi
    OPENSSL_OPT=" --with-openssl-opt=no-weak-ssl-ciphers \
                  --with-openssl-opt=no-ssl3 \
                  --with-openssl-opt=no-shared \
                  --with-openssl-opt=no-err \
                  --with-openssl-opt=${ECFLAG} \
                  --with-openssl=$OPENSSL_DIR "
                  #--with-openssl-opt=\"-DOPENSSL_NO_HEARTBEATS\" \
    echo $OPENSSL_OPT
    # 开启openssl 弱加密特性（不建议，但兼容ie8）
    #OPENSSL_OPT=" --with-openssl=$OPENSSL_DIR --with-openssl-opt='enable-weak-ssl-ciphers' "
}

function GET_OS_VERSION() {
    #if [[ -f /etc/os-release ]]; then
    #    source /etc/os-release
    #    VERSION_ID=$(echo $VERSION_ID | awk -F . '{print $1}')
    #fi
    #echo $VERSION_ID
    echo $(rpm -q centos-release | cut -d - -f3)
}

function start_lua() {
    cd $MAIN_DIR
    if [ ! -d LuaJIT-2.0.5 ]; then 
        tar xf LuaJIT-2.0.5.tar.gz
        cd LuaJIT-2.0.5 && make && make install
        is_failed
        export LUAJIT_LIB=/usr/local/lib
        export LUAJIT_INC=/usr/local/include/luajit-2.0
        cd -
    fi
    if [ ! -d lua-nginx-module-0.10.11 ]; then
        tar xf lua_nginx_module-0.10.11.tar.gz
    fi
    if [ ! -d ngx_devel_kit-0.3.0 ]; then
        tar xf ngx_devel_kit-0.3.0.tar.gz
    fi
    LUA_OPT=" --with-ld-opt="-Wl,-rpath,/usr/local/lib" --add-module=${MAIN_DIR}/ngx_devel_kit-0.3.0 --add-module=${MAIN_DIR}/lua-nginx-module-0.10.11 "
    OPENSSL_OPT=""
}
function end_lua() {
    cd $MAIN_DIR
    rm -rf LuaJIT-2.0.5 lua-nginx-module-0.10.11 ngx_devel_kit-0.3.0
}


function change_server_version_token() {
	local PWD=$(pwd) version_string=$1 
	cd $NGINX_SOURCE_DIR
	sed -i "s/^\(\#define NGINX_VER\b\s*\)\([\"/a-zA-Z]*\)\(\s*\)\(.*\)$/\1\"${version_string}-\"\3\4/" src/core/nginx.h
	cd $PWD	
}

function enable_ngx_http_connect_support() {
	local PWD=$(pwd)
	cd $NGINX_SOURCE_DIR
	patch -p1 < ${NGX_HTTP_PROXY_CONNECT_MODULE}/patch/proxy_connect_rewrite_1018.patch
        cd $PWD
}

dep_package
while [ "$1" != "${1##[-+]}" ]; do
    case "$1" in
        "-h"|"--help")
            echo -e $help_info
            exit
            ;;
        "--with-openssl")
            have_openssl="YES"
            shift 1
            ;;
        "--with-lua")
            have_lua="YES"
            shift 1
            ;;
        "-s"|"--version_string")
            SERVER_STR=$2
            shift 2
            change_server_version_token $SERVER_STR
            ;;
    esac
done

if [[ -d /etc/nginx ]]; then
    echo -e "\e[33mINFO: backup /etc/nginx -> /tmp\e[0m"
    sleep 3
    cp -a /etc/nginx /tmp/
    echo -e "\e[32mINFO: backup Done!\e[0m"
    rm -rf /etc/nginx
fi

#if [[ $have_openssl = "YES" ]]; then
#    default enable
#fi
start_openssl
if [[ $have_lua = "YES" ]]; then
    start_lua
fi
cd ${NGINX_SOURCE_DIR}


#OPENSSL_OPT=" --with-openssl=$OPENSSL_DIR --with-openssl-opt='enable-weak-ssl-ciphers' "
#LUA_OPT=" --with-ld-opt="-Wl,-rpath,/usr/local/lib" --add-module=${MAIN_DIR}/ngx_devel_kit-0.3.0 --add-module=${MAIN_DIR}/lua-nginx-module-0.10.11 "

#./configure --prefix=$INSTALL_PREFIX_DIR --http-log-path=/var/log/nginx/access.log --error-log-path=/var/log/nginx/error.log --lock-path=/var/lock/nginx.lock --with-file-aio --user=$NGINX_USER --group=$NGINX_USER --with-threads --with-http_v2_module --with-http_realip_module --with-http_addition_module --with-http_ssl_module --with-http_auth_request_module --with-http_stub_status_module --with-http_slice_module --with-http_gzip_static_module --with-http_sub_module --with-pcre --with-http_secure_link_module --add-module=$NGX_DYNAMIC_MODULE --with-openssl=$OPENSSL_DIR --with-openssl-opt='enable-weak-ssl-ciphers' --add-module=$NGX_VTS_MODULE --with-ld-opt="-Wl,-rpath,/usr/local/lib" --add-module=${MAIN_DIR}/ngx_devel_kit-0.3.0 --add-module=${MAIN_DIR}/lua-nginx-module-0.10.11
#./configure --prefix=$INSTALL_PREFIX_DIR --http-log-path=/var/log/nginx/access.log --error-log-path=/var/log/nginx/error.log --lock-path=/var/lock/nginx.lock --with-file-aio --user=$NGINX_USER --group=$NGINX_USER --with-threads --with-http_v2_module --with-http_realip_module --with-http_addition_module --with-http_ssl_module --with-http_auth_request_module --with-http_stub_status_module --with-http_slice_module --with-http_gzip_static_module --with-http_sub_module --with-pcre --with-http_secure_link_module --add-module=$NGX_DYNAMIC_MODULE --add-module=$NGX_VTS_MODULE --with-ld-opt="-Wl,-rpath,/usr/local/lib" --add-module=${MAIN_DIR}/ngx_devel_kit-0.3.0 --add-module=${MAIN_DIR}/lua-nginx-module-0.10.11
echo -e "INFO: OPENSSL_OPT: \e[33m${OPENSSL_OPT}\e[0m"
echo -e "INFO: LUA_OPT: \e[33m${LUA_OPT}\e[0m"
echo -e "INFO: Enable http proxy CONNECT Support. "
enable_ngx_http_connect_support
echo -e "Start configure ...."
sleep 5
./configure \
--prefix=$INSTALL_PREFIX_DIR \
--http-log-path=/var/log/nginx/access.log \
--error-log-path=/var/log/nginx/error.log \
--lock-path=/var/lock/nginx.lock \
--with-file-aio \
--user=$NGINX_USER \
--group=$NGINX_USER \
--with-threads \
--with-http_v2_module \
--with-http_realip_module \
--with-http_addition_module \
--with-http_ssl_module \
--with-http_auth_request_module \
--with-http_stub_status_module \
--with-http_slice_module \
--with-http_gzip_static_module \
--with-http_dav_module \
--with-cc-opt='-O2' \
--with-http_sub_module \
--with-pcre \
--with-http_secure_link_module \
--with-stream=dynamic \
--with-stream_ssl_module \
--with-stream_realip_module \
--with-stream_ssl_preread_module \
--add-module=$NGX_DYNAMIC_MODULE \
--add-module=$NGINX_STICKY_MODULE \
--add-module=$NGX_VTS_MODULE \
--add-module=$NGX_HTTP_PROXY_CONNECT_MODULE \
$OPENSSL_OPT \
$LUA_OPT

#--add-module=$NGX_REALTIME_REQUEST_MODULE --add-module=$NGX_REQ_STATUS_MODULE 

is_failed
echo -e "\e[33mStart make ....\e[0m"
sleep 3

make -j $(grep -c processor /proc/cpuinfo)
is_failed
echo -e "\e[33mStart make install ....\e[0m"
sleep 3

make install
is_failed

chown  -R ${NGINX_USER}.${NGINX_USER} $INSTALL_PREFIX_DIR
ln -s $INSTALL_PREFIX_DIR/conf /etc/nginx

cd $MAIN_DIR
function  end_openssl() {
    cd $MAIN_DIR
    rm -rf ${OPENSSL_VERSION}
}
end_openssl
end_lua

cd $INSTALL_PREFIX_DIR/conf
[ -d sites-available ] || mkdir sites-available
[ -d sites-enabled ] || mkdir sites-enabled

cd $NGINX_OTHER_CONFIG_DIR
if [[ GET_OS_VERSION -eq 6 ]]; then
    cp nginx /etc/init.d/ 
    chkconfig --add nginx
    chkconfig nginx on
elif [[ GET_OS_VERSION -eq 7 ]]; then
    cp nginx.service /usr/lib/systemd/system/
    systemctl enable nginx.service
fi

cp nginx_profile.sh /etc/profile.d/
cp nginx_logrotate /etc/logrotate.d/


is_failed && rm -rf ${NGINX_SOURCE_DIR}
is_failed && rm -rf ${OPENSSL_DIR} && echo -e "\e[32m$(basename ${NGINX_SOURCE_DIR}) install Done! \e[0m)"
