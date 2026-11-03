import SwiftUI

struct AuthSuccessScreen: View {
    var body: some View {
        ContentUnavailableView {
            Label("Авторизация успешна", systemImage: "checkmark.circle.fill")
        } description: {
            Text("Ответ получен от gRPC-сервера. Локальный mock-режим не создаёт учётную запись.")
        }
        .accessibilityIdentifier("auth.success")
        .navigationTitle("CarSharing")
    }
}
