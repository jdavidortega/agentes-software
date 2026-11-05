import contextlib
import io
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


class C2ImporteInvalido(unittest.TestCase):
    def test_flujo_con_la_muestra_invalida(self):  # par 4
        salida, error = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(salida), contextlib.redirect_stderr(error):
            codigo = resumen.main(["resumen.py", "contexto/gastos-invalido.csv"])
        self.assertEqual(codigo, 1)
        self.assertEqual(error.getvalue(), "error: fila 3: importe inválido «abc»\n")
        self.assertEqual(salida.getvalue(), "")  # sin resumen parcial


if __name__ == "__main__":
    unittest.main()
