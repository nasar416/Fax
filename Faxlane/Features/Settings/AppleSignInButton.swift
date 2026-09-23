import SwiftUI
import AuthenticationServices

/// Apple's own Sign in with Apple button (required by App Review).
/// Send the identity token to your server to link it with the guest account.
struct AppleSignInButton: View {
    @Environment(\.colorScheme) private var colorScheme
    var onSuccess: (String) -> Void

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            if case .success(let auth) = result, let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                onSuccess(name)
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
    }
}
