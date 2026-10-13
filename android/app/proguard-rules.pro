# ============================================================================
# R8 / ProGuard rules — sirf RELEASE build par lagte hain (debug me minify off).
#
# Flutter ka Gradle plugin (packages/flutter_tools/gradle FlutterPlugin.kt)
# release build type me khud:
#   isMinifyEnabled = true, isShrinkResources = true,
#   proguard-android-optimize.txt + flutter_proguard_rules.pro
# aur agar yeh file maujood ho to use bhi add kar leta hai. Isliye yahan sirf
# wahi rules hain jo *reflection / runtime-naam-se-lookup* par depend karte hain
# — static analysis unhe "useless" samajh kar class ka naam badal deti hai aur
# app install ke baad crash karti hai (debug me sab theek dikhta hai).
#
# Yahan likhe rules ke bina: Settings me API key save karna release APK me
# "Missing class ..." / NoSuchMethodError ke saath toot sakta hai.
# ============================================================================

# flutter_secure_storage (Settings me API key isise store hoti hai).
# Cipher class (RSA/AES) ka chunav runtime par hota hai, Android Keystore ke
# saath milkar chalti hai — poora plugin keep.
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Plugin ke andar androidx.security (EncryptedSharedPreferences) bhi use hota
# hai; ye AAR apne consumer rules ke saath aata hai, par R8 optimize mode me
# iske inner classes ke constructor hat sakte hain.
-keep class androidx.security.crypto.** { *; }

# In classes ke optional imports R8 ko warn kar sakte hain (purane Android par
# available nahi) — warning failure nahi honi chahiye.
-dontwarn com.it_nomads.fluttersecurestorage.**
-dontwarn androidx.security.crypto.**
