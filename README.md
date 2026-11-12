# Cotoveleira Inteligente

Aplicativo iOS nativo em SwiftUI para acompanhar séries e repetições. O modo demonstração funciona sem ESP32. O protocolo planejado para o firmware está em [GATT.md](GATT.md).

## Projeto

Requer Xcode 26 e XcodeGen em macOS. Execute `xcodegen generate` e abra `CotoveleiraInteligente.xcodeproj`. Compile para iOS 18 ou superior. No Linux, o projeto iOS não pode ser compilado.

## IPA

O workflow `iOS IPA` do GitHub Actions compila no runner macOS e disponibiliza um IPA sem assinatura nos artifacts. Para instalar no iPhone 16 com Sideloadly, baixe o artifact, extraia o ZIP e selecione o IPA no Sideloadly. A assinatura com um Apple ID gratuito ocorre no computador do usuário; pode exigir renovação periódica e está sujeita às regras da Apple. Nenhuma credencial Apple fica no GitHub.

O modo BLE requer firmware ESP32 compatível com `GATT.md`. A bateria aparece como indisponível se o periférico não oferecer telemetria.
