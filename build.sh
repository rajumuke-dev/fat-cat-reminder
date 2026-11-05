#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP=build/FatCatReminder.app
rm -rf build && mkdir -p $APP/Contents/MacOS
swiftc -O -swift-version 5 RestCat.swift -o $APP/Contents/MacOS/FatCatReminder
cp Info.plist $APP/Contents/Info.plist
mkdir -p $APP/Contents/Resources && cp Resources/*.mov $APP/Contents/Resources/
codesign --force --sign - $APP
mkdir -p ~/Applications && rm -rf ~/Applications/FatCatReminder.app && cp -R $APP ~/Applications/
echo "Installed ~/Applications/FatCatReminder.app"
