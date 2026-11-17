# Feedback háptico do treino

## Causa e correção

O firmware incrementava a repetição sem emitir um evento específico; o receptor
iOS aceitava somente os tipos 1–4. O serviço tinha intensidade 1, mas nitidez
0,4 na maioria dos padrões, sem fallback UIKit e sem handlers de parada/reset.
Ele enfileirava padrões pelo horário de término, adicionando latência e tocando
série e treino consecutivamente na conclusão. A sensação física de fraqueza não
foi medida; os limites do Taptic Engine não podem ser excedidos por software.

`repetitionCorrect()` agora emite tipo 5/motivo 0 antes dos eventos 2/4, inclusive
na última repetição. O pacote continua sendo versão/tipo/motivo/UInt32 LE, sete
bytes, com os mesmos UUIDs. Calibração, NVS, filtros e os outros pacotes não mudam.

No iOS, `WorkoutFeedbackCoordinator` valida, deduplica e roteia eventos; o estado
atualiza os contadores sem gerar outro pulso quando o tipo 5 já foi identificado.
Firmware antigo usa avanço de estado com atraso de 120 ms, cancelado por tipo 5.
A primeira leitura/reconexão estabelece uma base e não inventa repetições.
Um primeiro 5 tardio até 800 ms após o fallback é descartado como já atendido.
Isso depende do intervalo mínimo de repetição de 1000 ms do firmware; o pacote
não permite correlacionar perfeitamente estados/eventos com atrasos arbitrários.

Pausa, término manual, standby, desconexão e troca de modo cancelam feedback
pendente. Reconexão repete descoberta e inscrição e redefine a sequência.
O ponteiro do periférico é restaurado no `didConnect` da reconexão automática.

## Padrões e motor

| Evento | Instantes dos pulsos (segundos) |
|---|---|
| Correta | 0 |
| Incorreta | 0 / 0,16 |
| Série | 0 / 0,20 / 0,40 |
| Próxima série | 0 / 0,08 |
| Treino concluído | 0 / 0,15 / 0,35 / 0,65 / 0,95 |

Os eventos de treino usam transientes com intensidade 1 e nitidez 1. O motor é
reutilizado, preparado ao ativar o app/conectar/iniciar, reiniciado após parada,
e seus players são descartados após reset. Handlers retornam ao MainActor.
Falhas e ausência de suporte encaminham a UIKit heavy/rigid; no primeiro pulso
da conclusão, o fallback usa a notificação de sucesso do UIKit.

Há uma janela de 40 ms para reunir o burst 5/2/4 antes do primeiro pulso.
Assim, a série substitui a repetição final e a conclusão substitui a série.
Conclusões que cheguem depois dessa janela interrompem o padrão anterior; um
pulso já produzido não pode ser desfeito. Não há players simultâneos nem fila
de feedback atrasado; prioridades inferiores são descartadas enquanto a
conclusão estiver ativa. Fallbacks UIKit também são canceláveis.

Com o app inativo/tela bloqueada, Core Haptics não oferece garantia de padrões
personalizados. Erros e transições de série/treino usam notificações locais
opcionais; som/vibração dependem de permissão, Foco e ajustes do iOS. Não é
enviada uma notificação a cada repetição. Ajustes > Feedback háptico desativa
também esse caminho. A API confirma início do player, não movimento físico.

## Compilar e instalar

1. ESP32: copie `CotoveleiraESP32-Serial.ino` para uma pasta com esse mesmo nome,
   abra no Arduino IDE com ESP32 Dev Module/core Arduino ESP32 3.x, compile e
   grave na placa. Use o monitor serial a 115200. Bibliotecas BLE/Preferences
   vêm com o core. O pino do flex continua GPIO34.
2. iOS: em macOS com Xcode 26/XcodeGen, execute `xcodegen generate` e abra
   `CotoveleiraInteligente.xcodeproj`. Selecione o esquema de mesmo nome, configure
   o Team nos targets do app/widget e compile para o iPhone. Para o IPA sem
   assinatura usado pelo Sideloadly, siga [o procedimento de IPA](ipa-sideloadly.md).
   Esta alteração não executa nem publica o workflow automaticamente.
3. Execute os testes Swift em simulador com o runtime correspondente instalado:

```sh
xcodebuild -project CotoveleiraInteligente.xcodeproj -scheme CotoveleiraInteligente -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

## Procedimento no iPhone físico

1. Ative Feedback háptico em Ajustes e mantenha o app em primeiro plano.
   Toque cinco vezes na versão para abrir Engenharia; ative Modo desenvolvedor.
2. Em Testes hápticos, toque em cada padrão, aguardando 2 segundos entre testes:
   correta (1), incorreta (2), série (3), próxima série (duplo rápido), treino (5).
   Confirme a distinção física e confira Mecanismo/Diagnóstico háptico.
3. Fora do modo demonstração, conecte a placa e procure no log BLE:
   conexão estabelecida, eventos encontrados e notificações habilitadas para
   `4F1B0006…`. Configure 2 séries de 2 repetições e descanso de 5 segundos.
4. Ligue e inicie. Faça uma repetição válida: um pulso e um evento 5.
   A segunda deve gerar eventos 5/2 e somente o padrão de série; após o descanso,
   o aviso breve; ao concluir a segunda série, eventos 5/2/4 e padrão de treino.
5. Durante treino ativo, faça um movimento rejeitado ou envie `b` pelo serial:
   evento 1 e dois pulsos. `t` no serial simula repetição válida durante treino
   ligado e pode ser usado para separar transporte BLE da leitura física.
6. Pause e finalize manualmente: nenhum padrão de conclusão deve ser criado.
   Desconecte/reconecte: o snapshot não vibra; a próxima repetição válida vibra.
7. Teste Feedback háptico desligado, retorno do segundo plano e uma interrupção
   do iOS. Repita em firmware anterior sem tipo 5 para validar o fallback.
   Testes de pacotes duplicados são automatizados no XCTest; conferir seus
   resultados não equivale a reproduzir notificações duplicadas na placa.

Registros BLE e hápticos ficam na Engenharia e no console Xcode. Os registros
são limitados a 200 entradas por lista e podem ser copiados para investigar.

## Evidência disponível nesta execução

Foram adicionados 12 testes XCTest de decodificação, wraparound/deduplicação,
ordem estado/evento, primeiro evento tardio, padrões/prioridade, firmware legado,
pausa/término/standby/demo, reset de reconexão e fallback sem Core Haptics.
O teste de fallback exige um host de testes ativo; caso contrário é marcado skip.
Esses testes precisam ser executados no Xcode; testes de roteamento não comprovam
inscrição BLE real, latência nem força física do motor.

Neste Windows, Xcode, XcodeGen, Swift, Arduino CLI e compilador C++ não estão no
PATH. Não houve build iOS/ESP32, execução de XCTest nem teste físico de vibração.
As cinco verificações Python de contrato de fontes e os oito testes de regressão
do validador de empacotamento foram executados com sucesso. `git diff --check`
também passou. Esses checks não substituem compilação ou integração física.

Referências de ciclo de vida:
[preparação do Core Haptics](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics)
e [recuperação após reset](https://developer.apple.com/documentation/corehaptics/chhapticengine/resethandler-swift.property).
