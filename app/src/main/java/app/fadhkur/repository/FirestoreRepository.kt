package app.fadhkur.repository

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow

class FirestoreRepository(
    private val db: FirebaseFirestore = FirebaseFirestore.getInstance()
) {

    /**
     * Saves user profile metadata to Firestore: users/{userId}
     */
    fun saveUserProfile(
        userId: String,
        email: String,
        displayName: String? = null,
        onResult: (Result<Unit>) -> Unit
    ) {
        val userMap = hashMapOf(
            "email" to email,
            "displayName" to (displayName ?: ""),
            "updatedAt" to System.currentTimeMillis()
        )

        db.collection("users").document(userId)
            .set(userMap, SetOptions.merge())
            .addOnSuccessListener {
                onResult(Result.success(Unit))
            }
            .addOnFailureListener { exception ->
                onResult(Result.failure(exception))
            }
    }

    /**
     * Fetches user profile from Firestore.
     */
    fun getUserProfile(
        userId: String,
        onResult: (Result<Map<String, Any>?>) -> Unit
    ) {
        db.collection("users").document(userId)
            .get()
            .addOnSuccessListener { documentSnapshot ->
                if (documentSnapshot.exists()) {
                    onResult(Result.success(documentSnapshot.data))
                } else {
                    onResult(Result.success(null))
                }
            }
            .addOnFailureListener { exception ->
                onResult(Result.failure(exception))
            }
    }

    /**
     * Syncs user favorites (stations/reciters/surahs) to Firestore.
     */
    fun syncFavorites(
        userId: String,
        favoriteIds: Set<String>,
        onResult: ((Result<Unit>) -> Unit)? = null
    ) {
        val data = hashMapOf(
            "favoriteIds" to favoriteIds.toList(),
            "lastSyncedAt" to System.currentTimeMillis()
        )

        db.collection("users").document(userId)
            .set(data, SetOptions.merge())
            .addOnSuccessListener {
                onResult?.invoke(Result.success(Unit))
            }
            .addOnFailureListener { exception ->
                onResult?.invoke(Result.failure(exception))
            }
    }

    /**
     * Real-time listener for user favorites using Kotlin Flow.
     */
    fun observeFavorites(userId: String): Flow<Set<String>> = callbackFlow {
        val listener = db.collection("users").document(userId)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    close(error)
                    return@addSnapshotListener
                }

                if (snapshot != null && snapshot.exists()) {
                    @Suppress("UNCHECKED_CAST")
                    val list = snapshot.get("favoriteIds") as? List<String> ?: emptyList()
                    trySend(list.toSet())
                } else {
                    trySend(emptySet())
                }
            }

        awaitClose { listener.remove() }
    }
}
