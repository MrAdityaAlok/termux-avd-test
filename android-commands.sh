#!/bin/bash

# There are three shells: the host's, adb, and termux. Only adb lets us run
# commands directly on the emulated device, only termux provides a GNU
# environment on the emulated device (to e.g. run cargo). So we use adb to
# launch termux, then to send keystrokes to it while it's running.
# This means that the commands sent to termux are first parsed as arguments in
# this shell, then as arguments in the adb shell, before finally being used as
# text inputs to the app. Hence, the "'wrapping'" on those commands.
# There's no way to get any feedback from termux, so every time we run a
# command on it, we make sure it ends by creating a unique *.probe file at the
# end of the command. The contents of the file are used as a return code: 0 on
# success, some other number for errors (an empty file is basically the same as
# 0). Note that the return codes are text, not raw bytes.

this_repo="$(dirname $(dirname -- "$(readlink -- "${0}")"))"

hit_enter() {
	adb shell input keyevent 66
}

launch_termux() {
	echo "launching termux"
	if ! adb shell 'am start -n com.termux/.HomeActivity'; then
		echo "failed to launch termux"
		exit 1
	fi
	# the emulator can sometimes be a little slow to launch the app
	while ! adb shell 'ls /sdcard/launch.probe' 2> /dev/null; do
		echo "waiting for launch.probe"
		sleep 5
		adb shell input text 'touch\ /sdcard/launch.probe' && hit_enter
	done
	echo "found launch.probe"
	adb shell 'rm /sdcard/launch.probe' && echo "removed launch.probe"
}

run_termux_command() {
	command="$1" # text of the escaped command, including creating the probe!
	probe="$2"   # unique file that indicates the command is complete
	launch_termux
	adb shell input text "$command" && hit_enter
	while ! adb shell "ls $probe" 2> /dev/null; do
		echo "waiting for $probe"
		sleep 30
	done
	return_code=$(adb shell "cat $probe")
	adb shell "rm $probe"
	echo "return code: $return_code"
	return $return_code
}

snapshot() {
	apk="$1"
	echo "running snapshot"
	adb install -g "$apk"
	probe='/sdcard/pkg.probe'
	command="'yes | pkg up -y && pkg i binutils -y; touch $probe'"
	run_termux_command "$command" "$probe"
	echo "snapshot complete"
	adb shell input text "exit" && hit_enter && hit_enter
}

tests() {
	probe='/sdcard/tests.probe'
	command="'echo '==> hey how are you' && echo '==> I am in \$PWD' && env >/sdcard/tests.log 2>&1; echo \$? >$probe'"
	run_termux_command "$command" "$probe"
	return_code=$?
	adb pull /sdcard/tests.log .
	cat tests.log
	return $return_code
}

# adb logcat &
exit_code=0

if [ $# -eq 1 ]; then
	case "$1" in
		tests)
			tests
			exit_code=$?
			;;
	esac
elif [ $# -eq 2 ]; then
	case "$1" in
		snapshot)
			snapshot "$2"
			exit_code=$?
			;;
	esac
else
	exit_code=1
fi

#pkill adb
exit $exit_code
