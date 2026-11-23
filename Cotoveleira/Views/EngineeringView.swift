import SwiftUI
import Charts
import UIKit

struct EngineeringView: View {
    @ObservedObject private var haptics = HapticService.shared
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var workout: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var developer = false
    @State private var demoEvents: [String] = []
    @State private var demoAngle = -20.0
    @State private var demoBattery = 80.0

    private var samples: [SensorSample] { workout.demoMode ? workout.demoSamples : bluetooth.samples }
    private var diagnostic: DiagnosticTelemetry? { workout.demoMode ? nil : bluetooth.diagnostic }
    private var usesDegrees: Bool { workout.demoMode || diagnostic?.version == 2 }
    private var unit: String { usesDegrees ? "°" : "ADC" }

    private func reading(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(usesDegrees ? 2 : 0)))
        return usesDegrees ? "\(number)°" : "\(number) ADC"
    }

    private func readings(_ first: Double, _ second: Double) -> String {
        "\(reading(first)) / \(reading(second))"
    }

    private func logDemo(_ message: String) {
        demoEvents.append("\(Date.now.formatted(date: .omitted, time: .standard)) \(message)")
        if demoEvents.count > 200 { demoEvents.removeFirst() }
    }

    @ViewBuilder private var signalPanel: some View {
        if workout.demoMode || diagnostic != nil {
            Section(usesDegrees ? "Orientação do antebraço" : "Sinal ADC — sensor flex legado") {
                Chart(samples) { sample in
                    LineMark(x: .value("Hora", sample.date), y: .value(unit, sample.raw))
                        .foregroundStyle(by: .value("Sinal", "Bruto"))
                    LineMark(x: .value("Hora", sample.date), y: .value(unit, sample.filtered))
                        .foregroundStyle(by: .value("Sinal", "Filtrado"))
                }
                .chartYAxisLabel(unit)
                .frame(height: 180)
                let latest = workout.demoMode ? samples.last : diagnostic?.sample(at: .now)
                LabeledContent("Bruto / filtrado", value: latest.map { readings($0.raw, $0.filtered) } ?? "Indisponível")
                let low = workout.demoMode ? samples.map(\.raw).min() : bluetooth.minimum
                let high = workout.demoMode ? samples.map(\.raw).max() : bluetooth.maximum
                if let low, let high {
                    LabeledContent("Mínimo / máximo (app)", value: readings(low, high))
                }
                if let low = samples.map(\.raw).min(), let high = samples.map(\.raw).max() {
                    LabeledContent("Oscilação pico a pico (janela, app)", value: reading(high - low))
                }
                if let diagnostic { signalDetails(diagnostic) }
            }
        } else {
            Section("Sinal do sensor") { Text("Aguardando telemetria do ESP32") }
        }
    }

    @ViewBuilder private func signalDetails(_ telemetry: DiagnosticTelemetry) -> some View {
        switch telemetry.signal {
        case .flex(let flex):
            LabeledContent("Flexão (%)", value: "\(telemetry.progressPercent)")
            LabeledContent("Calibração extensão / flexão", value: readings(Double(flex.extensionADC), Double(flex.flexionADC)))
            LabeledContent("Zona morta", value: "\(flex.deadZoneADC) ADC")
            Text("40 amostras de ADC; média dos 20 valores centrais; estabilidade 100 ms; duração 350–8000 ms; intervalo mínimo 1000 ms.").font(.footnote)
        case .imu(let imu):
            LabeledContent("Sensor", value: "MPU-6050 (diagnóstico v2)")
            LabeledContent("IMU detectada", value: imu.health.contains(.detected) ? "Sim" : "Não")
            LabeledContent("Orientação válida", value: imu.health.contains(.orientationValid) ? "Sim" : "Não")
            LabeledContent("Erro I2C", value: imu.health.contains(.i2cError) ? "Sim" : "Não")
            LabeledContent("Progresso extensão → flexão",
                           value: telemetry.calibrationValid && imu.health.hasUsableOrientation ? "\(telemetry.progressPercent)%" : "Indisponível")
            LabeledContent("Referências de extensão / flexão",
                           value: telemetry.calibrationValid ? readings(imu.extensionDegrees, imu.flexionDegrees) : "Indisponível")
            Text("A IMU mede a orientação do antebraço. O ângulo articular absoluto do cotovelo exigiria também a orientação do braço.").font(.footnote)
        }
        LabeledContent("Calibração válida", value: telemetry.calibrationValid ? "Sim" : "Não")
        LabeledContent("Estado da máquina (0–3)", value: "\(telemetry.detectionState.rawValue)")
        LabeledContent("Limiares extensão / flexão", value: "\(telemetry.extensionThresholdPercent)% / \(telemetry.flexionThresholdPercent)%")
        LabeledContent("EMA", value: "\(telemetry.emaPercent)%")
    }

    private func copyDiagnostic() {
        var lines = [workout.demoMode ? "SIMULADO — orientação do antebraço" : "REAL — ESP32"]
        if let diagnostic {
            lines.append("Diagnóstico v\(diagnostic.version) | estado \(diagnostic.detectionState.rawValue) | calibração válida: \(diagnostic.calibrationValid) | bateria: \(diagnostic.batteryMillivolts) mV")
            lines.append("Limiares: \(diagnostic.extensionThresholdPercent)% / \(diagnostic.flexionThresholdPercent)% | EMA: \(diagnostic.emaPercent)%")
            switch diagnostic.signal {
            case .flex(let flex):
                lines.append("Flexão: \(diagnostic.progressPercent)% | referência: \(readings(Double(flex.extensionADC), Double(flex.flexionADC))) | zona morta: \(flex.deadZoneADC) ADC")
            case .imu(let imu):
                lines.append("Flags de integridade: \(imu.health.rawValue)")
                if diagnostic.calibrationValid {
                    lines.append("Referências: \(readings(imu.extensionDegrees, imu.flexionDegrees))")
                    if imu.health.hasUsableOrientation { lines.append("Progresso: \(diagnostic.progressPercent)%") }
                }
            }
        }
        lines += samples.map { "\($0.date.formatted(date: .omitted, time: .standard)) bruto / filtrado: \(readings($0.raw, $0.filtered))" }
        lines += (workout.demoMode ? demoEvents : bluetooth.events)
        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Modo desenvolvedor", isOn: $developer)
                    Toggle("Modo demonstração", isOn: $workout.demoMode).disabled(workout.isRunning)
                    Text(workout.demoMode ? "SIMULADO — orientação e treino" : "Telemetria real do ESP32")
                }
                if workout.demoMode {
                    Section("Simulação") {
                        Toggle("Energia simulada", isOn: $workout.demoPowered).disabled(workout.isRunning)
                        Slider(value: $demoBattery, in: 0...100)
                        Text("Bateria simulada: \(Int(demoBattery))%")
                        Slider(value: $demoAngle, in: -20...70, step: 1)
                            .accessibilityLabel("Orientação simulada")
                            .onChange(of: demoAngle) { _, value in workout.recordDemoOrientation(value) }
                            .disabled(!workout.demoPowered)
                        LabeledContent("Orientação manual simulada", value: reading(demoAngle))
                        if let latest = samples.last {
                            LabeledContent("Última orientação simulada", value: readings(latest.raw, latest.filtered))
                        }
                        Button("Repetição correta simulada") { workout.addRepetition() }
                            .disabled(workout.phase != .active)
                        Button("Repetição incorreta simulada") {
                            workout.simulateError()
                            logDemo("Erro simulado")
                        }
                        .disabled(workout.phase != .active)
                    }
                }
                if developer {
                    signalPanel
                    if !workout.demoMode {
                        Section("Comunicação e energia") {
                            LabeledContent("BLE", value: bluetooth.status)
                            LabeledContent("RSSI", value: bluetooth.rssi.map { "\($0) dBm" } ?? "Indisponível")
                            LabeledContent("Energia", value: bluetooth.powered.map { $0 ? "Ligado" : "Standby" } ?? "Desconectado")
                            LabeledContent("Bateria", value: bluetooth.battery.map { "\($0)%" } ?? "Indisponível")
                            LabeledContent("Tensão (mV)", value: diagnostic.map { "\($0.batteryMillivolts)" } ?? "Indisponível")
                            LabeledContent("Frequência instantânea (app)", value: bluetooth.frequency.map { String(format: "%.1f Hz", $0) } ?? "Indisponível")
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Text(bluetooth.lastUpdate.map { "Última telemetria: \($0.formatted()); \(timeline.date.timeIntervalSince($0) > 2 ? "desatualizada" : "recente")" } ?? "Sem telemetria")
                            }
                        }
                    }
                    Section("Testes hápticos") {
                        LabeledContent("Mecanismo", value: haptics.engineStatus)
                        ForEach(HapticService.Pattern.allCases, id: \.self) { pattern in
                            Button(pattern.title) { haptics.play(pattern) }
                        }
                        Button("Parar teste háptico") { haptics.cancel() }
                        Text("Testes não alteram o treino. Use o app em primeiro plano e habilite Feedback háptico em Ajustes.").font(.footnote)
                    }
                    Section("Diagnóstico háptico") {
                        Button("Limpar diagnóstico háptico") { haptics.clearDiagnostics() }
                        Button("Copiar diagnóstico háptico") { UIPasteboard.general.string = haptics.diagnostics.joined(separator: "\n") }
                        ForEach(Array(haptics.diagnostics.suffix(200).enumerated()), id: \.offset) { _, entry in
                            Text(entry).font(.caption.monospaced())
                        }
                    }
                    Section("Registros") {
                        Button("Limpar registros") {
                            if workout.demoMode { workout.clearDemoSamples(); demoEvents = [] }
                            else { bluetooth.clearDiagnostics() }
                        }
                        if !workout.demoMode {
                            Button("Reiniciar mínimos e máximos") { bluetooth.resetExtrema() }
                        }
                        Button("Copiar diagnóstico") { copyDiagnostic() }
                        ForEach(Array((workout.demoMode ? demoEvents : bluetooth.events).suffix(200).enumerated()), id: \.offset) { _, event in Text(event).font(.caption.monospaced()) }
                        Text("Motivos: 1 duração excessiva; 2 movimento rápido; 3 intervalo curto; 0 teste serial.").font(.footnote)
                    }
                }
            }
            .navigationTitle("Engenharia")
            .toolbar { Button("Concluído") { dismiss() } }
            .onChange(of: developer) { _, enabled in bluetooth.diagnostics(enabled && !workout.demoMode) }
            .onChange(of: workout.demoMode) { _, demo in
                bluetooth.demoMode = demo
                if !demo && developer { bluetooth.diagnostics(true) }
            }
            .onChange(of: workout.total) { previous, total in
                if workout.demoMode && total > previous { logDemo("Repetição simulada (total \(total))") }
            }
            .onDisappear { bluetooth.diagnostics(false) }
        }
    }
}
