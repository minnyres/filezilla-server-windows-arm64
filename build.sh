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

libfilezilla_version=0.47.0
libfilezilla_path=$PWD/libfilezilla-windows-$arch
filezilla_server_version=1.8.2
filezilla_server_path=$PWD/filezilla-server-windows-$arch
wxwidgets_version=3.2.4
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
}

# Build wxwidgets
wget https://github.com/wxWidgets/wxWidgets/releases/download/v${wxwidgets_version}/wxWidgets-${wxwidgets_version}.tar.bz2
tar xf wxWidgets-${wxwidgets_version}.tar.bz2
cd wxWidgets-${wxwidgets_version}
./configure --host=$TARGET --prefix=${wxwidgets_path} --with-zlib=sys --with-msw --with-libiconv-prefix=$vcpkg_dir --disable-shared --disable-debug_flag --enable-optimise --enable-unicode
gnumakeplusinstall

# Build libfilezilla
wget https://download.filezilla-project.org/libfilezilla/libfilezilla-${libfilezilla_version}.tar.xz
tar xf libfilezilla-${libfilezilla_version}.tar.xz
cd libfilezilla-${libfilezilla_version}
./configure --host=$TARGET --prefix=${libfilezilla_path} --disable-shared --enable-static 
gnumakeplusinstall

# Build filezilla server
wget https://download.filezilla-project.org/server/FileZilla_Server_${filezilla_server_version}_src.tar.xz
tar xf FileZilla_Server_${filezilla_server_version}_src.tar.xz
cd filezilla-server-${filezilla_server_version}
./configure --host=$TARGET --prefix=${filezilla_server_path} --disable-shared --enable-static --with-pugixml=builtin --with-wx-config=${wxwidgets_path}/bin/wx-config
gnumakeplusinstall
find . -name "*.exe" -exec $TARGET-strip {} \;
find $filezilla_server_path -name "*.exe" -exec $TARGET-strip {} \;

if [ $arch == "arm32" ]; then   
    cd ..
    mkdir FileZilla_Server_${filezilla_server_version}
    cp $filezilla_server_path/bin/*.exe FileZilla_Server_${filezilla_server_version}
    7z a -mx9 FileZilla_Server_${filezilla_server_version}_arm32.7z  FileZilla_Server_${filezilla_server_version}
elif [ $arch == "arm64" ]; then
    sed -i 's/PROGRAMFILES"/PROGRAMFILES64"/g' pkg/windows/install.nsi
    make pkg-exe
    cp pkg/windows/FileZilla_Server_${filezilla_server_version}_win64-setup.exe ../FileZilla_Server_${filezilla_server_version}_arm64-setup.exe
fi