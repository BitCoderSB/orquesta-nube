# orquesta-nube

Plugin de Claude Code para que **tu chat local mande trabajo a la nube**: tú sigues
trabajando en tu chat, le pides «haz esto en la nube», y él solo:

1. lanza una o varias sesiones de Claude Code en la nube (cada una es una máquina
   aparte), sin tarjetas ni botones de «Iniciar»;
2. espera en segundo plano sin gastar, y despierta cuando entregan;
3. lee lo que dejaron en su rama de GitHub (`nube-<nombre>`);
4. les responde si preguntan algo, y sigue esperando;
5. te da el análisis final.

Sirve para pruebas largas, mediciones, builds y tareas pesadas cuando tu PC es lenta.

## Instalar

Dile a tu Claude Code:

> Instala el plugin orquesta-nube: `claude plugin marketplace add BitCoderSB/orquesta-nube`
> y luego `claude plugin install orquesta-nube@orquesta-nube`. Después reinicia la sesión.

O hazlo tú en una terminal con esos mismos dos comandos.

## Requisitos

- El comando `claude` (Claude Code CLI) en el PATH, con la sesión iniciada en una cuenta
  de claude.ai: `claude auth login` (una vez).
- Un repositorio con remoto en GitHub y la nube de Claude Code habilitada para él
  (claude.ai/code).
- `bash` (en Windows, Git Bash, el mismo que usa Claude Code) y `git`.

## Usar

Dentro de un chat, en tu repositorio:

> Corre las pruebas en la nube repartidas en 4 máquinas y dime qué falló.

> Mide esto en la nube. Puedes subir mis cambios a una rama `nube-base-...` para que los vea.

## Lo que hay que saber

- **La nube clona tu rama tal como está en GitHub.** No ve los commits sin subir ni los
  cambios sin commit. Si hacen falta, el chat te pedirá permiso **una vez** para subirlos
  a una rama aparte (`nube-base-…`); tu rama no se toca.
- **Deja la PC encendida y Claude abierto** mientras la nube trabaja: el vigilante que
  despierta al chat corre en tu PC.
- Las ramas `nube-*` quedan en GitHub hasta que pidas borrarlas.

## Cómo funciona

`scripts/nube.sh` hace todo el trabajo:

- `lanzar` ejecuta `claude --cloud` en una consola real: una ventana minimizada de
  PowerShell en Windows, o `script` en Mac y Linux.
- `vigilar` espera a que cambie la rama de entrega.
- `leer` baja la rama y muestra `.nube/ESTADO.md` y `.nube/INFORME.md`.
- `responder` usa `claude -p "<mensaje>" --cloud <sesión>`.

El skill `nube` le explica al chat cuándo y cómo usar cada comando.
