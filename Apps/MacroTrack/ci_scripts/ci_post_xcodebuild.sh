#!/bin/zsh
# Xcode Cloud runs this after each xcodebuild action; Scripts/xcode-cloud.sh says what it does.
exec "${CI_PRIMARY_REPOSITORY_PATH:-${0:A:h}/../../..}/Scripts/xcode-cloud.sh" post-xcodebuild MacroTrack
