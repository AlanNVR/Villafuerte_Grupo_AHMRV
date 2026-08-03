#!/usr/bin/env bash
# =====================================================================
#  Completa fichas_tecnicas.csv con duracion, codec y tamano reales.
#
#  USO
#    1. Descifra el contenedor en una carpeta temporal, por ejemplo:
#         mkdir -p /tmp/ev && cd /tmp/ev
#         7z x ruta/al/evidencias_entrevistas_audios_01.7z
#         7z x ruta/al/evidencias_entrevistas_videos_01.7z      (y 02, 03, 04)
#         7z x ruta/al/evidencias_entrevistas_consentimientos_01.7z
#       La estructura resultante debe reproducir la columna
#       'ruta_en_contenedor' del CSV: audios/, videos/, consentimientos_firmados/
#
#    2. Ejecuta desde esa carpeta:
#         bash completar_fichas_tecnicas.sh fichas_tecnicas.csv
#
#    3. El script escribe fichas_tecnicas_completo.csv y verifica los hashes.
#
#  REQUISITOS: ffprobe (paquete ffmpeg) y sha256sum
# =====================================================================
set -uo pipefail

CSV="${1:-fichas_tecnicas.csv}"
OUT="fichas_tecnicas_completo.csv"

command -v ffprobe >/dev/null || { echo "ERROR: falta ffprobe. Instala ffmpeg."; exit 1; }
[ -f "$CSV" ] || { echo "ERROR: no encuentro $CSV"; exit 1; }

head -1 "$CSV" > "$OUT"

ok=0; falta=0; hash_mal=0

tail -n +2 "$CSV" | while IFS=';' read -r id tipo fecha cod dur codec tam sha cont ruta; do
  if [ ! -f "$ruta" ]; then
    echo "  AUSENTE   $ruta"
    echo "$id;$tipo;$fecha;$cod;AUSENTE;AUSENTE;AUSENTE;$sha;$cont;$ruta" >> "$OUT"
    falta=$((falta+1)); continue
  fi

  tam_real=$(stat -c%s "$ruta" 2>/dev/null || stat -f%z "$ruta")

  if [ "$tipo" = "consentimiento" ]; then
    dur_real="n/a"
    codec_real=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
                 -of csv=p=0 "$ruta" 2>/dev/null || echo "imagen")
  else
    dur_real=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$ruta")
    if [ "$tipo" = "video" ]; then
      v=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$ruta")
      a=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$ruta")
      codec_real="${v} / ${a}"
    else
      codec_real=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$ruta")
    fi
  fi

  sha_real=$(sha256sum "$ruta" | cut -d' ' -f1)
  if [ "$sha_real" != "$sha" ]; then
    echo "  HASH NO COINCIDE: $ruta"
    echo "     declarado: $sha"
    echo "     real     : $sha_real"
    hash_mal=$((hash_mal+1))
  fi

  echo "$id;$tipo;$fecha;$cod;$dur_real;$codec_real;$tam_real;$sha_real;$cont;$ruta" >> "$OUT"
  ok=$((ok+1))
done

echo ""
echo "Generado: $OUT"
echo ""
echo "=== Duracion total por tipo (minutos) ==="
awk -F';' 'NR>1 && $5!="n/a" && $5!="AUSENTE" && $5!="PENDIENTE" {s[$2]+=$5} END {for(t in s) printf "  %-16s %.1f min\n", t, s[t]/60}' "$OUT"

echo ""
echo "=== Verificacion contra los minimos de la Seccion 4.2 de la guia ==="
nv=$(awk -F';' 'NR>1 && $2=="video"'  "$OUT" | wc -l)
na=$(awk -F';' 'NR>1 && $2=="audio"'  "$OUT" | wc -l)
tv=$(awk -F';' 'NR>1 && $2=="video" && $5+0>0 {s+=$5} END {printf "%.0f", s/60}' "$OUT")
echo "  videos:           $nv   (minimo 8)"
echo "  audios:           $na   (minimo 8)"
echo "  duracion video:   ${tv:-0} min  (minimo 120)"
echo ""
echo "Si algun hash no coincide, el archivo fue modificado despues de calcular"
echo "checksums.sha256. Regenera ambos antes de volver a cifrar el contenedor."
