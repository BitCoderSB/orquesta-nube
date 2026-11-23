# orquesta-nube

Plugin de Claude Code para que **tu chat local mande trabajo a la nube**. Tú sigues
trabajando en tu chat, le pides «haz esto en la nube», y él solo:

1. lanza una o varias sesiones de Claude Code en la nube (cada una es una máquina Linux
   aparte), sin tarjetas ni botones de «Iniciar»;
2. espera en segundo plano sin gastar, y se despierta cuando entregan;
3. lee lo que dejaron en su rama de GitHub (`nube-<nombre>`);
4. les responde si preguntan algo, y sigue esperando;
5. te da el análisis y limpia: guarda una copia local y borra la rama.

Sirve para pruebas largas, mediciones, builds y tareas pesadas cuando tu PC es lenta.

## Instalar

Dile a tu Claude Code:

> Instala el plugin orquesta-nube del repo BitCoderSB/orquesta-nube

Luego abre un chat nuevo. La primera vez, el plugin revisa que todo esté en orden y te
dice qué falta.

## Dos modos

| | Modo consola (recomendado) | Modo app |
|---|---|---|
| Requisito | Claude Code de consola con `--cloud` y `claude auth login` (una vez; el inicio de sesión dura unas semanas) | Nada más: usa la app de escritorio |
| Permisos | Ninguno: lanza sin preguntar | La app pide permiso **en cada sesión** |
| Código que ve la nube | Tu rama actual, tal como está en GitHub | La rama por defecto del repositorio |
| Responder a la nube | Sí, solo | Necesita tu aprobación en esa sesión |

El plugin elige solo: si la consola está lista, usa el modo consola; si no, el modo app,
y te dice cómo pasarte al primero.

## Requisitos
- **Repositorio en GitHub** con Claude Code en la nube habilitado (claude.ai/code).
- **`git` y `bash`.** En Windows, Git Bash, el mismo que usa Claude Code.

**Probado en Windows.** Mac y Linux tienen su camino en el script, pero todavía no se
han probado.

## Usar

En un chat dentro de tu repositorio, por ejemplo:

> Corre las pruebas en la nube repartidas en 4 máquinas y dime qué falló.

> Mide esto en la nube; puedes subir mis cambios para que los vea.

## Lo que hay que saber

- **Qué ve la nube.** Clona tu rama tal como está en GitHub, sin lo que no hayas subido.
  Si hace falta, el chat te pide permiso una vez y sube tus cambios a una rama aparte
  (`nube-base-<tema>`) **sin tocar la tuya**. No sube archivos sin rastrear, como un
  `.env` nuevo.
- **Privacidad.** Si tu repositorio es **público**, las ramas `nube-*` también lo son
  mientras existen. El plugin te avisa.
- **Uso del plan.** Cada sesión en la nube consume uso de tu plan.
- **PC encendida y Claude abierto.** El vigilante que despierta al chat corre en tu PC.
- **Resultados.** Se guardan en `.git/nube/resultados/<nombre>/` de tu repositorio local.
- **Chats de nube.** Quedan en tu lista de claude.ai/code y hay que archivarlos a mano:
  dentro de la nube, archivar pide un permiso que no se puede dar desde fuera.

## Problemas frecuentes

| Mensaje | Qué hacer |
|---|---|
| `MODO=app` | Funciona, pero pedirá permiso por sesión. Para evitarlo: `claude auth login` en una terminal |
| `native binary not installed` | Reinstalar Claude Code (instalación por npm a medias) |
| `NO SE CREO LA SESION` | Leer el motivo que imprime; suele ser la sesión o el repositorio |
| `TIEMPO AGOTADO` | Abrir el enlace de la sesión (`lista`): puede estar esperando un permiso |

## Cómo funciona

`scripts/nube.sh` hace todo el trabajo, con estos comandos:

| Comando | Qué hace |
|---|---|
| `revisar` | Comprueba que todo esté listo |
| `subir-base` | Sube tus cambios a una rama aparte |
| `lanzar` | Ejecuta `claude --cloud` en una consola real: PowerShell minimizada en Windows, `script` en Mac y Linux |
| `vigilar` | Espera a que cambie alguna rama de entrega |
| `leer` | Muestra `.nube/ESTADO.md` e `.nube/INFORME.md` |
| `responder` | Envía un mensaje a la sesión: `claude -p … --cloud <sesión>` |
| `limpiar` | Guarda una copia y borra la rama, solo si no cambió desde que se leyó |

El skill `nube` le explica al chat cuándo y cómo usar cada comando.

Desinstalar: `claude plugin uninstall orquesta-nube@orquesta-nube`.
