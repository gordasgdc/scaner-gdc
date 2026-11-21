#!/usr/bin/env python3
# Scaner GDC — creat de Cristi Gordaș (GDC). SPDX-License-Identifier: GPL-3.0-only (with additional terms: see LICENSE-ADDITIONAL-TERMS.md)
"""Generates the Scaner GDC site (RO/EN/ES, identical structure and facts) into site/. Standard library only.
Usage: scripts/build-site.py --version 0.3.0 [--dmg-size "2.1 MB" --sha256 <hex> --archs "arm64 x86_64"] [--published]
Without --published the download is shown as an inactive preview (no link). Size/SHA/architectures come only from the final package.
EN is the root page; RO and ES live in /ro/ and /es/. No JavaScript."""
import argparse, html, json, pathlib, sys

ap = argparse.ArgumentParser()
ap.add_argument("--version", required=True); ap.add_argument("--dmg-size", default="—"); ap.add_argument("--sha256", default="—")
ap.add_argument("--check", action="store_true")
ap.add_argument("--archs", default="", help='architectures of the FINAL package, e.g. "arm64 x86_64" (from lipo -archs)')
ap.add_argument("--published", action="store_true", help="enable the download button; ONLY after the real release asset was verified")
a = ap.parse_args()
ROOT = pathlib.Path(__file__).resolve().parent.parent / "site"
CFG = json.loads((pathlib.Path(__file__).resolve().parent / "publish-config.json").read_text())
REPO = CFG["repository"]
DL = f'{REPO}/releases/latest/download/{CFG["stable_asset"]}'  # future URL: only linked when --published
V = a.version
PUB = a.published
if PUB and not (a.dmg_size != "—" and a.sha256 != "—" and a.archs): sys.exit("--published requires --dmg-size, --sha256 and --archs derived from the final package")
PEND = {"en": "Shown at publication", "ro": "Afișat la publicare", "es": "Se muestra al publicar"}
PREV = {"en": "Preview — download not yet published", "ro": "Previzualizare — descărcarea nu este încă publicată", "es": "Vista previa — la descarga aún no está publicada"}
def ARCH(code):
    if not a.archs: return PEND[code]
    names = {"arm64": "Apple silicon", "x86_64": "Intel"}
    return " / ".join(names[x] for x in a.archs.split())
CREDIT = "Scaner GDC — creat de Cristi Gordaș (GDC)."

T = {
"en": dict(code="en", lang="English", title="Scaner GDC — inventory and preview of OFX, LUT, DCTL and audio plug-ins for macOS",
 desc="Scaner GDC is a free macOS app that lists the OFX, LUT, DCTL, VST3, Audio Unit and VST resources installed on your Mac, previews them and lets you move items aside and restore them.",
 nav=[("workflow","How it works"),("formats","Formats"),("manage","Disable and restore"),("download","Download"),("license","Licence and source")],
 skip="Skip to content", h1="Scaner GDC",
 lead="A free macOS app that finds the OFX, LUT, DCTL, VST3, Audio Unit and VST resources installed on your Mac, shows what each one is, previews it, and lets you set items aside and bring them back. Scanning only reads; Disable and Restore move files, with a recorded way back.",
 dlbtn="Download for macOS", dlmeta=f"Version {V} · macOS 14 or later" + (f" · {a.dmg_size}" if PUB else "") + " · free",
 cap1="Library of a synthetic test setup: the grid, the inspector with a before/after LUT preview, and the sources on the left.",
 wf_h="Scan, inspect, organize",
 wf=[("Scan","Reads the standard plug-in and LUT folders, the DaVinci Resolve LUT and DCTL folder, and any folder you add. Read-only: it never opens plug-in binaries beyond the file header and never runs anything."),
     ("Inspect","Name, vendor, version, identifier, architectures, size and location, taken from the package's own metadata. Unknown stays unknown. Duplicates found in several places are flagged. Optionally, you can add a cover, a short description and the official page of a product: from your own image, or from a page you associate. Online lookup is off until you use it and never sends paths, files or licences. Automatic discovery of product pages is optional and needs a search key of your own; without it you associate the page yourself."),
     ("Organize","Search, filter by type, vendor or source, and sort. Move an item to a Disabled folder and restore it later; every operation is recorded in an activity list.")],
 fm_h="Formats and what is read", fm_th=("Format","Where it looks","What is read","Preview"),
 fm=[("OFX","/Library/OFX/Plugins","Bundle metadata, architectures","Bundle icon, if the bundle ships one"),
     ("VST3","/Library and ~/Library Audio/Plug-Ins/VST3","Bundle and module metadata","Bundle icon"),
     ("Audio Unit","/Library and ~/Library Audio/Plug-Ins/Components","Bundle and audio component metadata","Bundle icon"),
     ("VST","/Library and ~/Library Audio/Plug-Ins/VST","Bundle metadata","Bundle icon"),
     ("LUT (.cube)","DaVinci Resolve LUT folders and your own folders","Size, title, domain","Rendered on a synthetic reference image, before and after"),
     ("LUT (.3dl .dat .vlt .mga .csp)","same","File header","Listed; no preview"),
     ("DCTL","Resolve LUT folder (DCTL sub-folder)","The first 256 KB of text","Never executed; no preview")],
 lim_h="Limits you should know",
 lim=["Present on disk does not mean loaded, compatible or licensed in any host application.",
      "Previews of .cube files are rendered on a built-in reference image with sRGB assumed, 8-bit. They show the character of a LUT, not a host-accurate result on your footage.",
      "Vendor and version appear only when the package declares them; nothing is guessed.",
      "Plug-ins are never loaded, scanned by running them, or validated. There is no network access and no account."],
 mg_h="Disable and restore, with a way back",
 mg_p="Choosing “Move to Disabled…” first checks the item, then asks for confirmation in the app. The item is moved — never deleted — to a folder next to its source folder named “… (Disabled by GDC)”, or to a folder you choose in Settings. On the same volume the move is a single atomic rename that refuses to overwrite anything. Across volumes the item is copied, verified byte by byte, and only then is the original moved to the Trash.",
 mg_list=["Every operation is written to a journal; if the app or the Mac stops half-way, the next launch finishes or rolls back safely and tells you what it did.",
          "If something already exists at the destination, nothing is overwritten and the operation is blocked with the reason.",
          "System folders such as /Library/OFX/Plugins usually need administrator rights. Scaner GDC has no privileged helper, so it explains that the folder is not writable instead of asking for your password. Move such items yourself in Finder, or use a folder you own.",
          "Host applications keep loaded plug-ins until they restart. The app warns when a known host is running and never closes anything.",
          "Notarization by Apple does not grant file access; macOS permissions still apply."],
 cap2="Confirmation before any move: source, destination and warnings are shown first.",
 dl_h="Download and install", dl_p=f"Version {V}. Open the disk image and drag Scaner GDC to Applications. The app is signed with a Developer ID certificate and notarized by Apple, so macOS opens it without workarounds.",
 req="Requirements", reqs=[("macOS","14 (Sonoma) or later"),("Mac",ARCH("en")),("Size",a.dmg_size if PUB else PEND["en"]),("SHA-256",a.sha256 if PUB else PEND["en"])],
 relnotes="Release notes", rel=[(V,"Scanning of standard and custom folders, previews for .cube LUTs and bundle icons, recoverable Disable and Restore, diagnostics export, accessibility labels, new icon.")],
 allrel="All releases and notes",
 lic_h="Licence, source and credit",
 lic_p="Scaner GDC is free software. Use it, study it, modify it and redistribute it. The source code is public; anyone who distributes the app must also make the corresponding source available.",
 lic_dl=[("Author","Cristi Gordaș (GDC)"),("Licence","GNU General Public License v3 only, with additional terms under section 7 (attribution, no misrepresentation of origin, no trademark grant)"),("Credit shown in About",CREDIT),("Source",REPO)],
 lic_note="A modified version must keep this credit in its About window and say clearly that it is modified and not made or endorsed by the author. The credit is not required on anything you process with the app. The name and logo are outside the licence grant: the unmodified logo may identify the original; modified versions use their own identity (a neutral icon is provided). The app has no self-updater: to update, download the new release.",
 plat_h="Part of the GDC family", plat_p="Scaner GDC is a separate app. It sits next to GDC Plugin Manager, the platform where GDC apps are presented and managed.",
 plat_link="GDC Plugin Manager", foot_priv="Scaner GDC does not connect to the internet and does not collect data.",
 shot_alt1="Scaner GDC window with a grid of plug-ins and LUTs and an inspector showing an original and a LUT preview",
 shot_alt2="Confirmation dialog before moving an OFX effect to the Disabled folder"),
"ro": dict(code="ro", lang="Română", title="Scaner GDC — inventar și previzualizare pentru pluginuri OFX, LUT, DCTL și audio pe macOS",
 desc="Scaner GDC este o aplicație macOS gratuită care listează resursele OFX, LUT, DCTL, VST3, Audio Unit și VST instalate pe Mac, le previzualizează și permite mutarea lor deoparte și restaurarea.",
 nav=[("workflow","Cum funcționează"),("formats","Formate"),("manage","Dezactivare și restaurare"),("download","Descărcare"),("license","Licență și sursă")],
 skip="Treci la conținut", h1="Scaner GDC",
 lead="O aplicație macOS gratuită care găsește resursele OFX, LUT, DCTL, VST3, Audio Unit și VST instalate pe Mac, arată ce este fiecare, le previzualizează și îți permite să le pui deoparte și să le aduci înapoi. Scanarea doar citește; Dezactivarea și Restaurarea mută fișiere, cu cale de întoarcere înregistrată.",
 dlbtn="Descarcă pentru macOS", dlmeta=f"Versiunea {V} · macOS 14 sau mai nou" + (f" · {a.dmg_size}" if PUB else "") + " · gratuit",
 cap1="Biblioteca unei configurații sintetice de test: grila, inspectorul cu previzualizare LUT înainte/după și sursele din stânga.",
 wf_h="Scanează, inspectează, organizează",
 wf=[("Scanează","Citește folderele standard de pluginuri și LUT-uri, folderul LUT și DCTL din DaVinci Resolve și orice folder adaugi. Doar citire: nu deschide binarele pluginurilor dincolo de antetul fișierului și nu rulează nimic."),
     ("Inspectează","Nume, producător, versiune, identificator, arhitecturi, dimensiune și locație, luate din metadatele pachetului. Ce nu se știe rămâne necunoscut. Duplicatele găsite în mai multe locuri sunt marcate. Opțional poți adăuga coperta, o descriere scurtă și pagina oficială a unui produs: dintr-o imagine proprie sau dintr-o pagină pe care o asociezi. Căutarea online este oprită până o folosești și nu trimite niciodată căi, fișiere sau licențe. Descoperirea automată a paginilor este opțională și cere o cheie proprie de căutare; fără ea, asociezi tu pagina."),
     ("Organizează","Caută, filtrează după tip, producător sau sursă și sortează. Mută un element în folderul Dezactivate și restaurează-l mai târziu; fiecare operație apare într-o listă de activitate.")],
 fm_h="Formate și ce se citește", fm_th=("Format","Unde caută","Ce se citește","Previzualizare"),
 fm=[("OFX","/Library/OFX/Plugins","Metadatele pachetului, arhitecturi","Iconul pachetului, dacă îl conține"),
     ("VST3","/Library și ~/Library Audio/Plug-Ins/VST3","Metadatele pachetului și modulului","Iconul pachetului"),
     ("Audio Unit","/Library și ~/Library Audio/Plug-Ins/Components","Metadatele pachetului și componentei audio","Iconul pachetului"),
     ("VST","/Library și ~/Library Audio/Plug-Ins/VST","Metadatele pachetului","Iconul pachetului"),
     ("LUT (.cube)","Folderele LUT DaVinci Resolve și folderele tale","Dimensiune, titlu, domeniu","Randat pe o imagine de referință sintetică, înainte și după"),
     ("LUT (.3dl .dat .vlt .mga .csp)","la fel","Antetul fișierului","Listat; fără previzualizare"),
     ("DCTL","Folderul LUT Resolve (subfolderul DCTL)","Primii 256 KB de text","Nu se execută niciodată; fără previzualizare")],
 lim_h="Limite pe care e bine să le știi",
 lim=["Prezent pe disc nu înseamnă încărcat, compatibil sau licențiat într-o aplicație gazdă.",
      "Previzualizările fișierelor .cube sunt randate pe o imagine de referință încorporată, cu sRGB presupus, pe 8 biți. Arată caracterul unui LUT, nu un rezultat exact din aplicația gazdă pe materialul tău.",
      "Producătorul și versiunea apar doar dacă pachetul le declară; nu se ghicește nimic.",
      "Pluginurile nu sunt încărcate, rulate sau validate. Nu există acces la rețea și nici cont."],
 mg_h="Dezactivare și restaurare, cu cale de întoarcere",
 mg_p="„Mută în Dezactivate…” verifică întâi elementul, apoi cere confirmarea în aplicație. Elementul este mutat — niciodată șters — într-un folder lângă folderul sursă, numit „… (Disabled by GDC)”, sau într-un folder ales de tine în Setări. Pe același volum mutarea este o redenumire atomică, care refuză să suprascrie ceva. Între volume elementul este copiat, verificat octet cu octet și abia apoi originalul este mutat în Coș.",
 mg_list=["Fiecare operație este scrisă într-un jurnal; dacă aplicația sau Mac-ul se oprește la jumătate, la următoarea pornire operația este terminată sau anulată în siguranță și ți se spune ce s-a făcut.",
          "Dacă la destinație există deja ceva, nu se suprascrie nimic, iar operația este blocată cu motivul afișat.",
          "Folderele de sistem, precum /Library/OFX/Plugins, cer de obicei drepturi de administrator. Scaner GDC nu are asistent privilegiat și explică faptul că folderul nu poate fi scris, în loc să-ți ceară parola. Mută astfel de elemente din Finder sau folosește un folder al tău.",
          "Aplicațiile gazdă păstrează pluginurile încărcate până la repornire. Aplicația avertizează când rulează o gazdă cunoscută și nu închide nimic.",
          "Notarizarea Apple nu acordă acces la fișiere; permisiunile macOS rămân în vigoare."],
 cap2="Confirmare înainte de orice mutare: sursa, destinația și avertismentele sunt afișate mai întâi.",
 dl_h="Descărcare și instalare", dl_p=f"Versiunea {V}. Deschide imaginea de disc și trage Scaner GDC în Applications. Aplicația este semnată cu certificat Developer ID și notarizată de Apple, deci macOS o deschide fără ocolișuri.",
 req="Cerințe", reqs=[("macOS","14 (Sonoma) sau mai nou"),("Mac",ARCH("ro")),("Dimensiune",a.dmg_size if PUB else PEND["ro"]),("SHA-256",a.sha256 if PUB else PEND["ro"])],
 relnotes="Note de versiune", rel=[(V,"Scanarea folderelor standard și proprii, previzualizări pentru LUT .cube și iconuri de pachet, Dezactivare și Restaurare recuperabile, export de diagnostic, etichete de accesibilitate, pictogramă nouă.")],
 allrel="Toate versiunile și notele",
 lic_h="Licență, sursă și credit",
 lic_p="Scaner GDC este software liber. Îl poți folosi, studia, modifica și redistribui. Codul sursă este public; oricine distribuie aplicația trebuie să pună la dispoziție și sursa corespunzătoare.",
 lic_dl=[("Autor","Cristi Gordaș (GDC)"),("Licență","GNU General Public License v3 only, cu termeni suplimentari conform secțiunii 7 (atribuire, fără prezentare înșelătoare a originii, fără acordare de drepturi de marcă)"),("Credit afișat în Despre",CREDIT),("Sursă",REPO)],
 lic_note="O versiune modificată trebuie să păstreze acest credit în fereastra Despre și să spună clar că este modificată și nu a fost creată sau susținută de autor. Creditul nu este necesar pe nimic din ce procesezi cu aplicația. Numele și logo-ul sunt în afara licenței: logo-ul nealterat poate identifica originalul; versiunile modificate folosesc propria identitate (există o pictogramă neutră). Aplicația nu are actualizare automată: pentru actualizare, descarcă noua versiune.",
 plat_h="Parte din familia GDC", plat_p="Scaner GDC este o aplicație separată. Se află alături de GDC Plugin Manager, platforma în care aplicațiile GDC sunt prezentate și gestionate.",
 plat_link="GDC Plugin Manager", foot_priv="Scaner GDC nu se conectează la internet și nu colectează date.",
 shot_alt1="Fereastra Scaner GDC cu o grilă de pluginuri și LUT-uri și un inspector cu previzualizare originală și cu LUT",
 shot_alt2="Dialog de confirmare înainte de mutarea unui efect OFX în folderul Dezactivate"),
"es": dict(code="es", lang="Español", title="Scaner GDC — inventario y vista previa de plug-ins OFX, LUT, DCTL y de audio para macOS",
 desc="Scaner GDC es una app gratuita para macOS que lista los recursos OFX, LUT, DCTL, VST3, Audio Unit y VST instalados en tu Mac, los previsualiza y permite apartarlos y restaurarlos.",
 nav=[("workflow","Cómo funciona"),("formats","Formatos"),("manage","Desactivar y restaurar"),("download","Descarga"),("license","Licencia y código")],
 skip="Saltar al contenido", h1="Scaner GDC",
 lead="Una app gratuita para macOS que encuentra los recursos OFX, LUT, DCTL, VST3, Audio Unit y VST instalados en tu Mac, muestra qué es cada uno, los previsualiza y te deja apartarlos y recuperarlos. El escaneo solo lee; Desactivar y Restaurar mueven archivos, con una vía de vuelta registrada.",
 dlbtn="Descargar para macOS", dlmeta=f"Versión {V} · macOS 14 o posterior" + (f" · {a.dmg_size}" if PUB else "") + " · gratis",
 cap1="Biblioteca de una configuración sintética de prueba: la cuadrícula, el inspector con vista previa de LUT antes/después y las fuentes a la izquierda.",
 wf_h="Escanear, inspeccionar, organizar",
 wf=[("Escanear","Lee las carpetas estándar de plug-ins y LUT, la carpeta de LUT y DCTL de DaVinci Resolve y cualquier carpeta que añadas. Solo lectura: no abre los binarios de los plug-ins más allá de la cabecera del archivo y no ejecuta nada."),
     ("Inspeccionar","Nombre, fabricante, versión, identificador, arquitecturas, tamaño y ubicación, tomados de los metadatos del propio paquete. Lo que no se sabe sigue siendo desconocido. Los duplicados en varios lugares se marcan. Opcionalmente puedes añadir portada, una descripción breve y la página oficial de un producto: desde tu propia imagen o desde una página que asocies. La búsqueda en línea está desactivada hasta que la uses y nunca envía rutas, archivos ni licencias. El descubrimiento automático de páginas es opcional y requiere una clave de búsqueda propia; sin ella, asocias tú la página."),
     ("Organizar","Busca, filtra por tipo, fabricante u origen y ordena. Mueve un elemento a la carpeta de desactivados y restáuralo más tarde; cada operación queda en una lista de actividad.")],
 fm_h="Formatos y qué se lee", fm_th=("Formato","Dónde busca","Qué se lee","Vista previa"),
 fm=[("OFX","/Library/OFX/Plugins","Metadatos del paquete, arquitecturas","Icono del paquete, si lo incluye"),
     ("VST3","/Library y ~/Library Audio/Plug-Ins/VST3","Metadatos del paquete y del módulo","Icono del paquete"),
     ("Audio Unit","/Library y ~/Library Audio/Plug-Ins/Components","Metadatos del paquete y del componente de audio","Icono del paquete"),
     ("VST","/Library y ~/Library Audio/Plug-Ins/VST","Metadatos del paquete","Icono del paquete"),
     ("LUT (.cube)","Carpetas de LUT de DaVinci Resolve y tus propias carpetas","Tamaño, título, dominio","Renderizado sobre una imagen de referencia sintética, antes y después"),
     ("LUT (.3dl .dat .vlt .mga .csp)","igual","Cabecera del archivo","Listado; sin vista previa"),
     ("DCTL","Carpeta de LUT de Resolve (subcarpeta DCTL)","Los primeros 256 KB de texto","Nunca se ejecuta; sin vista previa")],
 lim_h="Límites que conviene conocer",
 lim=["Estar en el disco no significa estar cargado, ser compatible ni tener licencia en una aplicación anfitriona.",
      "Las vistas previas de archivos .cube se renderizan sobre una imagen de referencia integrada, con sRGB supuesto y 8 bits. Muestran el carácter de una LUT, no un resultado exacto del anfitrión sobre tu material.",
      "El fabricante y la versión aparecen solo si el paquete los declara; no se adivina nada.",
      "Los plug-ins no se cargan, no se ejecutan ni se validan. No hay acceso a la red ni cuenta."],
 mg_h="Desactivar y restaurar, con vuelta atrás",
 mg_p="«Mover a Desactivados…» comprueba primero el elemento y después pide confirmación en la app. El elemento se mueve —nunca se borra— a una carpeta junto a su carpeta de origen llamada «… (Disabled by GDC)», o a una carpeta que elijas en Ajustes. En el mismo volumen el movimiento es un único renombrado atómico que se niega a sobrescribir nada. Entre volúmenes el elemento se copia, se verifica byte a byte y solo entonces el original pasa a la Papelera.",
 mg_list=["Cada operación se escribe en un diario; si la app o el Mac se detienen a medias, en el siguiente arranque la operación se completa o se deshace con seguridad y se te indica qué se hizo.",
          "Si en el destino ya existe algo, no se sobrescribe nada y la operación se bloquea mostrando el motivo.",
          "Las carpetas del sistema, como /Library/OFX/Plugins, suelen exigir permisos de administrador. Scaner GDC no tiene asistente privilegiado y explica que la carpeta no es escribible en lugar de pedirte la contraseña. Mueve esos elementos desde el Finder o usa una carpeta tuya.",
          "Las aplicaciones anfitrionas conservan los plug-ins cargados hasta reiniciarse. La app avisa si hay un anfitrión conocido en ejecución y nunca cierra nada.",
          "La notarización de Apple no concede acceso a archivos; los permisos de macOS siguen vigentes."],
 cap2="Confirmación antes de cualquier movimiento: primero se muestran origen, destino y avisos.",
 dl_h="Descarga e instalación", dl_p=f"Versión {V}. Abre la imagen de disco y arrastra Scaner GDC a Aplicaciones. La app está firmada con un certificado Developer ID y notarizada por Apple, por lo que macOS la abre sin rodeos.",
 req="Requisitos", reqs=[("macOS","14 (Sonoma) o posterior"),("Mac",ARCH("es")),("Tamaño",a.dmg_size if PUB else PEND["es"]),("SHA-256",a.sha256 if PUB else PEND["es"])],
 relnotes="Notas de la versión", rel=[(V,"Escaneo de carpetas estándar y propias, vistas previas para LUT .cube e iconos de paquete, Desactivar y Restaurar recuperables, exportación de diagnóstico, etiquetas de accesibilidad, icono nuevo.")],
 allrel="Todas las versiones y notas",
 lic_h="Licencia, código y crédito",
 lic_p="Scaner GDC es software libre. Puedes usarlo, estudiarlo, modificarlo y redistribuirlo. El código fuente es público; quien distribuya la app debe ofrecer también el código fuente correspondiente.",
 lic_dl=[("Autor","Cristi Gordaș (GDC)"),("Licencia","GNU General Public License v3, con un término de atribución conforme a la sección 7"),("Crédito mostrado en Acerca de",CREDIT),("Código",REPO)],
 lic_note="Una versión modificada debe conservar este crédito en su ventana Acerca de y decir claramente que está modificada y que no ha sido creada ni respaldada por el autor. El crédito no es necesario en nada de lo que proceses con la app. El nombre y el logotipo quedan fuera de la licencia: el logotipo sin modificar puede identificar el original; las versiones modificadas usan su propia identidad (hay un icono neutro). La app no tiene actualización automática: para actualizar, descarga la nueva versión.",
 plat_h="Parte de la familia GDC", plat_p="Scaner GDC es una app independiente. Convive con GDC Plugin Manager, la plataforma donde se presentan y gestionan las apps de GDC.",
 plat_link="GDC Plugin Manager", foot_priv="Scaner GDC no se conecta a internet ni recopila datos.",
 shot_alt1="Ventana de Scaner GDC con una cuadrícula de plug-ins y LUT y un inspector con vista previa original y con LUT",
 shot_alt2="Diálogo de confirmación antes de mover un efecto OFX a la carpeta de desactivados"),
}
PLATFORM = "https://gordas.dev/"
e = html.escape

def btn(L):
    if PUB: return f'<a class="btn" href="{DL}">{e(L["dlbtn"])}</a>'
    return f'<span class="btn off" role="note">{e(PREV[L["code"]])}</span>'

def page(L):
    base = "" if L["code"] == "en" else "../"
    path = {"en": "", "ro": "ro/", "es": "es/"}
    site = CFG["pages_url"]
    langs = "".join(f'<a href="{(base + path[c]) or './'}" hreflang="{c}" lang="{c}"{" aria-current=\"page\"" if c == L["code"] else ""}>{c.upper()}</a>' for c in ("en", "ro", "es"))
    nav = "".join(f'<a href="#{i}">{e(t)}</a>' for i, t in L["nav"])
    steps = "".join(f'<li><span class="n">0{n+1}</span><h3>{e(h)}</h3><p>{e(p)}</p></li>' for n, (h, p) in enumerate(L["wf"]))
    th = "".join(f"<th scope=\"col\">{e(x)}</th>" for x in L["fm_th"])
    rows = "".join("<tr>" + "".join(f"<td>{e(c)}</td>" for c in r) + "</tr>" for r in L["fm"])
    lim = "".join(f"<li>{e(x)}</li>" for x in L["lim"]); mg = "".join(f"<li>{e(x)}</li>" for x in L["mg_list"])
    reqs = "".join(f"<dt>{e(k)}</dt><dd>{e(v)}</dd>" for k, v in L["reqs"])
    rel = "".join(f"<h3>{e(v)}</h3><p>{e(t)}</p>" for v, t in L["rel"])
    lic = "".join(f"<dt>{e(k)}</dt><dd>{e(v)}</dd>" for k, v in L["lic_dl"])
    alts = "".join(f'<link rel="alternate" hreflang="{c}" href="{site}{path[c]}">' for c in ("en", "ro", "es")) + f'<link rel="alternate" hreflang="x-default" href="{site}">'
    return f"""<!doctype html>
<html lang="{L['code']}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{e(L['title'])}</title><meta name="description" content="{e(L['desc'])}">
<meta name="color-scheme" content="light dark"><link rel="canonical" href="{site}{path[L['code']]}">{alts}
<meta property="og:title" content="Scaner GDC"><meta property="og:description" content="{e(L['desc'])}"><meta property="og:type" content="website">
<link rel="icon" type="image/svg+xml" href="{base}assets/logo.svg"><link rel="stylesheet" href="{base}assets/style.css?v={V}-2"></head>
<body><a class="skip" href="#main">{e(L['skip'])}</a>
<header class="top"><div class="wrap"><a class="brand" href="{base or './'}"><img src="{base}assets/logo.svg" alt="" width="34" height="34"><span>Scaner GDC</span></a>
<nav class="main" aria-label="Main">{nav}</nav><nav class="lang" aria-label="Language">{langs}</nav></div></header>
<main id="main">
<div class="hero"><div class="wrap"><div class="cols"><div><h1>{e(L['h1'])}</h1><p class="lead">{e(L['lead'])}</p></div>
<div class="dl">{btn(L)}<p class="meta">{e(L['dlmeta'])}</p></div></div>
<figure class="shot hero-shot"><img src="{base}assets/shots/main.png" width="1600" height="975" alt="{e(L['shot_alt1'])}"><figcaption>{e(L['cap1'])}</figcaption></figure></div></div>
<section id="workflow"><div class="wrap"><h2>{e(L['wf_h'])}</h2><ol class="steps">{steps}</ol></div></section>
<section id="formats"><div class="wrap split"><div><h2>{e(L['fm_h'])}</h2><h3>{e(L['lim_h'])}</h3><ul class="plain">{lim}</ul></div>
<div class="tablewrap"><table><thead><tr>{th}</tr></thead><tbody>{rows}</tbody></table></div></div></section>
<section id="manage"><div class="wrap split flip"><div><h2>{e(L['mg_h'])}</h2><p>{e(L['mg_p'])}</p><ul class="plain">{mg}</ul></div>
<figure class="shot"><img src="{base}assets/shots/confirm.png" width="1600" height="975" alt="{e(L['shot_alt2'])}" loading="lazy"><figcaption>{e(L['cap2'])}</figcaption></figure></div></section>
<section id="download"><div class="wrap split"><div><h2>{e(L['dl_h'])}</h2><p>{e(L['dl_p'])}</p><p>{btn(L)}</p><p><a href="{REPO}/releases">{e(L['allrel'])}</a></p></div>
<div><h3>{e(L['req'])}</h3><dl class="facts">{reqs}</dl><h3 style="margin-top:1.6rem">{e(L['relnotes'])}</h3>{rel}</div></div></section>
<section id="license"><div class="wrap split"><div><h2>{e(L['lic_h'])}</h2><p>{e(L['lic_p'])}</p><p class="note">{e(L['lic_note'])}</p></div>
<div><dl class="facts">{lic}</dl><h3 style="margin-top:1.6rem">{e(L['plat_h'])}</h3><p>{e(L['plat_p'])} <a href="{PLATFORM}">{e(L['plat_link'])}</a></p></div></div></section>
</main>
<footer><div class="wrap"><span>{e(CREDIT)}</span><span>{e(L['foot_priv'])}</span><span><a href="{REPO}">GitHub</a></span></div></footer></body></html>
"""

for c, L in T.items():
    out = ROOT if c == "en" else ROOT / c
    out.mkdir(parents=True, exist_ok=True)
    (out / "index.html").write_text(page(L), encoding="utf-8")
# parity check: same number of steps, rows, list items in every language
sizes = {c: (len(L["wf"]), len(L["fm"]), len(L["lim"]), len(L["mg_list"]), len(L["reqs"]), len(L["lic_dl"])) for c, L in T.items()}
if len(set(sizes.values())) != 1: sys.exit(f"language parity broken: {sizes}")
print("site generated; parity OK", sizes["en"])
