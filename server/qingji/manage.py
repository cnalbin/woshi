"""Manage private NAS accounts from the server console."""
import argparse
from getpass import getpass

from sqlalchemy.exc import IntegrityError

from .accounts import Accounts
from .config import Settings
from .storage import Storage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["create", "reset-password"])
    parser.add_argument("username")
    parser.add_argument("--legacy-owner", action="store_true", help="Assign the old NAS backup to this new account")
    args = parser.parse_args()
    if args.legacy_owner and args.action != "create":
        parser.error("--legacy-owner only applies to create")
    password = getpass("New password (at least 12 characters): ")
    if password != getpass("Repeat password: "):
        parser.exit(1, "Passwords do not match.\n")
    settings = Settings()
    engine = settings.engine()
    try:
        Storage(engine, settings.photo_directory, settings.owner_id).initialize()
        accounts = Accounts(engine, settings.owner_id)
        if args.action == "create":
            accounts.create(args.username.strip().lower(), password, args.legacy_owner)
        else:
            accounts.reset_password(args.username.strip().lower(), password)
    except IntegrityError:
        parser.exit(1, "Username or legacy backup is already assigned.\n")
    except ValueError as error:
        parser.exit(1, f"{error}\n")
    finally:
        engine.dispose()
    print("Account updated.")


if __name__ == "__main__":
    main()
