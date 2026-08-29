MeshLink — Offline Field Sync

Peer-to-peer data synchronization for field teams operating without internet. Devices exchange report updates over local Wi-Fi/Bluetooth and merge conflicting edits automatically using CRDTs — no server, no internet required.


Data model (v1)

Report

Field	Type	Notes
id	String	Unique per report
title	String	
description	String	Free text
status	Enum	Open / In Progress / Resolved
priority	Enum	Emergency / High / Medium / Low
needs_support	Boolean	
created_by	String	Team/device name
updated_at	int (per field)	Timestamp used for CRDT conflict resolution


Tech stack
Flutter (mobile app)
SQLite via sqflite (local storage)
Automerge (CRDT merge engine) — or hand-rolled LWW-register fallback, TBD Week 1
Nearby Connections API (device discovery + encrypted transport, Android)

Project structure
lib/
  models/       # Report data class + CRDT wrapper
  db/           # SQLite setup and queries
  sync/         # Discovery + merge logic
  screens/      # UI screens
  
Setup
flutter doctor — confirm no errors
flutter pub get
flutter run 
Status
