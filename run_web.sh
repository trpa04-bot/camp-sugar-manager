#!/bin/bash

# Pokreni Flutter na Chrome-u
flutter run -d chrome &

# Čekaj da se Chrome otvori (obično 3-5 sekundi)
sleep 5

# Nađi Chrome prozor i otvori ga u fokus
open -a "Google Chrome"
