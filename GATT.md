# Contrato GATT implementado

Central iPhone; periférico ESP32 `Cotoveleira`. Sufixo de todos os UUIDs: `-274C-4F4D-8D63-7A7F0C010001`. Versão 1; inteiros multibyte little-endian; pacotes menores que 20 bytes.

| Prefixo | Função | Propriedade | Payload |
|---|---|---|---|
| 4F1B0001 | Serviço | — | — |
| 4F1B0002 | Estado | Read/Notify | 12 bytes |
| 4F1B0003 | Comando | Write com resposta | versão, código, valor UInt16 |
| 4F1B0004 | Bateria | Read/Notify | percentual 0–100 |
| 4F1B0005 | Energia | Read/Notify | 0 standby, 1 ligado |
| 4F1B0006 | Evento | Notify | versão, tipo, motivo, sequência UInt32 |
| 4F1B0007 | Diagnóstico | Notify | 18 bytes |

Estado: offsets 0 versão; 1 fase (0 parado, 1 ativo, 2 pausado, 3 descanso, 4 concluído); 2–3 repetições; 4 série (base 1); 5 flags (bit 0 término manual); 6 meta séries; 7 meta repetições; 8–9 descanso configurado; 10–11 segundos restantes. Extensão do pacote original de 6 bytes com prefixo preservado. O app aceita ambos; sincronização completa exige firmware atualizado.

Comandos: 1 iniciar, 2 pausar, 3 retomar, 4 finalizar, 5 pular descanso (valor zero); 6 séries (1–10); 7 repetições (1–100); 8 descanso (5–300 s); 9 energia (0/1); 10 diagnóstico (0/1). Configuração muda apenas fora do treino. Standby aceita 9/10. Resposta de escrita confirma transporte; estado confirma execução. Firmware tem fila de 12 comandos; app serializa escritas. Não retransmite comandos de treino na reconexão.

Eventos (7 bytes, versão 1): 1 erro, 2 série, 3 descanso, 4 treino, **5 repetição correta** (motivo 0). Motivos de erro: 1 demorado, 2 rápido, 3 intervalo curto, 0 teste serial. Sequência UInt32 little-endian cresce por boot; app descarta repetidos e anteriores na conexão, incluindo wraparound, e reinicia deduplicação na reconexão. Eventos não são reproduzidos após reconexão. Toda repetição válida gera 5; fim de série gera 5/2, fim de treino gera 5/2/4. O app reúne eventos adjacentes por 40 ms e seleciona o padrão de maior prioridade (treino > série > erro > próxima série > repetição); se uma conclusão chegar depois da janela, interrompe o player anterior. Não mantém fila de vibrações atrasadas. Com firmware antigo sem tipo 5, avanço de contador ativo na mesma série gera fallback após 120 ms; snapshots iniciais/reconexão não vibram. Eventos 5 cancelam esse fallback e passam a ser a fonte de repetições da conexão. Um primeiro 5 atrasado até 800 ms após o fallback é reconhecido como já atendido, abaixo do intervalo mínimo de 1000 ms entre repetições imposto pelo firmware. A correlação de estado/evento é temporal, pois o protocolo não inclui contador no evento; atrasos arbitrários/perda de notificações exigem validação física e não permitem garantia de correlação perfeita. Estado, bateria, energia e diagnóstico mantêm seus formatos anteriores.

Diagnóstico: offsets 0 versão; 1–2 ADC bruto médio; 3–4 filtrado; 5 flexão percentual; 6–7 calibração estendido; 8–9 flexionado; 10 máquina de estados (0 espera extensão, 1 espera flexão, 2 espera retorno, 3 reset); 11 calibrado; 12–13 bateria mV; 14 limiar extensão; 15 limiar flexão; 16 EMA percentual; 17 zona morta ADC. Nominal 100 ms quando ligado e habilitado. App limita gráfico a 300 amostras e eventos a 200; frequência, extremos e oscilação são calculados localmente. Telemetria com mais de 2 s é desatualizada.

Bateria atualiza em 5 s ligado e 60 s standby; percentual estimado por tensão. Energia e estado são lidos na conexão/restauração. BLE não usa autenticação de aplicação.
