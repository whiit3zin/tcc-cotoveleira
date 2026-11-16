// Cotoveleira BLE: GPIO34 flex/100k, GPIO35 bateria divisor 1:1.
// Arduino ESP32 3.x. Standby logico, nao desligamento eletrico.
#include <Arduino.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

// -------- CONFIGURACAO DO HARDWARE --------
static constexpr uint8_t PIN_FLEX = 34;
static constexpr uint8_t PIN_BAT = 35;
// Sensor flex: limiares relativos aos dois pontos calibrados; nao sao
// valores fixos de ADC porque a resistencia muda entre pecas e montagens.
static constexpr uint8_t FLEX_LIMIAR_DOBRADO_PCT = 80;
static constexpr uint8_t FLEX_LIMIAR_ESTENDIDO_PCT = 20;
static constexpr uint16_t FLEX_DELTA_MIN_ADC = 120;
static constexpr uint32_t FLEX_ESTENDIDO_ESTAVEL_MS = 100;
static constexpr uint32_t FLEX_DOBRADO_ESTAVEL_MS = 100;
static constexpr uint32_t FLEX_DOBRA_MIN_MS = 350;
static constexpr uint32_t FLEX_DOBRA_MAX_MS = 8000;
static constexpr uint32_t FLEX_INTERVALO_MIN_MS = 1000;

Preferences prefs;
bool calibrated = true;
bool waitingBentCalibration = false;
uint16_t flexStraight = 2570;
uint16_t flexBent = 570;
uint16_t flexRaw = 0;
uint16_t rawMean = 0;
float flexSmoothed = 0;
uint8_t flexPct = 0;

uint16_t sampleFlexAverage() {
  uint32_t sum = 0;
  for (int i = 0; i < 64; ++i) {
    sum += analogRead(PIN_FLEX);
    delay(5);
  }
  return (uint16_t)(sum / 64);
}

void updateFlexReading() {
  int samples[40];
  for (int i = 0; i < 40; ++i) {
    samples[i] = analogRead(PIN_FLEX);
    delayMicroseconds(200);
  }
  uint32_t rawSum = 0;
  for (int i = 0; i < 40; ++i) rawSum += samples[i];
  rawMean = rawSum / 40;
  for (int i = 1; i < 40; ++i) {
    int v = samples[i], j = i - 1;
    while (j >= 0 && samples[j] > v) { samples[j + 1] = samples[j]; --j; }
    samples[j + 1] = v;
  }
  uint32_t sum = 0;
  for (int i = 10; i < 30; ++i) sum += samples[i];
  const float newest = sum / 20.0f;
  flexSmoothed += 0.15f * (newest - flexSmoothed);
  const int candidate = int(flexSmoothed + 0.5f);
  if (abs(candidate - int(flexRaw)) >= 30) flexRaw = uint16_t(candidate);
  if (!calibrated) { flexPct = 0; return; }
  const int32_t difference = int32_t(flexBent) - int32_t(flexStraight);
  if (difference == 0) { flexPct = 0; return; }
  float pct = 100.0f * (int32_t(flexRaw) - int32_t(flexStraight)) / difference;
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  flexPct = uint8_t(pct + 0.5f);
}

void loadFlexCalibration() {
  if (!prefs.begin("flexcal", false)) {
    Serial.println("[FLEX] NVS indisponivel; calibracao so nesta sessao");
    return;
  }
  if (prefs.isKey("straight") && prefs.isKey("bent")) {
    flexStraight = prefs.getUShort("straight", 0);
    flexBent = prefs.getUShort("bent", 0);
    calibrated = flexStraight <= 4095 && flexBent <= 4095 &&
      abs(int32_t(flexBent) - int32_t(flexStraight)) >= FLEX_DELTA_MIN_ADC;
    if (calibrated) {
      Serial.printf("[FLEX] calibracao recuperada: estendido=%u dobrado=%u\n", flexStraight, flexBent);
    }
  }
  if (!calibrated) Serial.println("[FLEX] CALIBRAR: envie 'e' estendido, depois 'd' dobrado.");
}

void calibrateFlex(char c) {
  if (c == 'p') {
    flexStraight = 2570;
    flexBent = 570;
    calibrated = true;
    waitingBentCalibration = false;
    prefs.putUShort("straight", flexStraight);
    prefs.putUShort("bent", flexBent);
    Serial.println("[FLEX] Perfil 100k: 2570/570 aplicado.");
    return;
  }
  if (c == 'x') {
    calibrated = false;
    waitingBentCalibration = false;
    prefs.remove("straight");
    prefs.remove("bent");
    Serial.println("[FLEX] calibracao apagada. Envie e, depois d.");
    return;
  }
  if (c == 'e') {
    calibrated = false;
    waitingBentCalibration = true;
    Serial.println("[FLEX] Fique ESTENDIDO e imovel por 0,4s...");
    flexStraight = sampleFlexAverage();
    Serial.printf("[FLEX] estendido=%u; AGORA dobre e envie 'd'.\n", flexStraight);
    return;
  }
  if (c == 'd') {
    if (!waitingBentCalibration) {
      Serial.println("[FLEX] PRIMEIRO calibre estendido com 'e'.");
      return;
    }
    Serial.println("[FLEX] Fique DOBRADO e imovel por 0,4s...");
    flexBent = sampleFlexAverage();
    const int32_t delta = abs(int32_t(flexBent) - int32_t(flexStraight));
    waitingBentCalibration = false;
    if (delta < FLEX_DELTA_MIN_ADC) {
      calibrated = false;
      Serial.printf("[FLEX] delta=%ld muito baixo. Verifique fio/divisor/posicao, repita e/d.\n", (long)delta);
      return;
    }
    calibrated = true;
    prefs.putUShort("straight", flexStraight);
    prefs.putUShort("bent", flexBent);
    Serial.printf("[FLEX] OK! estendido=%u dobrado=%u delta=%ld. Salvo na NVS.\n",
                  flexStraight, flexBent, (long)delta);
    Serial.println("[FLEX] Pode iniciar treino pelo iPhone.");
  }
}

static constexpr char SERVICE_UUID[] = "4F1B0001-274C-4F4D-8D63-7A7F0C010001";
static constexpr char STATE_UUID[] = "4F1B0002-274C-4F4D-8D63-7A7F0C010001";
static constexpr char COMMAND_UUID[] = "4F1B0003-274C-4F4D-8D63-7A7F0C010001";
static constexpr char BATTERY_UUID[] = "4F1B0004-274C-4F4D-8D63-7A7F0C010001";

enum Phase : uint8_t { IDLE = 0, ACTIVE = 1, PAUSED = 2, RESTING = 3, COMPLETED = 4 };
struct Command { uint8_t code; uint16_t value; };

BLEServer *bleServer = nullptr;
BLECharacteristic *stateChar = nullptr;
BLECharacteristic *batteryChar = nullptr;
QueueHandle_t cmdQueue = nullptr;
volatile bool connected = false;
bool wasConnected = false;

Phase phase = IDLE;
bool manuallyFinished = false;
uint16_t repetitions = 0;
uint8_t currentSet = 1;
uint16_t targetSets = 3;
uint16_t targetReps = 12;
uint16_t restSeconds = 60;
uint32_t restEndMs = 0;
bool stateDirty = true;
uint32_t lastStateMs = 0;
uint32_t lastBatteryMs = 0;
uint32_t lastFlexLogMs = 0;
float batteryVolts = 0.0f;
uint8_t batteryPct = 0;

// Additional BLE characteristics; existing packets remain unchanged.
BLECharacteristic *powerChar = nullptr, *eventChar = nullptr, *diagChar = nullptr;
bool powered = false, diagnostics = false;
uint32_t eventSeq = 0, lastDiagMs = 0;
void publishPower() {
  uint8_t v = powered ? 1 : 0;
  powerChar->setValue(&v, 1);
  if (connected) powerChar->notify();
}
void emitEvent(uint8_t type, uint8_t reason) {
  ++eventSeq;
  uint8_t p[] = {1, type, reason, uint8_t(eventSeq), uint8_t(eventSeq >> 8), uint8_t(eventSeq >> 16), uint8_t(eventSeq >> 24)};
  eventChar->setValue(p, sizeof(p));
  if (connected) eventChar->notify();
}

// -------- BLE --------
class ServerEvents : public BLEServerCallbacks {
  void onConnect(BLEServer *) override {
    connected = true;
    Serial.println("[BLE] iPhone conectado");
  }
  void onDisconnect(BLEServer *) override {
    connected = false;
    Serial.println("[BLE] iPhone desconectado");
  }
};
class CommandEvents : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) override {
    if (c->getLength() != 4) return;
    const uint8_t *data = c->getData();
    if (!data || data[0] != 1 || data[1] < 1 || data[1] > 10) return;
    Command cmd = { data[1], uint16_t(uint16_t(data[2]) | (uint16_t(data[3]) << 8)) };
    if (cmdQueue) xQueueSend(cmdQueue, &cmd, 0);
  }
};
void publishState(bool notify) {
  const uint8_t data[] = {
    1, uint8_t(phase), uint8_t(repetitions & 255), uint8_t(repetitions >> 8),
    currentSet, uint8_t(manuallyFinished),
    uint8_t(targetSets), uint8_t(targetReps), uint8_t(restSeconds), uint8_t(restSeconds >> 8),
    uint8_t(phase == RESTING ? max(0L, (long)(int32_t(restEndMs - millis()) + 999) / 1000) : 0),
    uint8_t(phase == RESTING ? max(0L, (long)(int32_t(restEndMs - millis()) + 999) / 1000) >> 8 : 0)
  };
  stateChar->setValue(data, sizeof(data));
  if (notify && connected) stateChar->notify();
  stateDirty = false;
}

float readBatteryVolts() {
  uint32_t sum = 0;
  for (int i = 0; i < 8; ++i) {
    sum += analogReadMilliVolts(PIN_BAT);
    delay(1);
  }
  return (sum / 8.0f) * 2.0f / 1000.0f;
}
uint8_t percentFromVolts(float v) {
  struct Point { float v; uint8_t p; };
  static const Point curve[] = {
    {3.30f, 0}, {3.50f, 10}, {3.60f, 20}, {3.75f, 45},
    {3.85f, 60}, {3.95f, 75}, {4.05f, 85}, {4.15f, 95}, {4.20f, 100}
  };
  if (v <= curve[0].v) return 0;
  for (unsigned i = 1; i < sizeof(curve)/sizeof(curve[0]); ++i) {
    if (v <= curve[i].v) {
      const float t = (v - curve[i-1].v) / (curve[i].v - curve[i-1].v);
      return (uint8_t)(curve[i-1].p + t * (curve[i].p - curve[i-1].p) + .5f);
    }
  }
  return 100;
}
void publishBattery(bool notify) {
  batteryVolts = readBatteryVolts();
  batteryPct = percentFromVolts(batteryVolts);
  batteryChar->setValue(&batteryPct, 1);
  if (notify && connected) batteryChar->notify();
  Serial.printf("[BATERIA] %.2f V ~%u%%\n", batteryVolts, batteryPct);
}

// -------- CONTAGEM DE REPETICOES COM SENSOR FLEX --------
// Sequencia obrigatoria: estendido estavel -> dobrado estavel ->
// estendido estavel. Compara apenas o padrao de flexao, nao avalia postura.
enum FlexStage : uint8_t { WAIT_STRAIGHT, WAIT_BEND, WAIT_RETURN, WAIT_RESET };
FlexStage flexStage = WAIT_STRAIGHT;
uint32_t stableSince = 0;
uint32_t bendFirstMs = 0;
uint32_t bendStableSince = 0;
uint32_t extensionFirstMs = 0;
uint32_t lastValidRepMs = 0;
bool hasValidRep = false;

void resetFlexState() {
  flexStage = WAIT_STRAIGHT;
  stableSince = 0;
  bendFirstMs = 0;
  bendStableSince = 0;
  extensionFirstMs = 0;
}
void completeRest() {
  if (phase != RESTING) return;
  ++currentSet;
  repetitions = 0;
  phase = ACTIVE;
  resetFlexState();
  stateDirty = true;
  emitEvent(3, 0);
  Serial.printf("[TREINO] nova serie %u\n", currentSet);
}
void repetitionCorrect(uint32_t now) {
  if (phase != ACTIVE) return;
  if (repetitions < targetReps) ++repetitions;
  lastValidRepMs = now;
  hasValidRep = true;
  stateDirty = true;
  Serial.printf("[FLEX] CERTO - serie %u rep %u\n", currentSet, repetitions);
  if (repetitions >= targetReps) {
    emitEvent(2, 0);
    if (currentSet >= targetSets) { phase = COMPLETED; emitEvent(4, 0); }
    else { phase = RESTING; restEndMs = now + uint32_t(restSeconds) * 1000UL; }
  }
}
void repetitionIncorrect(const char *reason) {
  if (phase != ACTIVE) return;
  Serial.printf("[FLEX] INVALIDO - %s (ADC=%u flexao=%u%%)\n", reason, flexRaw, flexPct);
  emitEvent(1, strcmp(reason, "movimento muito demorado") == 0 ? 1 : strcmp(reason, "movimento muito rapido") == 0 ? 2 : 3);
}
void processFlex(uint32_t now) {
  updateFlexReading();
  if (phase != ACTIVE || !calibrated) {
    resetFlexState();
    return;
  }
  const float relative = 100.0f * (int32_t(flexRaw) - int32_t(flexStraight)) / (int32_t(flexBent) - int32_t(flexStraight));
  const bool straight = relative <= FLEX_LIMIAR_ESTENDIDO_PCT;
  const bool bent = relative >= FLEX_LIMIAR_DOBRADO_PCT;

  switch (flexStage) {
    case WAIT_STRAIGHT:
    case WAIT_RESET:
      if (straight) {
        if (stableSince == 0) stableSince = now;
        if (now - stableSince >= FLEX_ESTENDIDO_ESTAVEL_MS) {
          flexStage = WAIT_BEND;
          stableSince = 0;
          bendStableSince = 0;
        }
      } else stableSince = 0;
      break;

    case WAIT_BEND:
      if (bent) {
        if (bendStableSince == 0) bendStableSince = now;
        if (now - bendStableSince >= FLEX_DOBRADO_ESTAVEL_MS) {
          bendFirstMs = bendStableSince;
          extensionFirstMs = 0;
          flexStage = WAIT_RETURN;
          Serial.println("[FLEX] flexao detectada, aguardando retorno");
        }
      } else bendStableSince = 0;
      break;

    case WAIT_RETURN:
      if (now - bendFirstMs > FLEX_DOBRA_MAX_MS) {
        repetitionIncorrect("movimento muito demorado");
        flexStage = WAIT_RESET;
        stableSince = 0;
        break;
      }
      if (straight) {
        if (extensionFirstMs == 0) extensionFirstMs = now;
        if (now - extensionFirstMs >= FLEX_ESTENDIDO_ESTAVEL_MS) {
          const uint32_t duration = extensionFirstMs - bendFirstMs;
          if (duration < FLEX_DOBRA_MIN_MS) repetitionIncorrect("movimento muito rapido");
          else if (hasValidRep && now - lastValidRepMs < FLEX_INTERVALO_MIN_MS)
            repetitionIncorrect("intervalo muito curto");
          else repetitionCorrect(now);
          flexStage = WAIT_RESET;
          stableSince = 0;
        }
      } else extensionFirstMs = 0;
      break;
  }
}

// -------- COMANDOS RECEBIDOS DO APP --------
void processCommand(uint8_t code, uint16_t value) {
  if (code == 9) {
    if (value > 1) return;
    bool next = value == 1;
    if (powered != next) {
      powered = next;
      phase = IDLE;
      repetitions = 0; currentSet = 1; hasValidRep = false;
      lastBatteryMs = millis();
      resetFlexState();
      if (powered) { flexSmoothed = analogRead(PIN_FLEX); flexRaw = uint16_t(flexSmoothed); }
      stateDirty = true;
    }
    publishPower();
    return;
  }
  if (code == 10) { if (value <= 1) diagnostics = value == 1; return; }
  if (!powered) return;
  switch (code) {
    case 1: // iniciar
      if (!calibrated || (phase != IDLE && phase != COMPLETED)) return;
      manuallyFinished = false;
      phase = ACTIVE;
      repetitions = 0;
      currentSet = 1;
      hasValidRep = false;
      resetFlexState();
      break;
    case 2: // pausar
      if (phase == ACTIVE) { phase = PAUSED; resetFlexState(); }
      break;
    case 3: // retomar
      if (phase == PAUSED) { phase = ACTIVE; resetFlexState(); }
      break;
    case 4: // finalizar
      if (phase != IDLE && phase != COMPLETED) { manuallyFinished = true; phase = COMPLETED; resetFlexState(); }
      break;
    case 5: // pular descanso
      completeRest();
      break;
    case 6: // configurar series
      if ((phase == IDLE || phase == COMPLETED) && value >= 1 && value <= 10) targetSets = value;
      break;
    case 7: // configurar repeticoes
      if ((phase == IDLE || phase == COMPLETED) && value >= 1 && value <= 100) targetReps = value;
      break;
    case 8: // configurar descanso
      if ((phase == IDLE || phase == COMPLETED) && value >= 5 && value <= 300) restSeconds = value;
      break;
    default: return;
  }
  stateDirty = true;
  Serial.printf("[APP] cmd=%u valor=%u fase=%u\n", code, value, uint8_t(phase));
}

// -------- STATUS E DIAGNOSTICO --------
const char* phaseLabel() {
  switch (phase) {
    case IDLE: return "PRONTO";
    case ACTIVE: return "TREINANDO";
    case PAUSED: return "PAUSADO";
    case RESTING: return "DESCANSO";
    case COMPLETED: return "FINALIZADO";
  }
  return "---";
}
void publishDiagnostics() {
  // 18 bytes, little endian, fits default BLE ATT payload.
  uint16_t mv = uint16_t(batteryVolts * 1000.0f);
  uint8_t p[] = {1, uint8_t(rawMean), uint8_t(rawMean >> 8), uint8_t(flexRaw), uint8_t(flexRaw >> 8), flexPct,
    uint8_t(flexStraight), uint8_t(flexStraight >> 8), uint8_t(flexBent), uint8_t(flexBent >> 8),
    uint8_t(flexStage), uint8_t(calibrated), uint8_t(mv), uint8_t(mv >> 8),
    FLEX_LIMIAR_ESTENDIDO_PCT, FLEX_LIMIAR_DOBRADO_PCT, 15, 30};
  diagChar->setValue(p, sizeof(p));
  if (connected) diagChar->notify();
}

bool serialLog = true;
void serialMenu() {
  Serial.println("\n=== COTOVELEIRA | MENU SERIAL ===");
  Serial.println("h/? : menu | i: status | l: alternar log");
  Serial.println("1: ligar | 0: standby | r: iniciar treino | f: finalizar");
  Serial.println("e: calibrar estendido | d: calibrar dobrado");
  Serial.println("p: perfil 2570/570 | x: apagar calibracao");
  Serial.println("t: simular rep | b: evento erro | s: evento serie");
}
void serialStatus() {
  Serial.printf("[STATUS] Energia=%s | BLE=%s | fase=%s | serie=%u/%u | rep=%u/%u | bateria=%.2f V (%u%%)\n", powered ? "LIGADO" : "STANDBY", connected ? "CONECTADO" : "DESCONECTADO", phaseLabel(), currentSet, targetSets, repetitions, targetReps, batteryVolts, batteryPct);
  if (powered) Serial.printf("[FLEX] Bruto(media)=%u | Filtrado=%u | Flexao=%u%% | Estado=%u\n", rawMean, flexRaw, flexPct, unsigned(flexStage));
  else Serial.println("[FLEX] Leitura suspensa; envie 1 para ligar.");
  Serial.printf("[CAL] %s | estendido=%u | dobrado=%u | limiares=%u%%/%u%% | EMA=0.15 | zona morta=30\n", calibrated ? "OK" : "NAO", flexStraight, flexBent, FLEX_LIMIAR_ESTENDIDO_PCT, FLEX_LIMIAR_DOBRADO_PCT);
}

void setup() {
  Serial.begin(115200);
  delay(250);
  analogReadResolution(12);
  analogSetPinAttenuation(PIN_BAT, ADC_11db);
  analogSetPinAttenuation(PIN_FLEX, ADC_11db);
  flexSmoothed = analogRead(PIN_FLEX);
  flexRaw = uint16_t(flexSmoothed);
  loadFlexCalibration();

  cmdQueue = xQueueCreate(12, sizeof(Command));
  if (!cmdQueue) {
    Serial.println("Falha na fila de comandos");
    while (true) delay(1000);
  }

  BLEDevice::init("Cotoveleira");
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerEvents());
  BLEService *service = bleServer->createService(BLEUUID(SERVICE_UUID), 32);
  stateChar = service->createCharacteristic(
    STATE_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  stateChar->addDescriptor(new BLE2902());
  BLECharacteristic *cmdChar = service->createCharacteristic(
    COMMAND_UUID, BLECharacteristic::PROPERTY_WRITE);
  cmdChar->setCallbacks(new CommandEvents());
  batteryChar = service->createCharacteristic(
    BATTERY_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  batteryChar->addDescriptor(new BLE2902());
  powerChar = service->createCharacteristic("4F1B0005-274C-4F4D-8D63-7A7F0C010001", BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  powerChar->addDescriptor(new BLE2902());
  eventChar = service->createCharacteristic("4F1B0006-274C-4F4D-8D63-7A7F0C010001", BLECharacteristic::PROPERTY_NOTIFY);
  eventChar->addDescriptor(new BLE2902());
  diagChar = service->createCharacteristic("4F1B0007-274C-4F4D-8D63-7A7F0C010001", BLECharacteristic::PROPERTY_NOTIFY);
  diagChar->addDescriptor(new BLE2902());
  publishPower();
  publishState(false);
  publishBattery(false);
  service->start();
  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("[BLE] Cotoveleira anunciando servico para iPhone");
  serialMenu();
  serialStatus();
}

void loop() {
  uint32_t now = millis();
  Command cmd;
  while (xQueueReceive(cmdQueue, &cmd, 0) == pdTRUE) processCommand(cmd.code, cmd.value);
  if (phase == RESTING && (int32_t)(now - restEndMs) >= 0) completeRest();
  while (Serial.available()) {
    char c = char(Serial.read());
    if (c == 'h' || c == '?') serialMenu();
    else if (c == 'i') serialStatus();
    else if (c == 'l') { serialLog = !serialLog; Serial.println(serialLog ? "Log ON" : "Log OFF"); }
    else if (c == '1' || c == '0') { processCommand(9, c == '1'); serialStatus(); }
    else if (c == 'r' || c == 'f') { if (!powered) Serial.println("Ligue com 1 primeiro."); else processCommand(c == 'r' ? 1 : 4, 0); }
    else if (c == 'e' || c == 'd' || c == 'x' || c == 'p') {
      if (!powered && (c == 'e' || c == 'd')) { Serial.println("Ligue com 1 primeiro."); continue; }
      if (phase == ACTIVE || phase == PAUSED || phase == RESTING) { Serial.println("Finalize o treino antes de calibrar."); continue; }
      calibrateFlex(c);
      resetFlexState();
    } else if (c == 'b' && powered) {
      emitEvent(1, 0);
    } else if (c == 's' && powered) {
      emitEvent(2, 0);
    } else if (c == 't' && phase == ACTIVE) {
      Serial.println("[TESTE] repeticao simulada pelo Monitor Serial");
      repetitionCorrect(now);
    }
  }
  now = millis();
  if (powered) processFlex(now);
  if (powered && diagnostics && connected && now - lastDiagMs >= 100) { publishDiagnostics(); lastDiagMs = now; }

  if (connected && !wasConnected) {
    wasConnected = true;
    stateDirty = true;
    publishPower();
  }
  if (!connected && wasConnected) {
    wasConnected = false;
    diagnostics = false;
    delay(100);
    BLEDevice::startAdvertising();
    Serial.println("[BLE] Anunciando novamente");
  }
  if (stateDirty || (powered && now - lastStateMs >= 1000)) {
    publishState(true);
    lastStateMs = now;
  }
  if (now - lastBatteryMs >= (powered ? 5000UL : 60000UL)) {
    publishBattery(true);
    lastBatteryMs = now;
  }
  if (powered && serialLog && now - lastFlexLogMs >= 400) {
    Serial.printf("[FLEX] bruto(media)=%u | filtrado=%u | dobra=%u%% | cal=%s | fase=%s | estado=%u | rep=%u/%u\n",
                  rawMean, flexRaw, flexPct, calibrated ? "OK" : "NAO", phaseLabel(), unsigned(flexStage), repetitions, targetReps);
    lastFlexLogMs = now;
  }
  delay(powered ? 10 : 100);
}
