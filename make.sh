#!/bin/bash

VERSION="1.1"
DEPLOY="false"
JDK_ROOT="$JAVA_HOME"
if [ ! -f "$JDK_ROOT/include/jni.h" ];
then
    JDK_ROOT="$(readlink -f `which java` | sed "s:/bin/java::")"
    if [ ! -f "$JDK_ROOT/include/jni.h" ];
    then
        JDK_ROOT="$(readlink -f `which java` | sed "s:/jre/bin/java::")"
        if [ ! -f "$JDK_ROOT/include/jni.h" ];
        then
            echo "Can't find JDK"
        fi
    fi
fi

mkdir -p build
if [ ! -f "build/bash_colors.sh" ];
then
    wget  -q https://raw.githubusercontent.com/maxtsepkov/bash_colors/738f82882672babfaa21a2c5e78097d9d8118f91/bash_colors.sh -O build/bash_colors.sh
fi
source build/bash_colors.sh


function cleanTMP {
    rm -Rf build/tmp
    mkdir -p build/tmp
}

function clean {
    rm -R build
    mkdir build   
}

function downloadIfRequired {
    if [ ! -d "build/bullet" ]; 
    then
        download
    fi
}

function download {
    clr_green "Download Bullet"
    rm -f build/tmp/vhacd.zip
    wget -q  https://github.com/bulletphysics/bullet3/archive/2.83.7.zip -O build/tmp/bullet.zip
    mkdir build/tmp/ext
    unzip -q build/tmp/bullet.zip -d  build/tmp/ext
    mv build/tmp/ext/* build/bullet
}

function setPlatformArch {
    PLATFORM=$1
    ARCH=$2
    OUT_PATH="$PWD/build/lib/native/$PLATFORM/$ARCH"
    mkdir -p $OUT_PATH
}

function buildLinux64 {
    buildLinux "x86_64"
}


function buildLinux32 {
    buildLinux "x86"
}

function findCppFiles {
    #Find c++ files
    echo "">build/tmp/cpplist.txt
    find  build/bullet/src/BulletCollision -type f -name '*.cpp' >> build/tmp/cpplist.txt
    find  build/bullet/src/BulletDynamics -type f -name '*.cpp' >> build/tmp/cpplist.txt
    find  build/bullet/src/BulletInverseDynamics -type f -name '*.cpp' >> build/tmp/cpplist.txt
    find  build/bullet/src/BulletSoftBody -type f -name '*.cpp' >> build/tmp/cpplist.txt
    find  build/bullet/src/LinearMath -type f -name '*.cpp' >> build/tmp/cpplist.txt
    find  build/bullet/src/clew -type f -name '*.cpp' >> build/tmp/cpplist.txt
    find  build/tmp/jmonkeyengine/jme3-bullet-native/src/native/cpp/ -type f -name '*.cpp' >> build/tmp/cpplist.txt

}

function buildLinux {
    downloadIfRequired
    setPlatformArch "linux" $1
    clr_green "Compile for $PLATFORM $ARCH..."
    arch_flag="-m64"
    if [ "$1" = "x86" ];
    then
        arch_flag="-m32"
    fi
    
    findCppFiles
    build_script="
    g++ -mtune=generic -DBT_NO_PROFILE=1 -fpermissive -U_FORTIFY_SOURCE -fPIC -O3 $arch_flag -shared
      -Ibuild/bullet/src/
      -I$JDK_ROOT/include
      -I$JDK_ROOT/include/linux
      -Ibuild/tmp/jmonkeyengine/jme3-bullet-native/src/native/cpp -pthread 
      $(cat build/tmp/cpplist.txt)
       -Wl,-soname,bulletjme.so -o $OUT_PATH/libbulletjme.so  -lrt"
    clr_escape "$(echo $build_script)" $CLR_BOLD $CLR_BLUE
    $build_script
    if [ $? -ne 0 ]; then exit 1; fi
}


function buildWindows {
    downloadIfRequired
    setPlatformArch "windows" $1
    clr_green "Compile for $PLATFORM $ARCH..."
    compiler="x86_64-w64-mingw32-g++"
    if [ "$1" = "x86" ];
    then
        compiler="i686-w64-mingw32-g++"
    fi

    findCppFiles


    build_script="
    $compiler -mtune=generic -DBT_NO_PROFILE=1 -fpermissive  -U_FORTIFY_SOURCE -O3 -DWIN32  -shared
       -Ibuild/bullet/src/
        -Ibuild/tmp/jmonkeyengine/jme3-bullet-native/src/native/cpp/fake_win32
        -I$JDK_ROOT/include
      -Ibuild/tmp/jmonkeyengine/jme3-bullet-native/src/native/cpp  -static
      $(cat build/tmp/cpplist.txt)
       -Wl,-soname,bulletjme.dll  -o $OUT_PATH/bulletjme.dll"
    clr_escape "$(echo $build_script)" $CLR_BOLD $CLR_BLUE
    $build_script
    if [ $? -ne 0 ]; then exit 1; fi

}

function buildWindows32 {
    buildWindows "x86"   
}

function buildWindows64 {
    buildWindows "x86-64"   
}

function buildMac32 {
    buildWindows "x86"   
}

function buildMac64 {
    buildWindows "x86_64"   
}


function buildMac {
    downloadIfRequired
    setPlatformArch "osx" $1
    clr_green "Compile for $PLATFORM $ARCH..."

    arch_flag="-arch x86_64"
    if [ "$1" = "x86" ];
    then
        arch_flag="-arch i386"
    fi

    build_script="
    g++ -mtune=generic -DBT_NO_PROFILE=1 -fpermissive $arch_flag -U_FORTIFY_SOURCE -fPIC -O3  -shared
        -Ibuild/bullet/src/
      -Ibuild/tmp/jmonkeyengine/jme3-bullet-native/src/native/cpp 
            -I$JDK_ROOT/include
      -I$JDK_ROOT/include/darwin
       $(cat build/tmp/cpplist.txt)
        -o $OUT_PATH/libbulletjme.dylib"
    clr_escape "$(echo $build_script)" $CLR_BOLD $CLR_BLUE
    $build_script
    if [ $? -ne 0 ]; then exit 1; fi
}

function travis {
    DEPLOY="false"
    VERSION=$TRAVIS_COMMIT
    if [ "$TRAVIS_TAG" != "" ];
    then
        echo "Deploy for $TRAVIS_TAG."
        VERSION=$TRAVIS_TAG
        DEPLOY="true"    
    fi

    echo "Run travis $1"
    if [ "$1" = "deploy" ];
    then
        if [ "$DEPLOY" != "true" ];
        then
            exit 0
        fi  
          
        rm -Rf deploy
        mkdir -p deploy/
        
        out=`curl -u$BINTRAY_USER:$BINTRAY_API_KEY --silent --head --write-out '%{http_code}'  -o deploy/tmpl.tar.gz.h  https://dl.bintray.com/riccardo/jme3-bullet-native-files/$VERSION/libs-winLinux-$VERSION.tar.gz`
        if [ "$out" != "200" ];
        then
            echo "[warning] Windows and Linux libs not found. Skip deploy."
            exit 0
        fi
        
        out=`curl -u$BINTRAY_USER:$BINTRAY_API_KEY --silent --head --write-out '%{http_code}'  -o deploy/tmpm.tar.gz.h https://dl.bintray.com/riccardo/jme3-bullet-native-files/$VERSION/libs-mac-$VERSION.tar.gz`
        if [ "$out" != "200" ];
        then
            echo "[warning] Mac libs not found. Skip deploy."
            exit 0
        fi
        
        curl -u$BINTRAY_USER:$BINTRAY_API_KEY --silent  -o deploy/tmpl.tar.gz https://dl.bintray.com/riccardo/jme3-bullet-native-files/$VERSION/libs-winLinux-$VERSION.tar.gz   
       
        curl -u$BINTRAY_USER:$BINTRAY_API_KEY --silent  -o deploy/tmpm.tar.gz https://dl.bintray.com/riccardo/jme3-bullet-native-files/$VERSION/libs-mac-$VERSION.tar.gz
      
        echo "Deploy!"
    
        rm -Rf buid/tests/
        mkdir -p build/tests
        mkdir -p build/lib/        

        tar -xzf deploy/tmpl.tar.gz -C build/lib/
        tar -xzf deploy/tmpm.tar.gz -C build/lib/
        
        
     #   curl -X PUT  -T  build/release/vhacd-native-$VERSION.jar -u$BINTRAY_USER:$BINTRAY_API_KEY\
       # "https://api.bintray.com/content/riccardo/v-hacd/v-hacd-java-bindings/$VERSION/vhacd/vhacd-native/$VERSION/"
        
                
    else
        if [ "$TRAVIS_OS_NAME" = "linux" ];
        then
            buildLinux32 
            buildLinux64  
            buildWindows32
            buildWindows64
            if [ "$DEPLOY" = "true" ];
            then           
                mkdir -p deploy/
                tar -C build/lib/ -czf deploy/libs-winLinux-$VERSION.tar.gz .
                curl -X PUT  -T  deploy/libs-winLinux-$VERSION.tar.gz -u$BINTRAY_USER:$BINTRAY_API_KEY\
                "https://api.bintray.com/content/riccardo/jme3-bullet-native-files/libs/$VERSION/$VERSION/"
           fi 
        fi
        if [ "$TRAVIS_OS_NAME" = "osx" ];
        then
            buildMac32
            buildMac64
            if [ "$DEPLOY" = "true" ];
            then    
                mkdir -p deploy/
                tar -C build/lib/ -czf deploy/libs-mac-$VERSION.tar.gz .
                curl -X PUT  -T  deploy/libs-mac-$VERSION.tar.gz -u$BINTRAY_USER:$BINTRAY_API_KEY\
                "https://api.bintray.com/content/riccardo/jme3-bullet-native-files/libs/$VERSION/$VERSION/"

            fi 
        fi
    fi
}



function buildAll {
    buildLinux32 
    buildLinux64  
    buildWindows32
    buildWindows64
}

cleanTMP
clr_green "Clone engine..."
git clone https://github.com/riccardobl/jmonkeyengine.git build/tmp/jmonkeyengine
if [ "$1" = "" ];
then
    echo "Usage: make.sh target"
    echo " - Targets: buildAll,buildWindows32,buildWindows64,buildLinux32,buildLinux64,buildMac32,buildMac64,clean"
    exit 0
fi
clr_magenta "Run $1..."
$1 ${*:2}
clr_magenta "Build complete, results are stored in $PWD/build/"
