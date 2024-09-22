#!/bin/bash -e

help_msg="Usage: ./build.sh [arm32|arm64]"

[ -z "$vcpkg_dir" ] && vcpkg_dir=$PWD/vcpkg
[ -z "$llvm_dir" ] && llvm_dir=$PWD/llvm-mingw

if [ $# == 1 ]; then
    if [ $1 == "arm32" ]; then
        arch=arm32
        vcpkg_libs_dir=$vcpkg_dir/installed/arm-mingw-static-release
        TARGET=armv7-w64-mingw32
    elif [ $1 == "arm64" ]; then
        arch=arm64
        vcpkg_libs_dir=$vcpkg_dir/installed/arm64-mingw-static-release
        TARGET=aarch64-w64-mingw32
    else
        echo $help_msg
        exit -1
    fi
else
    echo $help_msg
    exit -1
fi

libfilezilla_version=0.48.1
libfilezilla_path=$PWD/libfilezilla-windows-$arch
filezilla_server_version=1.9.1
filezilla_server_sha512=2f61aec813254e32808ef579da36897164ee89ef365f5e0bdd2de92cae5ad3575b486a838cce35c00e697ed1a6c6b0b93918eec9ae9ac620777c418d9204f97e
filezilla_server_path=$PWD/filezilla-server-windows-$arch
wxwidgets_version=3.2.6
wxwidgets_path=$PWD/wxmsw-windows-$arch

export PATH=$llvm_dir/bin:$wxwidgets_path/bin:$PATH
export PKG_CONFIG_LIBDIR=$vcpkg_libs_dir/lib/pkgconfig:$libfilezilla_path/lib/pkgconfig
export PKG_CONFIG_PATH=$PKG_CONFIG_LIBDIR
export CPPFLAGS="-D STRSAFE_NO_DEPRECATE -I$vcpkg_libs_dir/include -I$libfilezilla_path/include"
export LDFLAGS="-L$vcpkg_libs_dir/lib -L$libfilezilla_path/lib --static -s"

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
if [ $arch == "arm32" ]; then   
    git apply ../patches/wx-fix-arm32-support.patch
fi
mkdir build-$TARGET
cd build-$TARGET
../configure --host=$TARGET --prefix=${wxwidgets_path} --with-zlib=sys --with-msw --with-libiconv-prefix=$vcpkg_dir --disable-shared --disable-debug_flag --enable-optimise --enable-unicode
gnumakeplusinstall
popd

# Build libfilezilla
# $wget https://download.filezilla-project.org/libfilezilla/libfilezilla-${libfilezilla_version}.tar.xz
svn co https://svn.filezilla-project.org/svn/libfilezilla/trunk@11169 libfilezilla-${libfilezilla_version}
pushd libfilezilla-${libfilezilla_version}
autoreconf -fi
./configure --host=$TARGET --prefix=${libfilezilla_path} --disable-shared --enable-static 
gnumakeplusinstall
popd
rm -rf libfilezilla-${libfilezilla_version}

# Build filezilla server
# $wget https://download.filezilla-project.org/server/FileZilla_Server_${filezilla_server_version}_src.tar.xz
sha512sum sources/FileZilla_Server_${filezilla_server_version}_src.tar.xz
tar xf sources/FileZilla_Server_${filezilla_server_version}_src.tar.xz
pushd filezilla-server-${filezilla_server_version}
./configure --host=$TARGET --prefix=${filezilla_server_path} --disable-shared --enable-static --with-pugixml=builtin --with-wx-config=${wxwidgets_path}/bin/wx-config
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