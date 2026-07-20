package com.ishinadwelly.native_notification_plugin

import android.content.Context
import android.content.SharedPreferences
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import androidx.annotation.Keep
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.google.gson.annotations.SerializedName
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Call
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Path
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * Data class representing the WhatsApp-style reply payload sent to the Spring Boot API.
 */
@Keep
data class ReplyRequest(
    @SerializedName("chatId") val chatId: String,
    @SerializedName("receiverId") val receiverId: String,
    @SerializedName("message") val message: String,
    @SerializedName("clientMessageId") val clientMessageId: String? = null
)

/**
 * Alternative/Queue payload supporting Dwelly Spring Boot endpoint structure.
 */
@Keep
data class QueueReplyRequest(
    @SerializedName("content") val content: String,
    @SerializedName("messageType") val messageType: String = "TEXT",
    @SerializedName("clientMessageId") val clientMessageId: String? = null
)

@Keep
data class ReplyResponse(
    @SerializedName("status") val status: String?,
    @SerializedName("messageId") val messageId: String?,
    @SerializedName("createdAt") val createdAt: String?
)

@Keep
data class TokenRefreshRequest(
    @SerializedName("refreshToken") val refreshToken: String
)

@Keep
data class TokenRefreshResponse(
    @SerializedName("token") val token: String?,
    @SerializedName("refreshToken") val refreshToken: String?
)


/**
 * Retrofit interface defining our Spring Boot backend endpoints.
 */
interface SpringApiService {
    @POST("messages/reply")
    fun sendReply(
        @Header("Authorization") authorization: String,
        @Body request: ReplyRequest
    ): Call<ReplyResponse>

    // Support for Dwelly Spring Boot conversation queue endpoint
    @POST("conversations/{conversationId}/messages/queue")
    fun sendConversationQueuedReply(
        @Path("conversationId") conversationId: String,
        @Header("Authorization") authorization: String,
        @Body request: QueueReplyRequest
    ): Call<ReplyResponse>

    // Support for synchronous Dwelly Spring Boot conversation message endpoint
    @POST("conversations/{conversationId}/messages")
    fun sendConversationSyncReply(
        @Path("conversationId") conversationId: String,
        @Header("Authorization") authorization: String,
        @Body request: QueueReplyRequest
    ): Call<ReplyResponse>

    @POST("auth/refresh")
    fun refreshToken(
        @Body request: TokenRefreshRequest
    ): Call<TokenRefreshResponse>
}

/**
 * Secure token manager using Android EncryptedSharedPreferences (Hardware AES-256-GCM).
 * Also bridges tokens written by Flutter in standard SharedPreferences ("FlutterSharedPreferences" / "auth_token").
 */
class SecureTokenManager(private val context: Context) {

    private val encryptedPrefs: SharedPreferences by lazy {
        try {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            EncryptedSharedPreferences.create(
                context,
                "secret_auth_prefs",
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (e: Exception) {
            // Fallback if Keystore hardware encryption fails on older devices or customized ROMs
            context.getSharedPreferences("secure_auth_prefs_fallback", Context.MODE_PRIVATE)
        }
    }

    // Flutter stores tokens in standard SharedPreferences (or FlutterSharedPreferences) under "flutter.auth_token" / "auth_token"
    private val flutterPrefs: SharedPreferences by lazy {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    }

    private val defaultPrefs: SharedPreferences by lazy {
        context.getSharedPreferences(context.packageName + "_preferences", Context.MODE_PRIVATE)
    }

    fun saveToken(token: String, refreshToken: String? = null) {
        encryptedPrefs.edit().apply {
            putString(KEY_JWT_TOKEN, token)
            if (refreshToken != null) {
                putString(KEY_REFRESH_TOKEN, refreshToken)
            }
            apply()
        }
    }

    fun getToken(): String? {
        var token = encryptedPrefs.getString(KEY_JWT_TOKEN, null)
        if (!token.isNullOrEmpty()) return token

        // Check if Flutter wrote it with "flutter." prefix or direct prefix
        token = flutterPrefs.getString("flutter.auth_token", null)
            ?: flutterPrefs.getString("auth_token", null)
            ?: defaultPrefs.getString("auth_token", null)

        if (!token.isNullOrEmpty()) {
            saveToken(token)
        }
        return token
    }

    fun getRefreshToken(): String? {
        var token = encryptedPrefs.getString(KEY_REFRESH_TOKEN, null)
        if (!token.isNullOrEmpty()) return token

        token = flutterPrefs.getString("flutter.auth_refresh_token", null)
            ?: flutterPrefs.getString("auth_refresh_token", null)
            ?: defaultPrefs.getString("auth_refresh_token", null)

        return token
    }

    fun getApiBaseUrl(): String {
        var baseUrl = encryptedPrefs.getString(KEY_API_BASE_URL, null)
            ?: flutterPrefs.getString("flutter.api_base_url", null)
            ?: flutterPrefs.getString("api_base_url", null)
            ?: defaultPrefs.getString("api_base_url", null)
            ?: DEFAULT_BASE_URL

        baseUrl = baseUrl.trim()
        if (baseUrl.endsWith("/")) {
            baseUrl = baseUrl.substring(0, baseUrl.length - 1)
        }
        if (!baseUrl.endsWith("/api")) {
            baseUrl = "$baseUrl/api"
        }
        return "$baseUrl/"
    }

    fun saveApiBaseUrl(baseUrl: String) {
        encryptedPrefs.edit().putString(KEY_API_BASE_URL, baseUrl).apply()
    }

    fun clearTokens() {
        encryptedPrefs.edit().remove(KEY_JWT_TOKEN).remove(KEY_REFRESH_TOKEN).apply()
    }

    companion object {
        private const val KEY_JWT_TOKEN = "jwt_bearer_token"
        private const val KEY_REFRESH_TOKEN = "jwt_refresh_token"
        private const val KEY_API_BASE_URL = "api_base_url"
        private const val DEFAULT_BASE_URL = "https://api.ishinadwelly.com/api/"
    }
}

/**
 * Singleton API Client supporting automatic JWT attachment, 401 token refresh, and network validation.
 */
object ApiClient {
    private var retrofitInstance: Retrofit? = null
    private var currentBaseUrl: String = ""

    fun getService(context: Context): SpringApiService {
        val tokenManager = SecureTokenManager(context.applicationContext)
        val baseUrl = tokenManager.getApiBaseUrl()

        if (retrofitInstance == null || currentBaseUrl != baseUrl) {
            currentBaseUrl = baseUrl

            val loggingInterceptor = HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BODY
            }

            val authInterceptor = Interceptor { chain ->
                val originalRequest = chain.request()
                val token = tokenManager.getToken()

                val requestBuilder = originalRequest.newBuilder()
                if (!token.isNullOrEmpty() && originalRequest.header("Authorization") == null) {
                    requestBuilder.header("Authorization", "Bearer $token")
                }
                requestBuilder.header("Accept", "application/json")
                requestBuilder.header("Content-Type", "application/json")

                var response = chain.proceed(requestBuilder.build())

                // Automatically handle expired tokens (HTTP 401 / 403)
                if (response.code == 401 || response.code == 403) {
                    synchronized(this) {
                        val refreshToken = tokenManager.getRefreshToken()
                        if (!refreshToken.isNullOrEmpty()) {
                            response.close()

                            try {
                                val refreshService = getRefreshService(baseUrl)
                                val refreshCall = refreshService.refreshToken(TokenRefreshRequest(refreshToken))
                                val refreshResponse = refreshCall.execute()

                                if (refreshResponse.isSuccessful && refreshResponse.body() != null) {
                                    val newToken = refreshResponse.body()!!.token
                                    val newRefresh = refreshResponse.body()!!.refreshToken
                                    if (!newToken.isNullOrEmpty()) {
                                        tokenManager.saveToken(newToken, newRefresh)
                                        val newRequest = originalRequest.newBuilder()
                                            .header("Authorization", "Bearer $newToken")
                                            .header("Accept", "application/json")
                                            .header("Content-Type", "application/json")
                                            .build()
                                        response = chain.proceed(newRequest)
                                    }
                                }
                            } catch (e: Exception) {
                                e.printStackTrace()
                            }
                        }
                    }
                }
                response
            }

            val okHttpClient = OkHttpClient.Builder()
                .addInterceptor(authInterceptor)
                .addInterceptor(loggingInterceptor)
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(15, TimeUnit.SECONDS)
                .writeTimeout(15, TimeUnit.SECONDS)
                .build()

            retrofitInstance = Retrofit.Builder()
                .baseUrl(baseUrl)
                .client(okHttpClient)
                .addConverterFactory(GsonConverterFactory.create())
                .build()
        }
        return retrofitInstance!!.create(SpringApiService::class.java)
    }

    private fun getRefreshService(baseUrl: String): SpringApiService {
        val okHttp = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .build()
        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(okHttp)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(SpringApiService::class.java)
    }

    /**
     * Production-ready connectivity validation helper.
     */
    fun isNetworkAvailable(context: Context): Boolean {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = connectivityManager.activeNetwork ?: return false
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
            return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        } else {
            @Suppress("DEPRECATION")
            val networkInfo = connectivityManager.activeNetworkInfo
            return networkInfo != null && networkInfo.isConnected
        }
    }
}
