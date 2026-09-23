import SwiftUI
import AuthenticationServices

/// Apple's own Sign in with Apple button (required by App Review).
/// Send the identity token to your server to link it with the guest account.
struct AppleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Name (may be empty after the first sign-in) and the identity token for the server.
    var onSuccess: (_ name: String, _ identityToken: String?) -> Void

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            if case .success(let auth) = result, let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                let token = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
                onSuccess(name, token)
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
    }
}
