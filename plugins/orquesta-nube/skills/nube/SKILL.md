---
name: nube
description: Hacer trabajo en la nube (Claude Code on the web) orquestado desde este chat, sin pedir permisos ni clics al usuario. Úsalo cuando el usuario pida algo «en la nube», «en la cloud», «en otra máquina», «en paralelo en varias máquinas», o pida pruebas, mediciones, builds o tareas largas que no quiere correr en su PC.
allowed-tools: Bash(bash:*), Read
---

# Orquestar sesiones en la nube

El chat local es el orquestador: lanza sesiones en la nube, espera sin gastar a que
entreguen, lee lo que dejaron, les responde si preguntan y analiza el resultado. El
usuario no tiene que pulsar nada. Responde al usuario en su idioma.

Todo pasa por un solo script (en adelante `NUBE`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nube.sh" <comando> ...
```

Ejecútalo siempre desde la carpeta del repositorio del usuario.

## Qué NO usar

No uses `start_session` con `target: "cloud"`, ni el panel de terminal
(`run_in_terminal`), ni `Agent` con `isolation: "remote"`. Los dos primeros piden permiso
al usuario cada vez, y el tercero puede acabar corriendo en su PC. Para la nube, usa
solo `NUBE`.

## Antes de la primera tarea

1. `NUBE revisar`. Si dice `FALTA: iniciar sesión`, pide al usuario que ejecute
   `claude auth login` en una terminal. Él pega el código: tú nunca escribes códigos ni
   contraseñas. Si dice que falta `claude`, dale el enlace que imprime.
2. **La nube clona la rama actual tal como está en GitHub.** No ve los commits sin subir
   ni los cambios sin commit, y `revisar` dice cuántos hay. Si la tarea necesita esos
   cambios, pregunta al usuario una sola vez si puedes subirlos a una rama aparte
   (`nube-base-<tema>`), sin mover la suya. Con su sí, haz el commit y
   `git push origin HEAD:refs/heads/nube-base-<tema>`, y en la tarea pide empezar por
   `git fetch origin nube-base-<tema> && git checkout FETCH_HEAD`. Sin su sí, sigue con
   lo que está en GitHub y avísale.

## Lanzar

Escribe la tarea completa en un archivo temporal y lánzala:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nube.sh" lanzar <nombre> <archivo-tarea>
```

- `<nombre>`: minúsculas, números y guiones, único (p. ej. `pruebas-1`, `pruebas-2`).
  Su rama de entrega será `nube-<nombre>`.
- **La tarea se autocontiene.** La sesión de nube no tiene tu conversación, ni la
  memoria, ni archivos locales. Pon qué hacer, qué comandos correr y qué guardar en
  `.nube/`.
- El script añade por su cuenta las reglas de entrega: escribir `.nube/ESTADO.md` y
  `.nube/INFORME.md`, subir a su rama, no preguntar y detenerse con `ESTADO: PREGUNTA`
  si necesita una decisión.
- Para repartir trabajo, lanza varias sesiones, una por parte. Cada una es una máquina
  aparte y no comparten nada entre ellas. Para pruebas, por ejemplo,
  `vitest --shard=i/N` o `pytest` por grupos.
- El resultado debe decir `LANZADA ... sesion=session_...`. Si dice `NO SE CREO LA
  SESION`, lee el motivo y díselo al usuario.

## Esperar sin gastar

Deja el vigilante en segundo plano (`run_in_background: true`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nube.sh" vigilar <minutos> <nombre1> <nombre2> ...
```

- Termina en cuanto **alguna** rama cambia, y la app te despierta. No hagas sondeos ni
  sleeps por tu cuenta.
- Al despertar, haz `NUBE leer <nombre>` de cada nombre que diga `CAMBIO:`:
  - `ESTADO: TERMINADO`: guarda el resultado.
  - `ESTADO: PREGUNTA`: responde (ver abajo).
  - `ESTADO: ERROR`: decide si relanzar o informar.
- Si quedan sesiones sin entregar, vuelve a lanzar `vigilar` solo con esas.
- `TIEMPO AGOTADO`: dile al usuario cuáles no entregaron y su enlace
  (`https://claude.ai/code/<sesion>`, que sale en `NUBE lista`).

## Responder a una sesión de nube

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nube.sh" responder <nombre> "<mensaje>"
```

Debe devolver `"ok":true`. Respondes tú, con lo que sabes de la conversación. Pregunta al
usuario solo lo que sea decisión suya. Después, vuelve a lanzar `vigilar` con ese nombre.

## Informar

- Resume para el usuario con lo que **leíste** en las ramas: números y salidas reales,
  sin inventar.
- Di qué versión del código probó la nube: GitHub, o la rama `nube-base-…`.
## Limpiar al terminar (siempre, sin preguntar)

Para no dejar basura: cuando hayas leído una sesión con `ESTADO: TERMINADO` o
`ESTADO: ERROR` y ya no la vayas a relanzar ni a responder, límpiala:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/nube.sh" limpiar <nombre1> <nombre2> ...
```

Guarda una copia de su `.nube/` en `.git/nube/resultados/<nombre>/`, dentro del
repositorio local y fuera del código, y borra la rama `nube-<nombre>` de GitHub. Si
subiste una rama `nube-base-<tema>` para la tarea, bórrala también al final con
`NUBE limpiar-base nube-base-<tema>`. No limpies una sesión que está en
`ESTADO: PREGUNTA` o que sigue trabajando.

Los chats de nube no se pueden archivar desde la consola: quedan en claude.ai/code. Si el
usuario pregunta, dile que puede archivarlos ahí, y que sus nombres empiezan por
«nube».

## Límites que debes contar si vienen al caso

- El usuario debe dejar su PC encendida y Claude abierto mientras espera: el vigilante
  corre en su PC y es lo que te despierta.
- Lanzar sin avisos depende de que el usuario permita estos comandos. Este skill los
  declara en `allowed-tools`. Si aun así aparece un aviso, dile que puede añadir
  `Bash(bash:*)` a sus permisos o usar el modo Auto.
