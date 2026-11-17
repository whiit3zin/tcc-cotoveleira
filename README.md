# Cotoveleira Inteligente Bluetooth

Para gerar e conferir o IPA com o widget preservado, consulte [metadados e instalação pelo Sideloadly](docs/ipa-sideloadly.md).

App SwiftUI iOS 18+ e ESP32 Arduino 3.x. Referência exclusiva de firmware: `CotoveleiraESP32-Serial.ino`. O ESP32 processa o sensor e valida repetições; iPhone cuida da interface, histórico SwiftData e Core Haptics. Temas Sistema/Claro/Escuro e identidade visual preservados.

## Hardware e algoritmo

| Ligação | Configuração |
|---|---|
| Sensor flex | GPIO34, divisor com resistor 100 kΩ |
| Bateria | GPIO35, divisor 1:1 |
| Calibração referência | estendido 2570, flexionado 570 |

Use terra comum e sinais compatíveis com ESP32; GPIO35 recebe metade da tensão da bateria. OLED e buzzer foram removidos; feedback no Taptic Engine concentra a interface no iPhone.

Preservados: 40 amostras, média dos 20 valores centrais, EMA 0,15, zona morta 30 ADC; sequência extensão → flexão → extensão, estabilidade 100 ms, limiares 20/80%, duração 350–8000 ms e intervalo mínimo 1000 ms. Mede flexão, não postura clínica. Calibração personalizada persiste em NVS; sem valores salvos usa referência. `x` apaga e invalida na sessão; próximo boot volta à referência.

## Uso e energia

Conecte na aba Dispositivo, ligue virtualmente e inicie treino. Standby suspende sensor, contagem e diagnóstico; BLE permanece e bateria atualiza em 60 s (5 s ligado). Não corta energia elétrica. Finalize treino antes de usar o controle de standby do app. Firmware continua autônomo desconectado. Na reconexão o app recebe contagem, configuração e descanso; horário inicial reconstruído é o momento observado pelo app. [Contrato GATT](GATT.md).

Repetição correta gera um pulso forte; erro dois pulsos separados por 160 ms; série três pulsos separados por 200 ms; próxima série dois pulsos separados por 80 ms; treino cinco pulsos até 950 ms. Core Haptics usa intensidade/nitidez 1 nos eventos de treino, com fallback UIKit heavy/rigid. Eventos de conclusão têm prioridade e substituem os anteriores, com janela de coordenação de 40 ms. Ajustes inclui preferência persistente e permissão opcional para notificações. [Implementação e validação háptica](docs/haptic-feedback.md).

## Engenharia

Cinco toques na versão ao final de Ajustes, com menos de 2 s entre toques, abrem o menu. Não persiste desbloqueio entre execuções. Modo desenvolvedor exibe Swift Charts, ADC bruto médio/filtrado, calibração, filtros, máquina de estados, extremos, amplitude, RSSI, bateria, frequência, horários e eventos com motivos. Copiar, limpar, reiniciar extremos e testar padrões estão no painel. Diagnóstico é desativado ao sair; memória limitada a 300 amostras/200 eventos.

Demonstração só é selecionável no menu e não persiste. Inicie treino na aba Treino; avanço automático e manual, erro, sinal/flexão, bateria e energia simulados estão disponíveis. Dados são identificados como simulados, com gráfico/registros separados e sessões marcadas por origem; comandos de treino não chegam ao ESP32. O desligamento do stream real na transição é um comando de controle de diagnóstico.

## Serial e compilação

115200 baud, menu/status automáticos no boot. `h/?` menu; `i` status; `l` logs; `1/0` ligar/standby; `r/f` iniciar/finalizar; `p` padrão; `e/d` calibrar estendido/flexionado; `x` apagar; `t` simular repetição em treino; `b/s` erro/série ligado. Leituras contínuas a cada 400 ms ligado com logs ativos, independentemente do app. Calibração exige ligado e treino encerrado. Simulações seriais são testes explícitos de bancada.

Arduino: copie o arquivo para pasta `CotoveleiraESP32-Serial` de mesmo nome do sketch, selecione ESP32 Dev Module, core 3.x, compile e grave. BLE e Preferences vêm com o core.

macOS: Xcode 26 e XcodeGen; execute `xcodegen generate`, abra `CotoveleiraInteligente.xcodeproj`, compile/teste esquema CotoveleiraInteligente. Inclui extensão WidgetKit para Live Activity. Configure assinatura dos dois targets para instalar. Workflow existente gera IPA sem assinatura e executa XCTest quando publicado com autorização.

Windows: `py scripts/verify_integration.py`, `git diff --check`. Checks de fontes/metadados não substituem compilação. Xcode, Swift, Arduino CLI e compilador C++ estavam indisponíveis nesta execução. XCTest, layout, compilação iOS/ESP32 e testes físicos permanecem necessários.

Valide fisicamente: circuito/tensão; `p`, `e/d`, reinício/NVS; movimento completo e rejeições; compare app/serial; standby e intervalos bateria; entrada/saída diagnóstico; padrões, última série/fim treino; desconexão/reconexão e reboot ESP32; tela bloqueada e retorno; notificações permitidas/negadas; temas/texto grande. Execute XCTest no macOS.

## Restrições do iOS

CoreBluetooth usa `bluetooth-central` e restauração com identificador. Sistema controla execução e relançamento; encerramento forçado não garante restauração. Eventos perdidos desconectado não são recuperados. Nenhum mecanismo mantém execução permanente.

[Core Haptics pode parar em segundo plano](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics). App inativo usa notificações locais; permissão, Foco, silencioso e ajustes determinam apresentação/vibração. Não há garantia de padrão Taptic personalizado com tela bloqueada. Desligar feedback desliga também esse fallback.

[Live Activities usam ActivityKit e WidgetKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities). Iniciam em primeiro plano, mostram série/repetições/fase e ficam desatualizadas após 15 s sem atualização. Dependem da execução concedida ao app/BLE; sem servidor/APNs. Validar extensão e comportamento em iPhone físico.
