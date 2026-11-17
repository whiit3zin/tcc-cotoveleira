# Metadados do IPA e instalação pelo Sideloadly

O projeto Xcode é gerado por `xcodegen generate` a partir de `project.yml`.
O `.xcodeproj` não é versionado. Ambos os targets agora usam os valores globais
`MARKETING_VERSION = 1.0.0` e `CURRENT_PROJECT_VERSION = 3`.
Os dois plists referenciam essas configurações; a expansão ocorre no build.
Não copie o plist de fontes diretamente para um `.app` já compilado.

O plist anterior do WorkoutWidget só continha `NSExtension`, sem versões
explícitas. Isso é compatível com o erro `bundleVersion must be set` informado.
Sem o IPA que falhou, não foi possível confirmar seu conteúdo efetivo.
O widget fornece a Live Activity e a Dynamic Island do treino e foi preservado.

## Gerar e verificar no macOS

Com Xcode 26 e XcodeGen instalados, na raiz do repositório:

```sh
xcodegen generate
xcodebuild -project CotoveleiraInteligente.xcodeproj -scheme CotoveleiraInteligente -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
python3 scripts/check_bundle.py build/Build/Products/Release-iphoneos/CotoveleiraInteligente.app
mkdir -p staging/Payload
ditto build/Build/Products/Release-iphoneos/CotoveleiraInteligente.app staging/Payload/CotoveleiraInteligente.app
(cd staging && zip -qry ../CotoveleiraInteligente-unsigned.ipa Payload)
python3 scripts/check_bundle.py CotoveleiraInteligente-unsigned.ipa
```

Use uma pasta `staging` nova/vazia para evitar incorporar arquivos de builds
anteriores. O workflow `.github/workflows/ios.yml` faz o build em macOS, valida o
`.app`, cria o IPA e valida novamente os plists dentro do ZIP antes do upload.

O validador aceita plists XML/binários e exige versões numéricas resolvidas e
iguais, identificadores relacionados, tipos APPL/XPC!, executáveis presentes,
plataforma iPhoneOS, iOS mínimo 18.0 e a extensão em
`Payload/CotoveleiraInteligente.app/PlugIns/WorkoutWidget.appex`.
Também preserva as verificações de metadados de Bluetooth e Live Activities.
Não analisa o código Mach-O, arquitetura, entitlements ou validade criptográfica.

## Assinatura e instalação

O IPA desse workflow é deliberadamente **sem assinatura**, para ser assinado
com a conta do usuário no Sideloadly. Ele não está pronto para instalação direta.
O build da CI continua desativando assinatura pela linha de comando; os targets
não bloqueiam mais assinatura globalmente, permitindo configurar o mesmo Team
para app e extensão no Xcode em builds assinados.
Não há certificados, perfis ou entitlements personalizados no repositório.

No Sideloadly, use o IPA gerado com assinatura pela sua Apple ID e mantenha as
extensões incluídas. App e extensão precisam ser assinados/provisionados pelo
fluxo de instalação. A assinatura e a aceitação no dispositivo só podem ser
confirmadas com esse fluxo; a verificação de metadados não garante instalação.
Se exportar um app assinado no macOS, verifique também cada bundle:

```sh
codesign --verify --strict --verbose=2 Payload/CotoveleiraInteligente.app/PlugIns/WorkoutWidget.appex
codesign --verify --deep --strict --verbose=2 Payload/CotoveleiraInteligente.app
```

Esses comandos verificam assinatura local; não substituem checar perfis,
entitlements e instalação no iPhone 16. Após instalar, valide também a Live
Activity em treino real. Não remova o widget como contorno deste erro.

## Validação disponível no Windows

```powershell
py scripts/verify_integration.py
py -m unittest discover -s scripts -p 'test_*.py'
git diff --check
```

Os testes do validador usam fixtures temporárias sintéticas, sem binários iOS
reais; cobrem inclusive a ausência de CFBundleVersion na extensão, versões
divergentes e empacotamento inválido. Não produzem um IPA instalável.
Nesta correção não houve build Xcode, execução do workflow, validação de IPA
real, assinatura ou instalação física, pois o ambiente disponível é Windows e
não contém Xcode/XcodeGen nem um IPA para inspeção.
