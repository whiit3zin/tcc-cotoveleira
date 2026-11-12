# Contrato BLE proposto, versão 1

O firmware atual do ESP32 não foi verificado. Ele precisa implementar este contrato antes de o modo real funcionar.

O iPhone é a central; o ESP32 é o periférico. Anuncie o serviço `4F1B0001-274C-4F4D-8D63-7A7F0C010001`. Todas as características usam o mesmo UUID com `0001` substituído pelos identificadores abaixo.

| ID | Característica | Propriedade | Payload |
|---|---|---|---|
| `0002` | Estado | Read, Notify | 6 bytes: versão (1), fase (0 parado, 1 ativo, 2 pausado, 3 descanso, 4 concluído), repetições UInt16 LE, série UInt8 (começa em 1), flags UInt8 (reservado, 0) |
| `0003` | Comando | Write with response | 4 bytes: versão (1), código UInt8, valor UInt16 LE |
| `0004` | Bateria opcional | Read, Notify | 1 byte: porcentagem de 0 a 100 |

Comandos: `1` iniciar, `2` pausar, `3` retomar, `4` finalizar, `5` pular descanso, `6` configurar séries, `7` configurar repetições, `8` configurar descanso em segundos. Valor é zero para os comandos 1 a 5. O firmware deve responder às escritas e publicar novo estado. Pacotes com versão desconhecida, tamanho incorreto, fase inválida, série zero ou bateria acima de 100 são descartados pelo aplicativo. Cada pacote cabe em uma notificação BLE com MTU mínima (20 bytes úteis). Sem fragmentação.

O ESP32 precisa usar os UUIDs acima, contar repetições e séries, controlar o descanso e publicar notificações de estado. O aplicativo ainda não sincroniza relógios nem retransmite comandos após reconexão. Não há confirmação de compatibilidade com qualquer firmware existente.
