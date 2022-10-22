#!/bin/sh

set -ex

ANDROID_HOME=/opt/android-sdk
BUILD_TOOLS="$ANDROID_HOME/build-tools/33.0.0"
PLATFORM="$ANDROID_HOME/platforms/android-33"
NDK="$ANDROID_HOME/ndk/25.1.8937393/toolchains/llvm/prebuilt/linux-x86_64"

rm -rf build
mkdir -p build/{res,res-java,res-class,class,dex}

"$BUILD_TOOLS/aapt2" compile res/*/*.xml -o build/res

"$BUILD_TOOLS/aapt2" link \
    -o build/raw.unaligned.apk \
    --manifest AndroidManifest.xml \
    -I "$PLATFORM/android.jar" \
    --java build/res-java \
    -v \
    build/res/*.flat

javac \
    -classpath "$PLATFORM/android.jar" \
    -d build/res-class \
    build/res-java/app/raw/*.java

kotlinc \
    -classpath "$PLATFORM/android.jar:build/res-class" \
    -no-jdk \
    -Xno-param-assertions \
    -Xno-call-assertions \
    -Xno-receiver-assertions \
    -d build/class \
    kotlin/app/raw/*.kt

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

zip --junk-paths build/raw.unaligned.apk build/dex/classes.dex

pushd rust
export BINDGEN_EXTRA_CLANG_ARGS="--sysroot='$NDK/sysroot'"

SEP=$'\x1f'
export CARGO_ENCODED_RUSTFLAGS="-C${SEP}linker=$NDK/bin/aarch64-linux-android33-clang"
cargo build --release --target aarch64-linux-android

export CARGO_ENCODED_RUSTFLAGS="-C${SEP}linker=$NDK/bin/armv7a-linux-androideabi33-clang"
cargo build --release --target armv7-linux-androideabi

export CARGO_ENCODED_RUSTFLAGS="-C${SEP}linker=$NDK/bin/i686-linux-android33-clang"
cargo build --release --target i686-linux-android

export CARGO_ENCODED_RUSTFLAGS="-C${SEP}linker=$NDK/bin/x86_64-linux-android33-clang"
cargo build --release --target x86_64-linux-android
popd

mkdir -p build/lib/{arm64-v8a,armeabi-v7a,x86,x86_64}
cp rust/target/aarch64-linux-android/release/libraw.so build/lib/arm64-v8a/
cp rust/target/armv7-linux-androideabi/release/libraw.so build/lib/armeabi-v7a/
cp rust/target/i686-linux-android/release/libraw.so build/lib/x86/
cp rust/target/x86_64-linux-android/release/libraw.so build/lib/x86_64/

pushd build
zip raw.unaligned.apk -r lib

"$BUILD_TOOLS/zipalign" -v -p 4 raw.unaligned.apk raw.unsigned.apk

keytool -genkeypair \
    -keystore keystore.jks \
    -alias androidkey \
    -validity 10000 \
    -keyalg EC \
    -storepass android \
    -keypass android \
    -dname 'CN=app.raw'

"$BUILD_TOOLS/apksigner" sign \
    --ks keystore.jks \
    --ks-key-alias androidkey \
    --ks-pass pass:android \
    --key-pass pass:android \
    --out raw.apk \
    raw.unsigned.apk

set +e
adb install -r raw.apk && adb shell am start -n app.raw/.MainActivity
