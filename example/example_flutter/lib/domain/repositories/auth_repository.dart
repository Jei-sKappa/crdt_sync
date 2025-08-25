abstract interface class AuthRepository {
  AuthRepository();

  Stream<bool> get isAuthenticated;

  Future<void> logIn(
    String email,
    String password,
  );

  Future<void> signUp(
    String email,
    String password,
  );

  Future<void> logOut();

  String? getUserEmail();
}
