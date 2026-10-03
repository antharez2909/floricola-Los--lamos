"""Prueba de carga HTTP sencilla y segura para endpoints de lectura.

Ejemplo:
    python tools/load_test.py --url http://127.0.0.1:5000/api/status --users 10 --requests 100

No crea pedidos ni modifica stock. Para endpoints protegidos, usar --token con un
usuario de prueba. Esta herramienta sirve para obtener una medición reproducible,
no para afirmar una capacidad universal del sistema.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import statistics
import time
import urllib.error
import urllib.request


def una_peticion(url: str, token: str | None, timeout: float):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, headers=headers, method="GET")
    inicio = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            response.read()
            codigo = response.status
    except urllib.error.HTTPError as exc:
        codigo = exc.code
    except Exception:
        codigo = 0
    return (time.perf_counter() - inicio) * 1000, codigo


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--users", type=int, default=10)
    parser.add_argument("--requests", type=int, default=100)
    parser.add_argument("--timeout", type=float, default=10)
    parser.add_argument("--token")
    args = parser.parse_args()
    if args.users < 1 or args.requests < 1:
        raise SystemExit("users y requests deben ser mayores que 0")

    inicio = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.users) as executor:
        futures = [executor.submit(una_peticion, args.url, args.token, args.timeout)
                   for _ in range(args.requests)]
        resultados = [f.result() for f in futures]
    duracion = time.perf_counter() - inicio

    latencias = [r[0] for r in resultados]
    exitos = sum(200 <= r[1] < 300 for r in resultados)
    errores = len(resultados) - exitos
    print(f"URL: {args.url}")
    print(f"Solicitudes: {len(resultados)}")
    print(f"Concurrencia máxima: {args.users}")
    print(f"Exitosas 2xx: {exitos}")
    print(f"Errores/no-2xx: {errores}")
    print(f"Tiempo total: {duracion:.3f} s")
    print(f"Solicitudes/segundo: {len(resultados)/duracion:.2f}")
    print(f"Latencia promedio: {statistics.mean(latencias):.2f} ms")
    print(f"Latencia p95: {sorted(latencias)[max(0, int(len(latencias)*0.95)-1)]:.2f} ms")
    print(f"Latencia máxima: {max(latencias):.2f} ms")


if __name__ == "__main__":
    main()
