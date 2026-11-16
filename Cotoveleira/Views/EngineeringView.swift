import SwiftUI
import Charts
import UIKit

struct EngineeringView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var workout: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    @State private var developer = false
    @State private var demoSamples: [SensorSample] = []
    @State private var demoEvents: [String] = []
    @State private var demoFlex = 0.0
    @State private var demoBattery = 80.0
    private var samples: [SensorSample] { workout.demoMode ? demoSamples : bluetooth.samples }
    private func word(_ index: Int) -> String {
        guard bluetooth.diagnostic.count == 18 else { return "Indisponível" }
        return "\(Int(bluetooth.diagnostic[index]) | Int(bluetooth.diagnostic[index + 1]) << 8)"
    }
    private func byte(_ index: Int) -> String {
        bluetooth.diagnostic.count == 18 ? "\(bluetooth.diagnostic[index])" : "Indisponível"
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Modo desenvolvedor", isOn: $developer)
                    Toggle("Modo demonstração", isOn: $workout.demoMode).disabled(workout.isRunning)
                    Text(workout.demoMode ? "Dados simulados — separados do ESP32" : "Telemetria real do ESP32")
                }
                if workout.demoMode {
                    Section("Simulação") {
                        Toggle("Energia simulada", isOn: $workout.demoPowered).disabled(workout.isRunning)
                        Slider(value: $demoBattery, in: 0...100)
                        Text("Bateria simulada: \(Int(demoBattery))%")
                        Slider(value: $demoFlex, in: 0...100)
                            .onChange(of: demoFlex) { _, value in
                                let raw = Int(2570 - value * 20)
                                let filtered = Int(Double(demoSamples.last?.filtered ?? raw) * 0.85 + Double(raw) * 0.15)
                                demoSamples.append(SensorSample(date: .now, raw: raw, filtered: filtered))
                                if demoSamples.count > 300 { demoSamples.removeFirst() }
                            }
                        Text("Flexão simulada: \(Int(demoFlex))%")
                        Button("Repetição correta simulada") { workout.addRepetition(); demoEvents.append("\(Date.now): repetição simulada") }
                        Button("Repetição incorreta simulada") { workout.simulateError(); demoEvents.append("\(Date.now): erro simulado") }
                    }
                }
                if developer {
                    Section("Sinal ADC") {
                        Chart(samples) { sample in
                            LineMark(x: .value("Hora", sample.date), y: .value("ADC", sample.raw)).foregroundStyle(by: .value("Sinal", "Bruto"))
                            LineMark(x: .value("Hora", sample.date), y: .value("ADC", sample.filtered)).foregroundStyle(by: .value("Sinal", "Filtrado"))
                        }.frame(height: 180)
                        LabeledContent("Bruto / filtrado", value: samples.last.map { "\($0.raw) / \($0.filtered)" } ?? "Indisponível")
                        LabeledContent("Mínimo / máximo (app)", value: workout.demoMode ? "Simulado" : "\(bluetooth.minimum.map(String.init) ?? "—") / \(bluetooth.maximum.map(String.init) ?? "—")")
                        LabeledContent("Oscilação pico a pico (janela, app)", value: "\((samples.map(\.raw).max() ?? 0) - (samples.map(\.raw).min() ?? 0)) ADC")
                        if !workout.demoMode {
                            LabeledContent("Flexão (%)", value: byte(5))
                            LabeledContent("Calibração estendido / flexionado", value: "\(word(6)) / \(word(8))")
                            LabeledContent("Calibrado", value: byte(11))
                            LabeledContent("Estado da máquina (0–3)", value: byte(10))
                            LabeledContent("Limiares extensão / flexão (%)", value: "\(byte(14)) / \(byte(15))")
                            LabeledContent("EMA (%) / zona morta ADC", value: "\(byte(16)) / \(byte(17))")
                            Text("40 amostras; média dos 20 valores centrais; estabilidade 100 ms; duração 350–8000 ms; intervalo mínimo 1000 ms.").font(.footnote)
                        }
                    }
                    if !workout.demoMode {
                        Section("Comunicação e energia") {
                            LabeledContent("BLE", value: bluetooth.status)
                            LabeledContent("RSSI", value: bluetooth.rssi.map { "\($0) dBm" } ?? "Indisponível")
                            LabeledContent("Energia", value: bluetooth.powered.map { $0 ? "Ligado" : "Standby" } ?? "Desconectado")
                            LabeledContent("Bateria", value: bluetooth.battery.map { "\($0)%" } ?? "Indisponível")
                            LabeledContent("Tensão (mV)", value: word(12))
                            LabeledContent("Frequência instantânea (app)", value: bluetooth.frequency.map { String(format: "%.1f Hz", $0) } ?? "Indisponível")
                            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                                Text(bluetooth.lastUpdate.map { "Última telemetria: \($0.formatted()); \(timeline.date.timeIntervalSince($0) > 2 ? "desatualizada" : "recente")" } ?? "Sem telemetria")
                            }
                        }
                    }
                    Section("Testes hápticos") {
                        ForEach(HapticService.Pattern.allCases, id: \.self) { pattern in
                            Button(pattern.rawValue) { HapticService.shared.play(pattern) }
                        }
                    }
                    Section("Registros") {
                        Button("Limpar registros") { bluetooth.clearDiagnostics(); demoSamples = []; demoEvents = [] }
                        Button("Reiniciar mínimos e máximos") { bluetooth.resetExtrema() }
                        Button("Copiar diagnóstico") {
                            UIPasteboard.general.string = "\(workout.demoMode ? "SIMULADO" : "REAL")\n\(bluetooth.diagnostic)\n" + (workout.demoMode ? demoEvents : bluetooth.events).joined(separator: "\n")
                        }
                        ForEach(Array((workout.demoMode ? demoEvents : bluetooth.events).suffix(200).enumerated()), id: \.offset) { _, event in Text(event).font(.caption.monospaced()) }
                        Text("Motivos: 1 duração excessiva; 2 movimento rápido; 3 intervalo curto; 0 teste serial.").font(.footnote)
                    }
                }
            }
            .navigationTitle("Engenharia")
            .toolbar { Button("Concluído") { dismiss() } }
            .onChange(of: developer) { _, enabled in bluetooth.diagnostics(enabled && !workout.demoMode) }
            .onChange(of: workout.demoMode) { _, demo in
                // Disable the real stream before entering isolated demonstration.
                bluetooth.demoMode = false; bluetooth.diagnostics(developer && !demo); bluetooth.demoMode = demo
            }
            .onDisappear {
                let demo = bluetooth.demoMode
                bluetooth.demoMode = false; bluetooth.diagnostics(false); bluetooth.demoMode = demo
            }
        }
    }
}
