---
title: "Landing zone segura en Azure con Terraform"
id: "lab-05-azure-landing-zone"
category: "Nube y seguridad moderna"
type: "Laboratorio"
status: "diseño de referencia"
date: "2026-09-29"
time_to_reproduce: "1 hora sin conexión; 1–2 días para desplegar y verificar en Azure"
skills: [Terraform, Azure Policy, redes de Azure, Microsoft Sentinel, KQL, Microsoft Entra ID, Checkov, Trivy, tflint, GitHub Actions]
frameworks: [Microsoft Cloud Adoption Framework, CIS Microsoft Azure Foundations Benchmark, MITRE ATT&CK]
repo: "https://github.com/santorest/lab-05-azure-landing-zone"
bundle: "Publicado en el sitio del portafolio con su suma SHA-256"
---

# Landing zone segura en Azure con Terraform

> **Resumen:** una landing zone en Terraform para una organización ficticia ("Corp") que cierra las brechas
> habituales de una suscripción de Azure recién creada: grupos de administración con políticas, una red
> hub-spoke donde nada expone un puerto de administración y los servicios de datos no tienen endpoint
> público, Log Analytics y Sentinel con cinco detecciones, y acceso de administrador que solo existe a través
> de PIM. Todo se prueba sin conexión en CI con proveedores simulados, incluidas pruebas que demuestran que el
> código **rechaza** entradas inseguras.
> **Entregable: diseño de referencia. Probado y escaneado en CI, nunca desplegado en Azure.**

| | |
|---|---|
| **Rol asumido** | Ingeniero de seguridad en la nube que construye la primera suscripción de una organización pequeña |
| **Entorno** | Una suscripción de Azure y un tenant de Entra (diseñado para ellos), GitHub Actions (utilizado) |
| **Herramientas** | Terraform (azurerm 4.x, azuread 3.x), Azure Policy, Microsoft Sentinel/KQL, Entra ID, tflint, Checkov, Trivy |
| **Entregable** | 5 módulos + raíz + bootstrap del estado, 52 pruebas sin conexión, 5 detecciones, pipeline de CI, guías de despliegue y desmontaje |

---

## 1. Problema

Una suscripción de Azure nueva empieza siendo permisiva: cualquier región, cualquier IP pública,
administradores con permisos de Owner permanentes, ningún registro centralizado y nada que impida que un
ingeniero bienintencionado abra RDP a Internet. Para una organización pequeña, las amenazas realistas son:

- **Puertos de administración expuestos:** SSH/RDP/WinRM accesibles desde Internet, atacados por fuerza bruta en horas.
- **Endpoints de datos públicos:** cuentas de almacenamiento y key vaults accesibles desde cualquier lugar.
- **Acceso privilegiado permanente:** una sesión de administrador robada es de inmediato Owner de todo.
- **Sin evidencia:** los registros de actividad, de inicio de sesión y de recursos nunca se recopilan, así que no se puede investigar nada.
- **Dispersión y costo:** recursos en regiones inesperadas, sin etiquetas y sin alerta de presupuesto.

El objetivo: codificar las protecciones una sola vez, como código, para que cada suscripción empiece cerrada.

## 2. Arquitectura

![Arquitectura](diagrams/architecture.png)

| Área | Qué crea el código |
|---|---|
| Gobernanza | `corp` → `platform` (connectivity, management, identity), `landing-zones` (online, internal), `sandbox`; políticas en `corp`: ubicaciones permitidas, tres etiquetas obligatorias, denegar IP pública (personalizada), diagnóstico de Key Vault (DeployIfNotExists); presupuesto mensual con alertas al 50/80/100 % |
| Red | Hub + dos spokes, emparejados; cada subred que lo admite tiene un NSG que termina en denegar todo el tráfico entrante; almacenamiento y Key Vault solo mediante endpoints privados con zonas DNS privadas; Azure Firewall Basic opcional (desactivado) |
| Registros | Log Analytics (90 días), Sentinel, configuración de diagnóstico para el registro de actividad, cada NSG, el almacenamiento de blobs, Key Vault y los registros de inicio de sesión y auditoría de Entra; cinco reglas de análisis programadas |
| Identidad | Tres grupos de Entra; acceso condicional (MFA para administradores, MFA para todos, bloquear autenticación heredada) en modo solo informe; Owner, User Access Administrator y Global Administrator solo como asignaciones elegibles en PIM |
| Estado | Bootstrap aparte: cuenta de almacenamiento con autenticación solo de Entra, versionado, eliminación temporal, acceso desde una sola IP y un bloqueo CanNotDelete |

## 3. Construcción

### Gobernanza
Las políticas se asignan en el grupo de administración raíz para que todas las suscripciones las hereden. Los
ID de las definiciones integradas y los nombres de sus parámetros se verificaron contra el repositorio
`Azure/azure-policy` de Microsoft antes de usarlos. La política personalizada *denegar IP pública* tiene una
excepción prevista: si se activa el firewall, su grupo de recursos recibe una exención. Es una exención de
grupo de recursos y no de grupo de administración, porque una sola suscripción solo puede estar bajo un grupo
de administración.

### Red
La validación de entradas del módulo `network` es el núcleo. Cualquier regla de NSG adicional que permita el
tráfico entrante a 22, 3389, 5985 o 5986 desde `Internet`, `*`, `Any`, `0.0.0.0/0` o `::/0` se rechaza al
planificar, ya sea que el puerto aparezca solo, dentro de un rango (`20-25`, `1-65535`), dentro de una lista o
como `*`. Las reglas deben apuntar a una subred que exista y tenga NSG, con prioridades únicas entre 100 y 4000
(la 4096 queda reservada para la regla de denegar todo).

### Registros y detecciones
Las detecciones son datos: `detections/rules.yaml` contiene los metadatos de cada regla y su mapeo a ATT&CK, y
cada consulta es un archivo `.kql`. El módulo de registros hace fallar el plan si una consulta queda huérfana o
falta, o si una regla no tiene táctica.

| Regla | Fuente | ATT&CK |
|---|---|---|
| Rol privilegiado de Azure asignado (Owner / User Access Administrator) | AzureActivity | T1098 Account Manipulation |
| Regla de NSG que permite tráfico entrante desde Internet | AzureActivity | T1562 Impair Defenses |
| Directiva de acceso condicional creada, modificada o eliminada | AuditLogs | T1556 Modify Authentication Process |
| Eliminación masiva de recursos por un mismo autor (≥ 10 en 15 min) | AzureActivity | T1485 Data Destruction |
| Inicio de sesión correcto desde un país fuera de la lista permitida | SigninLogs | T1078 Valid Accounts |

### Identidad
El acceso condicional empieza en modo solo informe, y el módulo rechaza `ca_state = "enabled"` si no se indica
un grupo de acceso de emergencia (break glass), que queda excluido de todas las directivas. Owner, User Access
Administrator y Global Administrator son asignaciones **elegibles** de PIM, nunca activas. La elegibilidad de los
dos roles de Azure caduca a los 365 días; la de Global Administrator no tiene caducidad en Terraform (el recurso de
azuread no permite fijarla), así que su duración depende de la configuración de roles de PIM del tenant. Un paso de
CI falla si Terraform concede acceso permanente a un rol privilegiado, ya sea por su nombre (sin importar
mayúsculas) o por su ID.

## 4. Cómo se valida

No hay credenciales de Azure en ninguna parte del repositorio ni de su CI. Cada push y pull request ejecuta:

| Trabajo | Qué comprueba |
|---|---|
| fmt | `terraform fmt -check -recursive` |
| terraform (×7) | `init -backend=false`, `validate` y `terraform test` en `bootstrap/`, `landing-zone/` y cada módulo |
| tflint | Conjunto de reglas de azurerm (SKU, regiones y atributos no válidos) y buenas prácticas de Terraform |
| checkov | Configuraciones incorrectas en Terraform; SARIF a code scanning |
| trivy-config | Configuraciones incorrectas en Terraform, bloquea en High/Critical; SARIF a code scanning |
| policy-checks | Ningún acceso privilegiado permanente (y la comprobación se prueba a sí misma con un archivo incorrecto conocido) |
| secrets | gitleaks sobre todo el historial de git |

`terraform test` usa **proveedores simulados**: los esquemas reales de azurerm/azuread y su validación de
argumentos, pero sin llamadas a la API. Las pruebas positivas verifican las propiedades de seguridad de lo que
se crearía. Las pruebas negativas (`expect_failures`) verifican lo que el código rechaza:

| El código rechaza… | Prueba |
|---|---|
| RDP/SSH/WinRM desde Internet, escrito de seis formas distintas | `network`: 6 pruebas |
| Reglas de NSG en una subred inexistente o exenta de NSG, prioridades duplicadas o fuera de rango | `network`: 4 pruebas |
| Una landing zone sin hub | `network` |
| Lista de ubicaciones vacía, ubicación desconocida para la suscripción, ID de suscripción que no es un GUID | `governance` |
| Un presupuesto que no empieza el día 1 de un mes o no tiene contactos | `governance` |
| Aplicar el acceso condicional sin break glass; un estado de directiva mal escrito; un ID de break glass vacío o que no es un GUID | `identity` |
| Desajustes en las detecciones: consulta huérfana, archivo de consulta inexistente, regla sin tácticas (un caso de prueba para cada uno) | `logging` |
| Activar el firewall sin sus subredes | `firewall` |
| Una IP de despliegue que es un rango, privada o reservada | `bootstrap` |
| Etiquetas raíz sin `owner` / `env` / `cost-center`, o vacías; una `location` fuera de `allowed_locations` | `landing-zone` |

## 5. Resultados

Los únicos resultados de este laboratorio son salidas de pruebas y escáneres; no hay despliegue del que informar.

| Comprobación | Resultado |
|---|---|
| `terraform test`, ejecución local del 2026-09-30 tras las correcciones de la revisión final (Terraform 1.16.2) | **52 correctas, 0 fallidas** (bootstrap 3, governance 9, network 15, firewall 3, logging 9, identity 8, landing-zone 5) |
| Checkov 3.3.20, ejecución local | **50 correctas, 0 fallidas, 11 omitidas, 0 errores de análisis**. Cada omisión está justificada en `security/EXCEPTIONS.md` |
| tflint 0.64.0 + reglas azurerm 0.32.0, ejecución local | **0 problemas** (una regla ignorada en 4 recursos, justificada) |
| PR de demostración [#9](https://github.com/santorest/lab-05-azure-landing-zone/pull/9): RDP desde Internet ([detalles](docs/demo-prs.md), en inglés) | **Rechazado**: `terraform (landing-zone)` falló en la validación de puertos de administración; los otros 12 trabajos pasaron, **incluidos Checkov y Trivy, que no detectaron la regla** |
| CI en GitHub Actions, [ejecución 36666439154](https://github.com/santorest/lab-05-azure-landing-zone/actions/runs/36666439154) (commit `baa9e49`, Terraform 1.16.4) | **13/13 trabajos correctos**: las mismas 47 pruebas; Checkov 49 correctas / 0 fallidas / 9 omitidas; Trivy 0 High/Critical (sus 5 hallazgos Low/Medium son las mismas concesiones de almacenamiento, ignoradas con motivo); tflint sin problemas; ningún acceso privilegiado permanente; gitleaks: sin fugas |

## 6. Qué se verificó y qué no

**Verificado** (con pruebas y escáneres, sin conexión):
- El Terraform es válido frente a los esquemas reales de azurerm 4.81 / azuread 3.10, incluida la validación de
  argumentos. Los simulacros detectaron errores reales de esta forma: las subredes de un Azure Firewall deben
  llamarse `AzureFirewallSubnet` y `AzureFirewallManagementSubnet`.
- Las propiedades de seguridad de la sección 4: qué se crea, dónde se asignan las políticas, qué es privado,
  qué está en modo solo informe o solo elegible, y cada rechazo de las pruebas negativas.
- La línea base de los escáneres: ninguna comprobación fallida de Checkov o tflint fuera de las excepciones documentadas.

**No verificado** (solo un `plan`/`apply` real en Azure lo mostraría):
- Que Azure acepte cada recurso al aplicarlo (validación de la API, disponibilidad de nombres, cuotas, SKU por
  región, retrasos de propagación de los grupos de administración).
- Que las políticas realmente denieguen lo que deben y que la corrección DeployIfNotExists funcione.
- El comportamiento del acceso condicional y la activación de PIM (ambos requieren Entra ID P1/P2).
- Que las consultas KQL se analicen correctamente y las detecciones se disparen con eventos reales.
- La puntuación de seguridad de Defender for Cloud antes y después: [docs/measure-posture.md](docs/measure-posture.md)
  describe el procedimiento, y no se afirma ninguna puntuación.
- El costo real. Las cifras de [docs/teardown-and-cost.md](docs/teardown-and-cost.md) son estimaciones a precio de lista.

## 7. Decisiones de diseño y lecciones

El razonamiento completo está en [docs/design-decisions.md](docs/design-decisions.md) (en inglés). En resumen:
NSG en lugar de firewall (costo), acceso condicional en modo solo informe con break glass (riesgo de quedarse
fuera), roles de administrador solo elegibles, exención de política por grupo de recursos, configuración parcial
del backend y detecciones como datos.

Lecciones de la construcción:
- **Los proveedores simulados no ignoran el esquema.** Siguen ejecutando la validación de argumentos del
  proveedor real, así que los ID simulados deben parecer ID reales de Azure. La ventaja: detectaron sin conexión
  la regla de nombres de las subredes del firewall.
- **El modo plan no ve los valores generados.** Las aserciones sobre ID fallan con `command = plan`, así que las
  pruebas positivas usan `command = apply` contra los simulacros (sin llamadas a la API) y las negativas usan `plan`.
- **Un escáner puede fallar en silencio.** Checkov informó "Parsing errors: 1" y omitió por completo el módulo de
  gobernanza porque no podía analizar las claves `if`/`then` sin comillas dentro de `jsonencode`. Al ponerlas entre
  comillas, el módulo se pudo escanear, y ahora la CI falla ante cualquier error de análisis de Checkov.
- **ID simulados idénticos hacen que las aserciones pasen sin probar nada.** La revisión final encontró dos
  aserciones (qué grupo recibe la elegibilidad de PIM y qué zona DNS usa el Key Vault) que habrían pasado con un
  cableado incorrecto, porque todos los grupos o zonas simulados tenían el mismo ID. Ahora usan ID distintos
  mediante overrides, y cada una se comprobó rompiendo el código a propósito y viendo fallar la prueba.
- **Un hallazgo de escáner reveló un fallo real de diseño.** El Key Vault tenía el acceso público desactivado y
  ningún endpoint privado, así que nada podía alcanzarlo. La comprobación CKV2_AZURE_32 de Checkov lo señaló, y la
  solución fue un endpoint, no una omisión.
- **El `&&` de Terraform no cortocircuita.** Una validación del tipo "es una IP *y* no es privada" producía un error
  de evaluación con entradas mal formadas en lugar del mensaje previsto, hasta envolverla en `try(…, false)`.
- **Los escáneres estáticos no ven lo que llega por variables.** En el PR de demostración de RDP, la regla insegura
  venía del valor por defecto de una variable a través del `for_each` de un módulo; Checkov y Trivy la dejaron pasar.
  La validación de entradas (y sus pruebas) la rechazó. Los escáneres son la segunda línea, no el control.
- **La CI demostró su valor el primer día.** La primera ejecución de Dependabot propuso azurerm 5.x para todos los
  módulos; las pruebas fallaron por sus cambios incompatibles de esquema (los vínculos de zonas DNS privadas usan
  otros argumentos). Las versiones mayores de los proveedores ahora se excluyen en `dependabot.yml` y se migrarán
  de forma deliberada.
- **`prevent_destroy` choca con las pruebas.** No puede variar por entorno y bloquea el desmontaje que hace el propio
  `terraform test`. La cuenta del estado usa en su lugar un bloqueo de administración CanNotDelete.

## 8. Reprodúcelo

- Clonar: `git clone https://github.com/santorest/lab-05-azure-landing-zone.git`
- Ejecutar todas las comprobaciones sin conexión: `bash scripts/test-all.sh` (Terraform ≥ 1.9, sin cuenta de Azure).
- Desplegar: [docs/deploy.md](docs/deploy.md); desmontar: [docs/teardown-and-cost.md](docs/teardown-and-cost.md).
- Descargar el paquete: desde el sitio del portafolio (la suma SHA-256 aparece junto a la descarga).

## 9. Mapeo

| Área | Marco | Cómo lo aborda este proyecto |
|---|---|---|
| Organización de recursos; gobernanza | Microsoft Cloud Adoption Framework (áreas de diseño de landing zones) | Jerarquía de grupos de administración, políticas en la raíz, etiquetas, presupuesto |
| Topología de red y conectividad; seguridad | Microsoft Cloud Adoption Framework | Hub-spoke, NSG con denegación por defecto, endpoints privados, firewall opcional |
| Gestión de identidades y accesos | Microsoft Cloud Adoption Framework | Grupos, acceso condicional, elegibilidad en PIM, break glass |
| Administración; automatización de la plataforma y DevOps | Microsoft Cloud Adoption Framework | Registros centralizados, Sentinel, IaC con módulos probados y controles en CI |
| Secciones de identidad, cuentas de almacenamiento, registro y supervisión, redes y Key Vault | CIS Microsoft Azure Foundations Benchmark | MFA/acceso condicional y PIM; almacenamiento privado con TLS 1.2 y sin claves compartidas; diagnóstico del registro de actividad y de recursos; ningún puerto de administración desde Internet; Key Vault con RBAC, protección de purga y sin acceso público |
| T1098, T1562, T1556, T1485, T1078 | MITRE ATT&CK | Una regla de Sentinel para cada una (sección 3) |

---

*Organización ficticia, solo ID de ejemplo (GUID en ceros). Nada de este repositorio se desplegó, y no incluye
datos, tenants ni configuraciones de ninguna organización real.*
