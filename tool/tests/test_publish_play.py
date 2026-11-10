import io
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

from tool.publish_play import (
    API_ROOT,
    LANGUAGES,
    TOKEN_URL,
    ApiError,
    PlayPublisher,
    PublishError,
    build_plan,
    jwt_assertion,
    main,
)


NOTES = """# Release
```text
<es-ES>
• Primera nota española.
</es-ES>
<en-GB>
• First English note.
</en-GB>
```
"""


class FakeTransport:
    def __init__(self, uploaded_version=149, releases=None, failures=None, track="production"):
        self.track = track
        self.uploaded_version = uploaded_version
        self.releases = [{"status": "completed", "versionCodes": ["148"]}] if releases is None else releases
        self.failures = failures or {}
        self.calls = []
        self.track_payload = None

    def __call__(self, method, url, body=None, headers=None, timeout=30):
        content = body.read() if hasattr(body, "read") else body
        self.calls.append(
            {
                "method": method,
                "url": url,
                "body": content,
                "headers": headers,
                "timeout": timeout,
            }
        )
        path = urlsplit(url).path
        operation = (method, path)
        if operation in self.failures:
            return self.failures[operation]
        if url == TOKEN_URL:
            return 200, json.dumps({"access_token": "oauth-token"}).encode()
        if method == "POST" and path.endswith("/edits"):
            return 200, b'{"id":"edit-1"}'
        if method == "GET" and path.endswith(f"/tracks/{self.track}"):
            return 200, json.dumps({"track": self.track, "releases": self.releases}).encode()
        if method == "POST" and path.endswith("/bundles"):
            return 200, json.dumps({"versionCode": self.uploaded_version}).encode()
        if method == "PUT" and path.endswith(f"/tracks/{self.track}"):
            self.track_payload = json.loads(content)
            return 200, content
        if method == "POST" and path.endswith(":validate"):
            return 200, b'{"id":"edit-1"}'
        if method == "POST" and path.endswith(":commit"):
            return 200, b'{"id":"edit-1"}'
        if method == "DELETE":
            return 204, b""
        return 404, json.dumps({"error": {"message": f"Ruta inesperada: {method} {path}"}}).encode()


class PublishPlayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "pubspec.yaml").write_text("name: holybeans\nversion: 1.2.3+149\n")
        self.aab = self.root / "holybeans-1.2.3-149.aab"
        self.aab.write_bytes(b"bundle")
        self.notes = self.root / "release.md"
        self.notes.write_text(NOTES)

    def plan(self, track="production"):
        return build_plan(self.root, self.aab, self.notes, track)

    def publish(self, fake, plan=None):
        publisher = PlayPublisher(transport=fake)
        with patch.object(publisher, "authenticate", return_value="secret-token"):
            publisher.publish(plan or self.plan(), Path("unused.json"))

    def test_plan_reads_versions_notes_and_hash(self):
        plan = self.plan()
        self.assertEqual(plan.version_name, "1.2.3")
        self.assertEqual(plan.version_code, 149)
        self.assertEqual(plan.notes["es-ES"], "• Primera nota española.")
        self.assertEqual(plan.notes["en-GB"], "• First English note.")
        self.assertEqual(len(plan.sha256), 64)

    def test_missing_and_oversized_notes_are_rejected(self):
        self.notes.write_text("<es-ES>Nota</es-ES>")
        with self.assertRaisesRegex(PublishError, "en-GB"):
            self.plan()
        self.notes.write_text(
            f"<es-ES>{'x' * 501}</es-ES><en-GB>Valid</en-GB>"
        )
        with self.assertRaisesRegex(PublishError, "501"):
            self.plan()
        self.notes.write_text(
            f"<es-ES>{'x' * 500}</es-ES><en-GB>Valid</en-GB>"
        )
        self.assertEqual(len(self.plan().notes["es-ES"]), 500)

    def test_aab_must_match_pubspec(self):
        wrong = self.root / "holybeans-1.2.2-149.aab"
        wrong.write_bytes(b"bundle")
        with self.assertRaisesRegex(PublishError, "holybeans-1.2.3-149.aab"):
            build_plan(self.root, wrong, self.notes, "beta")
        (self.root / "pubspec.yaml").write_text("version: no-code\n")
        with self.assertRaisesRegex(PublishError, "pubspec.yaml"):
            self.plan()

    def test_invalid_track_is_rejected_before_network(self):
        for track in ["", " beta", "beta\n"]:
            with self.subTest(track=track), self.assertRaises(PublishError):
                self.plan(track)

    def test_dry_run_uses_no_network_or_credentials(self):
        output = io.StringIO()
        with patch("tool.publish_play.HttpTransport", side_effect=AssertionError("red")), patch(
            "tool.publish_play.build_plan", return_value=self.plan()
        ):
            with redirect_stdout(output):
                result = main([str(self.aab), str(self.notes)])
        self.assertEqual(result, 0)
        self.assertIn("Simulación completada", output.getvalue())
        self.assertIn("1.2.3 (149)", output.getvalue())

    def test_complete_publish_sequence_and_payload(self):
        fake = FakeTransport()
        self.publish(fake)
        operations = [(call["method"], urlsplit(call["url"]).path) for call in fake.calls]
        self.assertEqual(
            operations,
            [
                ("POST", f"/androidpublisher/v3/applications/com.caffeinateddev.holybeans/edits"),
                ("GET", f"/androidpublisher/v3/applications/com.caffeinateddev.holybeans/edits/edit-1/tracks/production"),
                ("POST", f"/upload/androidpublisher/v3/applications/com.caffeinateddev.holybeans/edits/edit-1/bundles"),
                ("PUT", f"/androidpublisher/v3/applications/com.caffeinateddev.holybeans/edits/edit-1/tracks/production"),
                ("POST", f"/androidpublisher/v3/applications/com.caffeinateddev.holybeans/edits/edit-1:validate"),
                ("POST", f"/androidpublisher/v3/applications/com.caffeinateddev.holybeans/edits/edit-1:commit"),
            ],
        )
        self.assertEqual(fake.calls[2]["body"], b"bundle")
        self.assertEqual(fake.calls[2]["headers"]["Content-Length"], "6")
        self.assertEqual(fake.calls[2]["timeout"], 600)
        commit = fake.calls[-1]
        self.assertEqual(
            parse_qs(urlsplit(commit["url"]).query),
            {"changesInReviewBehavior": ["ERROR_IF_IN_REVIEW"]},
        )
        release = fake.track_payload["releases"][0]
        self.assertEqual(release["name"], "1.2.3")
        self.assertEqual(release["versionCodes"], ["149"])
        self.assertEqual(release["status"], "completed")
        self.assertEqual(
            {note["language"] for note in release["releaseNotes"]}, set(LANGUAGES)
        )

    def test_cli_publishes_to_internal_by_default_and_allows_explicit_tracks(self):
        for track, options in [
            ("internal", []),
            ("production", ["--track", "production"]),
            ("beta", ["--track", "beta"]),
            ("internal", ["--track", "internal"]),
        ]:
            with self.subTest(track=track):
                fake = FakeTransport(track=track)
                output = io.StringIO()
                with patch("tool.publish_play.pubspec_version", return_value=("1.2.3", 149)), patch(
                    "tool.publish_play.HttpTransport", return_value=fake
                ), patch.object(PlayPublisher, "authenticate", return_value="secret-token"), redirect_stdout(output):
                    result = main([str(self.aab), str(self.notes), "--publish", *options])
                self.assertEqual(result, 0)
                self.assertIn(f"Track: {track}\n", output.getvalue())
                self.assertEqual(fake.track_payload["track"], track)
                self.assertEqual(fake.track_payload["releases"][0]["status"], "completed")
                self.assertTrue(fake.calls[-1]["url"].endswith(
                    ":commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW"
                ))

    def test_unfinished_track_release_is_preserved(self):
        for status in ["draft", "inProgress", "halted"]:
            with self.subTest(status=status):
                fake = FakeTransport(releases=[{"status": status}])
                with self.assertRaisesRegex(PublishError, status):
                    self.publish(fake)
                self.assertFalse(any("/bundles" in call["url"] for call in fake.calls))
                self.assertFalse(any(":commit" in call["url"] for call in fake.calls))
                self.assertEqual(fake.calls[-1]["method"], "DELETE")

    def test_version_mismatch_never_assigns_track_or_commits(self):
        fake = FakeTransport(uploaded_version=148)
        with self.assertRaisesRegex(PublishError, "148"):
            self.publish(fake)
        self.assertFalse(any(call["method"] == "PUT" for call in fake.calls))
        self.assertFalse(any(":commit" in call["url"] for call in fake.calls))
        self.assertEqual(fake.calls[-1]["method"], "DELETE")

    def test_api_error_redacts_access_token(self):
        path = f"{API_ROOT}/com.caffeinateddev.holybeans/edits/edit-1/tracks/production"
        path = path.replace("https://androidpublisher.googleapis.com", "")
        fake = FakeTransport(
            failures={
                ("GET", path): (
                    403,
                    b'{"error":{"message":"No usar secret-token"}}',
                )
            }
        )
        with self.assertRaises(PublishError) as raised:
            self.publish(fake)
        self.assertNotIn("secret-token", str(raised.exception))
        self.assertIn("[oculto]", str(raised.exception))

    def test_commit_failure_is_not_retried_or_deleted(self):
        suffix = "/androidpublisher/v3/applications/com.caffeinateddev.holybeans/edits/edit-1:commit"
        fake = FakeTransport(
            failures={
                ("POST", suffix): (
                    400,
                    b'{"error":{"message":"CHANGES_ALREADY_IN_REVIEW"}}',
                )
            }
        )
        with self.assertRaisesRegex(PublishError, "edit-1"):
            self.publish(fake)
        self.assertEqual(sum(":commit" in call["url"] for call in fake.calls), 1)
        self.assertFalse(any(call["method"] == "DELETE" for call in fake.calls))

    def test_jwt_contains_expected_claims_not_private_key(self):
        credentials = {
            "client_email": "publisher@example.iam.gserviceaccount.com",
            "private_key": "SECRET PRIVATE KEY",
            "private_key_id": "key-id",
        }
        assertion = jwt_assertion(credentials, now=1000, signer=lambda key, data: b"signature")
        self.assertNotIn("SECRET PRIVATE KEY", assertion)
        header, payload, _ = assertion.split(".")
        decode = lambda value: json.loads(
            __import__("base64").urlsafe_b64decode(value + "=" * (-len(value) % 4))
        )
        self.assertEqual(decode(header)["kid"], "key-id")
        claims = decode(payload)
        self.assertEqual(claims["iss"], credentials["client_email"])
        self.assertEqual(claims["aud"], TOKEN_URL)
        self.assertEqual(claims["exp"] - claims["iat"], 3600)

    def test_authenticate_uses_jwt_grant(self):
        fake = FakeTransport()
        publisher = PlayPublisher(transport=fake)
        with patch("tool.publish_play.load_service_account", return_value={}), patch(
            "tool.publish_play.jwt_assertion", return_value="assertion-secret"
        ):
            token = publisher.authenticate(Path("credentials.json"))
        self.assertEqual(token, "oauth-token")
        body = parse_qs(fake.calls[0]["body"].decode())
        self.assertEqual(body["assertion"], ["assertion-secret"])
        self.assertEqual(
            body["grant_type"], ["urn:ietf:params:oauth:grant-type:jwt-bearer"]
        )


if __name__ == "__main__":
    unittest.main()
