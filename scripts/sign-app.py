#!/usr/bin/env python3
"""Sign local builds with one private, app-specific identity across updates.

The certificate is not installed as a trusted system root. Its private key lives
in a separate, locked keychain, never in the login keychain or source repository.
"""
import fcntl
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tempfile


def run(*args, env=None):
    result = subprocess.run(args, text=True, capture_output=True, env=env)
    if result.returncode:
        # Do not echo command arguments: some Security operations contain passwords.
        operation = Path(args[0]).name + (f" {args[1]}" if args[0].endswith("/security") else "")
        detail = " " + result.stderr.strip() if args[0] == "/usr/bin/codesign" else ""
        raise RuntimeError(f"{operation} failed (exit {result.returncode}).{detail}")
    return result.stdout.strip()


def sign(app):
    explicit_identity = os.environ.get("OVO_SIGNING_IDENTITY")
    if explicit_identity:
        run("/usr/bin/codesign", "--force", "--sign", explicit_identity, str(app))
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
        return

    directory = Path.home() / "Library/Application Support/Ovo/Signing"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    lock_path = directory / "build.lock"
    with lock_path.open("a") as lock:
        lock_path.chmod(0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        password_file = directory / "keychain-password"
        keychain = directory / "OvoDevelopment.keychain-db"
        certificate = directory / "certificate.pem"
        if not password_file.exists():
            if keychain.exists():
                raise RuntimeError("The local signing keychain exists but its password file is missing.")
            descriptor = os.open(password_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, "w") as file:
                file.write(secrets.token_urlsafe(48))
        password_file.chmod(0o600)
        password = password_file.read_text()
        previous_keychains = shlex.split(run("/usr/bin/security", "list-keychains", "-d", "user"))
        try:
            if not keychain.exists():
                run("/usr/bin/security", "create-keychain", "-p", password, str(keychain))
                run("/usr/bin/security", "set-keychain-settings", "-lut", "21600", str(keychain))
                with tempfile.TemporaryDirectory(prefix="identity-", dir=directory) as temporary:
                    temporary = Path(temporary)
                    config = temporary / "certificate.conf"
                    config.write_text("""[req]
prompt = no
distinguished_name = subject
x509_extensions = signing
[subject]
CN = Ovo Local Development
[signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
""")
                    private_key = temporary / "key.pem"
                    archive = temporary / "identity.p12"
                    run("/usr/bin/openssl", "req", "-new", "-x509", "-newkey", "rsa:3072", "-nodes",
                        "-sha256", "-days", "3650", "-config", str(config),
                        "-keyout", str(private_key), "-out", str(certificate))
                    environment = dict(os.environ, OVO_TEMP_SIGNING_PASSWORD=password)
                    run("/usr/bin/openssl", "pkcs12", "-export", "-inkey", str(private_key),
                        "-in", str(certificate), "-out", str(archive),
                        "-passout", "env:OVO_TEMP_SIGNING_PASSWORD", env=environment)
                    run("/usr/bin/security", "import", str(archive), "-k", str(keychain),
                        "-P", password, "-T", "/usr/bin/codesign")
                    run("/usr/bin/security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:",
                        "-s", "-k", password, str(keychain))
            run("/usr/bin/security", "unlock-keychain", "-p", password, str(keychain))
            run("/usr/bin/security", "list-keychains", "-d", "user", "-s", *previous_keychains, str(keychain))
            fingerprint = run("/usr/bin/openssl", "x509", "-in", str(certificate),
                              "-noout", "-fingerprint", "-sha1").split("=", 1)[1].replace(":", "")
            requirement = f'designated => identifier "com.ovo.translator" and certificate leaf = H"{fingerprint}"'
            run("/usr/bin/codesign", "--force", "--sign", fingerprint, "--keychain", str(keychain),
                "--requirements", "=" + requirement, "--timestamp=none", str(app))
            run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
            print("Signed with the persistent Ovo local identity.")
        finally:
            if keychain.exists():
                subprocess.run(["/usr/bin/security", "lock-keychain", str(keychain)], capture_output=True)
            # Creating a keychain adds it to the search list. Restore the original list.
            run("/usr/bin/security", "list-keychains", "-d", "user", "-s", *previous_keychains)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: sign-app.py /path/to/Ovo.app")
    try:
        sign(Path(sys.argv[1]).resolve())
    except Exception as error:
        sys.exit(str(error))
