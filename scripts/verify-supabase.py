"""Comprueba la conexión; la prueba opcional libera sus propias reservas al terminar."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import json
from pathlib import Path
import re
import urllib.error
import urllib.request
import uuid
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-reservations", action="store_true")
    parser.add_argument("--test-rsvp-validation", action="store_true", help="Validar la nueva firma sin correo con un nombre vacío; no crea respuestas.")
    parser.add_argument("--snapshot", type=Path, help="Guardar únicamente la lista pública actual, sin modificar reservas.")
    args = parser.parse_args()
    source = (ROOT / "config.js").read_text()
    block = re.search(r"supabase\s*:\s*\{(.*?)\}", source, re.S).group(1)

    def field(name):
        return re.search(r"\b" + name + r"\s*:\s*['\"]([^'\"]*)['\"]", block).group(1)

    base, key, event = field("url").rstrip("/"), field("publishableKey"), field("eventId")
    assert re.fullmatch(r"https://[a-z0-9]+\.supabase\.co", base), "Revisar la URL de proyecto."
    assert key.startswith("sb_publishable_") or key.startswith("eyJ"), "Se necesita una clave pública."
    headers = {"Content-Type": "application/json", "apikey": key}
    if key.startswith("eyJ"):
        headers["Authorization"] = "Bearer " + key

    def rpc(name, params=None):
        request = urllib.request.Request(base + "/rest/v1/rpc/" + name,
                                         data=json.dumps({"p_event_id": event, **(params or {})}).encode(),
                                         headers=headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            result = json.loads(error.read())
            raise RuntimeError(f"{name}: HTTP {error.code}, {result.get('message', 'error del servidor')}") from None

    actual = rpc("invitation_available_gifts")
    if args.snapshot:
        args.snapshot.write_text(json.dumps(actual, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"available_gifts": len(actual), "categories": dict(Counter(gift["category"] for gift in actual))}, ensure_ascii=False))
        return
    expected = json.loads((ROOT / "supabase/regalos-luciano.json").read_text())
    expected_by_id = {gift["id"]: gift for gift in expected}
    assert set(gift["id"] for gift in actual) <= set(expected_by_id), "Hay regalos disponibles que no están en el Excel."
    expected_available = [gift for gift in expected if gift["id"] in {row["id"] for row in actual}]
    assert [gift["id"] for gift in actual] == [gift["id"] for gift in expected_available], "El orden no coincide con el Excel."
    for gift in actual:
        imported = expected_by_id[gift["id"]]
        for key_name in ("name", "description", "category", "icon", "color", "product_url"):
            assert gift[key_name] == imported[key_name], f"Revisar {key_name} de {imported['name']}."
        if imported["image_url"]:
            assert gift["image_url"] == imported["image_url"], "Revisar la imagen de " + imported["name"]
    report = {"date": datetime.now(ZoneInfo("America/Bogota")).date().isoformat(), "event_id": event, "connection": "ok", "gifts": len(actual),
              "categories": dict(Counter(gift["category"] for gift in actual)), "matches_import": True,
              "catalog_gifts": len(expected), "not_available": len(expected) - len(actual)}
    if args.test_reservations:
        gift_id = actual[0]["id"]
        tokens = [str(uuid.uuid4()), str(uuid.uuid4())]
        results = None
        try:
            def reserve(index):
                return rpc("invitation_reserve_gift", {"p_gift_id": gift_id, "p_token": tokens[index],
                                                       "p_name": "Prueba técnica " + str(index + 1)})
            with ThreadPoolExecutor(max_workers=2) as executor:
                results = list(executor.map(reserve, range(2)))
            assert sorted(results) == [False, True], "Se esperaba una sola reserva exitosa."
            winner, loser = results.index(True), results.index(False)
            assert [gift["id"] for gift in rpc("invitation_my_gifts", {"p_tokens": [tokens[winner]]})] == [gift_id]
            assert rpc("invitation_my_gifts", {"p_tokens": [tokens[loser]]}) == []
            assert gift_id not in [gift["id"] for gift in rpc("invitation_available_gifts")]
        finally:
            # Los tokens solo pueden cancelar las reservas de esta prueba.
            for token in tokens:
                rpc("invitation_cancel_gift", {"p_gift_id": gift_id, "p_token": token})
        restored = rpc("invitation_available_gifts")
        assert [gift["id"] for gift in restored] == [gift["id"] for gift in actual], "Revisar la restauración de la lista."
        report["reservation_test"] = {"simultaneous_attempts": 2, "successful": sum(results),
                                      "hidden_while_reserved": True, "own_reservations_checked": True,
                                      "cancelled_test_reservation": True, "available_after_test": len(restored)}
    report["private_tables_blocked"] = {}
    if args.test_rsvp_validation:
        try:
            rpc("invitation_save_rsvp", {"p_token": str(uuid.uuid4()), "p_name": "", "p_attending": True,
                                         "p_party_size": 1, "p_message": ""})
        except RuntimeError as error:
            if "HTTP 400" not in str(error) or "Revisa tu nombre y número de asistentes" not in str(error):
                raise
        else:
            raise AssertionError("El formulario debe rechazar un nombre vacío.")
        report["rsvp_without_email_validation"] = "ok"
    for table in ("invitation_rsvps", "invitation_gift_reservations"):
        request = urllib.request.Request(base + "/rest/v1/" + table + "?select=*&limit=0", headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                status = response.status
        except urllib.error.HTTPError as error:
            status = error.code
        report["private_tables_blocked"][table] = status in (401, 403)
        assert status in (401, 403), "Revisar los permisos de " + table
    (ROOT / "supabase/verificacion-conexion.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
