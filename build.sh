#!/bin/bash -e

help_msg="Usage: ./build.sh [arm32|arm64]"

[ -z "$vcpkg_dir" ] && vcpkg_dir=$PWD/vcpkg
[ -z "$llvm_dir" ] && llvm_dir=$PWD/llvm-mingw
work_dir=$PWD
prefix=$work_dir/install_dir

if [ $# == 1 ]; then
    if [ $1 == "arm32" ]; then
        arch=arm32
        vcpkg_libs_dir=$vcpkg_dir/installed/arm-mingw-dynamic-release
        TARGET=armv7-w64-mingw32
        export libclang_rt="${llvm_dir}/lib/clang/22/lib/windows/libclang_rt.builtins-arm.a"
    elif [ $1 == "arm64" ]; then
        arch=arm64
        vcpkg_libs_dir=$vcpkg_dir/installed/arm64-mingw-dynamic-release
        TARGET=aarch64-w64-mingw32
        export libclang_rt="${llvm_dir}/lib/clang/22/lib/windows/libclang_rt.builtins-aarch64.a"
    else
        echo $help_msg
        exit -1
    fi
else
    echo $help_msg
    exit -1
fi

libfilezilla_version=0.56.0
filezilla_server_version=1.12.6
filezilla_server_path=$PWD/filezilla-server-windows-$arch
gnutls_ver=3.8.13
gnutls_ver_main="${gnutls_ver%.*}"
nettle_ver=nettle_4.0_release_20260205
gmp_ver=6.3.0
idn2_ver=2.3.8
unistring_ver=1.4.2
fzssh_version=1.4.0
wxwidgets_version=3.2.11

export PATH=$llvm_dir/bin:$llvm_dir/$TARGET/bin:$vcpkg_libs_dir/bin:$prefix/bin:$PATH
export PKG_CONFIG_LIBDIR=$vcpkg_libs_dir/lib/pkgconfig:$prefix/lib/pkgconfig
export PKG_CONFIG_PATH=$PKG_CONFIG_LIBDIR
export CPPFLAGS="-I$vcpkg_libs_dir/include -I$prefix/include"
export LDFLAGS="-L$vcpkg_libs_dir/lib -L$prefix/lib -s"

wget="wget -nc --progress=bar:force"
gitclone="git clone --depth=1 --recursive"

function gnumakeplusinstall {
    make -j $(nproc)
    make install
    make clean
}

# Build wxwidgets
[ -d wxWidgets ] || $gitclone --branch v$wxwidgets_version --recurse-submodules --depth 1 https://github.com/wxWidgets/wxWidgets.git
pushd wxWidgets
./configure --host=$TARGET --prefix=$prefix --with-zlib=sys --with-msw --enable-shared --disable-debug_flag --enable-optimise --enable-unicode
gnumakeplusinstall
popd

# build libunistring
$wget https://ftp.gnu.org/gnu/libunistring/libunistring-${unistring_ver}.tar.xz
tar xf libunistring-${unistring_ver}.tar.xz
pushd libunistring-${unistring_ver}
./configure --host=$TARGET --prefix=$prefix --enable-shared --enable-static=no --enable-threads=windows
gnumakeplusinstall
popd

# build idn2
$wget https://ftp.gnu.org/gnu/libidn/libidn2-${idn2_ver}.tar.gz
tar xf libidn2-${idn2_ver}.tar.gz
pushd libidn2-${idn2_ver}
./configure --host=$TARGET --prefix=$prefix --disable-doc --enable-shared --enable-static=no 
gnumakeplusinstall
popd

# build gmp
$wget https://ftp.gnu.org/gnu/gmp/gmp-${gmp_ver}.tar.xz
tar xf gmp-${gmp_ver}.tar.xz
pushd gmp-${gmp_ver}
./configure --host=$TARGET --prefix=$prefix --disable-assembly --enable-shared --disable-static --disable-cxx
gnumakeplusinstall
popd

# build nettle
$gitclone https://github.com/gnutls/nettle.git --branch ${nettle_ver}
pushd nettle
autoreconf -fi
./configure --host=$TARGET --prefix=$prefix --enable-shared --disable-static --enable-public-key --disable-documentation
gnumakeplusinstall
popd

# build gnutls
$wget https://www.gnupg.org/ftp/gcrypt/gnutls/v${gnutls_ver_main}/gnutls-${gnutls_ver}.tar.xz
tar xf gnutls-${gnutls_ver}.tar.xz
pushd gnutls-${gnutls_ver}
./configure --build=x86_64-linux-gnu --host=$TARGET --prefix=$prefix --disable-hardware-acceleration --without-p11-kit --with-included-libtasn1 --enable-shared --enable-static=no --enable-threads=windows --disable-tools --with-zlib=yes --disable-tests --disable-openssl-compatibility --disable-doc --disable-cxx
gnumakeplusinstall
popd

# Build libfilezilla
$wget https://sources.archlinux.org/other/libfilezilla/libfilezilla-${libfilezilla_version}.tar.xz
tar xf libfilezilla-${libfilezilla_version}.tar.xz
pushd libfilezilla-${libfilezilla_version}
autoreconf -fi
./configure --host=$TARGET --prefix=$prefix --enable-shared --enable-static=no 
sed -i "s|-g++|-g++ $libclang_rt|g" libtool
gnumakeplusinstall
popd

# Build filezilla server
$wget https://sourceforge.net/projects/fabiololix-os-archive/files/src/FileZilla_Server_${filezilla_server_version}_src.tar.xz
tar xf FileZilla_Server_${filezilla_server_version}_src.tar.xz
pushd filezilla-server-${filezilla_server_version}
patch -Np2 -i ${work_dir}/patches/filezilla-server-Remove-demos-leftovers.patch
./configure --host=$TARGET --prefix=${filezilla_server_path} --enable-shared --disable-static --with-pugixml=builtin --with-wx-config=${prefix}/bin/wx-config
sed -i "s|-g++|-g++ $libclang_rt|g" libtool
gnumakeplusinstall
find . -name "*.exe" -exec $TARGET-strip {} \;
find $filezilla_server_path -name "*.exe" -exec $TARGET-strip {} \;

if [ $arch == "arm64" ]; then
    sed -i 's/PROGRAMFILES"/PROGRAMFILES64"/g' pkg/windows/install.nsi
    make pkg-exe
    cp pkg/windows/FileZilla_Server_${filezilla_server_version}_win64-setup.exe ../FileZilla_Server_${filezilla_server_version}_arm64-setup.exe
fi

popd
rm -rf filezilla-server-${filezilla_server_version}