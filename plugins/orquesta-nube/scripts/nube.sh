#!/usr/bin/env bash
# orquesta-nube: lanza sesiones de Claude Code en la nube, las vigila y les responde,
# sin paneles ni avisos. Uso: nube.sh <comando> [args]
#   revisar                         comprueba claude, sesion iniciada, remoto de GitHub y rama
#   instalar                        instala el comando claude de consola (con npm) si falta
#   subir-base <tema>               sube tus cambios (con y sin commit) a nube-base-<tema> SIN tocar tu rama
#   lanzar <nombre> <archivo|->     crea la sesion de nube; la tarea sale del archivo (o stdin)
#   preparar <nombre> <archivo|->   MODO APP (sin consola): arma la tarea para lanzarla con start_session
#   registrar <nombre> [session_id] MODO APP: anota la sesion creada con start_session
#   vigilar <minutos> <nombre...>   espera hasta que la rama de alguna sesion cambie
#   leer <nombre>                   baja la rama de resultados y muestra estado e informe
#   responder <nombre> <mensaje>    manda un mensaje de seguimiento a esa sesion
#   lista                           sesiones lanzadas desde este repositorio
#   limpiar <nombre...>             guarda copia local de .nube/ y borra la rama nube-<nombre> de GitHub
#   limpiar-base <tema|rama>        borra la rama nube-base-<tema> de GitHub
# Variable opcional: NUBE_REMOTO (nombre del remoto de GitHub; por defecto, el primero que apunte a github.com)
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERROR: $*" >&2; exit 2; }
raiz() { git rev-parse --show-toplevel 2>/dev/null || die "no estas dentro de un repositorio git"; }
estado_dir() { local d; d="$(git rev-parse --git-common-dir)/nube"; mkdir -p "$d"; echo "$d"; }
estado_file() { echo "$(estado_dir)/sesiones.tsv"; }
so() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo windows;; Darwin) echo mac;; *) echo linux;; esac; }
valida_nombre() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || die "nombre invalido '$1': usa minusculas, numeros y guiones"; }
rama_de() { echo "nube-$1"; }
ref_de() { echo "refs/nube/$1"; }   # copia local propia de la rama de cada sesion (no se pisa entre sesiones)

remoto() { # remoto de GitHub
  if [ -n "${NUBE_REMOTO:-}" ]; then echo "$NUBE_REMOTO"; return; fi
  local r
  for r in origin $(git remote 2>/dev/null); do
    case "$(git remote get-url "$r" 2>/dev/null)" in *github.com*) echo "$r"; return;; esac
  done
  echo origin
}

# Tabla nombre<TAB>sesion<TAB>rama<TAB>ultimo_sha<TAB>fecha, con bloqueo (varias llamadas pueden ir en paralelo)
bloquear() { local l i=0; l="$(estado_dir)/lock"; until mkdir "$l" 2>/dev/null; do i=$((i+1)); [ $i -gt 100 ] && rm -rf "$l"; sleep 0.1; done; }
desbloquear() { rmdir "$(estado_dir)/lock" 2>/dev/null; }
fila() { local f; f="$(estado_file)"; [ -f "$f" ] && awk -F'\t' -v n="$1" '$1==n' "$f" | tail -1; }
pon_fila() { # nombre sesion rama sha
  bloquear
  local f tmp; f="$(estado_file)"; tmp="$(mktemp "$f.XXXXXX")"; touch "$f"
  awk -F'\t' -v n="$1" '$1!=n' "$f" > "$tmp"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$(date -u +%Y-%m-%dT%H:%MZ)" >> "$tmp"
  mv "$tmp" "$f"; desbloquear
}
quita_fila() {
  bloquear
  local f tmp; f="$(estado_file)"
  if [ -f "$f" ]; then tmp="$(mktemp "$f.XXXXXX")"; awk -F'\t' -v n="$1" '$1!=n' "$f" > "$tmp"; mv "$tmp" "$f"; fi
  desbloquear
}

claude_bin() { # ruta del claude a usar: el del PATH o, si no hay, el que trae la app de escritorio
  if command -v claude >/dev/null && claude --version 2>&1 | head -1 | grep -qv 'native binary not installed'; then echo claude; return 0; fi
  if [ "$(so)" = windows ] && [ -n "${LOCALAPPDATA:-}" ]; then
    local b; b="$(ls -d "$LOCALAPPDATA"/Claude-Data/claude_*/claude-code/*/*/claude.exe 2>/dev/null | sort -V | tail -1)"
    [ -n "$b" ] && { echo "$b"; return 0; }
  fi
  return 1
}

comando_login() { # como debe escribir el usuario el inicio de sesion, segun el claude que hay
  local b="$1"
  if [ "$b" = claude ]; then echo "claude auth login"
  else echo "& \"$(cygpath -w "$b" 2>/dev/null || echo "$b")\" auth login   (en PowerShell)"; fi
}

comando_cloud_prueba() { # comando para que el usuario abra claude --cloud a la vista y conteste lo de primera vez
  local b="$1"
  if [ "$b" = claude ]; then echo "claude --cloud \"prueba\""
  else echo '& (Get-ChildItem "$env:LOCALAPPDATA\Claude-Data\claude_*\claude-code\*\*\claude.exe" | Sort-Object LastWriteTime | Select-Object -Last 1).FullName --cloud "prueba"   (en PowerShell, en la carpeta del proyecto)'; fi
}

primera_vez_pendiente() { # true si claude nunca se abrio a la vista en esta PC (bienvenida y eleccion de privacidad sin contestar)
  local f="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
  ! grep -q '"hasCompletedOnboarding": *true' "$f" 2>/dev/null
}

cmd_revisar() {
  local ok=1 cli=1 CL
  if CL="$(claude_bin)"; then
    [ "$CL" != claude ] && echo "OK: uso el claude que trae la app de escritorio: $CL"
    echo "claude: $("$CL" --version 2>&1 | head -1)"
    "$CL" --help 2>/dev/null | grep -q -- '--cloud' || { echo "SIN CONSOLA: esta version de claude no tiene --cloud (claude update)"; cli=0; }
    if [ $cli = 1 ]; then
      if "$CL" auth status 2>/dev/null | grep -q '"loggedIn": *true'; then echo "OK: sesion de claude.ai iniciada en la consola"
      else echo "SIN CONSOLA: falta iniciar sesion UNA vez. El usuario, en una terminal nueva: $(comando_login "$CL")"; cli=0; fi
      if [ $cli = 1 ] && primera_vez_pendiente; then
        echo "SIN CONSOLA: falta la primera apertura de claude en esta PC (estilo de colores y eleccion de privacidad: decide el usuario, una sola vez). El usuario pega en una terminal: $(comando_cloud_prueba "$CL")  y contesta lo que pregunte"; cli=0
      fi
    fi
  else
    echo "SIN CONSOLA: no hay comando claude ni el de la app (se instala con: instalar)"; cli=0
  fi
  raiz >/dev/null
  local r url; r="$(remoto)"; url="$(git remote get-url "$r" 2>/dev/null)"
  case "$url" in *github.com*) echo "OK: remoto de GitHub '$r' ($url)";; *) echo "FALTA: no hay remoto de GitHub (la nube clona desde GitHub). Si tiene otro nombre: NUBE_REMOTO=<nombre>"; ok=0;; esac
  local rama; rama="$(git symbolic-ref --short -q HEAD)"
  if [ -z "$rama" ]; then echo "AVISO: HEAD separado; la nube clonara la rama por defecto del repositorio"
  elif git ls-remote --exit-code --heads "$r" "$rama" >/dev/null 2>&1; then
    git fetch -q "$r" "$rama" 2>/dev/null
    echo "Rama actual: $rama (commits locales sin subir: $(git rev-list --count "$r/$rama..HEAD" 2>/dev/null || echo '?'); la nube NO los ve)"
  else
    echo "AVISO: la rama $rama no existe en GitHub; la nube no puede clonarla. Usa subir-base o sube la rama"
  fi
  [ -n "$(git status --porcelain 2>/dev/null)" ] && echo "AVISO: hay cambios sin commit; la nube NO los ve (subir-base los incluye)"
  case "$url" in *github.com*)
    if command -v gh >/dev/null && [ "$(gh repo view "$url" --json visibility -q .visibility 2>/dev/null)" = "PUBLIC" ]; then
      echo "AVISO: el repositorio es PUBLICO: las ramas nube-* que se suban las puede ver cualquiera"
    fi;;
  esac
  [ $ok = 1 ] || exit 1
  if [ $cli = 1 ]; then echo "LISTO MODO=consola (sin permisos: usa lanzar)"
  else echo "LISTO MODO=app (cada sesion pedira permiso al usuario: usa preparar + start_session + registrar. Para no pedirlo: el inicio de sesion de arriba, una vez)"; fi
}

claude_ok() { command -v claude >/dev/null && claude --version 2>&1 | head -1 | grep -qv 'native binary not installed'; }

cmd_instalar() { # instala el comando claude de consola (solo si no hay ninguno, ni el de la app)
  local CL
  if CL="$(claude_bin)"; then echo "YA INSTALADO (no hace falta instalar): $("$CL" --version 2>&1 | head -1) en $CL"; echo "Falta, si revisar lo pide: $(comando_login "$CL")"; return 0; fi
  command -v npm >/dev/null || { echo "SIN NPM: instala Node.js (que trae npm) o Claude Code segun su documentacion oficial, y vuelve a ejecutar: instalar"; exit 1; }
  echo "Instalando Claude Code de consola con npm (tarda un poco)..."
  local salida; salida="$(npm install -g @anthropic-ai/claude-code --include=optional 2>&1)"; echo "$salida" | tail -3
  echo "$salida" | grep -q 'EACCES' && echo "=> npm no tiene permiso para instalar global. Instala Claude Code con su instalador oficial (documentacion de Claude Code) o configura npm sin sudo, y reintenta."
  if ! claude_ok; then # npm a veces deja el programa a medias: se completa con su instalador
    local d; d="$(npm root -g 2>/dev/null)/@anthropic-ai/claude-code"
    [ -f "$d/install.cjs" ] && ( cd "$d" && node install.cjs 2>&1 | tail -2 )
  fi
  hash -r 2>/dev/null
  if claude_ok; then
    echo "INSTALADO: $(claude --version 2>&1 | head -1)"
    echo "Falta UNA vez: el usuario ejecuta 'claude auth login' en una terminal NUEVA y pega el codigo."
  else
    echo "NO QUEDO INSTALADO. Si dice que no encuentra 'claude', abre una terminal nueva y prueba 'claude --version'; npm global: $(npm root -g 2>/dev/null)"
    exit 1
  fi
}

cmd_preparar() { # modo app: arma la tarea completa y registra la sesion; el chat la lanza con start_session
  local nombre="${1:-}" origen="${2:--}"; valida_nombre "$nombre"
  if [ "$origen" != "-" ]; then
    [ -r "$origen" ] || die "no puedo leer el archivo de la tarea: $origen"
    origen="$(cd "$(dirname "$origen")" && pwd)/$(basename "$origen")"
  fi
  cd "$(raiz)" || exit 2
  [ -n "$(fila "$nombre")" ] && die "ya hay una sesion llamada '$nombre' (usa otro nombre, o limpiar $nombre)"
  local rama tmpd tf; rama="$(rama_de "$nombre")"; tmpd="$(estado_dir)/tmp"; mkdir -p "$tmpd"; tf="$tmpd/$nombre.tarea.txt"
  { encabezado "$nombre" "$rama"; if [ "$origen" = "-" ]; then cat; else cat "$origen"; fi; } > "$tf"
  [ -n "$(sed '1,/^TAREA:$/d' "$tf" | tr -d '[:space:]')" ] || die "la tarea esta vacia"
  pon_fila "$nombre" "app" "$rama" "$(git ls-remote "$(remoto)" "refs/heads/$rama" 2>/dev/null | cut -f1)"
  echo "PREPARADA nombre=$nombre rama=$rama"
  echo "TAREA_COMPLETA=$tf"
  echo "Siguiente: start_session (target cloud) con el contenido EXACTO de ese archivo como prompt; luego: registrar $nombre <session_id si lo tienes>"
}

cmd_registrar() { # modo app: guarda el id de la sesion creada con start_session (opcional)
  local n="${1:-}" sid="${2:-app}"; valida_nombre "$n"; raiz >/dev/null
  local f; f="$(fila "$n")"; [ -n "$f" ] || die "no conozco la sesion '$n' (primero: preparar)"
  pon_fila "$n" "$sid" "$(echo "$f" | cut -f3)" "$(echo "$f" | cut -f4)"
  echo "REGISTRADA $n sesion=$sid"
}

cmd_subir_base() {
  local tema="${1:-}"; valida_nombre "$tema"; cd "$(raiz)" || exit 2
  local r c; r="$(remoto)"
  # git stash create: commit con tus cambios rastreados (con y sin commit) sin tocar tu rama ni tu indice.
  # No incluye archivos sin rastrear (asi no se cuelan .env ni secretos nuevos).
  c="$(git stash create "nube-base $tema" 2>/dev/null)"; [ -n "$c" ] || c="$(git rev-parse HEAD)"
  git push -q "$r" "+$c:refs/heads/nube-base-$tema" || die "no pude subir nube-base-$tema"
  echo "SUBIDA nube-base-$tema @ $(git rev-parse --short "$c") (tu rama no se toco; archivos sin rastrear NO incluidos)"
  echo "En la tarea pon primero: git fetch origin nube-base-$tema && git checkout FETCH_HEAD"
  local sin; sin="$(git ls-files --others --exclude-standard | head -5)"
  [ -n "$sin" ] && { echo "Archivos nuevos sin rastrear que NO se subieron:"; echo "$sin"; }
  return 0
}

encabezado() { # nombre rama
cat <<EOF
nube: $1
Eres una sesion de trabajo en la nube controlada por OTRA sesion de Claude (el orquestador), no por una persona. Reglas:
- No hagas preguntas en el chat: nadie las lee.
- Todo lo que entregues va en la carpeta .nube/ de la raiz del repositorio. Escribe SIEMPRE .nube/ESTADO.md (la primera linea exactamente una de: ESTADO: TERMINADO / ESTADO: PREGUNTA / ESTADO: ERROR) y .nube/INFORME.md (resultado, con salidas reales de comandos; sin inventar numeros).
- Si necesitas una decision para seguir, escribe la pregunta en .nube/ESTADO.md con ESTADO: PREGUNTA, sube y detente: el orquestador te respondera con un mensaje nuevo; entonces sigue y vuelve a subir.
- Sube solo cuando entregues (TERMINADO, PREGUNTA o ERROR), no avances parciales.
- Para entregar (siempre, tambien si algo falla): git checkout -B $2 ; git add -f .nube ; (si la tarea pidio cambiar codigo: git add <esos archivos>) ; git commit -m 'nube: $1' ; git push -f origin $2 . No subas nada mas ni toques otras ramas.
- No cambies codigo del proyecto salvo que la tarea lo pida expresamente. Nunca subas secretos (.env, claves, tokens).

TAREA:
EOF
}

espera_o_corta() { # pid segundos -> 0 si termino, 1 si hubo que cortarlo
  local pid="$1" t=0
  while kill -0 "$pid" 2>/dev/null; do
    [ $t -ge "$2" ] && { pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null; return 1; }
    sleep 1; t=$((t+1))
  done
  wait "$pid" 2>/dev/null; return 0
}

cmd_lanzar() {
  local nombre="${1:-}" origen="${2:--}"; valida_nombre "$nombre"
  if [ "$origen" != "-" ]; then
    [ -r "$origen" ] || die "no puedo leer el archivo de la tarea: $origen"
    origen="$(cd "$(dirname "$origen")" && pwd)/$(basename "$origen")"
  fi
  cd "$(raiz)" || exit 2
  [ -n "$(fila "$nombre")" ] && die "ya hay una sesion llamada '$nombre' (usa otro nombre, o limpiar $nombre)"
  local r rama; r="$(remoto)"; rama="$(rama_de "$nombre")"
  local actual; actual="$(git symbolic-ref --short -q HEAD)"
  if [ -n "$actual" ] && ! git ls-remote --exit-code --heads "$r" "$actual" >/dev/null 2>&1; then
    die "tu rama '$actual' no existe en GitHub y la nube no podria clonarla. Sube la rama, o usa subir-base y empieza la tarea con git fetch origin nube-base-<tema> && git checkout FETCH_HEAD (cambiandote antes a una rama que si este en GitHub)"
  fi
  local CL; CL="$(claude_bin)" || die "no hay comando claude (ni el de la app): usa el modo app, o instalar"
  primera_vez_pendiente && die "falta la primera apertura de claude en esta PC (la contesta el usuario una vez). Que pegue en una terminal: $(comando_cloud_prueba "$CL")"
  local tmpd; tmpd="$(estado_dir)/tmp"; mkdir -p "$tmpd"
  local cuerpo="$tmpd/$nombre.cuerpo.txt" tf="$tmpd/$nombre.tarea.txt" log="$tmpd/$nombre.lanzar.log"
  if [ "$origen" = "-" ]; then cat > "$cuerpo"; else cat "$origen" > "$cuerpo"; fi
  [ -n "$(tr -d '[:space:]' < "$cuerpo")" ] || die "la tarea esta vacia"
  { encabezado "$nombre" "$rama"; cat "$cuerpo"; } > "$tf"
  rm -f "$log"
  local colgado=0
  case "$(so)" in
    windows)
      # Windows PowerShell 5.1 rompe las comillas dobles al pasar argumentos: solo aqui se cambian por simples.
      tr '"' "'" < "$tf" > "$tf.w" && mv "$tf.w" "$tf"
      local ps1 wtf wlog wcwd wcl
      ps1="$(cygpath -w "$DIR/lanzar-windows.ps1")"; wtf="$(cygpath -w "$tf")"; wlog="$(cygpath -w "$log")"; wcwd="$(cygpath -w "$PWD")"
      if [ "$CL" = claude ]; then wcl=claude; else wcl="$(cygpath -w "$CL")"; fi
      ps1="${ps1//\'/\'\'}"; wtf="${wtf//\'/\'\'}"; wlog="${wlog//\'/\'\'}"; wcwd="${wcwd//\'/\'\'}"; wcl="${wcl//\'/\'\'}"
      # Espera como mucho 3 minutos: si la consola oculta se queda esperando algo, se cierra.
      powershell.exe -NoProfile -Command "\$p = Start-Process powershell -WindowStyle Minimized -PassThru -WorkingDirectory '$wcwd' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"$ps1\"','-TareaArchivo','\"$wtf\"','-Log','\"$wlog\"','-Claude','\"$wcl\"'; if (-not \$p.WaitForExit(180000)) { Get-CimInstance Win32_Process | Where-Object { \$_.ParentProcessId -eq \$p.Id } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }; Stop-Process -Id \$p.Id -Force -ErrorAction SilentlyContinue; exit 124 }; exit \$p.ExitCode"
      [ $? = 124 ] && colgado=1 ;;
    mac)
      script -q "$log" bash -c '"$2" --cloud "$(cat "$1")"' _ "$tf" "$CL" </dev/null >/dev/null &
      espera_o_corta $! 180 || colgado=1 ;;
    linux)
      TF="$tf" CLB="$CL" script -qec '"$CLB" --cloud "$(cat "$TF")"' "$log" </dev/null >/dev/null &
      espera_o_corta $! 180 || colgado=1 ;;
  esac
  if [ "${colgado:-0}" = 1 ]; then
    echo "AVISO: claude --cloud no termino en 3 minutos y se cerro: se quedo esperando una respuesta. Lo ultimo que mostro:"
    [ -f "$log" ] && tr -d '\r' < "$log" | sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' | grep -av '^[[:space:]]*$' | grep -aEv '^(\*\*\*|Hora|Nombre|Usuario|M.quina|Aplicaci|Id\.|PS|Build|CLR|WSMan|Serializ|Inicio|Fin)' | tail -15
    echo "=> Que el usuario ejecute UNA vez, en una terminal visible y en esta carpeta: $(comando_cloud_prueba "$CL") , conteste lo que pregunte (es la primera vez de esa consola) y luego reintenta."
  fi
  [ -f "$log" ] || die "no se genero el registro del lanzamiento"
  local sid; sid="$(grep -ao 'claude\.ai/code/session_[A-Za-z0-9]*' "$log" | head -1 | sed 's#.*/##')"
  if [ -z "$sid" ]; then
    echo "NO SE CREO LA SESION. Salida de claude:"
    tr -d '\r' < "$log" | grep -aEv '^(\*\*\*|Hora|Nombre|Usuario|M.quina|Aplicaci|Id\.|PS|Build|CLR|WSMan|Serializ|Inicio|Fin|Start|End|Username|RunAs|Configuration|Machine|Host Application|Process ID)' | grep -av '^[[:space:]]*$' | head -20
    if grep -aEqi 'sign-in|login|authenticat' "$log"; then echo "=> El usuario debe ejecutar: claude auth login"
    elif grep -aEqi 'github|repositor|environment|entorno' "$log"; then echo "=> Parece que falta conectar GitHub o crear el entorno: el usuario debe abrir claude.ai/code una vez y conectar este repositorio"
    else echo "=> Si no queda claro, que el usuario ejecute una vez en una terminal visible: $(comando_cloud_prueba "$CL")"; fi
    exit 1
  fi
  local previo; previo="$(git ls-remote "$r" "refs/heads/$rama" 2>/dev/null | cut -f1)"
  pon_fila "$nombre" "$sid" "$rama" "$previo"
  rm -f "$cuerpo"
  echo "LANZADA nombre=$nombre sesion=$sid rama=$rama"
  echo "Ver: https://claude.ai/code/$sid"
  grep -aE 'commits ahead|uncommitted' "$log" | tr -d '\r' | head -2
}

cmd_vigilar() {
  local minutos="${1:-90}"; shift || true; [ $# -gt 0 ] || die "uso: vigilar <minutos> <nombre...>"
  [[ "$minutos" =~ ^[0-9]+$ ]] || die "minutos invalidos: $minutos"
  raiz >/dev/null
  local n; for n in "$@"; do [ -n "$(fila "$n")" ] || die "no conozco la sesion '$n' (usa: lista)"; done
  local r; r="$(remoto)"
  local fin=$(( $(date +%s) + minutos * 60 ))
  while :; do
    local cambios=()
    for n in "$@"; do
      local f rama ultimo sha; f="$(fila "$n")"
      rama="$(echo "$f" | cut -f3)"; ultimo="$(echo "$f" | cut -f4)"
      sha="$(git ls-remote "$r" "refs/heads/$rama" 2>/dev/null | cut -f1)"
      if [ -n "$sha" ] && [ "$sha" != "$ultimo" ]; then
        pon_fila "$n" "$(echo "$f" | cut -f2)" "$rama" "$sha"; cambios+=("$n")
      fi
    done
    if [ ${#cambios[@]} -gt 0 ]; then echo "CAMBIO: ${cambios[*]}  (leer cada una con: leer <nombre>)"; exit 0; fi
    if [ "$(date +%s)" -ge "$fin" ]; then echo "TIEMPO AGOTADO sin cambios en: $*"; exit 1; fi
    sleep 30
  done
}

baja() { # nombre -> deja la rama de la sesion en refs/nube/<nombre>; falla si no existe
  local r; r="$(remoto)"
  git fetch -q "$r" "+refs/heads/$(rama_de "$1"):$(ref_de "$1")" 2>/dev/null
}

cmd_leer() {
  local n="${1:-}"; valida_nombre "$n"; raiz >/dev/null
  baja "$n" || die "la rama $(rama_de "$n") no existe en GitHub todavia"
  # Se usa el sha y no "refs/...:ruta": Git Bash convierte "refs/a:b" como si fueran rutas de Windows.
  local sha; sha="$(git rev-parse "$(ref_de "$n")")"
  echo "== $(rama_de "$n") @ ${sha:0:9}"
  echo "== .nube/ESTADO.md"; git show "$sha:.nube/ESTADO.md" 2>/dev/null || echo "(no hay ESTADO.md)"
  echo; echo "== .nube/INFORME.md"; git show "$sha:.nube/INFORME.md" 2>/dev/null || echo "(no hay INFORME.md)"
  echo; echo "== archivos en .nube/ (leer con: git show $sha:<ruta>)"
  git -c core.quotePath=false ls-tree -r --name-only "$sha" .nube 2>/dev/null
}

cmd_responder() {
  local n="${1:-}"; shift || true; valida_nombre "$n"; [ $# -gt 0 ] || die "uso: responder <nombre> <mensaje>"
  raiz >/dev/null
  local f sid; f="$(fila "$n")"; [ -n "$f" ] || die "no conozco la sesion '$n'"
  sid="$(echo "$f" | cut -f2)"
  case "$sid" in session_*|cse_*) ;; *) die "la sesion '$n' se lanzo desde la app y no tengo su id: respondele con SendMessage si puedes, o pide al usuario que conteste en ese chat";; esac
  local CL; CL="$(claude_bin)" || die "no hay comando claude"
  "$CL" -p "$*" --cloud "$sid" --output-format json
}

cmd_lista() {
  local f; f="$(estado_file)"; [ -s "$f" ] || { echo "(ninguna sesion lanzada desde este repositorio)"; return; }
  printf 'NOMBRE\tSESION\tRAMA\tULTIMO_SHA\tFECHA\n'; cat "$f"
}

cmd_limpiar() {
  [ $# -gt 0 ] || die "uso: limpiar <nombre...>"
  cd "$(raiz)" || exit 2
  local r n; r="$(remoto)"
  for n in "$@"; do
    valida_nombre "$n"
    local rama ref dest sha ok=1; rama="$(rama_de "$n")"; ref="$(ref_de "$n")"; dest="$(estado_dir)/resultados/$n"
    if baja "$n"; then
      sha="$(git rev-parse "$ref")"; mkdir -p "$dest"
      local p rel
      while IFS= read -r -d '' p; do
        rel="${p#.nube/}"; mkdir -p "$dest/$(dirname "$rel")"
        git show "$sha:$p" > "$dest/$rel" || ok=0
      done < <(git -c core.quotePath=false ls-tree -r -z --name-only "$sha" .nube 2>/dev/null)
      echo "$sha" > "$dest/.commit"
      if [ $ok = 0 ]; then echo "AVISO $n: no pude copiar todo; NO borro $rama (copia parcial en $dest)"; continue; fi
      # --force-with-lease: si la sesion subio algo nuevo desde que lo bajamos, no se borra.
      if git push -q --force-with-lease="refs/heads/$rama:$sha" "$r" --delete "$rama" 2>/dev/null; then
        echo "LIMPIA $n: copia en $dest ; rama $rama borrada de GitHub"
      else
        echo "AVISO $n: copia en $dest, pero NO borre $rama (cambio desde que se leyo, o sin permiso). Vuelve a leerla."; continue
      fi
    else
      echo "$n: la rama $rama ya no existe en GitHub (nada que borrar)"
    fi
    git update-ref -d "$ref" 2>/dev/null
    rm -f "$(estado_dir)/tmp/$n".*
    quita_fila "$n"
  done
}

cmd_limpiar_base() {
  local t="${1:-}"; t="${t#nube-base-}"; valida_nombre "$t"
  raiz >/dev/null
  git push -q "$(remoto)" --delete "nube-base-$t" && echo "rama nube-base-$t borrada de GitHub"
}

c="${1:-}"; shift || true
case "$c" in
  revisar) cmd_revisar "$@";; subir-base) cmd_subir_base "$@";; lanzar) cmd_lanzar "$@";;
  preparar) cmd_preparar "$@";; registrar) cmd_registrar "$@";; instalar) cmd_instalar "$@";;
  vigilar) cmd_vigilar "$@";; leer) cmd_leer "$@";; responder) cmd_responder "$@";;
  lista) cmd_lista "$@";; limpiar) cmd_limpiar "$@";; limpiar-base) cmd_limpiar_base "$@";;
  *) sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 2;;
esac
