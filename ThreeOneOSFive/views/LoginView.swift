import SwiftUI

struct LoginView: View {

    var onLoginSuccess: (String, Date?) -> Void

    @State private var licenseKey: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var keyFieldHeight: CGFloat = 52

    // MARK: - VINI Design Tokens
    private let bgPrimary = Color.black
    private let bgCard = Color(red: 0.11, green: 0.11, blue: 0.12)       // #1C1C1E
    private let accentBlue = Color(red: 0.0, green: 0.62, blue: 1.0)     // #009EFF
    private let textPrimary = Color.white
    private let textSecondary = Color(red: 0.63, green: 0.63, blue: 0.65) // #A1A1A6
    private let borderInactive = Color(red: 0.22, green: 0.22, blue: 0.24) // #38383A

    var body: some View {
        ZStack {
            bgPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: - Icono
                Image(systemName: "key.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(accentBlue)
                    .frame(width: 80, height: 80)
                    .background(bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Spacer().frame(height: 28)

                // MARK: - Título
                Text("Ingresar licencia")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(textPrimary)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 10)

                // MARK: - Subtítulo
                Text("Activa tu cuenta con una clave de licencia")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer().frame(height: 36)

                // MARK: - Campo de licencia
                VStack(alignment: .leading, spacing: 8) {
                    Text("CLAVE DE LICENCIA")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textSecondary)
                        .tracking(0.8)

                    TextField("", text: $licenseKey)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(textPrimary)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .frame(height: keyFieldHeight)
                        .background(bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(licenseKey.isEmpty ? borderInactive : accentBlue.opacity(0.6), lineWidth: 1)
                        )
                        .onChange(of: licenseKey) { _ in
                            errorMessage = nil
                        }
                }
                .padding(.horizontal, 24)

                // MARK: - Error
                if let errorMessage {
                    Spacer().frame(height: 12)

                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .regular))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.23, blue: 0.19)) // #FF3B30
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }

                Spacer().frame(height: 28)

                // MARK: - Botón activar
                Button {
                    handleLogin()
                } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.9)
                        } else {
                            Text("Activar")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canSubmit ? accentBlue : accentBlue.opacity(0.35))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                }
                .disabled(!canSubmit || isLoading)
                .padding(.horizontal, 24)

                Spacer().frame(height: 12)

                // MARK: - Hint
                Text("Tu licencia se vincula a este dispositivo")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(textSecondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        !licenseKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func handleLogin() {
        errorMessage = nil
        isLoading = true

        LoginManager.login(licenseKey: licenseKey) { success, message, expiresAt in
            DispatchQueue.main.async {
                isLoading = false
                if success {
                    onLoginSuccess(licenseKey, expiresAt)
                } else {
                    errorMessage = message
                }
            }
        }
    }
}

#Preview {
    LoginView(onLoginSuccess: { _, _ in })
}
