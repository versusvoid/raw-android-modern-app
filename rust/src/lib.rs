#![no_std]

use core::panic::PanicInfo;
use core::ffi::c_char;

extern crate libc;

mod jni;

#[no_mangle]
pub unsafe extern fn Java_app_raw_MainActivity_hello(env: *mut jni::JNIEnv, _this: jni::jobject) -> jni::jstring {
    let s = b"this is string from rust!\0";
    let f = (&**env).NewStringUTF.unwrap_unchecked();
    f(env, s as *const u8 as *const c_char)
}

#[panic_handler]
#[no_mangle]
pub extern fn rust_begin_panic(_info: &PanicInfo) -> ! {
    unsafe { libc::abort() }
}
