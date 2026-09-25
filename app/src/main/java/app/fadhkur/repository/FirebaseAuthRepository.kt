package app.fadhkur.repository

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class FirebaseAuthRepository(
    private val auth: FirebaseAuth = FirebaseAuth.getInstance()
) {
    private val _currentUserState = MutableStateFlow<FirebaseUser?>(auth.currentUser)
    val currentUserState: StateFlow<FirebaseUser?> = _currentUserState.asStateFlow()

    private val authStateListener = FirebaseAuth.AuthStateListener { firebaseAuth ->
        _currentUserState.value = firebaseAuth.currentUser
    }

    init {
        auth.addAuthStateListener(authStateListener)
    }

    val currentUser: FirebaseUser?
        get() = auth.currentUser

    val isUserSignedIn: Boolean
        get() = auth.currentUser != null

    /**
     * Registers a new user using Email and Password authentication.
     */
    fun signUpWithEmailAndPassword(
        email: String,
        password: String,
        onResult: (Result<FirebaseUser>) -> Unit
    ) {
        if (email.isBlank() || password.isBlank()) {
            onResult(Result.failure(IllegalArgumentException("البريد الإلكتروني وكلمة المرور مطلوبة")))
            return
        }

        auth.createUserWithEmailAndPassword(email, password)
            .addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    val user = auth.currentUser
                    if (user != null) {
                        onResult(Result.success(user))
                    } else {
                        onResult(Result.failure(Exception("لم يتم العثور على بيانات المستخدم بعد التسجيل")))
                    }
                } else {
                    val exception = task.exception ?: Exception("فشل إنشاء الحساب")
                    onResult(Result.failure(exception))
                }
            }
    }

    /**
     * Signs in an existing user using Email and Password.
     */
    fun signInWithEmailAndPassword(
        email: String,
        password: String,
        onResult: (Result<FirebaseUser>) -> Unit
    ) {
        if (email.isBlank() || password.isBlank()) {
            onResult(Result.failure(IllegalArgumentException("يرجى إدخال البريد الإلكتروني وكلمة المرور")))
            return
        }

        auth.signInWithEmailAndPassword(email, password)
            .addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    val user = auth.currentUser
                    if (user != null) {
                        onResult(Result.success(user))
                    } else {
                        onResult(Result.failure(Exception("تعذر تسجيل الدخول")))
                    }
                } else {
                    val exception = task.exception ?: Exception("خطأ في تسجيل الدخول")
                    onResult(Result.failure(exception))
                }
            }
    }

    /**
     * Signs out the current user.
     */
    fun signOut() {
        auth.signOut()
    }

    /**
     * Sends a password reset email.
     */
    fun sendPasswordResetEmail(email: String, onResult: (Result<Unit>) -> Unit) {
        if (email.isBlank()) {
            onResult(Result.failure(IllegalArgumentException("البريد الإلكتروني مطلوب")))
            return
        }

        auth.sendPasswordResetEmail(email)
            .addOnCompleteListener { task ->
                if (task.isSuccessful) {
                    onResult(Result.success(Unit))
                } else {
                    val exception = task.exception ?: Exception("تعذر إرسال رابط إعادة تعيين كلمة المرور")
                    onResult(Result.failure(exception))
                }
            }
    }
}
