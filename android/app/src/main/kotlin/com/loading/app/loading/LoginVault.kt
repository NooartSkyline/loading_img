package com.loading.app.loading

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object LoginVault {
    private const val alias = "loading_login"
    private const val fileName = "login-vault.bin"

    fun read(context: Context, site: String): Map<String, String>? {
        val item = load(context)?.optJSONObject(site) ?: return null
        val user = item.optString("user").trim()
        val password = item.optString("password")
        if (user.isEmpty() || password.isEmpty()) return null
        return mapOf("user" to user, "password" to password)
    }

    fun write(context: Context, site: String, user: String, password: String) {
        val name = user.trim()
        if (name.isEmpty() || password.isEmpty()) return
        val all = load(context) ?: JSONObject()
        all.put(
            site,
            JSONObject().put("user", name).put("password", password),
        )
        val encrypted = encrypt(all.toString().toByteArray(Charsets.UTF_8))
        context.filesDir.resolve(fileName).writeBytes(encrypted)
    }

    private fun load(context: Context): JSONObject? {
        val file = context.filesDir.resolve(fileName)
        if (!file.exists()) return JSONObject()
        return try {
            JSONObject(String(decrypt(file.readBytes()), Charsets.UTF_8))
        } catch (_: Exception) {
            null
        }
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore")
        store.load(null)
        val existing = store.getKey(alias, null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        val spec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    private fun encrypt(plain: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return cipher.iv + cipher.doFinal(plain)
    }

    private fun decrypt(payload: ByteArray): ByteArray {
        val iv = payload.copyOfRange(0, 12)
        val body = payload.copyOfRange(12, payload.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        return cipher.doFinal(body)
    }
}
