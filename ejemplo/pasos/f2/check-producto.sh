# --- suite del producto (ejemplo): unittest de la biblioteca estándar ---
if [ ! -d tests ]; then echo "0 pruebas ejecutadas: aún no hay tests/"; exit 0; fi
salida=$(python3 -m unittest discover -s tests -t . 2>&1); rc=$?
printf '%s\n' "$salida" | tail -n 3
exit "$rc"
