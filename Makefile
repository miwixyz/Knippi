.PHONY: gen test sichttest release release-dry-run prune

APP = Knippi

# Das Xcode-Projekt ist generiert (gitignoriert), Quelle ist project.yml.
gen:
	xcodegen generate

# Alle Paket-Suiten + App-Tests, mehrere Minuten, Exit != 0 bei Fehler.
test:
	@sh scripts/test-all.sh

# Abgeschottete Testkopie „Knippi Sichttest“ bauen und starten.
sichttest:
	@sh scripts/sichttest.sh

# Signiert, notarisiert, GitHub-Release, Appcast. Probelauf: PUBLISH=0 make release
release:
	@bash scripts/release.sh

release-dry-run:
	@echo "VERSION:      $$(awk -F'\"' '/MARKETING_VERSION:/ { print $$2; exit }' project.yml)"
	@printf "DEVELOPER_ID: "; security find-identity -v -p codesigning | awk -F'\"' '/Developer ID Application/ { print $$2; exit }'
	@[ -z "$$(git status --porcelain)" ] && echo "Arbeitsbaum:  sauber" || echo "Arbeitsbaum:  NICHT sauber"

# Höchstens 5 GitHub-Releases (läuft auch am Ende von make release). Hier nur Vorschau.
prune:
	@GH_REPO=miwixyz/Knippi bash scripts/prune-releases.sh --dry-run
