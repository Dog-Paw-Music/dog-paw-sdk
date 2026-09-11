# WSL / WSLg JACK audio stack

Chosen path: **classic JACK + pacat bridge** into WSLg Pulse (Windows speakers).

This stack is for the dedicated **DogPaw** WSL2 + WSLg distro created by
`scripts/windows/Setup-DogPawWsl.ps1`. It is not used by the Flutter edit/test
Dev Container image.

## Shape

```text
jackd -d dummy
    → system:playback_*
    → dogpaw-jack-mirror (polls + jack_connect)
    → dogpaw_pulse:in_1 / in_2
    → dogpaw-jack-to-pulse
    → pacat --raw float32
    → PULSE_SERVER=unix:/mnt/wslg/PulseServer
    → Windows speakers
```

## Packages

```bash
sudo apt install -y jackd2 jack-tools pulseaudio-utils
```

## Enable

```bash
./scripts/wsl-audio/install-user-units.sh
systemctl --user status dogpaw-jackd-dummy dogpaw-jack-to-pulse dogpaw-jack-mirror
```

The install script **disables user PipeWire** so `jackd` owns JACK. That is
intentional inside the Dog Paw distro; do not enable these units on a general
purpose WSL distro you use for other work.

Windows hosts should prefer `scripts/windows/Setup-DogPawWsl.ps1`, which creates
an isolated `DogPaw` distro and enables this stack there.

## Smoke test

```bash
./scripts/wsl-audio/smoke-metro.sh
```

`jack_metro` does not autoconnect on dummy `jackd`; the smoke script connects it to `system:playback_*`, and `dogpaw-jack-mirror` copies those links onto the bridge within ~0.5s.

Dog Paw / Epiphany apps that already connect to `system:playback_*` need no extra step.

## Units

| Unit | Role |
|---|---|
| `dogpaw-jackd-dummy.service` | JACK server |
| `dogpaw-jack-to-pulse.service` | Bridge → pacat |
| `dogpaw-jack-mirror.service` | Mirror `system:playback_*` → bridge |
