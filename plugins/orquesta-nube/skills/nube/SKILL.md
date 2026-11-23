---
name: nube
description: Mandar trabajo a la nube (Claude Code on the web) orquestado desde este chat, sin pedir permisos ni clics al usuario. Úsalo cuando el usuario pida hacer algo «en la nube», «en la cloud», «en otra máquina» o «en varias máquinas en paralelo», o cuando diga que no quiere correr en su PC algo pesado (pruebas largas, mediciones, builds).
allowed-tools: Bash(bash *nube.sh*), Read, Write
---

# Orquestar sesiones en la nube

El chat local es el orquestador: lanza sesiones en la nube, espera sin gastar a que
entreguen, lee lo que dejaron, les responde si preguntan, analiza el resultado y limpia.
El usuario no tiene que pulsar nada. Responde al usuario en su idioma.

Todo pasa por un solo script (en adelante `NUBE`), ejecutado desde la carpeta del
repositorio del usuario:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nube.sh" <comando> ...
```

## Qué NO usar

No uses `start_session` con `target: "cloud"`, ni el panel de terminal
(`run_in_terminal`), ni `Agent` con `isolation: "remote"`. Los dos primeros piden permiso
al usuario cada vez, y el tercero puede acabar corriendo en su PC.

## Antes de la primera tarea

1. **Revisar.** Ejecuta `NUBE revisar`.
   - `FALTA: iniciar sesión`: pide al usuario que ejecute `claude auth login` en una
     terminal y que pegue él el código. Tú nunca escribes códigos ni contraseñas.
   - Cualquier otro `FALTA`: díselo al usuario tal cual.
   - Si dice que el repositorio es **público**, avísale una vez: lo que se suba a las
     ramas `nube-*` lo puede ver cualquiera.
2. **Qué código ve la nube.** La nube clona la rama actual **tal como está en GitHub**:
   no ve los commits sin subir ni los cambios sin commit, y `revisar` dice cuántos hay.
   Si la tarea los necesita, pregunta al usuario **una vez** si puedes subirlos a una
   rama aparte. Con su sí:
   - Ejecuta `NUBE subir-base <tema>`. Sube a `nube-base-<tema>` tus cambios con y sin
     commit **sin tocar la rama del usuario**, y no incluye archivos sin rastrear.
   - Empieza la tarea con `git fetch origin nube-base-<tema> && git checkout FETCH_HEAD`.

   Sin su sí, sigue con lo que está en GitHub y avísale.

## Cuántas máquinas

- Una por parte independiente. Usa más de una solo si reparte de verdad: pruebas por
  grupos (`vitest --shard=i/N`, `pytest` por carpetas), varios experimentos, varias
  mediciones.
- Por defecto, hasta **4**, salvo que el usuario pida otra cosa. Cada sesión consume uso
  del plan del usuario y tarda unos minutos en arrancar e instalar dependencias.

## Escribir la tarea

La sesión de nube no tiene tu conversación, ni la memoria, ni archivos locales: la tarea
debe bastarse sola. Escríbela en un archivo (con la herramienta Write) siguiendo esta
plantilla:

```
OBJETIVO: <qué hay que averiguar o hacer, en una frase>
PREPARAR: <instalación: npm ci, pip install -r ..., etc.>
HACER: <comandos exactos; para repartir, qué parte le toca (p. ej. --shard=2/4)>
GUARDAR EN .nube/: <qué archivos dejar además de INFORME.md: logs, json...>
LÍMITE: <tiempo máximo razonable; si se pasa, corta y entrega lo que haya con ESTADO: ERROR>
```

El script añade solo las reglas de entrega: `.nube/ESTADO.md` e `.nube/INFORME.md`,
subir a su rama, no preguntar en el chat y no subir secretos.

## Lanzar

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nube.sh" lanzar <nombre> <archivo-tarea>
```

- **Nombre.** Minúsculas, números y guiones, único (`pruebas-1`, `pruebas-2`…). Su rama
  de entrega será `nube-<nombre>`. Si el nombre ya existe, el script lo rechaza.
- **Varias sesiones.** Lánzalas una tras otra: cada lanzamiento tarda unos segundos.
- **Resultado esperado.** Debe salir `LANZADA ... sesion=session_...`. Si sale
  `NO SE CREO LA SESION`, cuéntale al usuario el motivo que imprime.

## Esperar sin gastar

Deja el vigilante en segundo plano (`run_in_background: true`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nube.sh" vigilar <minutos> <nombre1> <nombre2> ...
```

- **Minutos.** Calcúlalos con holgura: unos 5 de arranque más lo que tarde la tarea.
- **No sondees.** El vigilante termina en cuanto **alguna** rama cambia, y la app te
  despierta sola. No hagas sondeos ni `sleep` por tu cuenta.
- **Al despertar.** Ejecuta `NUBE leer <nombre>` por cada nombre que diga `CAMBIO:`, y
  según su estado:
  - `ESTADO: TERMINADO`: guarda el resultado.
  - `ESTADO: PREGUNTA`: respóndele (ver abajo).
  - `ESTADO: ERROR`: si el fallo es de la propia nube (instalación, red), relanza
    **una** vez con otro nombre; si se repite, informa.
- **Las que faltan.** Si quedan sesiones sin entregar, vuelve a lanzar `vigilar` solo
  con esas.
- **`TIEMPO AGOTADO`.** Dile al usuario cuáles no entregaron y el enlace de cada una
  (`https://claude.ai/code/<sesion>`, en `NUBE lista`). Puede que estén esperando un
  permiso dentro de la propia sesión.

## Responder a una sesión de nube

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nube.sh" responder <nombre> "<mensaje>"
```

- Debe devolver `"ok":true`.
- Respondes tú, con lo que sabes de la conversación. Pregunta al usuario solo lo que
  sea decisión suya.
- Después, vuelve a lanzar `vigilar` con ese nombre.

## Informar

- **Solo lo leído.** Resume con lo que **leíste** en las ramas: números y salidas
  reales, sin inventar.
- **Si repartiste.** Junta las partes (totales y fallos de cada una) y di qué parte
  falló.
- **Qué código se probó.** Di qué versión probó la nube: la de GitHub o
  `nube-base-<tema>`.

## Limpiar al terminar (siempre, sin preguntar)

Cuando hayas leído una sesión con `ESTADO: TERMINADO` o `ESTADO: ERROR` y no la vayas a
relanzar ni a responder:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nube.sh" limpiar <nombre1> <nombre2> ...
```

- **Qué hace.** Guarda una copia de su `.nube/` en `.git/nube/resultados/<nombre>/`
  (dentro del repositorio local, fuera del código) y borra la rama `nube-<nombre>` de
  GitHub.
- **Cuándo no borra.** Si la rama cambió desde que la leíste, no la borra: léela otra
  vez.
- **Rama base.** Si usaste `subir-base`, al final ejecuta
  `NUBE limpiar-base <tema>`.
- **Cuándo no limpiar.** Nunca limpies una sesión en `ESTADO: PREGUNTA` ni una que
  sigue trabajando.

Los chats de nube no se archivan solos: archivarlos pide permiso dentro de la sesión de
nube. Se archivan a mano en claude.ai/code. No le pidas al chat de nube que se archive
ni que se ponga título, porque eso lo deja parado esperando un permiso.

## Límites que debes contar si vienen al caso

- **PC encendida.** El usuario debe dejar la PC encendida y Claude abierto mientras
  espera: el vigilante corre en su PC y es lo que te despierta.
- **Avisos de permiso.** Este skill declara su script en `allowed-tools`. Si aun así
  aparece un aviso de permiso, el usuario puede permitirlo para la sesión.
