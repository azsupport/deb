# apt.azsupport.com

The apt repository of azsupport for Ubuntu 24.04 (noble) and 22.04 (jammy), amd64:

- `az-ffmpeg` — FFmpeg 9.1 (`/usr/local/bin/ffmpeg`, `ffprobe`), with the NVIDIA codecs and CUDA filters;
- `az-imagemagick7` — ImageMagick 7 (`/usr/local/bin/magick` and `convert`, `identify`…), with a strict policy.

They are built by [azsupport/ports](https://github.com/azsupport/ports) (`tools/ubuntu/`, the workflow
`ubuntu.yml`: the versions, patches and options of its FreeBSD packages, the libraries inside the programs) and
published in its releases `az-ubuntu<24|22>-amd64-<v3|v2>`; this repository makes the apt repository of them
(`tools/build.sh`, the workflow `apt.yml`: every hour, on GitHub Pages).

## Install

The level of the processor:

```
/lib64/ld-linux-x86-64.so.2 --help | grep supported
```

`x86-64-v3` (or `x86-64-v4`) — the component `v3`; only `x86-64-v2` — `v2`. A package of the wrong level refuses to
install.

```
sudo install -d -m 0755 /etc/apt/keyrings
sudo curl -fsSL -o /etc/apt/keyrings/az-apt.gpg https://apt.azsupport.com/az-apt.gpg
echo "deb [signed-by=/etc/apt/keyrings/az-apt.gpg] https://apt.azsupport.com $(. /etc/os-release && echo $VERSION_CODENAME) v3" | sudo tee /etc/apt/sources.list.d/az.list
sudo apt-get update
sudo apt-get install -y az-ffmpeg az-imagemagick7
```

The updates come with `apt-get upgrade`. To remove: `sudo apt-get remove -y az-ffmpeg az-imagemagick7`.

## The key

`22966A9D7BCB1232C702A2C4126B8086861CFADA` — `APT <github@azsupport.com>`, RSA 4096:

```
gpg --show-keys /etc/apt/keyrings/az-apt.gpg
```

## Layout

```
pool/<v3|v2>/a/<package>/<package>_<version>_amd64.deb
dists/<noble|jammy>/<v3|v2>/binary-amd64/Packages(.gz, .xz)
dists/<noble|jammy>/Release, InRelease, Release.gpg
az-apt.gpg, az-apt.asc
```

The version before the newest stays in the pool and in `Packages` until the next one.
