.PHONY: build app run install clean

build:
	swift build -c release

app:
	bash scripts/build-app.sh release

run: app
	open build/NotchFlow.app

install: app
	rm -rf /Applications/NotchFlow.app
	cp -R build/NotchFlow.app /Applications/
	open /Applications/NotchFlow.app

clean:
	rm -rf .build build
