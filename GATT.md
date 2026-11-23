# Contrato GATT

Central iPhone; periférico ESP32 `Cotoveleira`. Sufixo de todos os UUIDs: `-274C-4F4D-8D63-7A7F0C010001`. O firmware deste repositório transmite a versão 1. Inteiros multibyte são little-endian e os pacotes têm menos de 20 bytes.

| Prefixo | Função | Propriedade | Payload |
|---|---|---|---|
| 4F1B0001 | Serviço | — | — |
| 4F1B0002 | Estado | Read/Notify | 6 ou 12 bytes (v1) |
| 4F1B0003 | Comando | Write com resposta | 4 bytes (v1): versão, código, valor UInt16 |
| 4F1B0004 | Bateria | Read/Notify | percentual 0–100 |
| 4F1B0005 | Energia | Read/Notify | 0 standby, 1 ligado |
| 4F1B0006 | Evento | Notify | versão, tipo, motivo, sequência UInt32 |
| 4F1B0007 | Diagnóstico | Notify | 18 bytes (v1 flex ou v2 MPU-6050) |

Estado: offsets 0 versão; 1 fase (0 parado, 1 ativo, 2 pausado, 3 descanso, 4 concluído); 2–3 repetições; 4 série (base 1); 5 flags (bit 0 término manual); 6 meta séries; 7 meta repetições; 8–9 descanso configurado; 10–11 segundos restantes. Extensão do pacote original de 6 bytes com prefixo preservado. O app aceita ambos; sincronização completa exige firmware atualizado.

Comandos: 1 iniciar, 2 pausar, 3 retomar, 4 finalizar, 5 pular descanso (valor zero); 6 séries (1–10); 7 repetições (1–100); 8 descanso (5–300 s); 9 energia (0/1); 10 diagnóstico (0/1). Configuração muda apenas fora do treino. Standby aceita 9/10. Resposta de escrita confirma transporte; estado confirma execução. Firmware tem fila de 12 comandos; app serializa escritas. Não retransmite comandos de treino na reconexão.

Eventos (7 bytes, versão 1): 1 erro, 2 série, 3 descanso, 4 treino, **5 repetição correta** (motivo 0). Motivos de erro: 1 demorado, 2 rápido, 3 intervalo curto, 0 teste serial. Sequência UInt32 little-endian cresce por boot; app descarta repetidos e anteriores na conexão, incluindo wraparound, e reinicia deduplicação na reconexão. Eventos não são reproduzidos após reconexão. Toda repetição válida gera 5; fim de série gera 5/2, fim de treino gera 5/2/4. O app reúne eventos adjacentes por 40 ms e seleciona o padrão de maior prioridade (treino > série > erro > próxima série > repetição); se uma conclusão chegar depois da janela, interrompe o player anterior. Não mantém fila de vibrações atrasadas. Com firmware antigo sem tipo 5, avanço de contador ativo na mesma série gera fallback após 120 ms; snapshots iniciais/reconexão não vibram. Eventos 5 cancelam esse fallback e passam a ser a fonte de repetições da conexão. Um primeiro 5 atrasado até 800 ms após o fallback é reconhecido como já atendido, abaixo do intervalo mínimo de 1000 ms entre repetições imposto pelo firmware. A correlação de estado/evento é temporal, pois o protocolo não inclui contador no evento; atrasos arbitrários/perda de notificações exigem validação física e não permitem garantia de correlação perfeita. Estado, bateria, energia e diagnóstico mantêm seus formatos anteriores.

Bateria atualiza em 5 s ligado e 60 s standby; percentual estimado por tensão. Energia e estado são lidos na conexão/restauração. BLE não usa autenticação de aplicação.

## Diagnóstico v1 em uso

O firmware com sensor flex usa o byte 0 igual a 1. Os offsets 1–2, 3–4, 6–7 e 8–9 são UInt16 e contêm ADC bruto médio, ADC filtrado e referências ADC de extensão e flexão. O byte 5 contém flexão percentual e o byte 17 contém a zona morta em ADC. Os offsets 10–16 seguem os campos comuns da tabela abaixo. Cadência nominal de 100 ms quando ligado e com diagnóstico habilitado.

## Diagnóstico v2 proposto para o MPU-6050

O iOS aceita este formato. O sketch atual continua emitindo v1. A próxima atualização do firmware deve emitir v2 somente em `4F1B0007`, com o mesmo UUID e 18 bytes. Estado, comando, bateria, energia e eventos mantêm o formato v1.

| Offset | Tipo | Campo |
|---|---|---|
| 0 | UInt8 | Versão igual a 2 |
| 1–2 | Int16 LE | Orientação bruta do antebraço em centigraus |
| 3–4 | Int16 LE | Orientação filtrada em centigraus |
| 5 | UInt8 | Progresso relativo calibrado de extensão (0%) a flexão (100%) |
| 6–7 | Int16 LE | Referência de extensão em centigraus |
| 8–9 | Int16 LE | Referência de flexão em centigraus |
| 10 | UInt8 | Estado da detecção (0 espera extensão, 1 espera flexão, 2 espera retorno, 3 reset) |
| 11 | UInt8 | Calibração válida (0/1) |
| 12–13 | UInt16 LE | Bateria em milivolts |
| 14 | UInt8 | Limiar de extensão em % (0–100) |
| 15 | UInt8 | Limiar de flexão em % (0–100) |
| 16 | UInt8 | Coeficiente EMA em % (0–100) |
| 17 | UInt8 | Integridade (bit 0 IMU detectada, bit 1 orientação válida, bit 2 erro I2C) |

Os ângulos usam complemento de dois. Divida por 100 para obter graus. Exemplo: `2E FB` representa −1234 centigraus = −12,34°. O firmware deve deixar os bits 3–7 zerados. O app ignora esses bits ao avaliar a integridade. O gráfico e os extremos usam apenas orientações com bits 0 e 1 ativos e bit 2 desativado. O progresso também exige calibração válida. O iOS usa a orientação do antebraço como telemetria e recebe o resultado da detecção e a contagem do ESP32.

Exemplo de pacote v2 com orientação bruta de −12,34°, filtrada de 12,34°, progresso de 73%, bateria de 3700 mV e IMU íntegra:

```text
02 2E FB D2 04 49 00 80 FF 7F 03 01 74 0E 15 51 10 03
```

O app ignora pacotes de diagnóstico com tamanho ou versão desconhecidos, estado fora de 0–3, calibração fora de 0/1 ou percentual fora de 0–100. O gráfico guarda até 300 amostras e os registros até 200 entradas. A frequência exibida é a de chegada dos pacotes BLE, calculada pelo iPhone. Telemetria com mais de 2 s é marcada como desatualizada.
