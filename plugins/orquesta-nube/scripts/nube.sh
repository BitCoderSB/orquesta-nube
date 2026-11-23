#!/usr/bin/env bash
# orquesta-nube: lanza sesiones de Claude Code en la nube, las vigila y les responde,
# sin paneles ni avisos. Uso: nube.sh <comando> [args]
#   revisar                         comprueba claude, sesion iniciada y remoto de GitHub
#   lanzar <nombre> <archivo|->     crea la sesion de nube; la tarea sale del archivo (o stdin)
#   vigilar <minutos> <nombre...>   espera hasta que la rama de alguna sesion cambie
#   leer <nombre>                   baja la rama de resultados y muestra estado e informe
#   responder <nombre> <mensaje>    manda un mensaje de seguimiento a esa sesion
#   lista                           sesiones lanzadas desde este repositorio
#   limpiar <nombre...>             guarda copia local de .nube/ y borra la rama nube-<nombre> de GitHub
#   limpiar-base <rama>             borra una rama nube-base-* de GitHub (la de los cambios subidos)
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "ERROR: $*" >&2; exit 2; }

raiz() { git rev-parse --show-toplevel 2>/dev/null || die "no estas dentro de un repositorio git"; }
estado_dir() { local d; d="$(git rev-parse --git-common-dir)/nube"; mkdir -p "$d"; echo "$d"; }
estado_file() { echo "$(estado_dir)/sesiones.tsv"; }
so() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo windows;; Darwin) echo mac;; *) echo linux;; esac; }
valida_nombre() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]{0,40}$ ]] || die "nombre invalido '$1': usa minusculas, numeros y guiones"; }
rama_de() { echo "nube-$1"; }

# lee/escribe la tabla: nombre<TAB>sesion<TAB>rama<TAB>ultimo_sha<TAB>fecha
fila() { local f; f="$(estado_file)"; [ -f "$f" ] && awk -F'\t' -v n="$1" '$1==n' "$f" | tail -1; }
pon_fila() { # nombre sesion rama sha
  local f tmp; f="$(estado_file)"; tmp="$f.tmp"; touch "$f"
  awk -F'\t' -v n="$1" '$1!=n' "$f" > "$tmp"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$(date -u +%Y-%m-%dT%H:%MZ)" >> "$tmp"
  mv "$tmp" "$f"
}

cmd_revisar() {
  local ok=1
  command -v claude >/dev/null || { echo "FALTA: el comando claude no esta en el PATH. Instalalo: https://code.claude.com/docs/en/setup"; ok=0; }
  if command -v claude >/dev/null; then
    claude --version 2>&1 | head -1
    if claude auth status 2>/dev/null | grep -q '"loggedIn": *true'; then echo "OK: sesion de claude.ai iniciada"
    else echo "FALTA: iniciar sesion. El usuario debe ejecutar en una terminal: claude auth login"; ok=0; fi
  fi
  raiz >/dev/null
  local url; url="$(git remote get-url origin 2>/dev/null)"
  case "$url" in *github.com*) echo "OK: remoto de GitHub ($url)";; *) echo "FALTA: el remoto origin no es de GitHub (la nube clona desde GitHub)"; ok=0;; esac
  local rama; rama="$(git rev-parse --abbrev-ref HEAD)"
  git fetch -q origin "$rama" 2>/dev/null
  local ahead; ahead="$(git rev-list --count "origin/$rama..HEAD" 2>/dev/null || echo '?')"
  echo "Rama actual: $rama (commits locales sin subir: $ahead; la nube NO los ve)"
  [ -n "$(git status --porcelain 2>/dev/null)" ] && echo "AVISO: hay cambios sin commit; la nube NO los ve"
  [ $ok = 1 ] && echo "LISTO" || exit 1
}

encabezado() { # nombre rama
cat <<EOF
nube: $1
Eres una sesion de trabajo en la nube controlada por OTRA sesion de Claude (el orquestador), no por una persona. Reglas:
- No hagas preguntas en el chat: nadie las lee.
- Todo lo que entregues va en la carpeta .nube/ de la raiz del repositorio. Escribe SIEMPRE .nube/ESTADO.md (la primera linea exactamente una de: ESTADO: TERMINADO / ESTADO: PREGUNTA / ESTADO: ERROR) y .nube/INFORME.md (resultado, con salidas reales de comandos; sin inventar numeros).
- Si necesitas una decision para seguir, escribe la pregunta en .nube/ESTADO.md con ESTADO: PREGUNTA, sube y detente: el orquestador te respondera con un mensaje nuevo; entonces sigue y vuelve a subir.
- Para entregar (siempre, tambien si algo falla): git checkout -B $2 ; git add -f .nube ; git commit -m 'nube: $1' ; git push -f origin $2 . No subas nada mas ni toques otras ramas.
- No cambies codigo del proyecto salvo que la tarea lo pida expresamente; si lo pide, incluye esos cambios en el mismo commit.

TAREA:
EOF
}

cmd_lanzar() {
  local nombre="${1:-}" origen="${2:--}"; valida_nombre "$nombre"
  cd "$(raiz)" || exit 2
  local rama; rama="$(rama_de "$nombre")"
  local tmpd; tmpd="$(estado_dir)/tmp"; mkdir -p "$tmpd"
  local tf="$tmpd/$nombre.tarea.txt" log="$tmpd/$nombre.lanzar.log"
  { encabezado "$nombre" "$rama"; if [ "$origen" = "-" ]; then cat; else cat "$origen"; fi; } \
    | tr '"' "'" > "$tf"   # sin comillas dobles: Windows PowerShell 5.1 las rompe al pasar argumentos
  rm -f "$log"
  case "$(so)" in
    windows)
      local ps1 wtf wlog wcwd
      ps1="$(cygpath -w "$DIR/lanzar-windows.ps1")"; wtf="$(cygpath -w "$tf")"; wlog="$(cygpath -w "$log")"; wcwd="$(cygpath -w "$PWD")"
      powershell.exe -NoProfile -Command "\$p = Start-Process powershell -WindowStyle Minimized -PassThru -Wait -WorkingDirectory '$wcwd' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','\"$ps1\"','-TareaArchivo','\"$wtf\"','-Log','\"$wlog\"'; exit \$p.ExitCode" ;;
    mac)
      script -q "$log" bash -c 'claude --cloud "$(cat "$1")"' _ "$tf" </dev/null >/dev/null ;;
    linux)
      TF="$tf" script -qec 'claude --cloud "$(cat "$TF")"' "$log" </dev/null >/dev/null ;;
  esac
  [ -f "$log" ] || die "no se genero el registro del lanzamiento"
  local sid; sid="$(grep -ao 'session_[A-Za-z0-9]*' "$log" | head -1)"
  if [ -z "$sid" ]; then
    echo "NO SE CREO LA SESION. Salida de claude:"; tr -d '\r' < "$log" | grep -av '^\*\*\*\|^Hora\|^Nombre\|^Usuario\|^M.quina\|^Aplicaci\|^Id\.\|^PS\|^Build\|^CLR\|^WSMan\|^Serializ\|^Inicio\|^Fin\|^Start\|^End\|^Username\|^RunAs\|^Configuration\|^Machine\|^Host Application\|^Process ID' | sed '/^\s*$/d' | head -20
    grep -aqi 'sign-in\|login\|authenticat' "$log" && echo "=> El usuario debe ejecutar: claude auth login"
    exit 1
  fi
  local previo; previo="$(git ls-remote origin "refs/heads/$rama" 2>/dev/null | cut -f1)"
  pon_fila "$nombre" "$sid" "$rama" "$previo"
  echo "LANZADA nombre=$nombre sesion=$sid rama=$rama"
  echo "Ver: https://claude.ai/code/$sid"
  grep -a 'commits ahead\|uncommitted' "$log" | tr -d '\r' | head -2
}

cmd_vigilar() {
  local minutos="${1:-90}"; shift || true; [ $# -gt 0 ] || die "uso: vigilar <minutos> <nombre...>"
  raiz >/dev/null
  local fin=$(( $(date +%s) + minutos * 60 ))
  while :; do
    local cambios=()
    for n in "$@"; do
      local f rama ultimo sha; f="$(fila "$n")"; [ -n "$f" ] || die "no conozco la sesion '$n' (usa: lista)"
      rama="$(echo "$f" | cut -f3)"; ultimo="$(echo "$f" | cut -f4)"
      sha="$(git ls-remote origin "refs/heads/$rama" 2>/dev/null | cut -f1)"
      if [ -n "$sha" ] && [ "$sha" != "$ultimo" ]; then
        pon_fila "$n" "$(echo "$f" | cut -f2)" "$rama" "$sha"; cambios+=("$n")
      fi
    done
    if [ ${#cambios[@]} -gt 0 ]; then echo "CAMBIO: ${cambios[*]}  (leer cada una con: leer <nombre>)"; exit 0; fi
    if [ "$(date +%s)" -ge "$fin" ]; then echo "TIEMPO AGOTADO sin cambios en: $*"; exit 1; fi
    sleep 30
  done
}

cmd_leer() {
  local n="${1:-}"; valida_nombre "$n"; raiz >/dev/null
  local rama; rama="$(rama_de "$n")"
  git fetch -q origin "$rama" 2>/dev/null || die "la rama $rama no existe en GitHub todavia"
  echo "== $rama @ $(git rev-parse --short FETCH_HEAD)"
  echo "== .nube/ESTADO.md"; git show FETCH_HEAD:.nube/ESTADO.md 2>/dev/null || echo "(no hay ESTADO.md)"
  echo; echo "== .nube/INFORME.md"; git show FETCH_HEAD:.nube/INFORME.md 2>/dev/null || echo "(no hay INFORME.md)"
  echo; echo "== archivos en .nube/ (leer con: git show FETCH_HEAD:<ruta>)"; git ls-tree -r --name-only FETCH_HEAD .nube 2>/dev/null
}

cmd_responder() {
  local n="${1:-}"; shift || true; valida_nombre "$n"; [ $# -gt 0 ] || die "uso: responder <nombre> <mensaje>"
  raiz >/dev/null
  local f sid; f="$(fila "$n")"; [ -n "$f" ] || die "no conozco la sesion '$n'"
  sid="$(echo "$f" | cut -f2)"
  claude -p "$*" --cloud "$sid" --output-format json
}

cmd_lista() {
  local f; f="$(estado_file)"; [ -s "$f" ] || { echo "(ninguna sesion lanzada desde este repositorio)"; return; }
  printf 'NOMBRE\tSESION\tRAMA\tULTIMO_SHA\tFECHA\n'; cat "$f"
}

cmd_limpiar() {
  [ $# -gt 0 ] || die "uso: limpiar <nombre...>"
  raiz >/dev/null
  local n
  for n in "$@"; do
    valida_nombre "$n"
    local rama dest; rama="$(rama_de "$n")"; dest="$(estado_dir)/resultados/$n"
    if git fetch -q origin "$rama" 2>/dev/null; then
      mkdir -p "$dest"
      local p
      while IFS= read -r p; do
        mkdir -p "$dest/$(dirname "${p#.nube/}")"
        git show "FETCH_HEAD:$p" > "$dest/${p#.nube/}"
      done < <(git ls-tree -r --name-only FETCH_HEAD .nube 2>/dev/null)
      git rev-parse FETCH_HEAD > "$dest/.commit"
      if git push -q origin --delete "$rama" 2>/dev/null; then echo "LIMPIA $n: copia en $dest ; rama $rama borrada de GitHub"
      else echo "AVISO $n: copia en $dest, pero no pude borrar $rama de GitHub"; fi
    else
      echo "$n: la rama $rama ya no existe en GitHub (nada que borrar)"
    fi
    local f; f="$(estado_file)"; [ -f "$f" ] && { awk -F'\t' -v n="$n" '$1!=n' "$f" > "$f.tmp"; mv "$f.tmp" "$f"; }
  done
}

cmd_limpiar_base() {
  local r="${1:-}"; [[ "$r" == nube-base-* ]] || die "solo borro ramas nube-base-*"
  raiz >/dev/null
  git push -q origin --delete "$r" && echo "rama $r borrada de GitHub"
}

c="${1:-}"; shift || true
case "$c" in
  revisar) cmd_revisar "$@";; lanzar) cmd_lanzar "$@";; vigilar) cmd_vigilar "$@";;
  leer) cmd_leer "$@";; responder) cmd_responder "$@";; lista) cmd_lista "$@";;
  limpiar) cmd_limpiar "$@";; limpiar-base) cmd_limpiar_base "$@";;
  *) sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 2;;
esac
