# Datenschutzrichtlinie

[简体中文](PRIVACY.md) · [繁體中文](PRIVACY.zh-Hant.md) · [English](PRIVACY.en.md) · [日本語](PRIVACY.ja.md) · [한국어](PRIVACY.ko.md) · [Español](PRIVACY.es.md) · [Français](PRIVACY.fr.md) · [Deutsch](PRIVACY.de.md)

Datum des Inkrafttretens: 10. August 2026

ContactsDeduper ist ein Tool zur lokalen Erstkontakt-Organisation für iOS und macOS. In dieser Richtlinie wird erläutert, wie die App auf Kontaktdaten zugreift, diese verwendet und schützt.

## Daten, auf die die App zugreift

Nachdem Sie Zugriff auf Kontakte gewährt haben, kann die App die folgenden Kontaktinformationen lesen und ändern:

- Namen, Spitznamen, Organisationen, Abteilungen und Berufsbezeichnungen
- Telefonnummern, E-Mail-Adressen, URLs und Postanschriften
- Geburtstage, Jubiläen und Kontaktbeziehungen
- Soziale Profile, Instant-Messaging-Konten und Kontaktbilder
- Listen- und Gruppennamen sowie Mitgliedschaftsbeziehungen in Ihren Kontaktkonten

Diese Informationen werden nur verwendet, um doppelte Kontakte zu finden, übereinstimmende Beweise anzuzeigen, Kontakte zusammenzuführen und ein Backup zu erstellen oder wiederherzustellen, das Sie ausdrücklich auswählen.

## Erhebung und Übermittlung

- Die App verfügt über kein Kontosystem, Werbung, Analyse, Telemetrie oder Tracking-SDKs von Drittanbietern.
- Die App lädt keine Kontaktdaten zum Entwickler oder einem Drittanbieter-Server hoch.
- Die App benötigt keine Netzwerkverbindung. Die Sandbox-Konfiguration von macOS deaktiviert standardmäßig den ausgehenden Netzwerkzugriff.
- Ob Kontakte über iCloud, Google oder ein anderes Konto synchronisiert werden, wird durch die Systemkontakteinstellungen und den entsprechenden Kontoanbieter gesteuert, nicht durch die App.

## Dateien sichern

Sie können Kontakte explizit als JSON-Datei exportieren. Ein Backup kann vertrauliche Telefonnummern, E-Mail-Adressen, Postanschriften, Geburtstage, Beziehungen, soziale Konten und Kontaktbilder enthalten.

- Sicherungsdateien werden an dem Speicherort gespeichert, den Sie in der Systemdateiauswahl auswählen.
- Sicherungsdateien werden nicht auf die Server des Entwicklers hochgeladen.
- Das aktuelle Backup-Format ist nicht verschlüsselt. Speichern Sie es an einem vertrauenswürdigen Ort und geben Sie es nicht öffentlich weiter und übergeben Sie es nicht an ein Git-Repository.
- Während des Imports überprüft die App die Dateigröße, die Formatversion und die Kontaktanzahl, bevor sie in die Kontakte schreibt.

## Datenänderungen und Löschung

- Einzelkontaktgruppen- und Massenzusammenführungen ändern die Kontaktdatenbank des Systems und löschen die zum Entfernen ausgewählten doppelten Datensätze.
- Durch das Zusammenführen von Listen werden Mitglieder konsolidiert und doppelte Listen innerhalb desselben Kontaktkontos entfernt. Kontakte werden nicht als Nebeneffekt gelöscht.
- „Alle Kontakte löschen“ löscht Kontakte, auf die die App derzeit zugreifen kann.
- Alle destruktiven Aktionen bedürfen einer ausdrücklichen Bestätigung.
- Die App verwaltet keine Cloud-Kopie. Wenn möglich, exportieren Sie vor dem Zusammenführen oder Löschen ein Backup.

## Berechtigungskontrollen

Sie können den Kontaktzugriff jederzeit in den Systemeinstellungen von iOS oder macOS widerrufen. Die App kann Kontakte nicht mehr lesen oder ändern, nachdem der Zugriff widerrufen wurde.

## Aktualisierungen dieser Richtlinie

Wenn die App Netzwerkdienste, Analysen, Cloud-Synchronisierung oder eine neue Datennutzung hinzufügt, wird diese Richtlinie zusammen mit dem Code und der Release-Version aktualisiert.

## Kontakt

Bei Fragen zum Datenschutz verwenden Sie die [GitHub Issues] des Projekts (https://github.com/gewill/ContactsDeduper/issues). Hängen Sie keine echten Kontaktdaten oder Sicherungsdateien an ein Problem an.
