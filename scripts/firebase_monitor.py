"""
Firebase RTDB Monitor - Watches /automation-flags/unlock_door for changes.

Usage:
  pip install firebase-admin
  python firebase_monitor.py --cred path/to/serviceAccountKey.json --db https://vdb-poc-default-rtdb.asia-southeast1.firebasedatabase.app
"""

import argparse
import firebase_admin
from firebase_admin import credentials, db


def on_change(event):
    print(f"[CHANGE] Path: {event.path} | Value: {event.data}")


def main():
    parser = argparse.ArgumentParser(description="Monitor Firebase RTDB unlock_door")
    parser.add_argument("--cred", required=True, help="Path to service account JSON key")
    parser.add_argument(
        "--db",
        default="https://vdb-poc-default-rtdb.asia-southeast1.firebasedatabase.app",
        help="Firebase RTDB URL",
    )
    args = parser.parse_args()

    cred = credentials.Certificate(args.cred)
    firebase_admin.initialize_app(cred, {"databaseURL": args.db})

    ref = db.reference("/automation-flags/unlock_door")
    print(f"[INFO] Monitoring /automation-flags/unlock_door ...")
    print(f"[INFO] Current value: {ref.get()}")

    ref.listen(on_change)

    # Keep alive
    import signal
    signal.pause()


if __name__ == "__main__":
    main()
