#!/usr/bin/env python3

import argparse
import base64
import hashlib
import http.client
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote, urlencode, urlsplit

PACKAGE = "com.caffeinateddev.holybeans"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
TOKEN_URL = "https://oauth2.googleapis.com/token"
API_ROOT = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
UPLOAD_ROOT = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"
LANGUAGES = ("es-ES", "en-GB")
_UNSET = object()


class PublishError(Exception):
    pass


class ApiError(PublishError):
    def __init__(self, method, url, status, body, redactions=()):
        try:
            payload = json.loads(body.decode("utf-8")) if body else {}
            error = payload.get("error", payload)
            detail = error.get("message") if isinstance(error, dict) else None
            detail = detail or json.dumps(error, ensure_ascii=False)
        except (UnicodeDecodeError, json.JSONDecodeError):
            detail = body.decode("utf-8", errors="replace")[:500]
        for secret in redactions:
            if secret:
                detail = detail.replace(secret, "[oculto]")
        super().__init__(f"{method} {url}: HTTP {status}: {detail}")
        self.status = status


@dataclass(frozen=True)
class ReleasePlan:
    root: Path
    aab: Path
    notes_path: Path
    track: str
    version_name: str
    version_code: int
    notes: dict
    sha256: str


class HttpTransport:
    def __call__(self, method, url, body=None, headers=None, timeout=30):
        parts = urlsplit(url)
        if parts.scheme != "https" or not parts.netloc:
            raise PublishError(f"URL no segura: {url}")
        path = parts.path
        if parts.query:
            path += "?" + parts.query
        connection = http.client.HTTPSConnection(parts.netloc, timeout=timeout)
        try:
            connection.request(method, path, body=body, headers=headers or {})
            response = connection.getresponse()
            return response.status, response.read()
        except (OSError, http.client.HTTPException) as error:
            raise PublishError(f"{method} {url}: {error}") from error
        finally:
            connection.close()


def validate_track(track):
    if not track or track != track.strip() or len(track) > 128:
        raise PublishError("El track está vacío, tiene espacios exteriores o es demasiado largo.")
    if any(ord(character) < 32 for character in track):
        raise PublishError("El track contiene caracteres de control.")
    return track


def pubspec_version(root):
    text = (root / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\S+)\+([0-9]+)\s*$", text, re.MULTILINE)
    if not match:
        raise PublishError("No encuentro una versión nombre+código válida en pubspec.yaml.")
    return match.group(1), int(match.group(2))


def parse_release_notes(path):
    text = path.read_text(encoding="utf-8")
    notes = {}
    for language in LANGUAGES:
        tag = re.escape(language)
        match = re.search(rf"<{tag}>\s*(.*?)\s*</{tag}>", text, re.DOTALL)
        if not match:
            raise PublishError(f"Faltan las notas <{language}> en {path}.")
        value = match.group(1).strip()
        if not value:
            raise PublishError(f"Las notas {language} están vacías.")
        if len(value) > 500:
            raise PublishError(f"Las notas {language} tienen {len(value)} caracteres; Play admite 500.")
        notes[language] = value
    return notes


def file_sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build_plan(root, aab, notes_path, track):
    root = root.resolve()
    aab = aab.expanduser().resolve()
    notes_path = notes_path.expanduser().resolve()
    validate_track(track)
    version_name, version_code = pubspec_version(root)
    expected_name = f"holybeans-{version_name}-{version_code}.aab"
    if aab.name != expected_name:
        raise PublishError(f"El AAB debe llamarse {expected_name} para coincidir con pubspec.yaml.")
    if not aab.is_file() or aab.stat().st_size == 0:
        raise PublishError(f"El AAB no existe o está vacío: {aab}")
    if not notes_path.is_file():
        raise PublishError(f"El archivo de notas no existe: {notes_path}")
    return ReleasePlan(
        root=root,
        aab=aab,
        notes_path=notes_path,
        track=track,
        version_name=version_name,
        version_code=version_code,
        notes=parse_release_notes(notes_path),
        sha256=file_sha256(aab),
    )


def load_service_account(path):
    try:
        credentials = json.loads(path.expanduser().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PublishError(f"No puedo leer la cuenta de servicio {path}: {error}") from error
    if not isinstance(credentials, dict):
        raise PublishError("La cuenta de servicio debe ser un objeto JSON.")
    email = credentials.get("client_email")
    private_key = credentials.get("private_key")
    if not isinstance(email, str) or "@" not in email:
        raise PublishError("La cuenta de servicio no contiene client_email válido.")
    if not isinstance(private_key, str) or "BEGIN PRIVATE KEY" not in private_key:
        raise PublishError("La cuenta de servicio no contiene una private_key PKCS#8 válida.")
    return credentials


def base64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=")


def sign_rs256(private_key, signing_input):
    key_path = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", prefix="holybeans-play-", suffix=".pem", delete=False, encoding="utf-8"
        ) as key_file:
            key_path = Path(key_file.name)
            key_file.write(private_key)
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
            input=signing_input,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=30,
        )
        if result.returncode != 0:
            detail = result.stderr.decode("utf-8", errors="replace").strip()
            raise PublishError(f"OpenSSL no pudo firmar el JWT: {detail}")
        return result.stdout
    except FileNotFoundError as error:
        raise PublishError("No encuentro OpenSSL; es necesario para firmar el JWT.") from error
    finally:
        if key_path is not None:
            key_path.unlink(missing_ok=True)


def jwt_assertion(credentials, now=None, signer=sign_rs256):
    issued_at = int(time.time()) if now is None else now
    header = {"alg": "RS256", "typ": "JWT"}
    if credentials.get("private_key_id"):
        header["kid"] = credentials["private_key_id"]
    payload = {
        "iss": credentials["client_email"],
        "scope": SCOPE,
        "aud": TOKEN_URL,
        "iat": issued_at,
        "exp": issued_at + 3600,
    }
    encoded_header = base64url(json.dumps(header, separators=(",", ":")).encode())
    encoded_payload = base64url(json.dumps(payload, separators=(",", ":")).encode())
    signing_input = encoded_header + b"." + encoded_payload
    signature = signer(credentials["private_key"], signing_input)
    return (signing_input + b"." + base64url(signature)).decode("ascii")


def default_credentials_path():
    configured = os.environ.get("HOLYBEANS_PLAY_SERVICE_ACCOUNT")
    if configured:
        return Path(configured).expanduser()
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "holybeans" / "play-publisher.json"


class PlayPublisher:
    def __init__(self, transport=None, log=None):
        self.transport = transport or HttpTransport()
        self.log = log or (lambda message: None)

    def request(
        self,
        method,
        url,
        token=None,
        payload=_UNSET,
        body=None,
        headers=None,
        timeout=30,
        redactions=(),
    ):
        request_headers = {"Accept": "application/json", **(headers or {})}
        if token:
            request_headers["Authorization"] = f"Bearer {token}"
        if payload is not _UNSET:
            if body is not None:
                raise ValueError("payload y body son excluyentes")
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            request_headers["Content-Type"] = "application/json; charset=UTF-8"
        status, response_body = self.transport(
            method, url, body=body, headers=request_headers, timeout=timeout
        )
        secrets = tuple(redactions) + ((token,) if token else ())
        if not 200 <= status < 300:
            raise ApiError(method, url, status, response_body, secrets)
        if not response_body:
            return {}
        try:
            result = json.loads(response_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise PublishError(f"{method} {url}: respuesta JSON no válida") from error
        if not isinstance(result, dict):
            raise PublishError(f"{method} {url}: respuesta JSON inesperada")
        return result

    def authenticate(self, credentials_path):
        credentials = load_service_account(credentials_path)
        assertion = jwt_assertion(credentials)
        body = urlencode(
            {
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": assertion,
            }
        ).encode("ascii")
        response = self.request(
            "POST",
            TOKEN_URL,
            body=body,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            redactions=(assertion,),
        )
        token = response.get("access_token")
        if not isinstance(token, str) or not token:
            raise PublishError("OAuth no devolvió access_token.")
        return token

    def edits_url(self, package, edit_id=None):
        url = f"{API_ROOT}/{quote(package, safe='')}/edits"
        if edit_id is not None:
            url += "/" + quote(edit_id, safe="")
        return url

    def publish(self, plan, credentials_path, package=PACKAGE):
        token = self.authenticate(credentials_path)
        edit_id = None
        commit_started = False
        try:
            edit = self.request("POST", self.edits_url(package), token, payload={})
            edit_id = edit.get("id")
            if not isinstance(edit_id, str) or not edit_id:
                raise PublishError("Play no devolvió un editId válido.")
            self.log(f"Edición creada: {edit_id}")
            edit_url = self.edits_url(package, edit_id)
            track_url = f"{edit_url}/tracks/{quote(plan.track, safe='')}"
            current_track = self.request("GET", track_url, token)
            unfinished = [
                release.get("status", "desconocido")
                for release in current_track.get("releases", [])
                if release.get("status") != "completed"
            ]
            if unfinished:
                raise PublishError(
                    f"El track {plan.track} contiene releases {', '.join(unfinished)}; "
                    "no las sustituiré. Termina o descarta ese despliegue antes de publicar."
                )
            upload_url = (
                f"{UPLOAD_ROOT}/{quote(package, safe='')}/edits/{quote(edit_id, safe='')}"
                "/bundles?uploadType=media"
            )
            self.log(f"Subiendo {plan.aab.name} ({plan.aab.stat().st_size} bytes)…")
            with plan.aab.open("rb") as bundle:
                uploaded = self.request(
                    "POST",
                    upload_url,
                    token,
                    body=bundle,
                    headers={
                        "Content-Type": "application/octet-stream",
                        "Content-Length": str(plan.aab.stat().st_size),
                    },
                    timeout=600,
                )
            if uploaded.get("versionCode") != plan.version_code:
                raise PublishError(
                    f"Play devolvió versionCode {uploaded.get('versionCode')}; "
                    f"se esperaba {plan.version_code}. No se asignará el track."
                )
            release = {
                "name": plan.version_name,
                "versionCodes": [str(plan.version_code)],
                "status": "completed",
                "releaseNotes": [
                    {"language": language, "text": plan.notes[language]}
                    for language in LANGUAGES
                ],
            }
            self.request(
                "PUT",
                track_url,
                token,
                payload={"track": plan.track, "releases": [release]},
            )
            self.request("POST", edit_url + ":validate", token, body=b"")
            commit_url = edit_url + ":commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW"
            commit_started = True
            try:
                self.request("POST", commit_url, token, body=b"")
            except Exception as error:
                raise PublishError(
                    f"No se confirmó el commit de la edición {edit_id}; no se reintentó ni se "
                    f"canceló ninguna revisión. Comprueba Play Console antes de repetir: {error}"
                ) from error
            self.log(
                f"Release {plan.version_name} ({plan.version_code}) enviada al track "
                f"{plan.track}. Queda pendiente de la revisión de Google Play."
            )
        except Exception:
            if edit_id is not None and not commit_started:
                try:
                    self.request("DELETE", self.edits_url(package, edit_id), token)
                except Exception as cleanup_error:
                    self.log(f"Aviso: no pude descartar la edición {edit_id}: {cleanup_error}")
            raise


def print_plan(plan):
    print(f"AAB: {plan.aab}")
    print(f"SHA-256: {plan.sha256}")
    print(f"Versión: {plan.version_name} ({plan.version_code})")
    print(f"Paquete: {PACKAGE}")
    print(f"Track: {plan.track}")
    for language in LANGUAGES:
        print(f"Notas {language}: {len(plan.notes[language])} caracteres")


def argument_parser():
    parser = argparse.ArgumentParser(
        description="Valida y publica un AAB de HolyBeans con Google Play Developer API."
    )
    parser.add_argument("aab", type=Path, help="AAB compilado y firmado según docs/RELEASING.md")
    parser.add_argument("notes", type=Path, help="Documento con notas <es-ES> y <en-GB>")
    parser.add_argument(
        "--track", default="production", help="Track de Play (predeterminado: production)"
    )
    parser.add_argument("--credentials", type=Path, help="JSON de la cuenta de servicio")
    parser.add_argument(
        "--publish", action="store_true", help="Sube y envía la release; sin esta opción solo valida"
    )
    return parser


def main(argv=None):
    arguments = argument_parser().parse_args(argv)
    root = Path(__file__).resolve().parent.parent
    try:
        plan = build_plan(root, arguments.aab, arguments.notes, arguments.track)
        print_plan(plan)
        if not arguments.publish:
            print("Simulación completada: no se ha usado la red ni modificado Play. Añade --publish para publicar.")
            return 0
        credentials = arguments.credentials or default_credentials_path()
        PlayPublisher(log=print).publish(plan, credentials)
        return 0
    except PublishError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
