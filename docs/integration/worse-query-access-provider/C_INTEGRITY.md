# C. Informe de integridad

## 1. Referencias

- `main` protegido: `df99bf2fbb32b86966990077864a9d355271197b`.
- Rama: `feature/worse-query-access-provider`.
- Manifiesto completo del baseline: `BASELINE_SHA256.tsv`.
- Manifiesto de componentes protegidos: `PROTECTED_COMPONENTS.sha256`.
- SHA-256 del manifiesto protegido:
  `49670d8bd59f331b31efae3d3dc82bb3e547e5e8b573f86f5e9f029a451726ab`.
- Componentes protegidos verificados: **102**, con **0 diferencias**.

El CI ejecuta `shasum -a 256 -c PROTECTED_COMPONENTS.sha256` y además
intersecta `git diff --name-only df99bf2 HEAD` con la lista protegida; el job
falla si aparece cualquier ruta protegida.

## 2. Componentes protegidos (extracto)

| Componente | SHA-256 baseline | Estado final |
|---|---|---|
| `ThreeOneOSFive/exploit/bad_query.c` | `d119cd7343451d0909236c1f9258dd902323472bd47c9bc36a23aa19d70738a7` | sin cambios |
| `ThreeOneOSFive/exploit/bad_query.h` | `3c4bca13792b926d3336b0bf0673c59ffdc9a666bddd6da266575ef0328e1bc9` | sin cambios |
| `ThreeOneOSFive/exploit/mcm_bridge.m` | `cd969890e82b1e75c920a7611d888accd9a2c4b42fd4b587147509d938b1252f` | sin cambios |
| `ThreeOneOSFive/exploit/mcm_bridge.h` | `1ecc334319183f57113f989699a8c4da309ae0cc8380dc2fcdd6186cf3c2477d` | sin cambios |
| `ThreeOneOSFive/helpers/PatchTransaction.swift` | `77e6094ad64d29377a2e9d9906a1c4a3472152412b73ce05b0f9ac8be9bc15a7` | sin cambios |
| `ThreeOneOSFive/helpers/PatchProjectModels.swift` | `e51668a02985a705e42478147d1a547c284c4cedf4e70782b78bb80f390447d6` | sin cambios |
| `ThreeOneOSFive/helpers/ContainerBrowserLogic.swift` | `3991548def1cce1eff725ff716c1910e33910976af7c291414f0aa5f748c8a46` | sin cambios |
| `ThreeOneOSFive/helpers/ContainerIdentityResolver.swift` | `610b0e8ae7b8b599ba38ec2ca7e998eb1a6b5819f1b6043d29e9fc336dff8077` | sin cambios |
| `ThreeOneOSFive/helpers/FileManagerService.swift` | `57ddc1ec6126ca0c1bc5b329871dc36c9bd435eefebef5d469abe36a6c436795` | sin cambios |
| `ThreeOneOSFive/Info.plist` | `c1322976af99801cbb440bd0690077d532bcc88da768ad3f8f6f0ba5b42a22ad` | sin cambios |
| `ThreeOneOSFive/kexploit/*` | 12 archivos en el manifiesto | sin cambios |
| `ThreeOneOSFive/views/*` | todos los archivos en el manifiesto | sin cambios |
| `.github/workflows/main.yml` | `549162debd28554eadade8ea570d7b94548be6202568be32641cfe8fa8729678` | sin cambios |
| `.github/workflows/fix-login-files.yml` | `03eb2f7f714f3a306e2abf4f5672a7cc32a70e3e0a407fcc2b1a2087625b7295` | sin cambios |
| `vini-v2-cloudflare/*` | incluido en el manifiesto | sin cambios |

## 3. Proveedor vendorizado

| Archivo | SHA-256 | Estado |
|---|---|---|
| `ThirdParty/worse_query/worse_query.h` | `02c919ddec399349ff0a8c1230fea01d590fd30880688da6edbb51ac38365408` | idéntico a upstream |
| `ThirdParty/worse_query/worse_query.m` | `edad488641c58bdcfaa30622a5f1c8bcb08c1990d7dfeb1cb26c473ce3cd8c51` | idéntico a upstream |
| `ThirdParty/worse_query/LICENSE` | `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986` | idéntico a upstream |
| `ThirdParty/worse_query/README.md` | `5a15983bc7378efb27ffe2beda65a81aff69b3ea4d9069dca3b116cdb00b5716` | idéntico a upstream |

Upstream de referencia: `https://github.com/forcequitOS/worse_query`.
No se modificó ni una línea del motor; el adaptador vive fuera de
`ThirdParty/worse_query`.

## 4. Archivos de integración (modificados o nuevos)

| Archivo | SHA-256 final | Tipo |
|---|---|---|
| `ThreeOneOSFive/helpers/ContainerStore.swift` | `5a217a1fc2219298c1b0b7df80bfc35a3b08ab9bda76ac705dfbe825ec32fd77` | modificado |
| `ThreeOneOSFive/helpers/DevicePatchService.swift` | `3c83f8fcb39fde7335a0dcf30584666091aa4cc373dc7cecb9af2b450fcadbec` | modificado |
| `ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h` | `2056f4dd33711e79ab77ee4156b5a4d9894c8244fc3f858d11306373a4269500` | modificado |
| `ThreeOneOSFive.xcodeproj/project.pbxproj` | `a623aec34eab9126c7bbe58c33e8524568a20a240a590043ff3bdf0e9a66ce84` | modificado |
| `ThreeOneOSFive/helpers/WorseQueryAccessProvider.swift` | `d19a38e4271f47634df3697348fad79072333eb4f82b33ca3df2d5506055f888` | nuevo |
| `ThreeOneOSFive/helpers/WorseQueryProviderPolicy.swift` | `8d54ff3df14599256ee48413b66502272dcd870a87bba29f641695fb57b09c6a` | nuevo |
| `ThreeOneOSFive/helpers/WQEntitlements.m` | `2fb33766f8a7d4f1f2123fa68954bd12ad1c0861c530fae548bbb820cd568770` | nuevo |
| `ThreeOneOSFive/helpers/WQEntitlements.h` | `2a59b018e62df1582970712893b9795e8dcc0750989ef4e99b838c621b0517c9` | nuevo |
| `Tests/WorseQueryProviderPolicyTests.swift` | `eab0e3452b2dd1fe5555c0140ada9968e17534521db39455d7a60d0cf4d2cfa1` | nuevo |
| `Tests/ContainerIdentityContractTests.swift` | `440019d8f5ba3ed16b8d1db4b1914b932bdcf6fdabc1f852afc530399f31524e` | nuevo |
| `.github/workflows/worse-query-access-provider.yml` | `af6662e1601fa5d833fdf1a29f8c98cb3ade23399ff3cce5612390490f78573f` | nuevo |

## 5. Comparación con el binario

El CI compara la configuración de firma y el Bundle ID del producto construido
(`built-product.txt`, `signing-posture.txt`). No se firma con identidad real en
CI; por tanto no se afirma que los entitlements del `.app` experimental
coincidan con los de una firma de producción. Esa comparación queda
`PENDIENTE` para el dispositivo (ver informe E).
