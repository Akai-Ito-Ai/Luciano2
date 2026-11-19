"""Convierte la lista de los papás en datos de importación, sin editar el Excel."""
import argparse
import csv
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import uuid
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
import xml.etree.ElementTree as ET
import zipfile

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
EVENT_ID = "luciano-2026"


def product_url(value):
    url = urlsplit(value.strip())
    if url.scheme != "https" or not url.netloc:
        raise ValueError("El enlace de compra debe ser HTTPS.")
    if url.hostname in ("amazon.com", "www.amazon.com"):
        asin = re.search(r"/(?:dp|gp/product)/([A-Z0-9]{10})(?:/|$)", url.path)
        if not asin:
            raise ValueError("No se pudo identificar el producto de Amazon.")
        options = [(key, val) for key, val in parse_qsl(url.query) if key in ("th", "psc")]
        return urlunsplit(("https", "www.amazon.com", "/dp/" + asin.group(1), urlencode(options), ""))
    options = [(key, val) for key, val in parse_qsl(url.query) if not key.startswith("utm_")]
    return urlunsplit((url.scheme, url.netloc, url.path, urlencode(options), url.fragment))


def read_rows(source):
    with zipfile.ZipFile(source) as archive:
        if any(name.startswith("xl/media/") for name in archive.namelist()):
            raise ValueError("El Excel contiene imágenes incrustadas que necesitan revisión.")
        shared = []
        if "xl/sharedStrings.xml" in archive.namelist():
            shared = ["".join(cell.itertext()) for cell in ET.fromstring(archive.read("xl/sharedStrings.xml"))]
        sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
        rows = []
        for row in sheet.findall(".//m:sheetData/m:row", NS):
            values = {}
            for cell in row:
                if cell.find("m:f", NS) is not None:
                    raise ValueError("La lista contiene fórmulas: revisar antes de importar.")
                value = cell.find("m:v", NS)
                text = value.text if value is not None else ""
                if cell.get("t") == "s":
                    text = shared[int(text)]
                elif cell.get("t") == "inlineStr":
                    text = "".join(cell.find("m:is", NS).itertext())
                values[re.sub(r"\d", "", cell.get("r"))] = (text or "").strip()
            if values.get("A"):
                rows.append((int(row.get("r")), values))
        if [rows[0][1].get(col) for col in "ABCDE"] != ["Nombre", "Categoria", "Detalles", "Enlace", "Imagen"]:
            raise ValueError("Las columnas del Excel no corresponden a la plantilla.")
        return rows[1:]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, default=Path("supabase"))
    parser.add_argument("--separate-units", action="store_true", help="Tratar filas repetidas como unidades reservables independientes.")
    parser.add_argument("--deduplicate-url", action="append", default=[], help="Conservar solo la primera fila de este enlace, según indicación de los papás.")
    parser.add_argument("--date", help="Fecha de la importación, YYYY-MM-DD.")
    args = parser.parse_args()
    gifts, notes, omitted = [], [], []
    occurrences = Counter()
    deduplicate = {product_url(value) for value in args.deduplicate_url}
    source_rows = read_rows(args.source)
    categories = {"Ropita": ("clothes", "sage"), "Baño": ("bath", "peach"),
                  "Alimentación": ("bottle", "sage"), "Accesorios": ("bear", "sand")}
    for row, values in source_rows:
        name, category, description = (values.get(col, "") for col in "ABC")
        if not 2 <= len(name) <= 100 or len(description) > 300 or category not in categories:
            raise ValueError(f"Revisar nombre, categoría o detalles en la fila {row}.")
        link = product_url(values.get("D", ""))
        if occurrences[link] and link in deduplicate:
            omitted.append({"row": row, "name": name, "reason": "Duplicado omitido por indicación de los papás."})
            continue
        occurrences[link] += 1
        if occurrences[link] > 1 and not args.separate_units:
            raise ValueError(f"Enlace repetido en fila {row}: confirmar si representa otra unidad reservable.")
        image = values.get("E", "")
        if image and urlsplit(image).scheme != "https":
            raise ValueError(f"La imagen de la fila {row} debe usar HTTPS.")
        icon, color = categories[category]
        if category == "Accesorios":
            if "libro" in name.lower():
                icon = "book"
            elif any(term in name.lower() for term in ("sonidos", "cuna")):
                icon = "blanket"
        identity = EVENT_ID + ":" + link + (":unit:" + str(occurrences[link]) if occurrences[link] > 1 else "")
        gifts.append({"id": str(uuid.uuid5(uuid.NAMESPACE_URL, identity)),
                      "event_id": EVENT_ID, "name": name, "description": description,
                      "category": category, "icon": icon, "color": color, "image_url": image,
                      "product_url": link, "sort_order": (len(gifts) + 1) * 10, "enabled": True})
        if not description:
            notes.append(f"Fila {row}: {name}, sin descripción en el Excel.")
    if len({gift["id"] for gift in gifts}) != len(gifts):
        raise ValueError("Hay enlaces de producto repetidos: revisar antes de crear reservas duplicadas.")
    args.output.mkdir(parents=True, exist_ok=True)
    data_path = args.output / "regalos-luciano.json"
    data_path.write_text(json.dumps(gifts, ensure_ascii=False, indent=2) + "\n")
    with (args.output / "regalos-luciano.csv").open("w", newline="", encoding="utf-8-sig") as file:
        writer = csv.DictWriter(file, fieldnames=list(gifts[0]))
        writer.writeheader()
        writer.writerows({**gift, "enabled": "true"} for gift in gifts)
    quote = lambda value: "true" if value is True else str(value) if isinstance(value, int) else "'" + str(value).replace("'", "''") + "'"
    lines = ["-- Lista de los papás" + (", importación del " + args.date if args.date else "") + ".",
             "-- Importación repetible: conserva IDs, reservas, imágenes existentes y estado enabled.",
             "begin;", "insert into public.invitation_events(id,name) values ('luciano-2026','Baby shower de Luciano Mejía Villamizar') on conflict(id) do nothing;",
             "insert into public.invitation_gifts (" + ",".join(gifts[0]) + ") values"]
    lines.append(",\n".join("(" + ",".join(quote(value) for value in gift.values()) + ")" for gift in gifts))
    lines.extend(["on conflict(id) do update set",
                  "name=excluded.name, description=excluded.description, category=excluded.category,",
                  "icon=excluded.icon, color=excluded.color, product_url=excluded.product_url, sort_order=excluded.sort_order,",
                  "image_url=coalesce(nullif(excluded.image_url,''),invitation_gifts.image_url);",
                  "select category,count(*) as regalos from public.invitation_gifts where event_id='luciano-2026' and enabled group by category order by category;",
                  "commit;", ""])
    (args.output / "importar-regalos-luciano.sql").write_text("\n".join(lines))
    report = {"source": args.source.name, "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
              "date": args.date, "source_rows": len(source_rows), "omitted": omitted,
              "gifts": len(gifts), "categories": {category: sum(g["category"] == category for g in gifts) for category in categories},
              "images": sum(bool(g["image_url"]) for g in gifts), "notes": notes,
              "separate_units": [{"product_url": link, "units": count} for link, count in occurrences.items() if count > 1]}
    (args.output / "importacion-regalos-resumen.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
