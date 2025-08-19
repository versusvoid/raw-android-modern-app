#!/bin/sh

set -ex

ANDROID_HOME=/opt/android-sdk
BUILD_TOOLS="$ANDROID_HOME/build-tools/35.0.1"
PLATFORM="$ANDROID_HOME/platforms/android-35"
NDK="$ANDROID_HOME/ndk/26.1.10909125/toolchains/llvm/prebuilt/linux-x86_64"

rm -rf build
mkdir -p build/{res,res-java,res-class,class,dex}

# Compiling .xml resources into binary .flat format
"$BUILD_TOOLS/aapt2" compile res/*/*.xml -o build/res

# Linking .flat resources and manifest into proto-apk
# Generating R.java as side-effect
"$BUILD_TOOLS/aapt2" link \
    -o build/raw.unaligned.apk \
    --manifest AndroidManifest.xml \
    -I "$PLATFORM/android.jar" \
    --java build/res-java \
    -v \
    build/res/*.flat

# Compiling R.java into R.class
javac \
    -classpath "$PLATFORM/android.jar" \
    -d build/res-class \
    build/res-java/app/raw/*.java

# Compiling kotlin code into .class
kotlinc \
    -classpath "$PLATFORM/android.jar:build/res-class" \
    -no-jdk \
    -Xno-param-assertions \
    -Xno-call-assertions \
    -Xno-receiver-assertions \
    -d build/class \
    kotlin/app/raw/*.kt

# Compiling all the .class and kotlin-stdlib into classes.dex
java -cp "$BUILD_TOOLS/lib/d8.jar" com.android.tools.r8.R8 \
    --classpath "$PLATFORM/android.jar" \
    --output build/dex \
    --pg-conf proguard.txt \
    --no-minification \
    --no-data-resources \
    /usr/share/kotlin/lib/kotlin-stdlib.jar \
    /usr/share/kotlin/lib/annotations-13.0.jar \
    build/res-class/app/raw/*.class \
    build/class/app/raw/*.class

# Adding classes.dex to the root of .apk
zip --junk-paths build/raw.unaligned.apk build/dex/classes.dex

pushd rust
# Pointing bindgen to NDK to search for jni.h
export BINDGEN_EXTRA_CLANG_ARGS="--sysroot='$NDK/sysroot'"

# Building native library for every architecture
cargo build --release --target aarch64-linux-android \
        --config target.aarch64-linux-android.linker=\"$NDK/bin/aarch64-linux-android21-clang\"

cargo build --release --target armv7-linux-androideabi \
        --config target.armv7-linux-androideabi.linker=\"$NDK/bin/armv7a-linux-androideabi21-clang\"

cargo build --release --target i686-linux-android \
        --config target.i686-linux-android.linker=\"$NDK/bin/i686-linux-android21-clang\"

cargo build --release --target x86_64-linux-android \
        --config target.x86_64-linux-android.linker=\"$NDK/bin/x86_64-linux-android21-clang\"
popd

# Prepearing directory structure with native libraries for .apk
mkdir -p build/lib/{arm64-v8a,armeabi-v7a,x86,x86_64}
cp rust/target/aarch64-linux-android/release/libraw.so build/lib/arm64-v8a/
cp rust/target/armv7-linux-androideabi/release/libraw.so build/lib/armeabi-v7a/
cp rust/target/i686-linux-android/release/libraw.so build/lib/x86/
cp rust/target/x86_64-linux-android/release/libraw.so build/lib/x86_64/

pushd build
# Adding native libraries for all architectures to .apk
zip raw.unaligned.apk -r lib

# Aligning .apk (which is at it's core just a .zip file)
"$BUILD_TOOLS/zipalign" -v -p 4 raw.unaligned.apk raw.unsigned.apk

# Generating key for signing the .apk
keytool -genkeypair \
    -keystore keystore.jks \
    -alias androidkey \
    -validity 10000 \
    -keyalg EC \
    -storepass android \
    -keypass android \
    -dname 'CN=app.raw'

# Signing the .apk
"$BUILD_TOOLS/apksigner" sign \
    --ks keystore.jks \
    --ks-key-alias androidkey \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out raw.apk \
    raw.unsigned.apk

set +e

# Trying to install complete .apk to connected device or emulator
adb install -r raw.apk && adb shell am start -n app.raw/.MainActivity
