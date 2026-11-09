import contextlib
import io
import subprocess
import sys
import unittest

import resumen

CAB = "fecha,categoria,importe\n"


class C1Resumen(unittest.TestCase):
    def test_flujo_con_la_muestra_real(self):  # set de oro, par 1
        salida = io.StringIO()
        with contextlib.redirect_stdout(salida):
            codigo = resumen.main(["resumen.py", "contexto/gastos.csv"])
        self.assertEqual(codigo, 0)
        self.assertEqual(salida.getvalue(), "comida: 15.00\ntransporte: 3.25\nocio: 2.00\nTotal: 20.25\n")

    def test_empate_por_nombre(self):  # par 2
        self.assertEqual(resumen.resumir(io.StringIO(CAB + "x,b,1.00\nx,a,1.00\n")), ["a: 1.00", "b: 1.00", "Total: 2.00"])

    def test_solo_cabecera(self):  # par 3
        self.assertEqual(resumen.resumir(io.StringIO(CAB)), ["Total: 0.00"])


class Comando(unittest.TestCase):
    # La frontera del comando (sys.argv y el código de salida del proceso), una vez para todos los criterios;
    # las variantes siguen en main() y resumir().
    def correr(self, ruta):
        return subprocess.run([sys.executable, "resumen.py", ruta], capture_output=True, text=True, encoding="utf-8")

    def test_codigo_de_salida_del_proceso(self):
        valido = self.correr("contexto/gastos.csv")
        self.assertEqual((valido.returncode, valido.stdout.splitlines()[-1:]), (0, ["Total: 20.25"]))


if __name__ == "__main__":
    unittest.main()
